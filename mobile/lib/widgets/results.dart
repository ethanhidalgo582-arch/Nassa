// AI-generated content: this file contains code generated with the help of artificial intelligence (Claude, Anthropic).
// Contenido generado con IA: este archivo contiene código generado con ayuda de inteligencia artificial (Claude, Anthropic).
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../l10n.dart';
import '../services/api_service.dart';
import '../services/speech.dart';
import '../theme.dart';
import 'common.dart';

Map<String, dynamic> _m(dynamic v) => (v as Map?)?.cast<String, dynamic>() ?? const {};
num? _n(dynamic v) => v is num ? v : null;

/// Main summary: headline, key points, listen button. Visible without expanding anything.
class SummaryCard extends StatelessWidget {
  const SummaryCard({super.key, required this.module, required this.result, required this.speech, this.ai, this.fetchAudio});
  final ModuleStyle module;
  final Map<String, dynamic> result;
  final SpeechController speech;
  final Map<String, dynamic>? ai;
  /// Gemini voice for the current locale; null when Gemini is not configured.
  final Future<Uint8List?> Function(int part)? fetchAudio;

  @override
  Widget build(BuildContext context) {
    final lang = LocaleScope.of(context);
    final s = _m(_m(result['summary'])[lang]);
    final points = (s['points'] as List? ?? const []).cast<String>();
    final answer = ai != null && ai!['locale'] == lang ? _m(ai!['answer']) : null;
    final spoken = [
      s['speech'] ?? '',
      if (answer != null) ...[
        tr(context, 'ai'),
        answer['summary'],
        if ((answer['people_alert']?.toString() ?? '').trim().isNotEmpty) ...[tr(context, 'ai.alert'), answer['people_alert']],
        answer['pattern'],
        answer['meaning'],
        tr(context, 'ai.cannot'),
        ...((answer['cannot_conclude'] as List?) ?? const []),
      ],
    ].where((e) => e != null && e.toString().trim().isNotEmpty).join('. ').replaceAll('..', '.');
    return Card(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(colors: [module.light, Colors.white], begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(module.icon, color: module.color),
            const SizedBox(width: 8),
            Text(tr(context, 'result'), style: TextStyle(color: module.color, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
          ]),
          const SizedBox(height: 10),
          Semantics(
            header: true,
            child: SelectableText(s['headline']?.toString() ?? '',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(height: 1.35, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 10),
          for (final p in points)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(padding: const EdgeInsets.only(top: 7), child: Icon(Icons.circle, size: 7, color: module.color)),
                const SizedBox(width: 10),
                Expanded(child: SelectableText(p)),
              ]),
            ),
          const SizedBox(height: 12),
          ListenControls(speech: speech, text: spoken, owner: '${result['result_id']}|$lang', color: module.color,
              fetchAudio: fetchAudio),
        ]),
      ),
    );
  }
}

