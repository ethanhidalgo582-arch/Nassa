import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../l10n.dart';
import '../services/api_service.dart';
import '../services/speech.dart';
import '../theme.dart';
import 'scenes.dart';

class ImpactLogo extends StatelessWidget {
  const ImpactLogo({super.key, this.size = 36, this.showText = true, this.light = false});
  final double size;
  final bool showText;
  final bool light;

  @override
  Widget build(BuildContext context) {
    final mark = SvgPicture.asset('assets/brand/impact_mark.svg', width: size, height: size,
        semanticsLabel: 'IMPACT');
    if (!showText) return mark;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      mark,
      SizedBox(width: size * 0.28),
      Text('IMPACT',
          style: TextStyle(
              fontSize: size * 0.62, fontWeight: FontWeight.w900, letterSpacing: size * 0.09,
              color: light ? Colors.white : Palette.ink)),
    ]);
  }
}

/// Indeterminate, themed loader that names the real backend stage.
class StageLoader extends StatelessWidget {
  const StageLoader({super.key, required this.module, required this.stage, this.onCancel, this.elapsed});
  final ModuleStyle module;
  final String stage;
  final VoidCallback? onCancel;
  final double? elapsed;

  @override
  Widget build(BuildContext context) {
    final label = tr(context, 'stage.$stage');
    return Semantics(
      liveRegion: true,
      label: label,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(height: 150, child: AnimatedScene(builder: (t) => scenePainterFor(module.id, t))),
          const LinearProgressIndicator(minHeight: 3),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Text(label, key: ValueKey(label), style: Theme.of(context).textTheme.titleMedium),
                  ),
                  const SizedBox(height: 4),
                  Text(tr(context, 'loading.note'), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Palette.muted)),
                ]),
              ),
              if (onCancel != null) TextButton(onPressed: onCancel, child: Text(tr(context, 'cancel'))),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Error / no-data / not-configured states, visually different and never shown as zero.
class StatusCard extends StatelessWidget {
  const StatusCard({super.key, required this.error, this.onRetry, this.onChooseOther});
  final ApiException error;
  final VoidCallback? onRetry;
  final VoidCallback? onChooseOther;

  @override
  Widget build(BuildContext context) {
    final lang = LocaleScope.of(context);
    final (icon, color, title) = switch (error.kind) {
      'no_data' => (Icons.cloud_off_rounded, Palette.warning, tr(context, 'nodata.title')),
      'not_configured' => (Icons.settings_suggest_rounded, Palette.muted, tr(context, 'config.title')),
      'invalid_input' => (Icons.crop_free_rounded, Palette.warning, tr(context, 'error.title')),
      _ => (Icons.error_outline_rounded, Palette.error, tr(context, 'error.title')),
    };
    return Semantics(
      liveRegion: true,
      child: Card(
        color: color.withValues(alpha: 0.06),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: color.withValues(alpha: 0.4))),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, color: color),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color))),
            ]),
            const SizedBox(height: 8),
            Text(error.message(lang)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (onRetry != null && (error.retryable || error.kind == 'expired'))
                FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: Text(tr(context, 'retry'))),
              if (onChooseOther != null && (error.kind == 'no_data' || error.kind == 'invalid_input'))
                OutlinedButton.icon(
                    onPressed: onChooseOther, icon: const Icon(Icons.edit_location_alt_outlined), label: Text(tr(context, 'choose_other'))),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// "Listen to results": play / pause / resume / stop with visible state.
class ListenControls extends StatelessWidget {
  const ListenControls(
      {super.key, required this.speech, required this.text, required this.owner, required this.color, this.fetchAudio});
  final SpeechController speech;
  final String text;
  final String owner;
  final Color color;
  final Future<Uint8List?> Function(int part)? fetchAudio;

