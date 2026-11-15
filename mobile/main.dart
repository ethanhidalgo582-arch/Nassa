import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'services/api_service.dart';

void main() => runApp(const NisarApp());
const green = Color(0xff16834a);
const blueIce = Color(0xff2f80ed);
const greyLost = Color(0xff9aa3ad);

// Ilustraciones SVG personalizadas para las tarjetas del Dashboard
const String _svgForestIllustration = '''
<svg viewBox="0 0 120 80" xmlns="http://www.w3.org/2000/svg">
  <rect x="26" y="54" width="6" height="16" rx="2" fill="#6D4C41"/>
  <polygon points="29,18 12,56 46,56" fill="#2E7D32"/>
  <polygon points="29,10 15,40 43,40" fill="#43A047"/>
  <rect x="84" y="54" width="6" height="16" rx="2" fill="#6D4C41"/>
  <polygon points="87,20 70,56 104,56" fill="#2E7D32"/>
  <polygon points="87,12 73,42 101,42" fill="#43A047"/>
  <rect x="55" y="50" width="8" height="20" rx="2" fill="#5D4037"/>
  <polygon points="59,12 36,54 82,54" fill="#1B5E20"/>
  <polygon points="59,4 40,36 78,36" fill="#16834a"/>
  <ellipse cx="60" cy="71" rx="48" ry="4" fill="#C8E6C9"/>
</svg>
''';

const String _svgEarthquakeIllustration = '''
<svg viewBox="0 0 120 80" xmlns="http://www.w3.org/2000/svg">
  <path d="M12,38 L34,38 L44,58 L54,44 L64,64 L76,42 L86,38 L108,38 L108,68 L12,68 Z" fill="#EDE7F6"/>
  <polyline points="12,38 34,38 44,58 54,44 64,64 76,42 86,38 108,38" fill="none" stroke="#5E35B1" stroke-width="3.5" stroke-linejoin="round"/>
  <polyline points="44,58 49,68 41,74" fill="none" stroke="#4527A0" stroke-width="2.5" stroke-linecap="round"/>
  <polyline points="64,64 60,72 67,76" fill="none" stroke="#4527A0" stroke-width="2.5" stroke-linecap="round"/>
  <polyline points="22,22 36,22 42,12 49,30 56,8 63,28 70,14 76,22 98,22" fill="none" stroke="#D32F2F" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
''';

const String _svgIcebergIllustration = '''
<svg viewBox="0 0 120 80" xmlns="http://www.w3.org/2000/svg">
  <polygon points="34,42 46,16 60,24 72,10 88,42" fill="#E3F2FD" stroke="#2F80ED" stroke-width="2" stroke-linejoin="round"/>
  <polygon points="60,24 72,10 88,42 64,42" fill="#BBDEFB"/>
  <polygon points="34,42 88,42 96,56 76,72 44,70 26,54" fill="#90CAF9" opacity="0.75"/>
  <polygon points="64,42 88,42 96,56 76,72 60,58" fill="#64B5F6" opacity="0.85"/>
  <path d="M12,42 Q26,38 40,42 T68,42 T96,42 T110,42" fill="none" stroke="#1565C0" stroke-width="3" stroke-linecap="round"/>
  <path d="M18,50 Q34,47 50,50 T82,50 T104,50" fill="none" stroke="#2F80ED" stroke-width="1.8" stroke-linecap="round" opacity="0.7"/>
</svg>
''';

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
    'metricsTitle': 'Interpretación del análisis',
    'aiTitle': 'Interpretación con Gemini e Impacto Humano',
    'aiButton': 'Consultar a Gemini',
    'aiInterpreting': 'Interpretando…',
    'askGeminiFirst': 'Primero calcula las métricas para poder consultar a Gemini.',
    'geminiResult': 'Interpretación de Gemini:',
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
    'metricsTitle': 'Analysis interpretation',
    'aiTitle': 'Gemini Interpretation & Human Impact',
    'aiButton': 'Ask Gemini',
    'aiInterpreting': 'Interpreting…',
    'askGeminiFirst': 'First calculate the metrics to be able to query Gemini.',
    'geminiResult': 'Gemini interpretation:',
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
  const ForestZone({
    required this.id,
    required this.name,
    required this.coordsLabel,
    required this.polygon,
  });
  final String id;
  final String name;
  final String coordsLabel;
  final List<LatLng> polygon;
}

const List<ForestZone> forestZones = [
  ForestZone(
    id: 'amazonas',
    name: 'Amazonas (Brasil)',
    coordsLabel: '3.47°S, 62.20°W • NISAR L-Band SAR',
    polygon: [LatLng(-3.46, -62.21), LatLng(-3.46, -62.19), LatLng(-3.48, -62.19), LatLng(-3.48, -62.21)],
  ),
  ForestZone(
    id: 'peten',
    name: 'Petén (Guatemala)',
    coordsLabel: '16.92°N, 89.88°W • NISAR L-Band SAR',
    polygon: [LatLng(16.93, -89.89), LatLng(16.93, -89.87), LatLng(16.91, -89.87), LatLng(16.91, -89.89)],
  ),
];

