import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:fl_chart/fl_chart.dart';

import 'services/api_service.dart';

void main() => runApp(const NisarApp());
const green = Color(0xff16834a);
const labels = ['Dashboard', 'Bosques', 'Hundimiento', 'Glaciares'];
const modules = ['bosques', 'hundimiento', 'glaciares'];

const Map<String, Map<String, List<LatLng>>> zonasPrecargadas = {
  'bosques': {
    '📍 Amazonas (Brasil)': [LatLng(-3.46, -62.21), LatLng(-3.46, -62.19), LatLng(-3.48, -62.19), LatLng(-3.48, -62.21)],
    '📍 Petén (Guatemala)': [LatLng(16.93, -89.89), LatLng(16.93, -89.87), LatLng(16.91, -89.87), LatLng(16.91, -89.89)],
  },
  'hundimiento': {
    '📍 Ciudad de México': [LatLng(19.43, -99.13), LatLng(19.43, -99.11), LatLng(19.41, -99.11), LatLng(19.41, -99.13)],
    '📍 Yakarta (Indonesia)': [LatLng(-6.20, 106.84), LatLng(-6.20, 106.86), LatLng(-6.22, 106.86), LatLng(-6.22, 106.84)],
  },
  'glaciares': {
    '📍 Groenlandia': [LatLng(69.21, -49.99), LatLng(69.21, -49.97), LatLng(69.19, -49.97), LatLng(69.19, -49.99)],
    '📍 Thwaites (Antártida)': [LatLng(-75.50, -106.75), LatLng(-75.50, -106.73), LatLng(-75.52, -106.73), LatLng(-75.52, -106.75)],
    '📍 Perito Moreno (Arg)': [LatLng(-50.49, -73.13), LatLng(-50.49, -73.11), LatLng(-50.51, -73.11), LatLng(-50.51, -73.13)],
  }
};

class NisarApp extends StatelessWidget {
  const NisarApp({super.key});
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
    home: const DashboardScreen(),
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
  
  // 👇 AGREGA ESTA LÍNEA
  final userContextController = TextEditingController(); 
  