class MetricsGrid extends StatelessWidget {
  const MetricsGrid({super.key, required this.module, required this.result});
  final ModuleStyle module;
  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context) {
    final m = _m(result['metrics']);
    final tiles = <Widget>[];
    final c = module.color;
    switch (module.id) {
      case ModuleId.bosques:
        tiles.addAll([
          MetricTile(label: tr(context, 'f.loss'), value: fmtNum(context, _n(m['loss_ha']), decimals: 0), unit: 'ha',
              icon: Icons.local_fire_department_outlined, color: const Color(0xffb91c1c)),
          MetricTile(label: tr(context, 'f.loss_pct'), value: fmtNum(context, _n(m['loss_pct_of_forest_start'])), unit: '%',
              icon: Icons.percent_rounded, color: const Color(0xffb91c1c),
              note: tr(context, 'f.denominator', {'d': loc(context, m['loss_pct_denominator'])})),
          MetricTile(label: tr(context, 'f.forest_start'), value: fmtNum(context, _n(m['forest_start_ha']), decimals: 0), unit: 'ha',
              icon: Icons.forest_outlined, color: c),
          MetricTile(label: tr(context, 'f.valid'), value: fmtNum(context, _n(m['valid_data_pct'])), unit: '%',
              icon: Icons.verified_outlined,
              note: '${fmtNum(context, _n(m['valid_data_area_ha']), decimals: 0)} / ${fmtNum(context, _n(m['selected_area_ha']), decimals: 0)} ha'),
        ]);
      case ModuleId.hundimiento:
        final method = m['rate_method'] == 'linear_fit' ? tr(context, 'rate.linear') : tr(context, 'rate.two');
        tiles.addAll([
          MetricTile(label: tr(context, 's.cumulative'), value: fmtNum(context, _n(m['cumulative_los_mm']), signed: true), unit: 'mm',
              icon: Icons.south_rounded, color: c,
              note: '${fmtDate(context, _m(result['period'])['start'])} → ${fmtDate(context, _m(result['period'])['end'])}'),
          MetricTile(label: tr(context, 's.rate'), value: fmtNum(context, _n(m['rate_los_mm_per_year']), signed: true), unit: 'mm/año'.replaceAll('año', LocaleScope.of(context) == 'es' ? 'año' : 'yr'),
              icon: Icons.speed_rounded, color: c,
              note: m['rate_standard_error_mm_per_year'] != null
                  ? '$method · ±${fmtNum(context, _n(m['rate_standard_error_mm_per_year']))}'
                  : method),
          MetricTile(label: tr(context, 's.vertical'), value: fmtNum(context, _n(m['cumulative_vertical_estimate_mm']), signed: true), unit: 'mm',
              icon: Icons.height_rounded, note: tr(context, 's.los_vs_vertical')),
          MetricTile(label: tr(context, 's.observations'), value: fmtNum(context, _n(m['observations']), decimals: 0),
              icon: Icons.satellite_alt_outlined,
              note: '${tr(context, 's.coverage')}: ${fmtNum(context, _n(m['valid_coverage_pct_min']))}–${fmtNum(context, _n(m['valid_coverage_pct_max']))} %'),
        ]);
      case ModuleId.glaciares:
        final p = _m(result['period']);
        tiles.addAll([
          MetricTile(label: tr(context, 'g.median'), value: fmtNum(context, _n(m['median_los_mm']), signed: true), unit: 'mm',
              icon: Icons.swap_vert_rounded, color: c,
              note: '${fmtDate(context, p['start'])} → ${fmtDate(context, p['end'])} (${p['days']} ${tr(context, 'units.days')})'),
          MetricTile(label: tr(context, 'g.fast'), value: fmtNum(context, _n(m['p90_abs_rate_los_m_per_year']), decimals: 2),
              unit: LocaleScope.of(context) == 'es' ? 'm/año' : 'm/yr', icon: Icons.speed_rounded, color: c),
          MetricTile(label: tr(context, 'g.coverage'), value: fmtNum(context, _n(m['valid_coverage_pct'])), unit: '%',
              icon: Icons.verified_outlined, note: '${tr(context, 'g.coherence')}: ${fmtNum(context, _n(m['mean_coherence']), decimals: 2)}'),
          MetricTile(label: tr(context, 'g.outline'), value: fmtNum(context, _n(m['glacier_outline_area_km2'])), unit: 'km²',
              icon: Icons.ac_unit_rounded),
        ]);
    }
    return LayoutBuilder(builder: (context, box) {
      final cols = box.maxWidth >= 400 ? 2 : 1;
      final w = (box.maxWidth - (cols - 1) * 10) / cols;
      return Wrap(spacing: 10, runSpacing: 10, children: [for (final t in tiles) SizedBox(width: w, child: t)]);
    });
  }
}

class ChartCard extends StatelessWidget {
  const ChartCard({super.key, required this.title, required this.explanation, required this.child, this.footer});
  final String title;
  final String explanation;
  final Widget child;
  final String? footer;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SectionTitle(title, icon: Icons.insert_chart_outlined_rounded),
            Text(explanation, style: const TextStyle(color: Palette.muted, fontSize: 13.5)),
            const SizedBox(height: 14),
            SizedBox(height: 230, child: child),
            if (footer != null) ...[
              const SizedBox(height: 8),
              Text(footer!, style: const TextStyle(color: Palette.muted, fontSize: 12.5, fontStyle: FontStyle.italic)),
            ],
          ]),
        ),
      );
}