  @override
  Widget build(BuildContext context) {
    final lang = LocaleScope.of(context);
    return ListenableBuilder(
      listenable: speech,
      builder: (context, _) {
        final mine = speech.owner == owner;
        final state = mine ? speech.state : SpeechState.idle;
        final problem = mine ? speech.problem : null;
        final engine = mine ? speech.engine : null;
        final active = state == SpeechState.speaking || state == SpeechState.paused || state == SpeechState.starting;
        final generating = (state == SpeechState.starting && engine == SpeechEngine.gemini) ||
            (mine && speech.waitingNext && state == SpeechState.speaking);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (!active)
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: color),
                onPressed: () => speech.speak(text, lang, owner: owner, fetchAudio: fetchAudio),
                icon: const Icon(Icons.volume_up_rounded),
                label: Text(tr(context, 'listen')),
              )
            else if (generating) ...[
              OutlinedButton.icon(onPressed: speech.stop, icon: const Icon(Icons.stop_rounded), label: Text(tr(context, 'listen.stop'))),
              Semantics(
                liveRegion: true,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: color)),
                  const SizedBox(width: 8),
                  Text(tr(context, 'listen.generating'), style: TextStyle(color: color, fontWeight: FontWeight.w600)),
                ]),
              ),
            ] else ...[
              if (state == SpeechState.paused)
                FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: color),
                    onPressed: speech.resume,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(tr(context, 'listen.resume')))
              else
                FilledButton.tonalIcon(
                    onPressed: speech.pause, icon: const Icon(Icons.pause_rounded), label: Text(tr(context, 'listen.pause'))),
              OutlinedButton.icon(onPressed: speech.stop, icon: const Icon(Icons.stop_rounded), label: Text(tr(context, 'listen.stop'))),
              Semantics(
                liveRegion: true,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _Equalizer(color: color, running: state == SpeechState.speaking),
                  const SizedBox(width: 8),
                  Text(tr(context, state == SpeechState.paused ? 'listen.paused' : 'listen.speaking'),
                      style: TextStyle(color: color, fontWeight: FontWeight.w600)),
                ]),
              ),
            ],
          ]),
          if (active && !generating && engine != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(engine == SpeechEngine.gemini ? Icons.auto_awesome : Icons.record_voice_over_outlined, size: 14, color: Palette.muted),
                const SizedBox(width: 6),
                Text(tr(context, engine == SpeechEngine.gemini ? 'listen.engine.gemini' : 'listen.engine.browser'),
                    style: const TextStyle(fontSize: 12.5, color: Palette.muted)),
              ]),
            ),
          if (problem != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                switch (problem) {
                  'gemini_fallback' => tr(context, 'listen.gemini_fallback', {'m': speech.geminiError?.message(lang) ?? ''}),
                  'gemini_fallback_novoice' || 'gemini_fallback_unsupported' => tr(context, 'listen.gemini_fallback_novoice'),
                  'audio_blocked' => tr(context, 'listen.audio_blocked'),
                  'novoice' => tr(context, 'listen.novoice'),
                  _ => tr(context, 'listen.unsupported'),
                },
                style: const TextStyle(color: Palette.warning),
              ),
            ),
        ]);
      },
    );
  }
}

class _Equalizer extends StatefulWidget {
  const _Equalizer({required this.color, required this.running});
  final Color color;
  final bool running;
  @override
  State<_Equalizer> createState() => _EqualizerState();
}

class _EqualizerState extends State<_Equalizer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void didUpdateWidget(covariant _Equalizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  void _sync() {
    if (widget.running && !reduceMotion(context)) {
      if (!_c.isAnimating) _c.repeat(reverse: true);
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 4; i++)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                width: 4,
                height: 6 + 12 * (((_c.value + i * 0.27) % 1.0 - 0.5).abs() * 2),
                decoration: BoxDecoration(color: widget.color, borderRadius: BorderRadius.circular(2)),
              ),
          ],
        ),
      );
}

/// Small metric tile. Distinguishes "—" (no data) from 0.
class MetricTile extends StatelessWidget {
  const MetricTile({super.key, required this.label, required this.value, this.unit, this.note, this.icon, this.color});
  final String label;
  final String value;
  final String? unit;
  final String? note;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Palette.ink;
    return Semantics(
      label: '$label: $value ${unit ?? ''}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Palette.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            if (icon != null) ...[Icon(icon, size: 16, color: c), const SizedBox(width: 6)],
            Expanded(child: Text(label, style: const TextStyle(fontSize: 13, color: Palette.muted, fontWeight: FontWeight.w600))),
          ]),
          const SizedBox(height: 6),
          Text.rich(TextSpan(children: [
            TextSpan(text: value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: c, letterSpacing: -0.5)),
            if (unit != null && value != '—') TextSpan(text: ' $unit', style: const TextStyle(fontSize: 14, color: Palette.muted)),
          ])),
          if (note != null) ...[
            const SizedBox(height: 4),
            Text(note!, style: const TextStyle(fontSize: 12, color: Palette.muted)),
          ],
        ]),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.icon, this.trailing});
  final String text;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          if (icon != null) ...[Icon(icon, size: 20, color: Palette.muted), const SizedBox(width: 8)],
          Expanded(child: Semantics(header: true, child: Text(text, style: Theme.of(context).textTheme.titleMedium))),
          if (trailing != null) trailing!,
        ]),
      );
}

class LanguageToggle extends StatelessWidget {
  const LanguageToggle({super.key, this.light = false});
  final bool light;

  @override
  Widget build(BuildContext context) {
    final ctrl = LocaleScope.controllerOf(context);
    final lang = LocaleScope.of(context);
    return Tooltip(
      message: tr(context, 'language'),
      child: SegmentedButton<String>(
        showSelectedIcon: false,
        style: SegmentedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          foregroundColor: light ? Colors.white : Palette.ink,
          selectedForegroundColor: Colors.white,
          selectedBackgroundColor: Palette.green,
        ),
        segments: const [
          ButtonSegment(value: 'es', label: Text('ES'), tooltip: 'Español'),
          ButtonSegment(value: 'en', label: Text('EN'), tooltip: 'English'),
        ],
        selected: {lang},
        onSelectionChanged: (s) => ctrl.value = s.first,
      ),
    );
  }
}