class GlacierZone {
  const GlacierZone({
    required this.id,
    required this.name,
    required this.coordsLabel,
    required this.polygon,
  });
  final String id;
  final String name;
  final String coordsLabel;
  final List<LatLng> polygon;
}

const List<GlacierZone> glacierZones = [
  GlacierZone(
    id: 'groenlandia',
    name: 'Groenlandia',
    coordsLabel: '69.20°N, 49.98°W • NISAR GUNW L-Band',
    polygon: [LatLng(69.21, -49.99), LatLng(69.21, -49.97), LatLng(69.19, -49.97), LatLng(69.19, -49.99)],
  ),
  GlacierZone(
    id: 'thwaites',
    name: 'Thwaites (Antártida)',
    coordsLabel: '75.51°S, 106.74°W • NISAR GUNW L-Band',
    polygon: [LatLng(-75.50, -106.75), LatLng(-75.50, -106.73), LatLng(-75.52, -106.73), LatLng(-75.52, -106.75)],
  ),
  GlacierZone(
    id: 'perito_moreno',
    name: 'Perito Moreno (Arg)',
    coordsLabel: '50.50°S, 73.12°W • NISAR GUNW L-Band',
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

  final ValueNotifier<String> localeNotifier = ValueNotifier('es');

  void setLocale(String locale) {
    if (_locale == locale) return;
    setState(() => _locale = locale);
    localeNotifier.value = locale;
  }

  String get currentLocale => _locale;

  @override
  void dispose() {
    localeNotifier.dispose();
    super.dispose();
  }

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
      showA = false,
      nisarRadarMode = true; // Modo imagen satelital radar NISAR activado por defecto
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NisarApp.of(context)?.localeNotifier.addListener(_onLocaleChanged);
    });
  }

  void _onLocaleChanged() {
    if (!mounted) return;
    setState(() {
      ai = null;
      aiError = null;
      _forestAi = null;
      _forestAiError = null;
      _glacierAi = null;
      _glacierAiError = null;
    });
    if (result?['result_id'] != null) {
      interpret();
    }
    final forestData =
        _forestResults[_forestCacheKey(_forestZoneId, _forestYear, _forestMonth)];
    if (forestData?['result_id'] != null) {
      _interpretForest(forestData);
    }
    final glacierData = _glacierResults[_glacierZoneId];
    if (glacierData?['result_id'] != null) {
      _interpretGlacier(glacierData);
    }
  }

  @override
  void dispose() {
    NisarApp.of(context)?.localeNotifier.removeListener(_onLocaleChanged);
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
      bumpRequestModule();
      page = index;
      if (index > 0) module = modules[index - 1];
      busy = false;
      aiBusy = false;
      _forestAiLoading = false;
      _glacierAiLoading = false;
      error = null;
      aiError = null;
      ai = null;
      userContextController.clear();
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
    } catch (e) {
      if (mounted && id == request) {
        setError(e.toString());
      }
    } finally {
      if (mounted && id == request) {
        setBusy(false);
      }
    }
  }

  Future<void> calculate() async {
    if (busy) {
      setState(() => error = 'Ya hay un análisis en curso. Espera un momento.');
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
    final locale = NisarApp.of(context)?.currentLocale ?? 'es';
    setAiBusy(true);
    setAiError(null);
    try {
      final value = await api.interpret(
        resultId as String,
        userContext: userContext.text,
        locale: locale,
      );
      if (mounted && id == request && selectedModule == module) {
        setAi(value);
      }
    } catch (e) {
      if (mounted && id == request && selectedModule == module) {
        setAiError(e.toString());
      }
    } finally {
      if (mounted && id == request && selectedModule == module) {
        setAiBusy(false);
      }
    }
  }

  Future<void> interpret() async {
    Map<String, dynamic>? currentResult;
    
    if (module == 'bosques') {
      if (_forestLoading) {
        setState(() {
          aiError = NisarApp.of(context)?.currentLocale == 'en'
              ? 'Forest data is still loading. Please wait a moment.'
              : 'Los datos de bosques aún están cargando. Espera un momento.';
        });
        return;
      }
      final key = _forestCacheKey(_forestZoneId, _forestYear, _forestMonth);
      currentResult = _forestResults[key];
    } else if (module == 'glaciares') {
      if (_glacierLoading) {
        setState(() {
          aiError = NisarApp.of(context)?.currentLocale == 'en'
              ? 'Glacier data is still loading. Please wait a moment.'
              : 'Los datos de glaciares aún están cargando. Espera un momento.';
        });
        return;
      }
      currentResult = _glacierResults[_glacierZoneId];
    } else {
      currentResult = result;
    }

    if (currentResult == null || currentResult['result_id'] == null) {
      setState(() {
        aiError = NisarApp.of(context)?.currentLocale == 'en'
            ? 'First calculate or wait for metrics to load for this area to query Gemini.'
            : 'Primero calcula o espera a que carguen las métricas de esta área para poder consultar a Gemini.';
      });
      return;
    }

    setState(() => aiError = null);
    final id = ++request;

    await _interpretFor(
      id: id,
      selectedModule: module,
      currentResult: currentResult,
      userContext: userContextController,
      setAiBusy: (v) => setState(() => aiBusy = v),
      setAiError: (v) => setState(() => aiError = v),
      setAi: (v) {
        setState(() {
          ai = v;
          if (module == 'bosques') _forestAi = v;
          if (module == 'glaciares') _glacierAi = v;
        });
      },
    );
  }

  String _forestCacheKey(String zoneId, int year, int? month) =>
      '$zoneId|$year|${month ?? 'all'}';

  ForestZone get _currentForestZone =>
      forestZones.firstWhere((z) => z.id == _forestZoneId);

  GlacierZone get _currentGlacierZone =>
      glacierZones.firstWhere((z) => z.id == _glacierZoneId);

  Future<void> _loadForestChart({bool force = false}) async {
    if (_forestLoading) return;
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
    final locale = NisarApp.of(context)?.currentLocale ?? 'es';
    setState(() {
      _forestAiLoading = true;
      _forestAiError = null;
    });
    try {
      final value = await api.interpret(resultId as String, locale: locale);
      if (mounted && module == 'bosques') {
        setState(() => _forestAi = value);
      }
    } catch (e) {
      if (mounted && module == 'bosques') {
        setState(() => _forestAiError = e.toString());
      }
    } finally {
      if (mounted) setState(() => _forestAiLoading = false);
    }
  }

  Future<void> _loadGlacierChart({bool force = false}) async {
    if (_glacierLoading) return;
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
    final locale = NisarApp.of(context)?.currentLocale ?? 'es';
    setState(() {
      _glacierAiLoading = true;
      _glacierAiError = null;
    });
    try {
      final value = await api.interpret(resultId as String, locale: locale);
      if (mounted && module == 'glaciares') {
        setState(() => _glacierAi = value);
      }
    } catch (e) {
      if (mounted && module == 'glaciares') {
        setState(() => _glacierAiError = e.toString());
      }
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
                Text(
                  currentLang == 'en' ? 'Language' : 'Idioma',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
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

  // Tarjeta interactiva para el Dashboard con imagen SVG propia y navegación directa
  Widget _dashboardModuleCard({
    required String cardTitle,
    required String description,
    required String svgIllustration,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    final isEn = NisarApp.of(context)?.currentLocale == 'en';
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accentColor.withValues(alpha: 0.25), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 96,
                  height: 76,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: SvgPicture.string(svgIllustration, fit: BoxFit.contain),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cardTitle,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: accentColor,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        description,
                        style: const TextStyle(fontSize: 14, color: Colors.black87, height: 1.35),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Text(
                            isEn ? 'Explore module' : 'Explorar módulo',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: accentColor,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.arrow_forward_rounded, size: 16, color: accentColor),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

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

  // Galería cronológica de estado por año con contornos geográficos reales y radar NISAR
  Widget _yearlyEvolutionCard({required bool isForest}) {
    final isEn = NisarApp.of(context)?.currentLocale == 'en';
    final currentYear = DateTime.now().year;

    final years = isForest
        ? [for (var y = 2005; y <= currentYear; y++) y]
        : [for (var y = 2022; y <= currentYear; y++) y];

    final currentGlacierFraction =
        _glacierFraction(_glacierResults[_glacierZoneId]);

    double fractionForYear(int year) {
      if (isForest) {
        final key = _forestCacheKey(_forestZoneId, year, null);
        final cached = _forestResults[key];
        if (cached != null) {
          final (vivo, inicial) = _forestProportion(cached);
          if (inicial > 0) return (vivo / inicial).clamp(0.0, 1.0);
        }
        if (year == _forestYear) {
          final activeKey =
              _forestCacheKey(_forestZoneId, _forestYear, _forestMonth);
          final activeData = _forestResults[activeKey];
          if (activeData != null) {
            final (vivo, inicial) = _forestProportion(activeData);
            if (inicial > 0) return (vivo / inicial).clamp(0.0, 1.0);
          }
        }
        final span = math.max(1, currentYear - 2005);
        final progress = (year - 2005) / span;
        final base = _forestZoneId == 'amazonas' ? 0.96 : 0.94;
        final drop = _forestZoneId == 'amazonas' ? 0.14 : 0.18;
        return (base - (progress * drop)).clamp(0.0, 1.0);
      } else {
        final baseCurrent =
            currentGlacierFraction > 0 ? currentGlacierFraction : 0.85;
        final yearsBack = currentYear - year;
        final annualLoss = _glacierZoneId == 'thwaites'
            ? 0.035
            : (_glacierZoneId == 'groenlandia' ? 0.02 : 0.008);
        return (baseCurrent + (yearsBack * annualLoss)).clamp(0.0, 1.0);
      }
    }

    final zoneId = isForest ? _forestZoneId : _glacierZoneId;
    final activeColor = isForest ? green : blueIce;
    final zoneName =
        isForest ? _currentForestZone.name : _currentGlacierZone.name;

    return card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title(
            isEn
                ? 'NISAR Satellite & Contour Evolution — $zoneName'
                : 'Evolución satelital NISAR y contorno — $zoneName',
          ),
          Text(
            isEn
                ? (isForest
                    ? 'Geographic contour of $zoneName with NISAR L-band radar texture year by year (tap a year to inspect).'
                    : 'Geographic contour of $zoneName glacier with NISAR GUNW radar interferometry across years.')
                : (isForest
                    ? 'Contorno geográfico de $zoneName con imagen satelital radar NISAR banda-L año por año (toca un año para consultarlo).'
                    : 'Contorno geográfico del glaciar $zoneName con interferometría satelital NISAR GUNW a través de los años.'),
            style: const TextStyle(fontSize: 13, color: Colors.black54),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 168,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: years.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final y = years[index];
                final frac = fractionForYear(y);
                final pct = (frac * 100).round();
                final isSelected =
                    isForest ? y == _forestYear : y == currentYear;

                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: isForest && !_forestLoading
                      ? () {
                          setState(() {
                            _forestYear = y;
                            _forestMonth = null;
                            _forestError = null;
                            _forestAi = null;
                            _forestAiError = null;
                          });
                          _loadForestChart();
                        }
                      : null,
                  child: Container(
                    width: 112,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: nisarRadarMode
                          ? const Color(0xff0d1520)
                          : (isSelected
                              ? activeColor.withValues(alpha: 0.08)
                              : const Color(0xfff8fafb)),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? activeColor
                            : (nisarRadarMode
                                ? Colors.blueGrey.shade700
                                : const Color(0xffe0e5ea)),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$y',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: nisarRadarMode
                                ? Colors.white
                                : (isSelected ? activeColor : Colors.black87),
                          ),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 82,
                          width: 88,
                          child: CustomPaint(
                            painter: _GeoSatelliteContourPainter(
                              zoneId: zoneId,
                              fraction: frac,
                              activeColor: activeColor,
                              inactiveColor: nisarRadarMode
                                  ? Colors.blueGrey.shade800
                                  : Colors.grey.shade400,
                              radarMode: nisarRadarMode,
                              yearSeed: y,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          isEn
                              ? (isForest ? '$pct% forest' : '$pct% ice')
                              : (isForest ? '$pct% bosque' : '$pct% hielo'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: nisarRadarMode
                                ? (isForest
                                    ? Colors.greenAccent.shade200
                                    : Colors.lightBlueAccent.shade100)
                                : activeColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _aiSummaryCard({
    required Map<String, dynamic>? currentResult,
    required bool loading,
    required Map<String, dynamic>? analysis,
    required String? errorText,
  }) {
    final isEn = NisarApp.of(context)?.currentLocale == 'en';
    if (currentResult == null) {
      return card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            title(isEn ? 'Analysis summary (AI)' : 'Resumen del análisis (IA)'),
            Text(isEn
                ? 'The summary will appear here as soon as you load a chart or calculate metrics.'
                : 'El resumen aparecerá aquí en cuanto cargues un gráfico o calcules métricas.'),
          ],
        ),
      );
    }
    return card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title(isEn ? 'Analysis summary (AI)' : 'Resumen del análisis (IA)'),
          if (loading)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
          else if (errorText != null)
            Text(errorText, style: const TextStyle(color: Colors.red))
          else if (analysis == null)
            Text(isEn
                ? 'The summary could not be generated.'
                : 'No se pudo generar el resumen.')
          else ...[
            SelectableText(analysis['analysis']['summary'] as String, style: const TextStyle(fontSize: 15)),
            if (analysis['analysis']['observations'] != null && (analysis['analysis']['observations'] as List).isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                isEn ? 'Affected areas & key points:' : 'Lugares afectados y puntos clave:',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 6),
              for (final obs in (analysis['analysis']['observations'] as List))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• ', style: TextStyle(fontWeight: FontWeight.bold, color: green)),
                      Expanded(child: SelectableText(obs.toString(), style: const TextStyle(fontSize: 14))),
                    ],
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _forestChartCard() {
    final isEn = NisarApp.of(context)?.currentLocale == 'en';
    final zone = _currentForestZone;
    final key = _forestCacheKey(zone.id, _forestYear, _forestMonth);
    final data = _forestResults[key];
    final (vivo, inicial) = _forestProportion(data);
    final hasData = data != null && inicial > 0;
    final yearHasData = _yearHasData[_forestYear] ?? false;
    
    final monthNames = isEn 
        ? ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
        : ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];
        
    final fraction = inicial <= 0 ? 0.0 : (vivo / inicial).clamp(0.0, 1.0);

    return card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: title(
                  isEn
                      ? 'Forest contour & NISAR satellite view'
                      : 'Contorno del bosque y vista satelital NISAR',
                ),
              ),
              FilterChip(
                avatar: Icon(
                  Icons.satellite_alt,
                  size: 16,
                  color: nisarRadarMode ? Colors.white : green,
                ),
                label: Text(
                  isEn ? 'NISAR Radar' : 'Satélite NISAR',
                  style: TextStyle(
                    fontSize: 12,
                    color: nisarRadarMode ? Colors.white : Colors.black87,
                  ),
                ),
                selected: nisarRadarMode,
                selectedColor: const Color(0xff0d1520),
                checkmarkColor: Colors.greenAccent,
                onSelected: (v) => setState(() => nisarRadarMode = v),
              ),
            ],
          ),
          Text(isEn 
              ? 'Geographic contour of ${zone.name}: green shows living forest; grey shows lost area.' 
              : 'Contorno geográfico de ${zone.name}: el verde representa el bosque vivo; el gris, la superficie perdida.'),
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
            allYearText: isEn ? 'All year' : 'Todo el año',
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
            Text(isEn 
                ? 'No mapped forest area for this zone and date.' 
                : 'No hay superficie forestal cartografiada para esta zona y fecha.')
          else
            _GeoSatelliteVisualizer(
              zoneId: zone.id,
              zoneName: zone.name,
              coordsLabel: zone.coordsLabel,
              yearLabel: _forestMonth == null
                  ? '$_forestYear'
                  : '${monthNames[_forestMonth! - 1]} $_forestYear',
              fraction: fraction,
              activeColor: green,
              inactiveColor: Colors.grey.shade400,
              radarMode: nisarRadarMode,
              yearSeed: _forestYear,
            ),
        ],
      ),
    );
  }

  Widget _glacierChartCard() {
    final isEn = NisarApp.of(context)?.currentLocale == 'en';
    final zone = _currentGlacierZone;
    final data = _glacierResults[zone.id];
    final fraction = _glacierFraction(data);
    final hasData = data != null && fraction > 0;

    return card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: title(
                  isEn
                      ? 'Glacier contour & NISAR satellite view'
                      : 'Contorno del glaciar y vista satelital NISAR',
                ),
              ),
              FilterChip(
                avatar: Icon(
                  Icons.satellite_alt,
                  size: 16,
                  color: nisarRadarMode ? Colors.white : blueIce,
                ),
                label: Text(
                  isEn ? 'NISAR Radar' : 'Satélite NISAR',
                  style: TextStyle(
                    fontSize: 12,
                    color: nisarRadarMode ? Colors.white : Colors.black87,
                  ),
                ),
                selected: nisarRadarMode,
                selectedColor: const Color(0xff0d1520),
                checkmarkColor: Colors.lightBlueAccent,
                onSelected: (v) => setState(() => nisarRadarMode = v),
              ),
            ],
          ),
          Text(isEn 
              ? 'Geographic contour of ${zone.name}: blue shows stable ice; grey shows loss of coherence.' 
              : 'Contorno geográfico de ${zone.name}: la parte azul representa hielo estable; el gris, pérdida de coherencia.'),
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
            Text(isEn 
                ? 'No GUNW product available for this zone.' 
                : 'No hay producto GUNW disponible para esta zona.')
          else
            _GeoSatelliteVisualizer(
              zoneId: zone.id,
              zoneName: zone.name,
              coordsLabel: zone.coordsLabel,
              yearLabel: '${DateTime.now().year}',
              fraction: fraction,
              activeColor: blueIce,
              inactiveColor: Colors.grey.shade400,
              radarMode: nisarRadarMode,
              yearSeed: DateTime.now().year,
            ),
        ],
      ),
    );
  }

  Widget dashboardContent() {
    final isEn = NisarApp.of(context)?.currentLocale == 'en';
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          isEn ? 'Welcome to NISAR App' : 'Bienvenido a NISAR App',
          style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        Text(
          isEn
              ? 'This application allows you to explore and analyze NASA (NISAR) and OpenStreetMap (OSM) satellite data to better understand changes on Earth\'s surface. Select a card below to enter each module:'
              : 'Esta aplicación te permite explorar y analizar datos satelitales de la NASA (NISAR) y de OpenStreetMap (OSM) para entender mejor los cambios en la superficie de la Tierra. Selecciona una tarjeta para ingresar a cada módulo:',
          style: const TextStyle(fontSize: 15),
        ),
        const SizedBox(height: 24),

        // 1. Card interactiva de Bosques (con ilustración de bosque)
        _dashboardModuleCard(
          cardTitle: isEn ? 'Forests Module' : 'Módulo de Bosques',
          description: isEn
              ? 'Monitor forest health and loss using historical OpenStreetMap data to compare past states (from 2005) with current status.'
              : 'Monitorea la salud y la pérdida de superficies forestales usando datos históricos de OpenStreetMap (desde 2005).',
          svgIllustration: _svgForestIllustration,
          accentColor: green,
          onTap: () => navigate(1),
        ),

        // 2. Card interactiva de Hundimiento (con ilustración de temblor/falla sísmica)
        _dashboardModuleCard(
          cardTitle: isEn ? 'Subsidence Module' : 'Módulo de Hundimiento',
          description: isEn
              ? 'Analyze ground displacement using radar interferometry (NISAR data) to detect subsidence, earthquakes, or uplift.'
              : 'Analiza el desplazamiento del terreno mediante interferometría radar (datos NISAR) para detectar hundimientos y actividad sísmica.',
          svgIllustration: _svgEarthquakeIllustration,
          accentColor: Colors.deepPurple,
          onTap: () => navigate(2),
        ),

        // 3. Card interactiva de Glaciares (con ilustración de iceberg/glaciar)
        _dashboardModuleCard(
          cardTitle: isEn ? 'Glaciers Module' : 'Módulo de Glaciares',
          description: isEn
              ? 'Evaluate ice movement and stability in key global glaciers using NISAR GUNW products.'
              : 'Evalúa el movimiento y la estabilidad del hielo en glaciares clave del planeta usando productos GUNW.',
          svgIllustration: _svgIcebergIllustration,
          accentColor: blueIce,
          onTap: () => navigate(3),
        ),
      ],
    );
  }

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
              if (aiBusy)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (ai != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.auto_awesome, color: Colors.blue, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            t('geminiResult'),
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 16),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SelectableText(
                        ai!['analysis']['summary'] as String,
                        style: const TextStyle(fontSize: 14, height: 1.4),
                      ),
                      if (ai!['analysis']['observations'] != null &&
                          (ai!['analysis']['observations'] as List).isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          NisarApp.of(context)?.currentLocale == 'en'
                              ? 'Key points & areas at risk:'
                              : 'Puntos clave y zonas en riesgo:',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const SizedBox(height: 6),
                        for (final obs in (ai!['analysis']['observations'] as List))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('• ', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                                Expanded(child: SelectableText(obs.toString(), style: const TextStyle(fontSize: 13))),
                              ],
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ] else ...[
                Text(
                  NisarApp.of(context)?.currentLocale == 'en'
                      ? 'Select an area and calculate metrics to view Gemini\'s interpretation here.'
                      : 'Selecciona un área y calcula las métricas para ver aquí la interpretación de Gemini.',
                  style: const TextStyle(color: Colors.black54, fontSize: 14),
                ),
              ],
            ],
          ),
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
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SelectableText(aiError!, style: const TextStyle(color: Colors.red)),
                ),
            ],
          ),
        ),
      ],
      if (module == 'bosques' || module == 'glaciares') ...[
        if (module == 'bosques') _forestChartCard(),
        if (module == 'glaciares') _glacierChartCard(),
        // Línea de tiempo visual por año (debajo del gráfico y arriba de la interpretación)
        _yearlyEvolutionCard(isForest: module == 'bosques'),
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
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SelectableText(aiError!, style: const TextStyle(color: Colors.red)),
                ),
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
    required this.allYearText,
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
  final String allYearText;
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
            hint: Text(allYearText),
            items: [
              DropdownMenuItem(value: null, child: Text(allYearText)),
              for (var m = 1; m <= 12; m++)
                DropdownMenuItem(value: m, child: Text(monthNames[m - 1])),
            ],
            onChanged: onMonthChanged,
          ),
        IconButton(
          tooltip: NisarApp.of(context)?.currentLocale == 'en' ? 'Refresh' : 'Recargar',
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    );
  }
}

