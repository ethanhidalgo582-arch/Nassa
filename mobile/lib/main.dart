import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'services/api_service.dart';

void main() => runApp(const NisarApp());
const green = Color(0xff16834a);
const blueIce = Color(0xff2f80ed);
const greyLost = Color(0xff9aa3ad);

const Map<String, Map<String, String>> localizedTexts = {
  'es': {
    'appTitle': 'NISAR App',
    'dashboard': 'Dashboard',
    'bosques': 'Bosques',
    'hundimiento': 'Hundimiento',
    'glaciares': 'Glaciares',
    'serverAvailable': 'Servidor disponible',
    'serverNoConnection': 'Sin conexión con el servidor',
    'checkingServer': 'Comprobando conexión…',
    'calculating': 'Calculando…',
    'calculateMetrics': 'Calcular métricas',
    'clearArea': 'Limpiar área',
    'undoVertex': 'Deshacer vértice',
    'advancedOptions': 'Opciones avanzadas: elegir fechas',
    'areaAndPeriod': 'Área y período',
    'preloadZones': 'Zonas críticas precargadas:',
    'mapTitle': 'Mapa del área seleccionada',
    'metricsTitle': 'Métricas calculadas',
    'aiTitle': 'Interpretación con Gemini e Impacto Humano',
    'aiButton': 'Consultar a Gemini',
    'aiInterpreting': 'Interpretando…',
  },
  'en': {
    'appTitle': 'NISAR App',
    'dashboard': 'Dashboard',
    'bosques': 'Forests',
    'hundimiento': 'Subsidence',
    'glaciares': 'Glaciers',
    'serverAvailable': 'Server available',
    'serverNoConnection': 'No server connection',
    'checkingServer': 'Checking connection…',
    'calculating': 'Calculating…',
    'calculateMetrics': 'Calculate metrics',
    'clearArea': 'Clear area',
    'undoVertex': 'Undo vertex',
    'advancedOptions': 'Advanced options: choose dates',
    'areaAndPeriod': 'Area and period',
    'preloadZones': 'Preloaded critical zones:',
    'mapTitle': 'Selected area map',
    'metricsTitle': 'Calculated metrics',
    'aiTitle': 'Gemini Interpretation & Human Impact',
    'aiButton': 'Ask Gemini',
    'aiInterpreting': 'Interpreting…',
  },
};

const modules = ['bosques', 'hundimiento', 'glaciares'];

const Map<String, Map<String, List<LatLng>>> zonasPrecargadas = {
  'bosques': {
    '📍 Amazonas (Brasil)': [
      LatLng(-3.46, -62.21), LatLng(-3.46, -62.19),
      LatLng(-3.48, -62.19), LatLng(-3.48, -62.21),
    ],
    '📍 Petén (Guatemala)': [
      LatLng(16.93, -89.89), LatLng(16.93, -89.87),
      LatLng(16.91, -89.87), LatLng(16.91, -89.89),
    ],
  },
  'hundimiento': {
    '📍 Ciudad de México': [
      LatLng(19.43, -99.13), LatLng(19.43, -99.11),
      LatLng(19.41, -99.11), LatLng(19.41, -99.13),
    ],
    '📍 Yakarta (Indonesia)': [
      LatLng(-6.20, 106.84), LatLng(-6.20, 106.86),
      LatLng(-6.22, 106.86), LatLng(-6.22, 106.84),
    ],
  },
  'glaciares': {
    '📍 Groenlandia': [
      LatLng(69.21, -49.99), LatLng(69.21, -49.97),
      LatLng(69.19, -49.97), LatLng(69.19, -49.99),
    ],
    '📍 Thwaites (Antártida)': [
      LatLng(-75.50, -106.75), LatLng(-75.50, -106.73),
      LatLng(-75.52, -106.73), LatLng(-75.52, -106.75),
    ],
    '📍 Perito Moreno (Arg)': [
      LatLng(-50.49, -73.13), LatLng(-50.49, -73.11),
      LatLng(-50.51, -73.11), LatLng(-50.51, -73.13),
    ],
  },
};

class ForestZone {
  const ForestZone({required this.id, required this.name, required this.polygon});
  final String id;
  final String name;
  final List<LatLng> polygon;
}

const List<ForestZone> forestZones = [
  ForestZone(
    id: 'amazonas',
    name: 'Amazonas (Brasil)',
    polygon: [LatLng(-3.46, -62.21), LatLng(-3.46, -62.19), LatLng(-3.48, -62.19), LatLng(-3.48, -62.21)],
  ),
  ForestZone(
    id: 'peten',
    name: 'Petén (Guatemala)',
    polygon: [LatLng(16.93, -89.89), LatLng(16.93, -89.87), LatLng(16.91, -89.87), LatLng(16.91, -89.89)],
  ),
];

class GlacierZone {
  const GlacierZone({required this.id, required this.name, required this.polygon});
  final String id;
  final String name;
  final List<LatLng> polygon;
}

