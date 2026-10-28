import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:fl_chart/fl_chart.dart';

import 'ai_analysis_panel.dart';
import 'services/api_service.dart';

void main() => runApp(const NisarDemoApp());

class NisarDemoApp extends StatelessWidget {
  const NisarDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NISAR Demo',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final ApiService _api = ApiService();
  List<Polygon> _zones = [];
  Map<String, dynamic>? _selectedData;
  Map<String, dynamic>? _stats;
  bool? _geminiConfigured;
  bool _loading = false;
  bool _dashboardLoading = true;
  String? _dashboardError;
  String? _selectionError;
  int _selectionId = 0;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _dashboardLoading = true;
      _dashboardError = null;
    });
    try {
      final results = await Future.wait([
        _api.getClassifiedZones(),
        _api.getDashboardStats(),
        _api.getHealth(),
      ]);
      final polygons = <Polygon>[];
      for (final feature in results[0]['features'] as List<dynamic>) {
        final coordinates = feature['geometry']['coordinates'][0] as List;
        polygons.add(Polygon(
          points: coordinates
              .map<LatLng>((c) =>
                  LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
              .toList(),
          color: const Color(0x59609590),
          borderColor: Colors.teal,
          borderStrokeWidth: 2,
        ));
      }
      if (!mounted) return;
      setState(() {
        _zones = polygons;
        _stats = results[1];
        _geminiConfigured = results[2]['gemini']['configured'] as bool;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _dashboardError = error.toString());
    } finally {
      if (mounted) setState(() => _dashboardLoading = false);
    }
  }

  Future<void> _onTap(LatLng point) async {
    final selectionId = ++_selectionId;
    setState(() {
      _loading = true;
      _selectedData = null;
      _selectionError = null;
    });
    try {
      final data = await _api.getDisplacement(point.latitude, point.longitude);
      if (!mounted || selectionId != _selectionId) return;
      setState(() => _selectedData = data);
    } catch (error) {
      if (!mounted || selectionId != _selectionId) return;
      setState(() => _selectionError = error.toString());
    } finally {
      if (mounted && selectionId == _selectionId) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NISAR Demo + Gemini'),
        actions: [
          IconButton(
            tooltip: 'Actualizar conexión',
            onPressed: _dashboardLoading ? null : _loadDashboard,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: const LatLng(14.6349, -90.5069),
              initialZoom: 11,
              onTap: (_, point) => _onTap(point),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.demo.nisar',
              ),
              PolygonLayer(polygons: _zones),
              const Align(
                alignment: Alignment.topRight,
                child: ColoredBox(
                  color: Colors.white,
                  child: Padding(
                    padding: EdgeInsets.all(4),
                    child: Text('© OpenStreetMap contributors',
                        style: TextStyle(fontSize: 10)),
                  ),
                ),
              ),
            ],
          ),
          DraggableScrollableSheet(
            initialChildSize: 0.35,
            minChildSize: 0.18,
            maxChildSize: 0.9,
            builder: (context, controller) => Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8)],
              ),
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.all(16),
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Demostración con datos simulados',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Este mapa no muestra alertas reales. Selecciona un punto '
                    'dentro del polígono para explorar la demo.',
                  ),
                  if (_dashboardLoading) const LinearProgressIndicator(),
                  if (_dashboardError != null)
                    Text(_dashboardError!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  if (_stats != null) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 24,
                      runSpacing: 12,
                      children: [
                        _chip('Alertas reales', '${_stats!['activeAlerts'] ?? 'Sin validar'}'),
                        _chip('Área crítica (km²)',
                            '${_stats!['criticalAreaKm2'] ?? 'Sin calcular'}'),
                        _chip('Población afectada',
                            '${_stats!['affectedPopulation'] ?? 'Sin calcular'}'),
                      ],
                    ),
                  ],
                  const Divider(height: 24),
                  if (_loading)
                    const Center(child: CircularProgressIndicator()),
                  if (_selectionError != null) Text(_selectionError!),
                  if (_selectedData != null && !_loading) ...[
                    Text(
                      'Punto: ${(_selectedData!['latitude'] as num).toStringAsFixed(4)}, '
                      '${(_selectedData!['longitude'] as num).toStringAsFixed(4)}',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Desplazamiento LOS simulado: '
                      '${_selectedData!['current_displacement_mm']} mm',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 180,
                      child: _buildChart(_selectedData!['history'] as List),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_selectedData!['note']}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    AiAnalysisPanel(
                      key: ValueKey(
                          '${_selectedData!['latitude']}:${_selectedData!['longitude']}'),
                      api: _api,
                      latitude: (_selectedData!['latitude'] as num).toDouble(),
                      longitude: (_selectedData!['longitude'] as num).toDouble(),
                      configured: _geminiConfigured,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.teal)),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      );

  Widget _buildChart(List<dynamic> history) {
    final spots = [
      for (int i = 0; i < history.length; i++)
        FlSpot(i.toDouble(), (history[i]['displacement_mm'] as num).toDouble()),
    ];
    return LineChart(LineChartData(
      gridData: const FlGridData(show: true),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 1,
            reservedSize: 30,
            getTitlesWidget: (value, meta) {
              final index = value.toInt();
              if (value != index || index < 0 || index >= history.length) {
                return const SizedBox.shrink();
              }
              final date = history[index]['date'] as String;
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(date.substring(0, 7),
                    style: const TextStyle(fontSize: 9)),
              );
            },
          ),
        ),
      ),
      borderData: FlBorderData(show: true),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: false,
          color: Colors.teal,
          barWidth: 3,
          dotData: const FlDotData(show: true),
        ),
      ],
    ));
  }
}