/// 1, 2, 2.5, 5 x 10^n ceiling: readable axis maxima that do not exaggerate.
double niceCeil(double v) {
  if (v <= 0) return 1;
  final e = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
  for (final m in const [1.0, 2.0, 2.5, 5.0, 10.0]) {
    if (v <= m * e) return m * e;
  }
  return 10 * e;
}

Widget _axisLabel(String s) => Padding(padding: const EdgeInsets.only(top: 6), child: Text(s, style: const TextStyle(fontSize: 11)));

class ForestChart extends StatelessWidget {
  const ForestChart({super.key, required this.result});
  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context) {
    final rows = (result['annual_loss'] as List).cast<Map>();
    final peak = rows.fold<double>(0, (a, r) => math.max(a, (r['loss_ha'] as num).toDouble()));
    final maxY = niceCeil(peak * 1.1);
    final step = (rows.length / 8).ceil().clamp(1, 10);
    return ChartCard(
      title: tr(context, 'f.chart.title'),
      explanation: tr(context, 'f.chart.expl'),
      footer: tr(context, 'zero_vs_nodata'),
      child: BarChart(BarChartData(
        maxY: maxY,
        minY: 0,
        gridData: const FlGridData(drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(touchTooltipData: BarTouchTooltipData(
          getTooltipItem: (g, _, rod, __) => BarTooltipItem(
              '${rows[g.x]['year']}\n${fmtNum(context, rod.toY, decimals: 0)} ha',
              const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        )),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            axisNameWidget: const Text('ha', style: TextStyle(fontSize: 11)),
            sideTitles: SideTitles(showTitles: true, reservedSize: 48, interval: maxY / 4,
                getTitlesWidget: (v, meta) => Text(fmtNum(context, v, decimals: 0), style: const TextStyle(fontSize: 10.5))),
          ),
          bottomTitles: AxisTitles(sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 26,
            getTitlesWidget: (v, meta) {
              final i = v.toInt();
              if (i < 0 || i >= rows.length || (i % step != 0 && i != rows.length - 1)) return const SizedBox.shrink();
              return _axisLabel('${rows[i]['year']}');
            },
          )),
        ),
        barGroups: [
          for (var i = 0; i < rows.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: (rows[i]['loss_ha'] as num).toDouble(),
                width: math.max(6, 180 / rows.length),
                color: const Color(0xffdc2626),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ]),
        ],
      )),
    );
  }
}