const List<GlacierZone> glacierZones = [
  GlacierZone(
    id: 'groenlandia',
    name: 'Groenlandia',
    polygon: [LatLng(69.21, -49.99), LatLng(69.21, -49.97), LatLng(69.19, -49.97), LatLng(69.19, -49.99)],
  ),
  GlacierZone(
    id: 'thwaites',
    name: 'Thwaites (Antártida)',
    polygon: [LatLng(-75.50, -106.75), LatLng(-75.50, -106.73), LatLng(-75.52, -106.73), LatLng(-75.52, -106.75)],
  ),
  GlacierZone(
    id: 'perito_moreno',
    name: 'Perito Moreno (Arg)',
    polygon: [LatLng(-50.49, -73.13), LatLng(-50.49, -73.11), LatLng(-50.51, -73.11), LatLng(-50.51, -73.13)],
  ),
];

enum SelectionMode { rectangle, polygon }

class NisarApp extends StatefulWidget {
  const NisarApp({super.key});

  @override
  State<NisarApp> createState() => _NisarAppState();

  static _NisarAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<_NisarAppState>();
}

class _NisarAppState extends State<NisarApp> {
  String _locale = 'es';

  void setLocale(String locale) {
    setState(() {
      _locale = locale;
    });
  }

  String get currentLocale => _locale;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'NISAR App',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xfff8fafb),
      colorScheme: ColorScheme.fromSeed(seedColor: green, primary: green),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        isDense: true,
      ),
    ),
    home: const SplashScreen(),
  );
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.api});
  final ApiService? api;
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final ApiService api;
  final controller = MapController();

  int page = 0, request = 0;
  String module = 'bosques';
  DateTime a = DateTime.now().subtract(const Duration(days: 60)),
      b = DateTime.now().subtract(const Duration(days: 12));
  List<LatLng> area = [];
  final Map<String, Map<String, dynamic>> results = {};
  SelectionMode mode = SelectionMode.rectangle;
  bool busy = false,
      aiBusy = false,
      advanced = false,
      showA = false;
  String? error, aiError, connection;
  Map<String, dynamic>? ai;
  final userContextController = TextEditingController();

  String _forestZoneId = forestZones.first.id;
  int _forestYear = 2020;
  int? _forestMonth;
  final Map<String, Map<String, dynamic>> _forestResults = {};
  final Map<int, bool> _yearHasData = {};
  bool _forestLoading = false;
  String? _forestError;
  Map<String, dynamic>? _forestAi;
  bool _forestAiLoading = false;
  String? _forestAiError;

  String _glacierZoneId = glacierZones.first.id;
  final Map<String, Map<String, dynamic>> _glacierResults = {};
  bool _glacierLoading = false;
  String? _glacierError;
  Map<String, dynamic>? _glacierAi;
  bool _glacierAiLoading = false;
  String? _glacierAiError;

  Map<String, dynamic>? get result => results[module];

  String t(String key) {
    final lang = NisarApp.of(context)?.currentLocale ?? 'es';
    return localizedTexts[lang]?[key] ?? localizedTexts['es']?[key] ?? key;
  }

  List<String> get labelsList => [
    t('dashboard'),
    t('bosques'),
    t('hundimiento'),
    t('glaciares'),
  ];

  String day(DateTime d) => d.toIso8601String().substring(0, 10);

  @override
  void initState() {
    super.initState();
    api = widget.api ?? ApiService();
    health();
  }

  @override
  void dispose() {
    api.close();
    controller.dispose();
    userContextController.dispose();
    super.dispose();
  }

  Future<void> health() async {
    try {
      await api.getHealth();
      if (mounted) setState(() => connection = t('serverAvailable'));
    } catch (e) {
      if (mounted) setState(() => connection = t('serverNoConnection'));
    }
  }

  void clearResultsModule() {
    results.clear();
    ai = null;
    aiError = null;
    error = null;
    busy = false;
    aiBusy = false;
  }

  void bumpRequestModule() => request++;

  void navigate(int index) {
    setState(() {
      page = index;
      if (index > 0) module = modules[index - 1];
      error = null;
      ai = null;
      aiError = null;
      area = [];
    });
    if (index == 1) _ensureForestLoaded();
    if (index == 3) _ensureGlacierLoaded();
  }

  void _ensureForestLoaded() {
    if (_forestResults.containsKey(_forestCacheKey(_forestZoneId, _forestYear, _forestMonth))) return;
    _loadForestChart();
  }

  void _ensureGlacierLoaded() {
    if (_glacierResults.containsKey(_glacierZoneId)) return;
    _loadGlacierChart();
  }

  void _addVertexOrRect(List<LatLng> current, LatLng p, SelectionMode currentMode) {
    if (currentMode == SelectionMode.polygon) {
      if (current.length < 50) current.add(p);
    } else {
      current
        ..clear()
        ..addAll([
          LatLng(p.latitude - .01, p.longitude - .01),
          LatLng(p.latitude - .01, p.longitude + .01),
          LatLng(p.latitude + .01, p.longitude + .01),
          LatLng(p.latitude + .01, p.longitude - .01),
        ]);
    }
  }

  void tap(LatLng p) {
    setState(() {
      bumpRequestModule();
      error = null;
      _addVertexOrRect(area, p, mode);
    });
  }

  Future<void> date(bool first) async {
    final chosen = await showDatePicker(
      context: context,
      initialDate: first ? a : b,
      firstDate: DateTime(2012, 9, 12),
      lastDate: DateTime.now(),
    );
    if (chosen != null && mounted) {
      setState(() {
        clearResultsModule();
        bumpRequestModule();
        if (first) {
          a = chosen;
        } else {
          b = chosen;
        }
      });
    }
  }

  Future<void> _calculateFor({
    required String moduleName,
    required List<LatLng> polygon,
    required bool isAdvanced,
    required DateTime dateA,
    required DateTime dateB,
    required int id,
    required Map<String, Map<String, dynamic>> store,
    required void Function(bool) setBusy,
    required void Function(String?) setError,
  }) async {
    setBusy(true);
    setError(null);
    try {
      final payload = <String, dynamic>{
        'module': moduleName,
        'polygon': polygon.map((p) => [p.latitude, p.longitude]).toList(),
        if (isAdvanced) 'date_a': day(dateA),
        if (isAdvanced) 'date_b': day(dateB),
      };
      final data = await api.getMetrics(payload);
      if (mounted && id == request) {
        setState(() => store[moduleName] = data);
        if (moduleName == 'bosques' || moduleName == 'glaciares') {
          _interpretFor(
            id: id,
            selectedModule: moduleName,
            currentResult: data,
            userContext: userContextController,
            setAiBusy: (v) => setState(() => aiBusy = v),
            setAiError: (v) => setState(() => aiError = v),
            setAi: (v) => setState(() => ai = v),
          );
        }
      }
    } catch (e) {
      if (mounted && id == request) {
        setError(e.toString());
      }
    } finally {
      if (mounted) setBusy(false);
    }
  }

  Future<void> calculate() async {
    if (busy) {
      setState(() => error = 'Ya hay un análisis de gráfico en curso. Espera un momento.');
      return;
    }
    if (area.length < 3 || (advanced && !a.isBefore(b))) {
      setState(() => error = 'Selecciona un área y dos fechas en orden.');
      return;
    }
    final id = ++request;
    await _calculateFor(
      moduleName: module,
      polygon: area,
      isAdvanced: advanced,
      dateA: a,
      dateB: b,
      id: id,
      store: results,
      setBusy: (v) => setState(() => busy = v),
      setError: (v) => setState(() => error = v),
    );
  }

  Future<void> _interpretFor({
    required int id,
    required String selectedModule,
    required Map<String, dynamic>? currentResult,
    required TextEditingController userContext,
    required void Function(bool) setAiBusy,
    required void Function(String?) setAiError,
    required void Function(Map<String, dynamic>?) setAi,
  }) async {
    final resultId = currentResult?['result_id'];
    if (resultId == null) return;
    setAiBusy(true);
    setAiError(null);
    try {
      final value = await api.interpret(
        resultId as String,
        userContext: userContext.text,
      );
      if (mounted && id == request && selectedModule == module) {
        setAi(value);
      }
    } catch (e) {
      if (mounted && id == request && selectedModule == module) {
        setAiError(e.toString());
      }
    } finally {
      if (mounted) setAiBusy(false);
    }
  }

  Future<void> interpret() => _interpretFor(
        id: request,
        selectedModule: module,
        currentResult: result,
        userContext: userContextController,
        setAiBusy: (v) => setState(() => aiBusy = v),
        setAiError: (v) => setState(() => aiError = v),
        setAi: (v) => setState(() => ai = v),
      );

  String _forestCacheKey(String zoneId, int year, int? month) =>
      '$zoneId|$year|${month ?? 'all'}';

  ForestZone get _currentForestZone =>
      forestZones.firstWhere((z) => z.id == _forestZoneId);

  GlacierZone get _currentGlacierZone =>
      glacierZones.firstWhere((z) => z.id == _glacierZoneId);

  Future<void> _loadForestChart({bool force = false}) async {
    if (busy || _forestLoading) return;
    final key = _forestCacheKey(_forestZoneId, _forestYear, _forestMonth);
    if (!force && _forestResults.containsKey(key)) {
      final cached = _forestResults[key];
      if (cached != null && cached['result_id'] != null && _forestAi == null) {
        await _interpretForest(cached);
      }
      return;
    }
    setState(() {
      _forestLoading = true;
      _forestError = null;
      _forestAi = null;
      _forestAiError = null;
    });
    final zone = _currentForestZone;
    final dateA = _forestMonth == null
        ? DateTime(_forestYear, 1, 1)
        : DateTime(_forestYear, _forestMonth!, 1);
    final dateB = _forestMonth == null
        ? DateTime(_forestYear, 12, 31)
        : DateTime(
            _forestYear,
            _forestMonth!,
            DateUtils.getDaysInMonth(_forestYear, _forestMonth!),
          );
    try {
      final data = await api.getMetrics({
        'module': 'bosques',
        'polygon': zone.polygon.map((p) => [p.latitude, p.longitude]).toList(),
        'date_a': day(dateA),
        'date_b': day(dateB),
      });
      if (!mounted) return;
      final hasArea = (data['snapshots'] as List?)?.isNotEmpty == true &&
          ((data['snapshots'][1]['area_ha'] as num?) ?? 0) > 0;
      setState(() {
        _forestResults[key] = data;
        _yearHasData[_forestYear] = hasArea;
        _forestLoading = false;
      });
      if (hasArea) await _interpretForest(data);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _forestError = e.toString();
        _yearHasData[_forestYear] = false;
        _forestLoading = false;
      });
    }
  }

  Future<void> _interpretForest(Map<String, dynamic>? data) async {
    final resultId = data?['result_id'];
    if (resultId == null) return;
    setState(() {
      _forestAiLoading = true;
      _forestAiError = null;
    });
    try {
      final value = await api.interpret(resultId as String);
      if (mounted) setState(() => _forestAi = value);
    } catch (e) {
      if (mounted) setState(() => _forestAiError = e.toString());
    } finally {
      if (mounted) setState(() => _forestAiLoading = false);
    }
  }

  Future<void> _loadGlacierChart({bool force = false}) async {
    if (busy || _glacierLoading) return;
    final zone = _currentGlacierZone;
    if (!force && _glacierResults.containsKey(zone.id)) {
      final cached = _glacierResults[zone.id];
      if (cached != null && cached['result_id'] != null && _glacierAi == null) {
        await _interpretGlacier(cached);
      }
      return;
    }
    setState(() {
      _glacierLoading = true;
      _glacierError = null;
      _glacierAi = null;
      _glacierAiError = null;
    });
    try {
      final data = await api.getMetrics({
        'module': 'glaciares',
        'polygon': zone.polygon.map((p) => [p.latitude, p.longitude]).toList(),
      });
      if (!mounted) return;
      setState(() {
        _glacierResults[zone.id] = data;
        _glacierLoading = false;
      });
      await _interpretGlacier(data);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _glacierError = e.toString();
        _glacierLoading = false;
      });
    }
  }

  Future<void> _interpretGlacier(Map<String, dynamic>? data) async {
    final resultId = data?['result_id'];
    if (resultId == null) return;
    setState(() {
      _glacierAiLoading = true;
      _glacierAiError = null;
    });
    try {
      final value = await api.interpret(resultId as String);
      if (mounted) setState(() => _glacierAi = value);
    } catch (e) {
      if (mounted) setState(() => _glacierAiError = e.toString());
    } finally {
      if (mounted) setState(() => _glacierAiLoading = false);
    }
  }

  (double, double) _forestProportion(Map<String, dynamic>? res) {
    if (res == null) return (0, 0);
    final snaps = res['snapshots'] as List?;
    if (snaps == null || snaps.length < 2) return (0, 0);
    final inicial = (snaps[0]['area_ha'] as num?)?.toDouble() ?? 0;
    final vivo = (snaps[1]['area_ha'] as num?)?.toDouble() ?? 0;
    return (vivo, inicial);
  }

  double _glacierFraction(Map<String, dynamic>? res) {
    if (res == null) return 0;
    final coh = (res['mean_coherence'] as num?)?.toDouble() ?? 0;
    return coh.clamp(0.0, 1.0);
  }

  Widget navigation(bool drawer) {
    final currentLang = NisarApp.of(context)?.currentLocale ?? 'es';
    final currentLabels = labelsList;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'NISAR App',
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
            ),
          ),
          for (int i = 0; i < currentLabels.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                selected: page == i,
                selectedTileColor: const Color(0xffe8f5ec),
                selectedColor: green,
                leading: Icon([
                  Icons.dashboard_outlined,
                  Icons.forest_outlined,
                  Icons.vertical_align_bottom,
                  Icons.ac_unit,
                ][i]),
                title: Text(currentLabels[i]),
                onTap: () {
                  navigate(i);
                  if (drawer) Navigator.pop(context);
                },
              ),
            ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.language, size: 18, color: Colors.black54),
                const SizedBox(width: 8),
                const Text('Idioma', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const Spacer(),
                DropdownButton<String>(
                  value: currentLang,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: 'es', child: Text('ES', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(value: 'en', child: Text('EN', style: TextStyle(fontSize: 13))),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      NisarApp.of(context)?.setLocale(val);
                      setState(() {});
                    }
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextButton.icon(
              onPressed: health,
              icon: const Icon(Icons.refresh),
              label: Text(connection ?? t('checkingServer')),
            ),
          ),
        ],
      ),
    );
  }

  Widget card(Widget child, {Color? color}) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: color ?? Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xffe5e9ed)),
    ),
    child: child,
  );

  Widget title(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      text,
      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
    ),
  );

  Widget map() => SizedBox(
    height: 420,
    child: Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: FlutterMap(
            mapController: controller,
            options: MapOptions(
              initialCenter: const LatLng(14.6349, -90.5069),
              initialZoom: 11,
              onTap: (_, p) => tap(p),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.nisar.monitoreo',
              ),
              PolygonLayer(
                polygons: [
                  if (area.length >= 3)
                    Polygon(
                      points: area,
                      color: Colors.blue.withValues(alpha: .12),
                      borderColor: Colors.blue,
                      borderStrokeWidth: 2,
                    ),
                ],
              ),
              CircleLayer(
                circles: [
                  for (final p in area)
                    CircleMarker(point: p, radius: 4, color: Colors.blue),
                  for (final p in (result?['points'] ?? []) as List)
                    CircleMarker(
                      point: LatLng(
                        (p['lat'] as num).toDouble(),
                        (p['lng'] as num).toDouble(),
                      ),
                      radius: 4,
                      color: (p['value'] as num) < 0
                          ? Colors.deepPurple
                          : Colors.orange,
                    ),
                ],
              ),
              const Align(
                alignment: Alignment.bottomRight,
                child: ColoredBox(
                  color: Colors.white,
                  child: Padding(
                    padding: EdgeInsets.all(5),
                    child: Text(
                      '© OpenStreetMap contributors',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          right: 12,
          top: 12,
          child: Column(
            children: [
              FloatingActionButton.small(
                heroTag: 'zoom_in',
                backgroundColor: Colors.white,
                foregroundColor: Colors.black87,
                onPressed: () {
                  final zoom = controller.camera.zoom + 1;
                  controller.move(controller.camera.center, zoom);
                },
                child: const Icon(Icons.add),
              ),
              const SizedBox(height: 8),
              FloatingActionButton.small(
                heroTag: 'zoom_out',
                backgroundColor: Colors.white,
                foregroundColor: Colors.black87,
                onPressed: () {
                  final zoom = controller.camera.zoom - 1;
                  controller.move(controller.camera.center, zoom);
                },
                child: const Icon(Icons.remove),
              ),
            ],
          ),
        ),
        Positioned(
          top: 12,
          left: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xffe5e9ed)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.swipe, size: 16, color: Colors.blue),
                const SizedBox(width: 6),
                Text(
                  NisarApp.of(context)?.currentLocale == 'en'
                      ? 'One finger: pan | Two fingers: zoom'
                      : 'Un dedo: desplazar | Dos dedos: zoom',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget chart(Map<String, dynamic>? res) {
    final values = (res?['chart'] ?? []) as List;
    if (values.isEmpty) {
      return Text(
        NisarApp.of(context)?.currentLocale == 'en'
            ? 'No chart yet. Select an area, dates and calculate metrics.'
            : 'Sin gráfica todavía. Selecciona un área, las fechas y calcula las métricas.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${res!['measurement']} · ${res['unit']}'),
        const SizedBox(height: 16),
        SizedBox(
          height: 235,
          child: BarChart(
            BarChartData(
              barGroups: [
                for (int i = 0; i < values.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: (values[i]['value'] as num).toDouble(),
                        width: 28,
                        color: green,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  ),
              ],
              gridData: const FlGridData(drawVerticalLine: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 52)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 38,
                    getTitlesWidget: (v, meta) {
                      final i = v.toInt();
                      return i >= 0 && i < values.length
                          ? Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                values[i]['label'] as String,
                                style: const TextStyle(fontSize: 10),
                              ),
                            )
                          : const SizedBox.shrink();
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
        for (final v in values)
          Text(
            '${v['label']}: ${(v['value'] as num).toStringAsFixed(3)} ${res['unit']}',
          ),
      ],
    );
  }

  Widget areaSummaryFor(List<LatLng> pts) {
    if (pts.length < 3) return const SizedBox.shrink();
    const radius = 6371008.8;
    double sum = 0;
    for (var i = 0; i < pts.length; i++) {
      final p = pts[i], q = pts[(i + 1) % pts.length];
      final dlon = (q.longitude - p.longitude) * math.pi / 180;
      sum += dlon * (2 + math.sin(p.latitude * math.pi / 180) + math.sin(q.latitude * math.pi / 180));
    }
    final km2 = (sum * radius * radius / 2).abs() / 1000000;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        NisarApp.of(context)?.currentLocale == 'en'
            ? 'Approx area: ${km2.toStringAsFixed(2)} km² (${(km2 * 100).toStringAsFixed(1)} ha).'
            : 'Área aproximada: ${km2.toStringAsFixed(2)} km² (${(km2 * 100).toStringAsFixed(1)} ha).',
      ),
    );
  }

  Widget areaSummary() => areaSummaryFor(area);

  Widget modeSelector({
    required SelectionMode value,
    required void Function(SelectionMode) onChanged,
    required bool disabled,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: SegmentedButton<SelectionMode>(
          segments: [
            ButtonSegment(
              value: SelectionMode.rectangle,
              label: Text(NisarApp.of(context)?.currentLocale == 'en' ? 'Rectangle' : 'Recuadro'),
              icon: const Icon(Icons.crop_square),
            ),
            ButtonSegment(
              value: SelectionMode.polygon,
              label: Text(NisarApp.of(context)?.currentLocale == 'en' ? 'Polygon' : 'Polígono'),
              icon: const Icon(Icons.polyline),
            ),
          ],
          selected: {value},
          onSelectionChanged: disabled ? null : (s) => onChanged(s.first),
        ),
      );

  Widget zonasChips({
    required String targetModule,
    required void Function(List<LatLng>) onSelect,
    required bool disabled,
  }) {
    final zonas = zonasPrecargadas[targetModule];
    if (zonas == null || zonas.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final entry in zonas.entries)
          ActionChip(
            avatar: Icon(
              targetModule == 'glaciares'
                  ? Icons.ac_unit
                  : targetModule == 'bosques'
                      ? Icons.forest
                      : Icons.location_city,
              size: 18,
              color: Colors.blue,
            ),
            label: Text(entry.key),
            onPressed: disabled ? null : () => onSelect(entry.value),
          ),
      ],
    );
  }

  Widget _aiSummaryCard({
    required Map<String, dynamic>? currentResult,
    required bool loading,
    required Map<String, dynamic>? analysis,
    required String? errorText,
  }) {
    if (currentResult == null) {
      return card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            title('Resumen del análisis (IA)'),
            const Text('El resumen aparecerá aquí en cuanto cargues un gráfico o calcules métricas.'),
          ],
        ),
      );
    }
    return card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title('Resumen del análisis (IA)'),
          if (loading)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
          else if (errorText != null)
            Text(errorText, style: const TextStyle(color: Colors.red))
          else if (analysis == null)
            const Text('No se pudo generar el resumen.')
          else ...[
            SelectableText(analysis['analysis']['summary'] as String, style: const TextStyle(fontSize: 15)),
          ],
        ],
      ),
    );
  }

  Widget _forestChartCard() {
    final zone = _currentForestZone;
    final key = _forestCacheKey(zone.id, _forestYear, _forestMonth);
    final data = _forestResults[key];
    final (vivo, inicial) = _forestProportion(data);
    final hasData = data != null && inicial > 0;
    final yearHasData = _yearHasData[_forestYear] ?? false;
    const monthNames = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];
    final fraction = inicial <= 0 ? 0.0 : (vivo / inicial).clamp(0.0, 1.0);

    return card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title('Proporción de bosque (inmersivo)'),
          const Text('La copa verde representa el bosque vivo; el gris, la superficie perdida.'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final z in forestZones)
                ChoiceChip(
                  label: Text(z.name),
                  selected: z.id == _forestZoneId,
                  onSelected: _forestLoading
                      ? null
                      : (_) {
                          setState(() {
                            _forestZoneId = z.id;
                            _forestError = null;
                            _forestAi = null;
                            _forestAiError = null;
                          });
                          _loadForestChart();
                        },
                ),
            ],
          ),
          const SizedBox(height: 12),
          _DateSelector(
            year: _forestYear,
            month: _forestMonth,
            firstYear: 2005,
            lastYear: DateTime.now().year,
            showMonths: yearHasData,
            monthNames: monthNames,
            onYearChanged: (y) {
              setState(() {
                _forestYear = y;
                _forestMonth = null;
                _forestError = null;
                _forestAi = null;
                _forestAiError = null;
              });
              _loadForestChart();
            },
            onMonthChanged: (m) {
              setState(() {
                _forestMonth = m;
                _forestError = null;
                _forestAi = null;
                _forestAiError = null;
              });
              _loadForestChart();
            },
            onRefresh: () => _loadForestChart(force: true),
          ),
          const SizedBox(height: 12),
          if (_forestLoading)
            const Center(child: CircularProgressIndicator())
          else if (_forestError != null)
            Text(_forestError!, style: const TextStyle(color: Colors.red))
          else if (!hasData)
            const Text('No hay superficie forestal cartografiada para esta zona y fecha.')
          else
            _SvgProportionChart(
              assetPath: 'assets/forest.svg',
              fraction: fraction,
              activeColor: green,
              inactiveColor: Colors.grey.shade400,
            ),
        ],
      ),
    );
  }

  Widget _glacierChartCard() {
    final zone = _currentGlacierZone;
    final data = _glacierResults[zone.id];
    final fraction = _glacierFraction(data);
    final hasData = data != null && fraction > 0;

    return card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title('Proporción de hielo (inmersivo)'),
          const Text('La parte azul representa hielo estable; el gris, pérdida de coherencia.'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final z in glacierZones)
                ChoiceChip(
                  label: Text(z.name),
                  selected: z.id == _glacierZoneId,
                  onSelected: _glacierLoading
                      ? null
                      : (_) {
                          setState(() {
                            _glacierZoneId = z.id;
                            _glacierError = null;
                            _glacierAi = null;
                            _glacierAiError = null;
                          });
                          _loadGlacierChart();
                        },
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_glacierLoading)
            const Center(child: CircularProgressIndicator())
          else if (_glacierError != null)
            Text(_glacierError!, style: const TextStyle(color: Colors.red))
          else if (!hasData)
            const Text('No hay producto GUNW disponible para esta zona.')
          else
            _SvgProportionChart(
              assetPath: 'assets/glacier.svg',
              fraction: fraction,
              activeColor: Colors.blue,
              inactiveColor: Colors.grey.shade400,
            ),
        ],
      ),
    );
  }

  Widget dashboardContent() => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text(
        NisarApp.of(context)?.currentLocale == 'en' ? 'Welcome to NISAR App' : 'Bienvenido a NISAR App',
        style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 16),
      Text(
        NisarApp.of(context)?.currentLocale == 'en'
            ? 'This application allows you to explore and analyze NASA (NISAR) and OpenStreetMap (OSM) satellite data to better understand changes on Earth\'s surface. Below is an overview of what you will find in each module:'
            : 'Esta aplicación te permite explorar y analizar datos satelitales de la NASA (NISAR) y de OpenStreetMap (OSM) para entender mejor los cambios en la superficie de la Tierra. A continuación, te explicamos qué encontrarás en cada uno de los módulos:',
        style: const TextStyle(fontSize: 15),
      ),
      const SizedBox(height: 24),
      
      // Módulo Bosques
      card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.forest, color: green, size: 28),
                const SizedBox(width: 12),
                Text(
                  NisarApp.of(context)?.currentLocale == 'en' ? 'Forests Module' : 'Módulo de Bosques',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: green,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              NisarApp.of(context)?.currentLocale == 'en'
                  ? 'Monitor forest health and loss using historical OpenStreetMap data to compare past states (from 2005) with current status.'
                  : 'Monitorea la salud y la pérdida de superficies forestales usando datos históricos de OpenStreetMap (desde 2005).',
            ),
          ],
        ),
      ),

      // Módulo Hundimiento
      card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.vertical_align_bottom, color: Colors.deepPurple, size: 28),
                const SizedBox(width: 12),
                Text(
                  NisarApp.of(context)?.currentLocale == 'en' ? 'Subsidence Module' : 'Módulo de Hundimiento',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.deepPurple,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              NisarApp.of(context)?.currentLocale == 'en'
                  ? 'Analyze ground displacement using radar interferometry (NISAR data) to detect subsidence or uplift.'
                  : 'Analiza el desplazamiento del terreno mediante interferometría radar (datos NISAR) para detectar hundimientos.',
            ),
          ],
        ),
      ),

      // Módulo Glaciares
      card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.ac_unit, color: blueIce, size: 28),
                const SizedBox(width: 12),
                Text(
                  NisarApp.of(context)?.currentLocale == 'en' ? 'Glaciers Module' : 'Módulo de Glaciares',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: blueIce,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              NisarApp.of(context)?.currentLocale == 'en'
                  ? 'Evaluate ice movement and stability in key global glaciers using NISAR GUNW products.'
                  : 'Evalúa el movimiento y la estabilidad del hielo en glaciares clave del planeta usando productos GUNW.',
            ),
          ],
        ),
      ),
    ],
  );

  Widget moduleContent() => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text(
        labelsList[page],
        style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 24),
      if (module == 'hundimiento') ...[
        card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title(t('areaAndPeriod')),
              if (zonasPrecargadas.containsKey(module)) ...[
                Text(t('preloadZones'), style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                zonasChips(
                  targetModule: module,
                  disabled: busy,
                  onSelect: (coords) {
                    final centro = LatLng(
                      coords.map((c) => c.latitude).reduce((a, b) => a + b) / coords.length,
                      coords.map((c) => c.longitude).reduce((a, b) => a + b) / coords.length,
                    );
                    controller.move(centro, 8);
                    setState(() {
                      clearResultsModule();
                      area = coords;
                    });
                  },
                ),
                const SizedBox(height: 16),
              ],
              modeSelector(
                value: mode,
                disabled: busy,
                onChanged: (m) => setState(() {
                  mode = m;
                  area = [];
                  bumpRequestModule();
                  error = null;
                }),
              ),
              const SizedBox(height: 4),
              areaSummary(),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => setState(() {
                              clearResultsModule();
                              bumpRequestModule();
                              area = [];
                            }),
                    child: Text(t('clearArea')),
                  ),
                  if (mode == SelectionMode.polygon && area.isNotEmpty)
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => setState(() {
                                bumpRequestModule();
                                area = area.sublist(0, area.length - 1);
                              }),
                      child: Text(t('undoVertex')),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: busy || area.length < 3 ? null : calculate,
                icon: const Icon(Icons.analytics_outlined),
                label: Text(busy ? t('calculating') : t('calculateMetrics')),
              ),
            ],
          ),
        ),
        card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title(t('mapTitle')),
              const SizedBox(height: 10),
              map(),
            ],
          ),
        ),
        card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title(t('metricsTitle')),
              chart(result),
            ],
          ),
        ),
      ],
      if (module == 'bosques' || module == 'glaciares') ...[
        if (module == 'bosques') _forestChartCard(),
        if (module == 'glaciares') _glacierChartCard(),
        if (module == 'bosques')
          _aiSummaryCard(
            currentResult: _forestResults[_forestCacheKey(_forestZoneId, _forestYear, _forestMonth)],
            loading: _forestAiLoading,
            analysis: _forestAi,
            errorText: _forestAiError,
          ),
        if (module == 'glaciares')
          _aiSummaryCard(
            currentResult: _glacierResults[_glacierZoneId],
            loading: _glacierAiLoading,
            analysis: _glacierAi,
            errorText: _glacierAiError,
          ),
        card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title(t('aiTitle')),
              const SizedBox(height: 12),
              TextField(
                controller: userContextController,
                maxLength: 1000,
                maxLines: 3,
                enabled: !aiBusy,
                decoration: InputDecoration(
                  labelText: NisarApp.of(context)?.currentLocale == 'en' ? 'Your query (Optional)' : 'Escribe tu consulta (Opcional)',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: aiBusy ? null : interpret,
                icon: const Icon(Icons.auto_awesome),
                label: Text(aiBusy ? t('aiInterpreting') : t('aiButton')),
              ),
              if (aiError != null)
                SelectableText(aiError!, style: const TextStyle(color: Colors.red)),
              if (ai != null) ...[
                const SizedBox(height: 12),
                SelectableText(ai!['analysis']['summary'] as String),
              ],
            ],
          ),
        ),
      ],
    ],
  );

  Widget content() {
    if (page == 0) return dashboardContent();
    return moduleContent();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      appBar: wide ? null : AppBar(title: Text(t('appTitle'))),
      drawer: wide ? null : Drawer(child: navigation(true)),
      body: Row(
        children: [
          if (wide)
            Material(
              color: Colors.white,
              child: SizedBox(
                width: 230,
                child: navigation(false),
              ),
            ),
          Expanded(child: content()),
        ],
      ),
    );
  }
}

