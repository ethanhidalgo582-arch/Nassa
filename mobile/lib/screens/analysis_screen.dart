import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../app.dart';
import '../l10n.dart';
import '../services/api_service.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/map_panel.dart';
import '../widgets/results.dart';
import '../widgets/scenes.dart';

class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({super.key, required this.module});
  final ModuleStyle module;

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  final _map = MapController();
  final _search = TextEditingController();
  List<Map<String, dynamic>>? _found;
  bool _searching = false;
  ApiException? _searchError;
  LatLngBounds? _fit;
  bool _intro = true;
  String? _lastLang;

  late ModuleSession session;
  ModuleStyle get m => widget.module;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    session = AppServices.of(context).sessions[m.id]!;
    final lang = LocaleScope.of(context);
    if (_lastLang != null && _lastLang != lang) _maybeInterpret();
    _lastLang = lang;
    if (reduceMotion(context)) _intro = false;
  }

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _intro = false);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _map.dispose();
    super.dispose();
  }

  Map<String, dynamic>? get _config => AppServices.of(context).config.value;
  Map<String, dynamic> get _moduleConfig => ((_config?['modules'] as Map?)?[m.key] as Map?)?.cast<String, dynamic>() ?? {};
  double get _maxArea => ((_config?['limits'] as Map?)?['max_area_km2'] as num?)?.toDouble() ?? 20000;

  // ----------------------------------------------------------------- zone ---
  static double areaKm2(List<LatLng> pts) {
    if (pts.length < 3) return 0;
    const r = 6371008.8;
    double sum = 0;
    for (var i = 0; i < pts.length; i++) {
      final p = pts[i], q = pts[(i + 1) % pts.length];
      sum += (q.longitude - p.longitude) * math.pi / 180 *
          (2 + math.sin(p.latitude * math.pi / 180) + math.sin(q.latitude * math.pi / 180));
    }
    return (sum * r * r / 2).abs() / 1e6;
  }

  void _select(List<LatLng> pts, {String? note}) {
    AppServices.of(context).speech.stop();
    session.cancelJob(api: AppServices.of(context).api);
    session.setSelection(pts, note: note);
    setState(() => _fit = LatLngBounds.fromPoints(pts));
  }

  List<LatLng> _box(double s, double w, double n, double e) => [LatLng(n, w), LatLng(n, e), LatLng(s, e), LatLng(s, w)];

  /// Default box side (km) when a searched place is a point or is too large.
  double get _defaultSideKm => switch (m.id) { ModuleId.hundimiento => 8, _ => 15 };

  void _useSearchResult(Map<String, dynamic> r) {
    final lat = (r['lat'] as num).toDouble(), lon = (r['lon'] as num).toDouble();
    final b = r['bounds'] as List?;
    List<LatLng> pts;
    String? note;
    if (b != null) {
      pts = _box((b[0] as num).toDouble(), (b[1] as num).toDouble(), (b[2] as num).toDouble(), (b[3] as num).toDouble());
      final a = areaKm2(pts);
      if (a < 1 || a > math.min(_maxArea, 3000)) pts = const [];
    } else {
      pts = const [];
    }
    if (pts.isEmpty) {
      final half = _defaultSideKm / 2;
      final dLat = half / 111.32;
      final dLon = half / (111.32 * math.max(0.05, math.cos(lat * math.pi / 180)));
      pts = _box(lat - dLat, lon - dLon, lat + dLat, lon + dLon);
      note = LocaleScope.of(context) == 'es'
          ? 'Recuadro de ${_defaultSideKm.round()} km alrededor del lugar buscado. Ajústalo si lo necesitas.'
          : '${_defaultSideKm.round()} km box around the searched place. Adjust it if needed.';
    }
    _select(pts, note: note);
    setState(() => _found = null);
  }

  Future<void> _doSearch() async {
    final q = _search.text.trim();
    if (q.length < 2) return;
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final r = await AppServices.of(context).api.geocode(q, LocaleScope.of(context));
      if (mounted) setState(() => _found = r);
    } on ApiException catch (e) {
      if (mounted) setState(() => _searchError = e);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _onMapTap(LatLng p) {
    if (session.mode == DrawMode.rectangle) {
      if (session.draft.isEmpty) {
        session.update(() => session.draft = [p]);
      } else {
        final a = session.draft.first;
        _select(_box(math.min(a.latitude, p.latitude), math.min(a.longitude, p.longitude), math.max(a.latitude, p.latitude),
            math.max(a.longitude, p.longitude)));
      }
      return;
    }
    if (session.mode == DrawMode.polygon) {
      if (session.draft.length < 60) session.update(() => session.draft = [...session.draft, p]);
      return;
    }
    // query a forest cell
    final cells = ((session.result?['grid'] as Map?)?['cells'] as List?)?.cast<Map>();
    if (cells == null) return;
    final hit = cells.where((c) =>
        p.latitude >= (c['s'] as num) && p.latitude <= (c['n'] as num) && p.longitude >= (c['w'] as num) &&
        p.longitude <= (c['e'] as num));
    session.update(() => session.cell = hit.isEmpty ? null : hit.first.cast<String, dynamic>());
  }

  void _useVisibleArea() {
    final b = _map.camera.visibleBounds;
    final dLat = (b.north - b.south) * 0.1, dLon = (b.east - b.west) * 0.1;
    _select(_box(b.south + dLat, b.west + dLon, b.north - dLat, b.east - dLon));
  }

  // --------------------------------------------------------------- period ---
  String _periodText(BuildContext context) {
    final d = _moduleConfig['default'] as Map?;
    if (m.id == ModuleId.bosques) {
      final a = session.startYear ?? d?['start_year'];
      final b = session.endYear ?? d?['end_year'];
      return tr(context, 'period.years', {'a': '${a ?? '—'}', 'b': '${b ?? '—'}'});
    }
    final a = session.startDate?.toIso8601String().substring(0, 10) ?? d?['start_date'] as String?;
    final b = session.endDate?.toIso8601String().substring(0, 10) ?? d?['end_date'] as String?;
    return tr(context, 'period.dates', {'a': fmtDate(context, a), 'b': fmtDate(context, b)});
  }

  // -------------------------------------------------------------- actions ---
  void _analyze() {
    AppServices.of(context).speech.stop();
    session.analyze(AppServices.of(context).api).then((_) {});
  }

  void _maybeInterpret() {
    if (session.result != null && (_config?['gemini_configured'] ?? false) == true) {
      session.interpret(AppServices.of(context).api, LocaleScope.of(context));
    }
  }

  // ---------------------------------------------------------------- build ---
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        if (session.result != null) WidgetsBinding.instance.addPostFrameCallback((_) => _maybeInterpret());
        final wide = MediaQuery.sizeOf(context).width >= 1100;
        final mapWidget = _buildMap(context);
        final panel = _buildPanel(context, wide);
        final content = wide
            ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SizedBox(width: 470, child: panel),
                Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(0, 16, 16, 16), child: mapWidget)),
              ])
            : CustomScrollView(slivers: [
                SliverToBoxAdapter(child: _header(context)),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(height: math.min(460, MediaQuery.sizeOf(context).height * 0.55), child: mapWidget),
                  ),
                ),
                SliverPadding(padding: const EdgeInsets.all(16), sliver: SliverList.list(children: _sections(context))),
              ]);
        return Stack(children: [
          Positioned.fill(child: content),
          IgnorePointer(
            ignoring: !_intro,
            child: AnimatedOpacity(
              opacity: _intro ? 1 : 0,
              duration: const Duration(milliseconds: 450),
              child: _ModuleIntro(module: m),
            ),
          ),
        ]);
      },
    );
  }

  Widget _buildPanel(BuildContext context, bool wide) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [_header(context), ..._sections(context)],
      );

  Widget _header(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Row(children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: m.color.withValues(alpha: 0.4))),
            clipBehavior: Clip.antiAlias,
            child: AnimatedScene(builder: (t) => scenePainterFor(m.id, t), period: const Duration(seconds: 10)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Semantics(header: true, child: Text(tr(context, m.key), style: Theme.of(context).textTheme.headlineSmall)),
              Text(tr(context, '${m.key}.desc'), style: const TextStyle(color: Palette.muted)),
              const SizedBox(height: 2),
              Text(tr(context, '${m.key}.source'), style: TextStyle(color: m.color, fontWeight: FontWeight.w600, fontSize: 12.5)),
            ]),
          ),
        ]),
      );

  List<Widget> _sections(BuildContext context) {
    final s = session;
    final out = <Widget>[];
    final needsEarthdata = m.id != ModuleId.bosques && _config != null && _config!['earthdata_configured'] == false;
    if (needsEarthdata) {
      out.add(StatusCard(error: ApiException('not_configured', {
        'es': 'Este servidor aún no tiene credenciales de NASA Earthdata, necesarias para leer NISAR. Puedes preparar la zona, pero el análisis no se podrá ejecutar.',
        'en': 'This server has no NASA Earthdata credentials yet, required to read NISAR. You can prepare the area, but the analysis cannot run.',
      })));
      out.add(const SizedBox(height: 12));
    }
    if (s.result == null || s.running) {
      out.addAll([_zoneCard(context), const SizedBox(height: 12), _periodCard(context), const SizedBox(height: 14), _analyzeButton(context)]);
    } else {
      out.add(_compactSetup(context));
    }
    out.add(const SizedBox(height: 14));
    if (s.running) {
      out.add(StageLoader(module: m, stage: s.job?.stage ?? 'queued', onCancel: () {
        s.cancelJob(api: AppServices.of(context).api);
        s.update(() {});
      }));
    } else if (s.error != null) {
      out.add(StatusCard(
        error: s.error!,
        onRetry: _analyze,
        onChooseOther: () => s.update(() {
          s.error = null;
          s.mode = DrawMode.rectangle;
        }),
      ));
    } else if (s.result != null) {
      out.addAll(_resultSections(context, s.result!));
    }
    return out;
  }

  Widget _zoneCard(BuildContext context) {
    final s = session;
    final lang = LocaleScope.of(context);
    final area = areaKm2(s.selection);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _StepTitle(n: 1, text: tr(context, 'zone'), color: m.color, done: s.selection.length >= 3),
          Text(tr(context, 'zone.help'), style: const TextStyle(color: Palette.muted)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _doSearch(),
                decoration: InputDecoration(
                  hintText: tr(context, 'search.hint'),
                  prefixIcon: const Icon(Icons.search_rounded),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: _searching ? null : _doSearch,
              child: _searching
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(tr(context, 'search.button')),
            ),
          ]),
          if (_searchError != null)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text(_searchError!.message(lang), style: const TextStyle(color: Palette.error))),
          if (_found != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _found!.isEmpty
                  ? Text(tr(context, 'search.none'))
                  : Column(children: [
                      for (final r in _found!.take(5))
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.place_outlined, color: m.color),
                          title: Text(r['name'] as String, maxLines: 2, overflow: TextOverflow.ellipsis),
                          trailing: Text(tr(context, 'search.use'), style: TextStyle(color: m.color, fontWeight: FontWeight.w700)),
                          onTap: () => _useSearchResult(r),
                        ),
                    ]),
            ),
          const SizedBox(height: 12),
          Text(tr(context, 'examples'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in presets[m.id]!)
              ActionChip(
                avatar: Icon(m.icon, size: 18, color: m.color),
                label: Text(p.name[lang] ?? p.name['es']!),
                onPressed: () => _select(p.polygon),
              ),
          ]),
          const SizedBox(height: 12),
          Text(tr(context, 'draw'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ChoiceChip(
              avatar: const Icon(Icons.crop_square_rounded, size: 18),
              label: Text(tr(context, 'draw.rect')),
              selected: s.mode == DrawMode.rectangle,
              onSelected: (v) => s.update(() {
                s.mode = v ? DrawMode.rectangle : DrawMode.none;
                s.draft = [];
              }),
            ),
            ChoiceChip(
              avatar: const Icon(Icons.polyline_rounded, size: 18),
              label: Text(tr(context, 'draw.poly')),
              selected: s.mode == DrawMode.polygon,
              onSelected: (v) => s.update(() {
                s.mode = v ? DrawMode.polygon : DrawMode.none;
                s.draft = [];
              }),
            ),
            ActionChip(avatar: const Icon(Icons.fit_screen_rounded, size: 18), label: Text(tr(context, 'draw.view')), onPressed: _useVisibleArea),
          ]),
          if (s.mode != DrawMode.none)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: m.light, borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                Icon(Icons.touch_app_rounded, color: m.color),
                const SizedBox(width: 8),
                Expanded(child: Text(tr(context, s.mode == DrawMode.rectangle ? 'draw.rect.help' : 'draw.poly.help'))),
                if (s.mode == DrawMode.polygon) ...[
                  IconButton(tooltip: tr(context, 'draw.undo'), onPressed: s.draft.isEmpty ? null : () => s.update(() => s.draft = s.draft.sublist(0, s.draft.length - 1)),
                      icon: const Icon(Icons.undo_rounded)),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: m.color, minimumSize: const Size(40, 40)),
                    onPressed: s.draft.length >= 3 ? () => _select(List.of(s.draft)) : null,
                    child: Text(tr(context, 'draw.close')),
                  ),
                ],
              ]),
            ),
          const SizedBox(height: 12),
          Row(children: [
            Icon(s.selection.length >= 3 ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                color: s.selection.length >= 3 ? m.color : Palette.muted, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                s.selection.length >= 3 ? tr(context, 'area.selected', {'km2': fmtNum(context, area, decimals: area < 10 ? 2 : 0)}) : tr(context, 'area.none'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (s.selection.isNotEmpty)
              TextButton(onPressed: () => _select(const []), child: Text(tr(context, 'draw.clear'))),
          ]),
          if (area > _maxArea)
            Text(tr(context, 'area.too_big', {'max': fmtNum(context, _maxArea, decimals: 0)}), style: const TextStyle(color: Palette.error)),
          if (s.selectionNote != null)
            Padding(padding: const EdgeInsets.only(top: 4), child: Text(s.selectionNote!, style: const TextStyle(fontSize: 12.5, color: Palette.muted))),
        ]),
      ),
    );
  }

  Widget _periodCard(BuildContext context) {
    final s = session;
    final cfg = _moduleConfig;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _StepTitle(n: 2, text: tr(context, 'period'), color: m.color, done: true),
          Text(tr(context, 'period.auto'), style: const TextStyle(color: Palette.muted)),
          const SizedBox(height: 6),
          Row(children: [
            Icon(Icons.event_available_rounded, color: m.color),
            const SizedBox(width: 8),
            Expanded(child: Text(_periodText(context), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
          ]),
          if (m.id != ModuleId.bosques)
            Padding(padding: const EdgeInsets.only(top: 6), child: Text(tr(context, 'period.nisar_note'), style: const TextStyle(fontSize: 12.5, color: Palette.muted))),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              initiallyExpanded: s.advanced,
              onExpansionChanged: (v) => s.advanced = v,
              title: Text(tr(context, 'advanced'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              leading: const Icon(Icons.tune_rounded),
              childrenPadding: const EdgeInsets.only(bottom: 8),
              children: m.id == ModuleId.bosques ? _forestAdvanced(context, cfg) : _nisarAdvanced(context, cfg),
            ),
          ),
        ]),
      ),
    );
  }

  List<Widget> _forestAdvanced(BuildContext context, Map<String, dynamic> cfg) {
    final s = session;
    final first = (cfg['first_year'] as num?)?.toInt() ?? 2001;
    final last = (cfg['last_year'] as num?)?.toInt() ?? 2025;
    final d = cfg['default'] as Map?;
    final a = s.startYear ?? (d?['start_year'] as num?)?.toInt() ?? last - 9;
    final b = s.endYear ?? (d?['end_year'] as num?)?.toInt() ?? last;
    DropdownButtonFormField<int> dd(String label, int value, void Function(int) set) => DropdownButtonFormField<int>(
          initialValue: value,
          decoration: InputDecoration(labelText: label),
          items: [for (var y = first; y <= last; y++) DropdownMenuItem(value: y, child: Text('$y'))],
          onChanged: (v) {
            if (v != null) s.update(() => set(v));
            s.clearResult();
          },
        );
    return [
      Row(children: [
        Expanded(child: dd(tr(context, 'adv.start_year'), a, (v) {
          s.startYear = v;
          if ((s.endYear ?? b) < v) s.endYear = v;
        })),
        const SizedBox(width: 10),
        Expanded(child: dd(tr(context, 'adv.end_year'), b, (v) {
          s.endYear = v;
          if ((s.startYear ?? a) > v) s.startYear = v;
        })),
      ]),
      const SizedBox(height: 10),
      Text(tr(context, 'adv.canopy', {'v': '${s.canopy}'})),
      Slider(value: s.canopy.toDouble(), min: 10, max: 75, divisions: 13, label: '${s.canopy} %',
          onChanged: (v) => s.update(() => s.canopy = v.round()), onChangeEnd: (_) => s.clearResult()),
    ];
  }

  List<Widget> _nisarAdvanced(BuildContext context, Map<String, dynamic> cfg) {
    final s = session;
    final first = DateTime.tryParse(cfg['first_date'] as String? ?? '') ?? DateTime(2025, 10, 28);
    final d = cfg['default'] as Map?;
    final a = s.startDate ?? DateTime.tryParse(d?['start_date'] as String? ?? '') ?? first;
    final b = s.endDate ?? DateTime.tryParse(d?['end_date'] as String? ?? '') ?? DateTime.now();
    Future<void> pick(bool start) async {
      final v = await showDatePicker(
        context: context,
        initialDate: start ? a : b,
        firstDate: first.subtract(const Duration(days: 60)),
        lastDate: DateTime.now(),
        locale: Locale(LocaleScope.of(context)),
      );
      if (v == null) return;
      s.update(() {
        if (start) {
          s.startDate = v;
          if (!v.isBefore(s.endDate ?? b)) s.endDate = v.add(const Duration(days: 12));
        } else {
          s.endDate = v;
          if (!(s.startDate ?? a).isBefore(v)) s.startDate = v.subtract(const Duration(days: 12));
        }
      });
      s.clearResult();
    }

    return [
      Row(children: [
        Expanded(child: OutlinedButton.icon(onPressed: () => pick(true), icon: const Icon(Icons.event_rounded),
            label: Text('${tr(context, 'adv.start_date')}: ${fmtDate(context, a.toIso8601String())}'))),
        const SizedBox(width: 8),
        Expanded(child: OutlinedButton.icon(onPressed: () => pick(false), icon: const Icon(Icons.event_rounded),
            label: Text('${tr(context, 'adv.end_date')}: ${fmtDate(context, b.toIso8601String())}'))),
      ]),
      const SizedBox(height: 10),
      Text(tr(context, 'adv.coherence', {'v': s.coherence.toStringAsFixed(2)})),
      Slider(value: s.coherence, min: 0.2, max: 0.7, divisions: 10, label: s.coherence.toStringAsFixed(2),
          onChanged: (v) => s.update(() {
                s.coherence = v;
                s.advanced = true;
              }),
          onChangeEnd: (_) => s.clearResult()),
    ];
  }

  Widget _analyzeButton(BuildContext context) {
    final s = session;
    final ok = s.selection.length >= 3 && areaKm2(s.selection) <= _maxArea && !s.running;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _StepTitle(n: 3, text: tr(context, 'step4'), color: m.color, done: false),
      FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: m.color, minimumSize: const Size.fromHeight(56)),
        onPressed: ok ? _analyze : null,
        icon: Icon(s.running ? Icons.hourglass_top_rounded : Icons.play_arrow_rounded),
        label: Text(tr(context, 'analyze')),
      ),
      if (s.selection.length < 3)
        Padding(padding: const EdgeInsets.only(top: 6), child: Text(tr(context, 'analyze.need_zone'), textAlign: TextAlign.center,
            style: const TextStyle(color: Palette.muted))),
    ]);
  }

  /// After a result: compact zone/period summary with a way back to editing.
  Widget _compactSetup(BuildContext context) {
    final s = session;
    final sel = (s.result?['selection'] as Map?)?['area_km2'] as num?;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(children: [
          Icon(Icons.crop_free_rounded, color: m.color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(context, 'area.selected', {'km2': fmtNum(context, sel, decimals: (sel ?? 0) < 10 ? 2 : 0)}),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(_resultPeriod(context), style: const TextStyle(color: Palette.muted, fontSize: 13)),
            ]),
          ),
          TextButton.icon(
            onPressed: () {
              AppServices.of(context).speech.stop();
              s.clearResult();
            },
            icon: const Icon(Icons.edit_rounded),
            label: Text(tr(context, 'period.change')),
          ),
        ]),
      ),
    );
  }

  String _resultPeriod(BuildContext context) {
    final p = (session.result?['period'] as Map?) ?? const {};
    if (m.id == ModuleId.bosques) return loc(context, p['label']);
    return '${fmtDate(context, p['start'] as String?)} → ${fmtDate(context, p['end'] as String?)}';
  }

  List<Widget> _resultSections(BuildContext context, Map<String, dynamic> r) {
    final s = session;
    final lang = LocaleScope.of(context);
    final services = AppServices.of(context);
    const gap = SizedBox(height: 14);
    return [
      SummaryCard(
        module: m,
        result: r,
        speech: services.speech,
        ai: s.ai[lang],
        fetchAudio: ((_config?['tts'] as Map?)?['gemini'] ?? false) == true
            ? (part) async {
                if (part > 1) return null;
                // Part 0: computed summary (plays first). Part 1: Gemini explanation, same language.
                if (part == 1) {
                  await s.ensureInterpretation(services.api, lang);
                  if (s.ai[lang] == null) return null;
                }
                return services.api.speechAudio(r['result_id'] as String, lang, part: part);
              }
            : null,
      ),
      gap,
      SectionTitle(tr(context, 'metrics'), icon: Icons.dashboard_outlined),
      MetricsGrid(module: m, result: r),
      if (m.id == ModuleId.bosques) ...[
        gap,
        _cellInfo(context),
      ],
      gap,
      switch (m.id) {
        ModuleId.bosques => ForestChart(result: r),
        ModuleId.hundimiento => SubsidenceCharts(result: r, color: m.color),
        ModuleId.glaciares => GlacierChart(result: r, color: m.color),
      },
      gap,
      AiCard(
        module: m,
        ai: s.ai[lang],
        loading: s.aiLoading.contains(lang),
        error: s.aiError[lang],
        onRequest: () => s.interpret(services.api, lang, force: true),
        configured: (_config?['gemini_configured'] ?? true) == true,
      ),
      gap,
      DetailsCard(result: r),
      const SizedBox(height: 24),
      OutlinedButton.icon(onPressed: _analyze, icon: const Icon(Icons.refresh_rounded), label: Text(tr(context, 'analyze.again'))),
    ];
  }

  Widget _cellInfo(BuildContext context) {
    final c = session.cell;
    if (c == null) {
      return Row(children: [
        const Icon(Icons.ads_click_rounded, size: 18, color: Palette.muted),
        const SizedBox(width: 8),
        Expanded(child: Text(tr(context, 'tap_cell'), style: const TextStyle(color: Palette.muted))),
      ]);
    }
    return Card(
      color: Palette.forestLight,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(tr(context, 'cell.title'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const Spacer(),
            IconButton(visualDensity: VisualDensity.compact, tooltip: tr(context, 'draw.clear'),
                onPressed: () => session.update(() => session.cell = null), icon: const Icon(Icons.close, size: 18)),
          ]),
          Text(tr(context, 'cell.loss', {'v': fmtNum(context, c['loss_ha'] as num?)})),
          Text(tr(context, 'cell.forest', {'v': fmtNum(context, c['forest_start_ha'] as num?)})),
          Text(tr(context, 'cell.nodata', {'v': fmtNum(context, c['no_data_pct'] as num?)})),
          if (c['main_loss_year'] != null) Text(tr(context, 'cell.year', {'v': '${c['main_loss_year']}'})),
        ]),
      ),
    );
  }

  // ------------------------------------------------------------------ map ---
  Widget _buildMap(BuildContext context) {
    final r = session.result;
    final layers = (r?['layers'] as Map?) ?? const {};
    final overlays = <OverlaySpec>[];
    void add(String id, String key, {bool visible = true}) {
      final o = OverlaySpec.fromJson(id, tr(context, key), layers[id], visible: visible);
      if (o != null) overlays.add(o);
    }

    if (m.id == ModuleId.bosques) {
      add('forest_start', 'layer.forest');
      add('loss', 'layer.loss');
      add('no_data', 'layer.nodata');
    } else {
      add('displacement', 'layer.displacement');
      add('no_data', 'layer.nodata');
    }
    final outlines = <List<LatLng>>[
      for (final f in (((r?['outlines'] as Map?)?['features'] as List?) ?? const [])) ...polygonsFromGeoJson((f as Map)['geometry']),
    ];
    final cell = session.cell;
    return MapPanel(
      key: ValueKey('map-${m.key}'),
      module: m,
      controller: _map,
      selection: session.selection,
      draft: session.draft,
      overlays: _cachedOverlays(overlays, r?['result_id'] as String?),
      outlines: outlines,
      highlight: cell == null
          ? null
          : _box((cell['s'] as num).toDouble(), (cell['w'] as num).toDouble(), (cell['n'] as num).toDouble(), (cell['e'] as num).toDouble()),
      legend: r == null ? null : _legend(context, r),
      periodLabel: r == null ? null : '${tr(context, 'map')}: ${_resultPeriod(context)}',
      onTap: _onMapTap,
      busyLabel: session.running ? tr(context, 'stage.${session.job?.stage ?? 'queued'}') : null,
      fitBounds: _fit ?? (session.selection.length >= 3 ? LatLngBounds.fromPoints(session.selection) : null),
      cartoKey: (_config?['tiles'] as Map?)?['carto_key'] as String?,
    );
  }

  // Keep decoded images (and their visibility toggles) stable across rebuilds.
  String? _overlayKey;
  List<OverlaySpec> _overlayCache = const [];
  List<OverlaySpec> _cachedOverlays(List<OverlaySpec> fresh, String? resultId) {
    final key = '$resultId|${LocaleScope.of(context)}';
    if (key != _overlayKey) {
      final old = {for (final o in _overlayCache) o.id: o.visible};
      for (final o in fresh) {
        o.visible = old[o.id] ?? o.visible;
      }
      _overlayCache = fresh;
      _overlayKey = key;
    }
    return _overlayCache;
  }

  Widget _legend(BuildContext context, Map<String, dynamic> r) {
    final legend = (r['legend'] as Map?) ?? const {};
    final lang = LocaleScope.of(context);
    if (m.id == ModuleId.bosques) {
      final classes = (legend['loss_classes'] as List).cast<Map>();
      return LegendRows(rows: [
        for (final c in classes)
          (hexColor(c['color'] as String),
              lang == 'es'
                  ? 'Pérdida en ${c['min_pct'] == 0 ? '>0' : c['min_pct']}–${c['max_pct']} % de la celda'
                  : 'Loss in ${c['min_pct'] == 0 ? '>0' : c['min_pct']}–${c['max_pct']} % of the cell',
              false),
        (Palette.green.withValues(alpha: 0.55), tr(context, 'layer.forest'), false),
        (Palette.noData, tr(context, 'layer.nodata'), true),
      ], note: loc(context, legend));
    }
    final classes = (legend['classes'] as List).cast<Map>();
    final pick = [0, 2, classes.length ~/ 2, classes.length - 3, classes.length - 1];
    String range(Map c) => '${fmtNum(context, c['min'] as num, decimals: 0)} … ${fmtNum(context, c['max'] as num, decimals: 0)} mm';
    return LegendRows(rows: [
      for (final i in pick)
        (hexColor(classes[i]['color'] as String),
            '${range(classes[i])}${i == 0 ? (lang == 'es' ? ' · se aleja' : ' · away') : (i == classes.length - 1 ? (lang == 'es' ? ' · se acerca' : ' · towards') : '')}',
            false),
      (Palette.noData, tr(context, 'layer.nodata'), true),
    ], note: loc(context, legend));
  }
}

class _StepTitle extends StatelessWidget {
  const _StepTitle({required this.n, required this.text, required this.color, required this.done});
  final int n;
  final String text;
  final Color color;
  final bool done;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: done ? color : color.withValues(alpha: 0.15),
            child: done
                ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                : Text('$n', style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13)),
          ),
          const SizedBox(width: 10),
          Semantics(header: true, child: Text(text, style: Theme.of(context).textTheme.titleMedium)),
        ]),
      );
}

/// Short themed entrance animation for each module (skipped with reduced motion).
class _ModuleIntro extends StatelessWidget {
  const _ModuleIntro({required this.module});
  final ModuleStyle module;

  @override
  Widget build(BuildContext context) => Stack(children: [
        Positioned.fill(child: AnimatedScene(builder: (t) => scenePainterFor(module.id, t), period: const Duration(seconds: 4))),
        Positioned.fill(child: ColoredBox(color: module.color.withValues(alpha: 0.25))),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(module.icon, color: module.color, size: 32),
              const SizedBox(width: 12),
              Text(tr(context, module.key), style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: module.color)),
            ]),
          ),
        ),
      ]);
}