// Visualizador principal de contorno geográfico real + imagen satelital NISAR Banda-L
class _GeoSatelliteVisualizer extends StatelessWidget {
  const _GeoSatelliteVisualizer({
    required this.zoneId,
    required this.zoneName,
    required this.coordsLabel,
    required this.yearLabel,
    required this.fraction,
    required this.activeColor,
    required this.inactiveColor,
    required this.radarMode,
    required this.yearSeed,
  });

  final String zoneId;
  final String zoneName;
  final String coordsLabel;
  final String yearLabel;
  final double fraction;
  final Color activeColor;
  final Color inactiveColor;
  final bool radarMode;
  final int yearSeed;

  @override
  Widget build(BuildContext context) {
    final pct = (fraction * 100).toStringAsFixed(1);
    return Container(
      height: 320,
      width: double.infinity,
      decoration: BoxDecoration(
        color: radarMode ? const Color(0xff0b131e) : const Color(0xfff1f5f9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: radarMode ? Colors.blueGrey.shade800 : const Color(0xffe2e8f0),
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 44, 20, 36),
              child: CustomPaint(
                painter: _GeoSatelliteContourPainter(
                  zoneId: zoneId,
                  fraction: fraction,
                  activeColor: activeColor,
                  inactiveColor: radarMode
                      ? Colors.blueGrey.shade800
                      : inactiveColor,
                  radarMode: radarMode,
                  yearSeed: yearSeed,
                  detailed: true,
                ),
              ),
            ),
          ),
          // Encabezado telemétrico satelital NISAR
          Positioned(
            top: 10,
            left: 14,
            right: 14,
            child: Row(
              children: [
                Icon(
                  Icons.satellite_alt_rounded,
                  size: 16,
                  color: radarMode ? Colors.cyanAccent : activeColor,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '$zoneName ($yearLabel)',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: radarMode ? Colors.white : Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: activeColor.withValues(alpha: radarMode ? 0.25 : 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: activeColor.withValues(alpha: 0.6)),
                  ),
                  child: Text(
                    '$pct%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: radarMode ? Colors.white : activeColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Pie con coordenadas y sensor SAR
          Positioned(
            bottom: 8,
            left: 14,
            right: 14,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  coordsLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: radarMode ? Colors.white70 : Colors.black54,
                  ),
                ),
                Text(
                  radarMode ? 'NASA-ISRO SAR (L-Band)' : 'GIS Contour',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: radarMode ? Colors.cyanAccent.shade100 : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Pintor vectorial de contornos geográficos reales (Amazonas, Petén, Groenlandia, Thwaites, Perito Moreno)
// con simulación de textura interferométrica satelital NISAR Banda-L
class _GeoSatelliteContourPainter extends CustomPainter {
  _GeoSatelliteContourPainter({
    required this.zoneId,
    required this.fraction,
    required this.activeColor,
    required this.inactiveColor,
    required this.radarMode,
    required this.yearSeed,
    this.detailed = false,
  });

  final String zoneId;
  final double fraction;
  final Color activeColor;
  final Color inactiveColor;
  final bool radarMode;
  final int yearSeed;
  final bool detailed;

  ui.Path _buildZoneContour(Size size) {
    final w = size.width;
    final h = size.height;
    final path = ui.Path();

    switch (zoneId) {
      case 'amazonas':
        // Silueta de la Cuenca Amazónica (Brasil) con el curso del río Amazonas
        path.moveTo(w * 0.14, h * 0.34);
        path.cubicTo(w * 0.25, h * 0.14, w * 0.48, h * 0.10, w * 0.68, h * 0.16);
        path.cubicTo(w * 0.82, h * 0.20, w * 0.92, h * 0.30, w * 0.90, h * 0.44);
        path.cubicTo(w * 0.86, h * 0.56, w * 0.78, h * 0.64, w * 0.72, h * 0.80);
        path.cubicTo(w * 0.60, h * 0.90, w * 0.42, h * 0.88, w * 0.28, h * 0.82);
        path.cubicTo(w * 0.14, h * 0.74, w * 0.08, h * 0.54, w * 0.14, h * 0.34);
        path.close();
        break;

      case 'peten':
        // Contorno geográfico del Departamento de Petén / Reserva de la Biosfera Maya (Guatemala)
        path.moveTo(w * 0.24, h * 0.12);
        path.lineTo(w * 0.76, h * 0.12);
        path.lineTo(w * 0.76, h * 0.78);
        path.cubicTo(w * 0.64, h * 0.82, w * 0.54, h * 0.90, w * 0.40, h * 0.88);
        path.cubicTo(w * 0.28, h * 0.84, w * 0.18, h * 0.72, w * 0.14, h * 0.56);
        path.cubicTo(w * 0.18, h * 0.44, w * 0.24, h * 0.34, w * 0.24, h * 0.12);
        path.close();
        break;

      case 'groenlandia':
        // Contorno geográfico de Groenlandia / Glaciar Jakobshavn
        path.moveTo(w * 0.44, h * 0.08);
        path.cubicTo(w * 0.64, h * 0.06, w * 0.80, h * 0.14, w * 0.82, h * 0.28);
        path.cubicTo(w * 0.78, h * 0.46, w * 0.66, h * 0.66, w * 0.52, h * 0.92);
        path.cubicTo(w * 0.40, h * 0.84, w * 0.32, h * 0.66, w * 0.28, h * 0.46);
        path.cubicTo(w * 0.24, h * 0.28, w * 0.30, h * 0.12, w * 0.44, h * 0.08);
        path.close();
        break;

      case 'thwaites':
        // Lengua y cuenca del Glaciar Thwaites (Antártida Occidental)
        path.moveTo(w * 0.12, h * 0.26);
        path.cubicTo(w * 0.32, h * 0.14, w * 0.66, h * 0.12, w * 0.88, h * 0.24);
        path.cubicTo(w * 0.92, h * 0.42, w * 0.84, h * 0.64, w * 0.70, h * 0.78);
        path.cubicTo(w * 0.56, h * 0.90, w * 0.44, h * 0.92, w * 0.32, h * 0.80);
        path.cubicTo(w * 0.18, h * 0.66, w * 0.08, h * 0.46, w * 0.12, h * 0.26);
        path.close();
        break;

      case 'perito_moreno':
      default:
        // Frente del Glaciar Perito Moreno sobre el Lago Argentino (Patagonia)
        path.moveTo(w * 0.12, h * 0.22);
        path.lineTo(w * 0.58, h * 0.16);
        path.cubicTo(w * 0.74, h * 0.24, w * 0.88, h * 0.36, w * 0.88, h * 0.50);
        path.cubicTo(w * 0.88, h * 0.64, w * 0.74, h * 0.76, w * 0.58, h * 0.84);
        path.lineTo(w * 0.12, h * 0.78);
        path.cubicTo(w * 0.20, h * 0.60, w * 0.20, h * 0.40, w * 0.12, h * 0.22);
        path.close();
        break;
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final contour = _buildZoneContour(size);

    // 1. Retícula satelital de fondo si está activo el modo radar NISAR
    if (radarMode && detailed) {
      final gridPaint = Paint()
        ..color = Colors.cyanAccent.withValues(alpha: 0.08)
        ..strokeWidth = 0.8;
      const step = 22.0;
      for (double x = 0; x <= size.width; x += step) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      }
      for (double y = 0; y <= size.height; y += step) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      }
    }

    // 2. Base del contorno completo (representa el 100% histórico / área total)
    final basePaint = Paint()
      ..color = inactiveColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(contour, basePaint);

    // 3. Recorte proporcional del área activa (bosque vivo o hielo estable)
    canvas.save();
    canvas.clipPath(contour);

    final activeRect = Rect.fromLTWH(
      0,
      size.height * (1 - fraction.clamp(0.0, 1.0)),
      size.width,
      size.height * fraction.clamp(0.0, 1.0),
    );

    final activePaint = Paint()
      ..color = activeColor.withValues(alpha: radarMode ? 0.82 : 0.92)
      ..style = PaintingStyle.fill;
    canvas.drawRect(activeRect, activePaint);

    // 4. Textura interferométrica satelital NISAR (bandas de fase y textura SAR)
    if (radarMode) {
      final rnd = math.Random(yearSeed + zoneId.hashCode);
      final specklePaint = Paint()..style = PaintingStyle.fill;
      final dots = detailed ? 260 : 45;
      for (int i = 0; i < dots; i++) {
        final dx = rnd.nextDouble() * size.width;
        final dy = rnd.nextDouble() * size.height;
        final isBright = rnd.nextBool();
        specklePaint.color = (isBright ? Colors.white : Colors.black)
            .withValues(alpha: detailed ? 0.12 : 0.16);
        canvas.drawCircle(
          Offset(dx, dy),
          detailed ? (1.0 + rnd.nextDouble() * 1.6) : 1.0,
          specklePaint,
        );
      }

      // Franjas de fase interferométrica (InSAR fringes)
      if (detailed) {
        final fringePaint = Paint()
          ..color = Colors.cyanAccent.withValues(alpha: 0.22)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4;
        for (int f = 1; f <= 5; f++) {
          final r = (size.shortestSide * 0.14) * f;
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(size.width * 0.52, size.height * 0.48),
              width: r * 1.4,
              height: r,
            ),
            fringePaint,
          );
        }
      }
    }

    // 5. Hidrografía característica (Río Amazonas o Lago Argentino)
    if (zoneId == 'amazonas' || zoneId == 'perito_moreno') {
      final riverPaint = Paint()
        ..color = (radarMode ? Colors.cyanAccent : Colors.lightBlue.shade200)
            .withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = detailed ? 3.2 : 1.5
        ..strokeCap = StrokeCap.round;
      final river = ui.Path();
      if (zoneId == 'amazonas') {
        river.moveTo(size.width * 0.15, size.height * 0.46);
        river.cubicTo(
          size.width * 0.38,
          size.height * 0.36,
          size.width * 0.62,
          size.height * 0.52,
          size.width * 0.88,
          size.height * 0.38,
        );
      } else {
        river.moveTo(size.width * 0.62, size.height * 0.18);
        river.cubicTo(
          size.width * 0.72,
          size.height * 0.42,
          size.width * 0.70,
          size.height * 0.62,
          size.width * 0.60,
          size.height * 0.82,
        );
      }
      canvas.drawPath(river, riverPaint);
    }

    canvas.restore();

    // 6. Borde geográfico resaltado del contorno
    final borderPaint = Paint()
      ..color = radarMode
          ? Colors.cyanAccent.withValues(alpha: 0.85)
          : activeColor.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = detailed ? 2.2 : 1.3;
    canvas.drawPath(contour, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _GeoSatelliteContourPainter oldDelegate) =>
      oldDelegate.zoneId != zoneId ||
      oldDelegate.fraction != fraction ||
      oldDelegate.radarMode != radarMode ||
      oldDelegate.yearSeed != yearSeed ||
      oldDelegate.activeColor != activeColor;
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