class _DateSelector extends StatelessWidget {
  const _DateSelector({
    required this.year,
    required this.month,
    required this.firstYear,
    required this.lastYear,
    required this.showMonths,
    required this.monthNames,
    required this.onYearChanged,
    required this.onMonthChanged,
    required this.onRefresh,
  });

  final int year;
  final int? month;
  final int firstYear;
  final int lastYear;
  final bool showMonths;
  final List<String> monthNames;
  final ValueChanged<int> onYearChanged;
  final ValueChanged<int?> onMonthChanged;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final years = [for (var y = firstYear; y <= lastYear; y++) y];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        DropdownButton<int>(
          value: year,
          items: [
            for (final y in years)
              DropdownMenuItem(value: y, child: Text('$y')),
          ],
          onChanged: (y) {
            if (y != null) onYearChanged(y);
          },
        ),
        if (showMonths)
          DropdownButton<int?>(
            value: month,
            hint: const Text('Todo el año'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Todo el año')),
              for (var m = 1; m <= 12; m++)
                DropdownMenuItem(value: m, child: Text(monthNames[m - 1])),
            ],
            onChanged: onMonthChanged,
          ),
        IconButton(
          tooltip: 'Recargar',
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    );
  }
}

class _SvgProportionChart extends StatelessWidget {
  const _SvgProportionChart({
    required this.assetPath,
    required this.fraction,
    required this.activeColor,
    required this.inactiveColor,
  });