class SubsidenceCharts extends StatelessWidget {
  const SubsidenceCharts({super.key, required this.result, required this.color});
  final Map<String, dynamic> result;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final series = (result['series'] as List).cast<Map>();
    final start = DateTime.parse(series.first['date'] as String);
    final spots = [
      for (final s in series)
        FlSpot(DateTime.parse(s['date'] as String).difference(start).inDays.toDouble(), (s['cumulative_los_mm'] as num).toDouble()),
    ];
    final ys = spots.map((s) => s.y);
    final lo = math.min(0.0, ys.reduce(math.min));
    final hi = math.max(0.0, ys.reduce(math.max));
    final span = math.max(10.0, (hi - lo) * 1.3); // at least ±5 mm: avoids exaggerating tiny changes
    final mid = (hi + lo) / 2;
    final two = series.length == 2;
    final pairs = (result['pairs'] as List? ?? const []).cast<Map>();
    return Column(children: [
      ChartCard(
        title: tr(context, 's.chart.title'),
        explanation: tr(context, 's.chart.expl'),
        footer: two ? tr(context, 's.chart.two') : null,
        child: LineChart(LineChartData(
          minY: mid - span / 2,
          maxY: mid + span / 2,
          minX: 0,
          maxX: math.max(1, spots.last.x),
          gridData: const FlGridData(drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          extraLinesData: ExtraLinesData(horizontalLines: [HorizontalLine(y: 0, color: Palette.ink.withValues(alpha: 0.5), strokeWidth: 1)]),
          lineTouchData: LineTouchData(touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (ts) => [
              for (final t in ts)
                LineTooltipItem(
                    '${fmtDate(context, series[t.spotIndex]['date'] as String)}\n${fmtNum(context, t.y, signed: true)} mm',
                    const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ],
          )),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              axisNameWidget: const Text('mm (LOS)', style: TextStyle(fontSize: 11)),
              sideTitles: SideTitles(showTitles: true, reservedSize: 44,
                  getTitlesWidget: (v, meta) => Text(fmtNum(context, v, decimals: 0), style: const TextStyle(fontSize: 10.5))),
            ),
            bottomTitles: AxisTitles(sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: 1,
              getTitlesWidget: (v, meta) {
                final i = spots.indexWhere((s) => s.x == v);
                final show = i == 0 || i == spots.length - 1 || (i > 0 && spots.length <= 5);
                if (i < 0 || !show) return const SizedBox.shrink();
                return _axisLabel(fmtDate(context, series[i]['date'] as String));
              },
            )),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: false,
              color: color,
              barWidth: 3,
              dotData: FlDotData(getDotPainter: (s, _, __, ___) =>
                  FlDotCirclePainter(radius: 5, color: Colors.white, strokeColor: color, strokeWidth: 3)),
              belowBarData: BarAreaData(show: false),
            ),
          ],
        )),
      ),
      if (pairs.length > 1) ...[
        const SizedBox(height: 12),
        ChartCard(
          title: tr(context, 's.pairs.title'),
          explanation: tr(context, 's.pairs.expl'),
          child: BarChart(BarChartData(
            gridData: const FlGridData(drawVerticalLine: false),
            borderData: FlBorderData(show: false),
            extraLinesData: ExtraLinesData(horizontalLines: [HorizontalLine(y: 0, color: Palette.ink, strokeWidth: 1)]),
            barTouchData: BarTouchData(touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (g, _, rod, __) => BarTooltipItem(
                  '${fmtDate(context, pairs[g.x]['reference_date'] as String)} → ${fmtDate(context, pairs[g.x]['secondary_date'] as String)}\n'
                  '${fmtNum(context, rod.toY, signed: true)} mm · ±${fmtNum(context, _n(pairs[g.x]['reference_noise_mm']))}',
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            )),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40,
                  getTitlesWidget: (v, meta) => Text(fmtNum(context, v, decimals: 0), style: const TextStyle(fontSize: 10.5)))),
              bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28,
                  getTitlesWidget: (v, meta) {
                    final i = v.toInt();
                    if (i < 0 || i >= pairs.length) return const SizedBox.shrink();
                    return _axisLabel(fmtDate(context, pairs[i]['secondary_date'] as String).split(' ').take(2).join(' '));
                  })),
            ),
            barGroups: [
              for (var i = 0; i < pairs.length; i++)
                BarChartGroupData(x: i, barRods: [
                  BarChartRodData(
                    toY: (_n(pairs[i]['median_los_mm']) ?? 0).toDouble(),
                    color: (_n(pairs[i]['median_los_mm']) ?? 0) < 0 ? const Color(0xffd73027) : const Color(0xff4575b4),
                    width: 18,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ]),
            ],
          )),
        ),
      ],
    ]);
  }
}