  int page = 0, request = 0;
  String module = 'bosques';
  DateTime a = DateTime.now().subtract(const Duration(days: 60)),
      b = DateTime.now().subtract(const Duration(days: 12));
  List<LatLng> area = [];
  final Map<String, Map<String, dynamic>> results = {};
  bool drawing = false,
      busy = false,
      aiBusy = false,
      advanced = false,
      showA = false;
  String? error, aiError, connection;
  Map<String, dynamic>? ai;
  Map<String, dynamic>? get result => results[module];
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
      if (mounted) setState(() => connection = 'Servidor disponible');
    } catch (e) {
      if (mounted) setState(() => connection = 'Sin conexión con el servidor');
    }
  }

  void invalidate() {
    request++;
    results.clear();
    ai = null;
    aiError = null;
    error = null;
    busy = false;
    aiBusy = false;
  }

  void navigate(int index) {
    setState(() {
      page = index;
      if (index > 0) module = modules[index - 1];
      error = null;
      ai = null;
      aiError = null;
      area = [];
    });
  }

  void irAZonaPrecargada(List<LatLng> coords) {
    final centro = LatLng(
      coords.map((c) => c.latitude).reduce((a, b) => a + b) / coords.length,
      coords.map((c) => c.longitude).reduce((a, b) => a + b) / coords.length,
    );
    controller.move(centro, 10);
    
    setState(() {
      invalidate();
      area = coords;
    });
  }

  void tap(LatLng p) {
    setState(() {
      invalidate();
      if (drawing) {
        if (area.length < 50) area = [...area, p];
      } else {
        area = [
          LatLng(p.latitude - .01, p.longitude - .01),
          LatLng(p.latitude - .01, p.longitude + .01),
          LatLng(p.latitude + .01, p.longitude + .01),
          LatLng(p.latitude + .01, p.longitude - .01),
        ];
      }
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
        invalidate();
        if (first) {
          a = chosen;
        } else {
          b = chosen;
        }
      });
    }
  }

  Future<void> calculate() async {
    if (area.length < 3 || (advanced && !a.isBefore(b))) {
      setState(() => error = 'Selecciona un área y dos fechas en orden.');
      return;
    }
    final id = ++request;
    final selected = module;
    setState(() {
      busy = true;
      error = null;
      ai = null;
      aiError = null;
    });
    try {
      final payload = <String, dynamic>{
        'module': selected,
        'polygon': area.map((p) => [p.latitude, p.longitude]).toList(),
        if (advanced) 'date_a': day(a),
        if (advanced) 'date_b': day(b),
      };
      final data = await api.getMetrics(payload);
      if (mounted && id == request) setState(() => results[selected] = data);
    } catch (e) {
      if (mounted && id == request) setState(() => error = e.toString());
    } finally {
      if (mounted && id == request) setState(() => busy = false);
    }
  }

  Future<void> interpret() async {
    final id = request;
    final selected = module;
    final resultId = result?['result_id'];
    if (resultId == null) return;
    setState(() {
      aiBusy = true;
      aiError = null;
    });
    try {
      // 👇 ENVIAMOS LA PREGUNTA Y EL CONTEXTO DEL USUARIO
      final value = await api.interpret(
        resultId as String, 
        userContext: userContextController.text
      );
      if (mounted && id == request && selected == module) {
        setState(() => ai = value);
      }
    } catch (e) {
      if (mounted && id == request && selected == module) {
        setState(() => aiError = e.toString());
      }
    } finally {
      if (mounted && id == request) setState(() => aiBusy = false);
    }
  }

  Widget navigation(bool drawer) => SafeArea(
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
        for (int i = 0; i < labels.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              selected: page == i,
              selectedTileColor: const Color(0xffe8f5ec),
              selectedColor: green,
              leading: Icon(
                [
                  Icons.dashboard_outlined,
                  Icons.forest_outlined,
                  Icons.vertical_align_bottom,
                  Icons.ac_unit, 
                ][i],
              ),
              title: Text(labels[i]),
              onTap: () {
                navigate(i);
                if (drawer) Navigator.pop(context);
              },
            ),
          ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextButton.icon(
            onPressed: health,
            icon: const Icon(Icons.refresh),
            label: Text(connection ?? 'Comprobando conexión…'),
          ),
        ),
      ],
    ),
  );

  Widget card(Widget child) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
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

  List<Polygon> forestPolygons() {
    final features =
        (result?[showA ? 'map_a' : 'map_b'] ?? result?['map'] ?? []) as List;
    final polygons = <Polygon>[];
    for (final f in features) {
      final g = f['geometry'];
      final coords = g['coordinates'] as List;
      final parts = g['type'] == 'MultiPolygon' ? coords : [coords];
      for (final part in parts) {
        if ((part as List).isEmpty) continue;
        List<LatLng> ring(dynamic r) => (r as List)
            .map(
              (p) => LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble()),
            )
            .toList();
        polygons.add(
          Polygon(
            points: ring(part[0]),
            holePointsList: [for (final hole in part.skip(1)) ring(hole)],
            color: green.withValues(alpha: .3),
            borderColor: green,
            borderStrokeWidth: 1,
          ),
        );
      }
    }
    return polygons;
  }

  Widget map() => SizedBox(
    height: 420,
    child: ClipRRect(
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
              ...forestPolygons(),
              if (area.length >= 3)
                Polygon(
                  points: area,
                  color: Colors.blue.withValues(alpha: .08),
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
  );

  Widget chart() {
    final values = (result?['chart'] ?? []) as List;
    if (values.isEmpty) {
      return const Text(
        'Sin gráfica todavía. Selecciona un área, las fechas y calcula las métricas.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${result!['measurement']} · ${result!['unit']}'),
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
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: true, reservedSize: 52),
                ),
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
            '${v['label']}: ${(v['value'] as num).toStringAsFixed(3)} ${result!['unit']}',
          ),
        if (result?['chart_kind'] == 'spatial_summary')
          const Text(
            'Distribución espacial del cambio entre las dos adquisiciones; no es una tendencia temporal.',
          ),
      ],
    );
  }

  Widget areaSummary() {
    if (area.length < 3) return const SizedBox.shrink();
    const radius = 6371008.8;
    double sum = 0;
    for (var i = 0; i < area.length; i++) {
      final p = area[i], q = area[(i + 1) % area.length];
      final dlon = (q.longitude - p.longitude) * math.pi / 180;
      sum += dlon * (2 + math.sin(p.latitude * math.pi / 180) +
          math.sin(q.latitude * math.pi / 180));
    }
    final km2 = (sum * radius * radius / 2).abs() / 1000000;
    final lats = area.map((p) => p.latitude).toList();
    final lons = area.map((p) => p.longitude).toList();
    final south = lats.reduce(math.min), north = lats.reduce(math.max);
    final west = lons.reduce(math.min), east = lons.reduce(math.max);
    const distance = Distance();
    final midLat = (south + north) / 2, midLon = (west + east) / 2;
    final width = distance.as(LengthUnit.Kilometer, LatLng(midLat, west), LatLng(midLat, east));
    final height = distance.as(LengthUnit.Kilometer, LatLng(south, midLon), LatLng(north, midLon));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text('Área aproximada: ${km2.toStringAsFixed(2)} km² '
          '(${(km2 * 100).toStringAsFixed(1)} ha). '
          'Extensión: ${width.toStringAsFixed(2)} × ${height.toStringAsFixed(2)} km.'),
    );
  }

  Widget content() => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      if (page == 0) Wrap(spacing: 12, runSpacing: 12, children: [
        for (var i = 1; i < labels.length; i++)
          OutlinedButton.icon(onPressed: () => navigate(i), icon: Icon([Icons.forest_outlined, Icons.vertical_align_bottom, Icons.ac_unit][i-1]), label: Text(labels[i])),
      ]),
      Text(
        labels[page],
        style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      Text(
        module == 'bosques'
            ? 'Compara bosque cartografiado en OpenStreetMap.'
            : module == 'glaciares' 
                ? 'Analiza el movimiento de los glaciares y el impacto del deshielo.'
                : 'Explora fase radar y sus límites de interpretación.',
      ),
      const SizedBox(height: 24),
      card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            title('Área y período'),
            
            if (zonasPrecargadas.containsKey(module)) ...[
              const Text('Zonas críticas precargadas:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in zonasPrecargadas[module]!.entries)
                    ActionChip(
                      avatar: Icon(
                        module == 'glaciares' ? Icons.ac_unit : (module == 'bosques' ? Icons.forest : Icons.location_city),
                        size: 18,
                        color: Colors.blue
                      ),
                      label: Text(entry.key),
                      onPressed: busy ? null : () => irAZonaPrecargada(entry.value),
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],

            areaSummary(),
            if (page == 0)
              DropdownButton<String>(
                value: module,
                items: [
                  for (int i = 0; i < modules.length; i++)
                    DropdownMenuItem(
                      value: modules[i],
                      child: Text(labels[i + 1]),
                    ),
                ],
                onChanged: busy
                    ? null
                    : (v) => setState(() {
                        module = v!;
                        ai = null;
                        error = null;
                        area = []; 
                      }),
              ),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Opciones avanzadas: elegir fechas'), value: advanced, onChanged: busy ? null : (v) => setState(() { invalidate(); advanced=v; })),
            if (!advanced) Text(module == 'bosques' ? 'Período automático: hoy y 365 días antes.' : 'Período automático: producto GUNW disponible más reciente.'),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                if (advanced) OutlinedButton.icon(onPressed: busy ? null : () => date(true), icon: const Icon(Icons.calendar_today), label: Text('Fecha A · ${day(a)}')),
                if (advanced) OutlinedButton.icon(onPressed: busy ? null : () => date(false), icon: const Icon(Icons.calendar_today), label: Text('Fecha B · ${day(b)}')),
                FilterChip(
                  label: const Text('Dibujar polígono'),
                  selected: drawing,
                  onSelected: busy
                      ? null
                      : (v) => setState(() {
                          invalidate();
                          drawing = v;
                          area = [];
                        }),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          invalidate();
                          area = [];
                        }),
                  child: const Text('Limpiar área'),
                ),
                if (drawing)
                  TextButton(
                    onPressed: busy || area.isEmpty
                        ? null
                        : () => setState(() {
                            invalidate();
                            area = area.sublist(0, area.length - 1);
                          }),
                    child: const Text('Deshacer vértice'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              drawing ? 'Toca el mapa para añadir entre 3 y 50 vértices.' : 'Toca el mapa para seleccionar un recuadro de 0,02° por lado.',
            ),
            if (module == 'hundimiento') const Text('Proyección vertical estimada bajo el supuesto de movimiento horizontal nulo. El ángulo se obtiene del producto cuando puede asociarse de forma fiable.'),
            if (module == 'glaciares') const Text('El análisis de glaciares mide el movimiento de la superficie de hielo. Un movimiento constante indica flujo glaciar normal; un cambio abrupto puede indicar desestabilización.'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: busy || area.length < 3 ? null : calculate,
              icon: const Icon(Icons.analytics_outlined),
              label: Text(busy ? 'Calculando…' : 'Calcular métricas'),
            ),
            if (busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
              const Text('La descarga satelital puede tardar varios minutos.'),
            ],
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: SelectableText(
                  error!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
          ],
        ),
      ),
      card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            title('Mapa del área seleccionada'),
            if (module == 'bosques' && result != null)
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: Text('Fecha A · ${result!['snapshots'][0]['date']}'),
                    selected: showA,
                    onSelected: (_) => setState(() => showA = true),
                  ),
                  ChoiceChip(
                    label: Text('Fecha B · ${result!['snapshots'][1]['date']}'),
                    selected: !showA,
                    onSelected: (_) => setState(() => showA = false),
                  ),
                ],
              ),
            const SizedBox(height: 10),
            map(),
            const SizedBox(height: 10),
            Text(
              module == 'bosques'
                  ? 'Verde: bosque cartografiado. Azul: área de consulta.'
                  : 'Puntos: muestra de píxeles; morado < 0 mm, naranja ≥ 0 mm. Azul: área de consulta.',
            ),
            if (area.isNotEmpty)
              Text(
                'Primer vértice: ${area.first.latitude.toStringAsFixed(4)}, ${area.first.longitude.toStringAsFixed(4)}',
              ),
          ],
        ),
      ),
      card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            title('Métricas calculadas'),
            chart(),
            if (result != null) ...[
              const SizedBox(height: 12),
              Text('Fuente: ${result!['source']}'),
              if (result!['date_a'] != null) Text('Fechas del producto: ${result!['date_a']} a ${result!['date_b']}'),
        if (result!['incidence_deg'] != null) Text('Ángulo aplicado: ${result!['incidence_deg']}° · rango del cubo: ${result!['incidence_range_deg']}'),
        if (result!['selected_area_km2'] != null) Text('Área seleccionada: ${result!['selected_area_km2']} km² · huella: ${result!['footprint_area_km2']} km² · área válida aproximada: ${result!['valid_area_km2']} km² (${result!['valid_coverage_pct']}%)'),
        if (result!['partial_coverage'] == true) const Text('Cobertura parcial: el producto no cubre toda el área seleccionada.'),
        if (result!['product'] != null)
                SelectableText('Producto: ${result!['product']}'),
              if (result!['mean'] != null)
                Text(
                  'Media: ${result!['mean']} mm · Coherencia: ${result!['mean_coherence']} · Píxeles válidos: ${result!['valid_pixels']}',
                ),
              if (result!['snapshots'] != null) ...[
                for (final snap in result!['snapshots'] as List)
                  Text(
                    "${snap['date']}: agua cartografiada ${snap['water_ha'] ?? 'sin dato'} ha · resto no cartografiado como agua ${snap['land_ha'] ?? 'sin dato'} ha",
                  ),
              ],
              if (result!['delta'] != null)
                Text(
                  'Diferencia de superficie cartografiada: ${result!['delta']} ha',
                ),
              const SizedBox(height: 12),
              for (final line in result!['limitations'] as List)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('• $line'),
                ),
            ],
          ],
        ),
      ),
      card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            title('Interpretación con Gemini e Impacto Humano'),
            const Text(
              'Opcional. Si falla, el mapa y las métricas siguen disponibles.',
            ),
            const SizedBox(height: 12),
            
            // 👇 NUEVO CAMPO DE TEXTO PARA LA SITUACIÓN DEL USUARIO
            TextField(
              controller: userContextController,
              maxLength: 1000,
              maxLines: 3,
              enabled: result != null && !aiBusy,
              decoration: const InputDecoration(
                labelText: '¿Cómo te afecta esto? (Opcional)',
                hintText: 'Ej: Vivo cerca de la costa, ¿qué significa este deshielo para mi comunidad?',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),

            OutlinedButton.icon(
              onPressed: result == null || aiBusy ? null : interpret,
              icon: const Icon(Icons.auto_awesome),
              label: Text(aiBusy ? 'Interpretando…' : 'Interpretar resultados'),
            ),
            if (aiError != null)
              SelectableText(
                aiError!,
                style: const TextStyle(color: Colors.red),
              ),
            if (ai != null) ...[
              const SizedBox(height: 12),
              SelectableText(ai!['analysis']['summary'] as String),
              for (final key in [
                'observations',
                'limitations',
                'suggested_next_steps',
              ])
                for (final item in ai!['analysis'][key] as List)
                  Text('• $item'),
            ],
          ],
        ),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      appBar: wide ? null : AppBar(title: const Text('NISAR App')),
      drawer: wide ? null : Drawer(child: navigation(true)),
      body: Row(
        children: [
          if (wide)
            Container(
              width: 230,
              color: Colors.white,
              child: navigation(false),
            ),
          Expanded(child: content()),
        ],
      ),
    );
  }
}