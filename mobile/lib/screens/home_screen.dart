// AI-generated content: this file contains code generated with the help of artificial intelligence (Claude, Anthropic).
// Contenido generado con IA: este archivo contiene código generado con ayuda de inteligencia artificial (Claude, Anthropic).
import 'package:flutter/material.dart';

import '../l10n.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/scenes.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final pad = w < 600 ? 16.0 : 32.0;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(pad, pad, pad, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _Hero(compact: w < 760),
            const SizedBox(height: 28),
            SectionTitle(tr(context, 'steps.title'), icon: Icons.route_rounded),
            const _Steps(),
            const SizedBox(height: 28),
            LayoutBuilder(builder: (context, box) {
              final cols = box.maxWidth >= 980 ? 3 : (box.maxWidth >= 640 ? 2 : 1);
              final cw = (box.maxWidth - (cols - 1) * 16) / cols;
              return Wrap(spacing: 16, runSpacing: 16, children: [
                for (final m in ModuleStyle.all) SizedBox(width: cw, child: _ModuleCard(module: m)),
              ]);
            }),
            const SizedBox(height: 28),
            Text(tr(context, 'footer.attrib'), style: const TextStyle(fontSize: 12, color: Palette.muted)),
          ]),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.compact});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final text = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      if (!compact) ...[const ImpactLogo(size: 44, light: true), const SizedBox(height: 18)],
      Semantics(
        header: true,
        child: Text(compact ? tr(context, 'hero.title').replaceAll('\n', ' ') : tr(context, 'hero.title'),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white, height: 1.2)),
      ),
      const SizedBox(height: 12),
      Text(tr(context, 'hero.body'), style: const TextStyle(color: Colors.white70, fontSize: 16.5, height: 1.45)),
      const SizedBox(height: 20),
      FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Palette.ink),
        onPressed: () => Navigator.of(context).pushReplacementNamed('/bosques'),
        icon: const Icon(Icons.arrow_forward_rounded),
        label: Text('${tr(context, 'open')}: ${tr(context, 'bosques')}'),
      ),
    ]);
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        color: Palette.ink,
        child: compact
            ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SizedBox(height: 220, child: AnimatedScene(builder: (t) => OrbitScenePainter(t), period: const Duration(seconds: 12))),
                Padding(padding: const EdgeInsets.all(22), child: text),
              ])
            : ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 340),
                child: IntrinsicHeight(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(flex: 5, child: Padding(padding: const EdgeInsets.all(36), child: text)),
                    Expanded(flex: 4, child: AnimatedScene(builder: (t) => OrbitScenePainter(t), period: const Duration(seconds: 12))),
                  ]),
                ),
              ),
      ),
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps();

  @override
  Widget build(BuildContext context) {
    const icons = [Icons.touch_app_rounded, Icons.edit_location_alt_rounded, Icons.date_range_rounded, Icons.analytics_rounded,
      Icons.record_voice_over_rounded];
    return Wrap(spacing: 10, runSpacing: 10, children: [
      for (var i = 0; i < 5; i++)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Palette.line)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            CircleAvatar(radius: 13, backgroundColor: Palette.green,
                child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800))),
            const SizedBox(width: 10),
            Icon(icons[i], size: 20, color: Palette.muted),
            const SizedBox(width: 6),
            Flexible(child: Text(tr(context, 'step${i + 1}'), style: const TextStyle(fontWeight: FontWeight.w600))),
          ]),
        ),
    ]);
  }
}

class _ModuleCard extends StatefulWidget {
  const _ModuleCard({required this.module});
  final ModuleStyle module;
  @override
  State<_ModuleCard> createState() => _ModuleCardState();
}

class _ModuleCardState extends State<_ModuleCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.module;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: _hover && !reduceMotion(context) ? 1.015 : 1,
        duration: const Duration(milliseconds: 160),
        child: Card(
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: _hover ? m.color : Palette.line, width: _hover ? 2 : 1),
          ),
          child: InkWell(
            onTap: () => Navigator.of(context).pushReplacementNamed(m.route),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(height: 170, child: AnimatedScene(builder: (t) => scenePainterFor(m.id, t), period: const Duration(seconds: 8))),
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: m.light, borderRadius: BorderRadius.circular(10)),
                      child: Icon(m.icon, color: m.color),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(tr(context, m.key), style: Theme.of(context).textTheme.titleLarge)),
                  ]),
                  const SizedBox(height: 10),
                  Text(tr(context, '${m.key}.desc'), style: const TextStyle(fontSize: 15)),
                  const SizedBox(height: 10),
                  Text(tr(context, '${m.key}.source'), style: TextStyle(fontSize: 12.5, color: m.color, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: m.color),
                      onPressed: () => Navigator.of(context).pushReplacementNamed(m.route),
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: Text(tr(context, 'open')),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