  final String assetPath;
  final double fraction;
  final Color activeColor;
  final Color inactiveColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 300,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          ColorFiltered(
            colorFilter: ColorFilter.mode(inactiveColor, BlendMode.srcIn),
            child: SvgPicture.asset(assetPath, fit: BoxFit.contain),
          ),
          ClipPath(
            clipper: _BottomRevealClipper(fraction: fraction),
            child: ColorFiltered(
              colorFilter: ColorFilter.mode(activeColor, BlendMode.srcIn),
              child: SvgPicture.asset(assetPath, fit: BoxFit.contain),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomRevealClipper extends CustomClipper<ui.Path> {
  _BottomRevealClipper({required this.fraction});
  final double fraction;

  @override
  ui.Path getClip(Size size) {
    final path = ui.Path();
    path.moveTo(0, size.height);
    path.lineTo(size.width, size.height);
    path.lineTo(size.width, size.height * (1 - fraction));
    path.lineTo(0, size.height * (1 - fraction));
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant _BottomRevealClipper oldClipper) =>
      oldClipper.fraction != fraction;
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.api});
  final ApiService? api;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  late final ApiService _api;
  String _statusMessage = 'Conectando con el servidor...';

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? ApiService();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      setState(() => _statusMessage = 'Verificando servidor...');
      await _api.getHealth();
      await Future.delayed(const Duration(milliseconds: 800));

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => DashboardScreen(api: _api),
        ),
      );
    } catch (e) {
      setState(() {
        _statusMessage = 'Sin conexión con el servidor. Reintentando...';
      });
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) _initializeApp();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff8fafb),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.satellite_alt_rounded,
                size: 80,
                color: Color(0xff16834a),
              ),
              const SizedBox(height: 24),
              const Text(
                'NISAR App',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xff16834a),
                ),
              ),
              const SizedBox(height: 32),
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xff9aa3ad),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}