class GlacierChart extends StatelessWidget {
  const GlacierChart({super.key, required this.result, required this.color});
  final Map<String, dynamic> result;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final m = _m(result['metrics']);
    final p10 = (_n(m['p10_los_mm']) ?? 0).toDouble();
    final p90 = (_n(m['p90_los_mm']) ?? 0).toDouble();
    final med = (_n(m['median_los_mm']) ?? 0).toDouble();
    final lim = math.max(10.0, [p10.abs(), p90.abs(), med.abs()].reduce(math.max) * 1.25);
    return ChartCard(
      title: tr(context, 'g.chart.title'),
      explanation: tr(context, 'g.chart.expl'),
      child: LayoutBuilder(builder: (context, box) {
        double x(double v) => (v + lim) / (2 * lim) * box.maxWidth;
        return Stack(children: [
          Positioned(left: x(0) - 1, top: 20, bottom: 40, child: Container(width: 2, color: Palette.ink.withValues(alpha: 0.5))),
          Positioned(
            left: x(math.min(p10, p90)),
            width: (x(p90) - x(p10)).abs().clamp(3, box.maxWidth),
            top: 80,
            height: 46,
            child: Semantics(
              label: 'P10 ${fmtNum(context, p10)} mm, P90 ${fmtNum(context, p90)} mm',
              child: Container(decoration: BoxDecoration(color: color.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color, width: 2))),
            ),
          ),
          Positioned(left: x(med) - 2, top: 70, height: 66, width: 4, child: Container(color: Palette.ink)),
          Positioned(left: (x(med) - 60).clamp(0, box.maxWidth - 120), top: 40, width: 120,
              child: Text('${tr(context, 'g.median')}\n${fmtNum(context, med, signed: true)} mm',
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700))),
          Positioned(left: (x(p10) - 40).clamp(0, box.maxWidth - 80), top: 132, width: 80,
              child: Text('P10\n${fmtNum(context, p10)} mm', textAlign: TextAlign.center, style: const TextStyle(fontSize: 11))),
          Positioned(left: (x(p90) - 40).clamp(0, box.maxWidth - 80), top: 132, width: 80,
              child: Text('P90\n${fmtNum(context, p90)} mm', textAlign: TextAlign.center, style: const TextStyle(fontSize: 11))),
          Positioned(left: 0, right: 0, bottom: 0, child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('${fmtNum(context, -lim, decimals: 0)} mm', style: const TextStyle(fontSize: 11)),
            Text(LocaleScope.of(context) == 'es' ? '← se aleja · 0 · se acerca →' : '← away · 0 · towards →',
                style: const TextStyle(fontSize: 11, color: Palette.muted)),
            Text('+${fmtNum(context, lim, decimals: 0)} mm', style: const TextStyle(fontSize: 11)),
          ])),
        ]);
      }),
    );
  }
}

/// Gemini explanation. Optional: results never depend on it.
class AiCard extends StatelessWidget {
  const AiCard({super.key, required this.module, required this.ai, required this.loading, required this.error, required this.onRequest,
      this.configured = true});
  final bool configured;
  final ModuleStyle module;
  final Map<String, dynamic>? ai;
  final bool loading;
  final ApiException? error;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    final lang = LocaleScope.of(context);
    final answer = ai != null && ai!['locale'] == lang ? _m(ai!['answer']) : null;
    final verification = _m(ai?['verification']);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SectionTitle(tr(context, 'ai'), icon: Icons.auto_awesome_outlined),
          if (loading)
            Row(children: [
              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 12),
              Expanded(child: Text(tr(context, 'ai.loading'))),
            ])
          else if (error != null)
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(error!.message(lang), style: TextStyle(color: error!.kind == 'not_configured' ? Palette.muted : Palette.error)),
              if (error!.retryable) TextButton.icon(onPressed: onRequest, icon: const Icon(Icons.refresh), label: Text(tr(context, 'retry'))),
            ])
          else if (answer == null && !configured)
            Text(tr(context, 'ai.not_configured'), style: const TextStyle(color: Palette.muted))
          else if (answer == null)
            OutlinedButton.icon(onPressed: onRequest, icon: const Icon(Icons.auto_awesome), label: Text(tr(context, 'ai.button')))
          else ...[
            SelectableText(answer['summary']?.toString() ?? '', style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            if ((answer['people_alert']?.toString() ?? '').trim().isNotEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xfffff4e5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Palette.warning.withValues(alpha: 0.5)),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.warning_amber_rounded, color: Palette.warning),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(tr(context, 'ai.alert'), style: const TextStyle(fontWeight: FontWeight.w700, color: Palette.warning)),
                      const SizedBox(height: 4),
                      SelectableText(answer['people_alert'].toString()),
                    ]),
                  ),
                ]),
              ),
            for (final (k, label) in [('what_changed', 'ai.what'), ('how_much', 'ai.how'), ('pattern', 'ai.pattern'), ('meaning', 'ai.meaning')])
              if ((answer[k]?.toString() ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr(context, label), style: TextStyle(fontWeight: FontWeight.w700, color: module.color)),
                    const SizedBox(height: 2),
                    SelectableText(answer[k].toString()),
                  ]),
                ),
            Text(tr(context, 'ai.cannot'), style: const TextStyle(fontWeight: FontWeight.w700, color: Palette.warning)),
            for (final c in (answer['cannot_conclude'] as List? ?? const []))
              Padding(padding: const EdgeInsets.only(top: 4), child: Text('• $c')),
            if (verification['ok'] == false)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xfffff4e5), borderRadius: BorderRadius.circular(10)),
                child: Text(tr(context, 'ai.unverified', {'n': (verification['unverified_numbers'] as List).join(', ')}),
                    style: const TextStyle(color: Palette.warning)),
              ),
            const SizedBox(height: 10),
            Text(tr(context, 'ai.disclaimer'), style: const TextStyle(fontSize: 12, color: Palette.muted)),
          ],
        ]),
      ),
    );
  }
}

