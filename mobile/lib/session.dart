import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import 'services/api_service.dart';
import 'theme.dart';

enum DrawMode { none, rectangle, polygon }

class Preset {
  const Preset(this.name, this.south, this.west, this.north, this.east);
  final Map<String, String> name;
  final double south, west, north, east;
  List<LatLng> get polygon => [LatLng(north, west), LatLng(north, east), LatLng(south, east), LatLng(south, west)];
}

/// Example areas only define WHERE to look; every value shown comes from the backend.
const presets = <ModuleId, List<Preset>>{
  ModuleId.bosques: [
    Preset({'es': 'Laguna del Tigre (Petén, Guatemala)', 'en': 'Laguna del Tigre (Petén, Guatemala)'}, 17.15, -90.10, 17.30, -89.90),
    Preset({'es': 'Rondônia (Brasil)', 'en': 'Rondônia (Brazil)'}, -9.95, -63.20, -9.75, -62.95),
    Preset({'es': 'Gran Chaco (Paraguay)', 'en': 'Gran Chaco (Paraguay)'}, -21.60, -60.60, -21.40, -60.35),
  ],
  ModuleId.hundimiento: [
    Preset({'es': 'Ciudad de México (oriente)', 'en': 'Mexico City (east)'}, 19.34, -99.10, 19.40, -99.04),
    Preset({'es': 'Valle de San Joaquín (California)', 'en': 'San Joaquin Valley (California)'}, 36.05, -119.65, 36.15, -119.50),
    Preset({'es': 'Yakarta norte (Indonesia)', 'en': 'North Jakarta (Indonesia)'}, -6.16, 106.75, -6.10, 106.85),
  ],
  ModuleId.glaciares: [
    Preset({'es': 'Sermeq Kujalleq / Jakobshavn (Groenlandia)', 'en': 'Sermeq Kujalleq / Jakobshavn (Greenland)'}, 69.10, -49.95, 69.25, -49.40),
    Preset({'es': 'Perito Moreno (Argentina)', 'en': 'Perito Moreno (Argentina)'}, -50.58, -73.32, -50.42, -73.00),
    Preset({'es': 'Gran Glaciar de Aletsch (Suiza)', 'en': 'Great Aletsch Glacier (Switzerland)'}, 46.40, 7.95, 46.55, 8.10),
  ],
};

/// Per-module state that survives navigation between sections.
class ModuleSession extends ChangeNotifier {
  ModuleSession(this.module);
  final ModuleId module;

  List<LatLng> selection = [];
  List<LatLng> draft = [];
  DrawMode mode = DrawMode.none;
  String? selectionNote;

  int? startYear, endYear;
  DateTime? startDate, endDate;
  int canopy = 30;
  double coherence = 0.35;
  bool advanced = false;

  JobStatus? job;
  Map<String, dynamic>? result;
  ApiException? error;
  final Map<String, Map<String, dynamic>> ai = {};
  final Set<String> aiLoading = {};
  final Map<String, ApiException> aiError = {};
  final Map<String, Future<void>> _aiInflight = {};
  Map<String, dynamic>? cell;
  StreamSubscription<JobStatus>? _sub;
  int _request = 0;

  bool get running => job != null && !job!.done && !job!.failed && result == null && error == null;

  void update(VoidCallback fn) {
    fn();
    notifyListeners();
  }

  void setSelection(List<LatLng> pts, {String? note}) {
    selection = pts;
    selectionNote = note;
    draft = [];
    mode = DrawMode.none;
    clearResult();
  }

  void clearResult() {
    cancelJob();
    result = null;
    error = null;
    cell = null;
    ai.clear();
    aiError.clear();
    aiLoading.clear();
    _aiInflight.clear();
    notifyListeners();
  }

  void cancelJob({ApiService? api}) {
    _sub?.cancel();
    _sub = null;
    final j = job;
    if (api != null && j != null && !j.done && !j.failed) api.cancel(j.id);
    job = null;
    _request++;
  }

  Map<String, dynamic> payload() => {
        'module': module.name,
        'polygon': [for (final p in selection) [p.latitude, p.longitude]],
        if (module == ModuleId.bosques) ...{
          if (startYear != null) 'start_year': startYear,
          if (endYear != null) 'end_year': endYear,
          'canopy_threshold': canopy,
        } else ...{
          if (startDate != null) 'start_date': _d(startDate!),
          if (endDate != null) 'end_date': _d(endDate!),
          if (advanced) 'min_coherence': coherence,
        },
      };

  static String _d(DateTime d) => d.toIso8601String().substring(0, 10);

  Future<void> analyze(ApiService api) async {
    cancelJob(api: api);
    final id = ++_request;
    result = null;
    error = null;
    cell = null;
    ai.clear();
    aiError.clear();
    job = JobStatus({'job_id': '', 'status': 'queued', 'stage': 'queued'});
    notifyListeners();
    try {
      final first = await api.startAnalysis(payload());
      if (id != _request) return;
      _sub = api.watch(first).listen((s) {
        if (id != _request) return;
        job = s;
        if (s.done) result = s.result;
        if (s.failed) error = s.error;
        notifyListeners();
      }, onError: (Object e) {
        if (id != _request) return;
        error = e is ApiException ? e : ApiException.network();
        notifyListeners();
      });
    } on ApiException catch (e) {
      if (id != _request) return;
      error = e;
      notifyListeners();
    }
  }

  /// Waits for the interpretation in [lang] (starting it if needed) so the Gemini voice
  /// reads the summary and the explanation together. Errors are kept, not thrown.
  Future<void> ensureInterpretation(ApiService api, String lang) async {
    if (ai.containsKey(lang)) return;
    final inflight = _aiInflight[lang];
    if (inflight != null) return inflight;
    if (aiError.containsKey(lang)) return;
    await interpret(api, lang);
  }

  Future<void> interpret(ApiService api, String lang, {bool force = false}) {
    final rid = result?['result_id'] as String?;
    if (rid == null || ai.containsKey(lang)) return Future.value();
    if (!force && aiError.containsKey(lang)) return Future.value();
    final inflight = _aiInflight[lang];
    if (inflight != null) return inflight;
    final f = _interpret(api, lang, rid);
    _aiInflight[lang] = f;
    return f.whenComplete(() => _aiInflight.remove(lang));
  }

  Future<void> _interpret(ApiService api, String lang, String rid) async {
    aiLoading.add(lang);
    aiError.remove(lang);
    notifyListeners();
    try {
      final r = await api.interpret(rid, lang);
      if (result?['result_id'] == rid) ai[lang] = r;
    } on ApiException catch (e) {
      if (result?['result_id'] == rid) aiError[lang] = e;
    } finally {
      aiLoading.remove(lang);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