/// Expandable technical details: limitations, scope, sources, pairs.
class DetailsCard extends StatelessWidget {
  const DetailsCard({super.key, required this.result});
  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context) {
    final lang = LocaleScope.of(context);
    final lim = (_m(result['limitations'])[lang] as List? ?? const []).cast<String>();
    final src = _m(result['source']);
    final geometry = _m(result['geometry']);
    final pairs = (result['pairs'] as List? ?? const []).cast<Map>();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          leading: const Icon(Icons.fact_check_outlined),
          title: Text(tr(context, 'details'), style: const TextStyle(fontWeight: FontWeight.w700)),
          children: [
            Text(tr(context, 'limitations'), style: const TextStyle(fontWeight: FontWeight.w700)),
            for (final l in lim) Padding(padding: const EdgeInsets.only(top: 6), child: Text('• $l')),
            if (result['stats_scope'] != null) ...[
              const SizedBox(height: 10),
              Text(loc(context, result['stats_scope']), style: const TextStyle(fontStyle: FontStyle.italic)),
            ],
            const SizedBox(height: 14),
            Text(tr(context, 'source'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            SelectableText([
              src['name'],
              if (src['version'] != null) src['version'],
              if (src['collection'] != null) src['collection'],
              if (src['license'] != null) src['license'],
              if (src['citation'] != null) src['citation'],
              if (src['spec'] != null) src['spec'],
            ].whereType<String>().join(' · ')),
            if (geometry.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                    'Track ${geometry['track'] ?? '—'} · Frame ${geometry['frame'] ?? '—'} · ${geometry['direction'] ?? ''} · '
                    '${geometry['polarization'] ?? ''} · λ ${geometry['wavelength_cm'] ?? '—'} cm · EPSG:${geometry['epsg'] ?? '—'}',
                    style: const TextStyle(fontSize: 12.5, color: Palette.muted)),
              ),
            if (pairs.isNotEmpty) ...[
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowHeight: 36,
                  dataRowMinHeight: 32,
                  dataRowMaxHeight: 40,
                  columns: [
                    DataColumn(label: Text(lang == 'es' ? 'Fechas' : 'Dates')),
                    DataColumn(label: Text(lang == 'es' ? 'Mediana (mm)' : 'Median (mm)'), numeric: true),
                    DataColumn(label: Text(lang == 'es' ? 'Desv. espacial' : 'Spatial SD'), numeric: true),
                    DataColumn(label: Text(lang == 'es' ? 'Válidos %' : 'Valid %'), numeric: true),
                    DataColumn(label: Text(lang == 'es' ? 'Coherencia' : 'Coherence'), numeric: true),
                  ],
                  rows: [
                    for (final p in pairs)
                      DataRow(cells: [
                        DataCell(Text('${fmtDate(context, p['reference_date'] as String)} → ${fmtDate(context, p['secondary_date'] as String)}')),
                        DataCell(Text(fmtNum(context, _n(p['median_los_mm']), signed: true))),
                        DataCell(Text(fmtNum(context, _n(p['spatial_std_mm'])))),
                        DataCell(Text(fmtNum(context, _n(p['valid_coverage_pct'])))),
                        DataCell(Text(fmtNum(context, _n(p['mean_coherence']), decimals: 2))),
                      ]),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
