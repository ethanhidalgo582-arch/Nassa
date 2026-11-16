// AI-generated content: this file contains code generated with the help of artificial intelligence (Claude, Anthropic).
// Contenido generado con IA: este archivo contiene código generado con ayuda de inteligencia artificial (Claude, Anthropic).
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Lightweight vector scenes drawn with CustomPainter (no external images).
/// `t` goes 0..1 and loops; painters are pure functions of `t`.

double _wave(double t, [double phase = 0]) => math.sin((t + phase) * 2 * math.pi);

// ---------------------------------------------------------------- forest ---
class ForestScenePainter extends CustomPainter {
  ForestScenePainter(this.t, {this.showBear = true, this.sky = const Color(0xffe8f5ec)});
  final double t;
  final bool showBear;
  final Color sky;

  @override
  void paint(Canvas c, Size s) {
    final w = s.width, h = s.height;
    c.drawRect(Offset.zero & s, Paint()..color = sky);
    // sun
    c.drawCircle(Offset(w * 0.82, h * 0.22), h * 0.09, Paint()..color = const Color(0xfffde68a));
    // far hills
    final hills = Path()..moveTo(0, h * 0.62);
    for (double x = 0; x <= w; x += w / 40) {
      hills.lineTo(x, h * 0.58 + math.sin(x / w * 6 + 1) * h * 0.05);
    }
    hills
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    c.drawPath(hills, Paint()..color = const Color(0xffb7dfc5));
    // trees in two parallax rows
    void row(double baseY, double size, double speed, Color col, Color trunk) {
      final spacing = size * 1.25;
      final offset = (t * speed * w) % spacing;
      for (double x = -spacing + -offset; x < w + spacing; x += spacing) {
        final tx = x + spacing / 2;
        c.drawRect(Rect.fromLTWH(tx - size * 0.06, baseY - size * 0.25, size * 0.12, size * 0.25), Paint()..color = trunk);
        final p = Path()
          ..moveTo(tx, baseY - size * 1.15)
          ..lineTo(tx - size * 0.42, baseY - size * 0.22)
          ..lineTo(tx + size * 0.42, baseY - size * 0.22)
          ..close();
        c.drawPath(p, Paint()..color = col);
        final p2 = Path()
          ..moveTo(tx, baseY - size * 1.35)
          ..lineTo(tx - size * 0.3, baseY - size * 0.7)
          ..lineTo(tx + size * 0.3, baseY - size * 0.7)
          ..close();
        c.drawPath(p2, Paint()..color = Color.lerp(col, Colors.white, 0.12)!);
      }
    }

    row(h * 0.70, h * 0.32, 0.15, const Color(0xff3f9a62), const Color(0xff6d4c41));
    c.drawRect(Rect.fromLTWH(0, h * 0.78, w, h * 0.22), Paint()..color = const Color(0xff8bc79f));
    if (showBear) _bear(c, Offset(w * 0.5, h * 0.80), h * 0.16);
    row(h * 1.02, h * 0.42, 0.35, Palette.green, const Color(0xff5d4037));
    // falling leaves
    final leaf = Paint()..color = const Color(0xff4caf50);
    for (var i = 0; i < 6; i++) {
      final lt = (t * 1.3 + i / 6) % 1.0;
      final x = w * ((i * 0.17 + 0.08) % 1.0) + _wave(lt * 2, i / 6) * w * 0.03;
      final y = lt * h * 0.9;
      c.save();
      c.translate(x, y);
      c.rotate(lt * 6 + i);
      c.drawOval(Rect.fromCenter(center: Offset.zero, width: h * 0.035, height: h * 0.018), leaf);
      c.restore();
    }
  }

  void _bear(Canvas c, Offset feet, double size) {
    final fur = Paint()..color = const Color(0xff5b3a29);
    final dark = Paint()..color = const Color(0xff3e271b);
    final step = t * 8 * math.pi;
    final bob = math.sin(step * 2).abs() * size * 0.04;
    final body = Rect.fromCenter(center: feet.translate(0, -size * 0.55 - bob), width: size * 1.5, height: size * 0.8);
    // legs (two pairs swinging)
    for (var i = 0; i < 4; i++) {
      final front = i < 2;
      final phase = (i.isEven ? 0 : math.pi);
      final lx = body.center.dx + (front ? size * 0.45 : -size * 0.45) + (i.isEven ? size * 0.08 : -size * 0.08);
      final swing = math.sin(step + phase) * size * 0.12;
      final legPaint = Paint()
        ..color = i.isEven ? fur.color : dark.color
        ..strokeWidth = size * 0.22
        ..strokeCap = StrokeCap.round;
      c.drawLine(Offset(lx, body.center.dy + size * 0.1), Offset(lx + swing, feet.dy - size * 0.05), legPaint);
    }
    c.drawRRect(RRect.fromRectAndRadius(body, Radius.circular(size * 0.4)), fur);
    final head = body.centerRight.translate(size * 0.05, -size * 0.2);
    c.drawCircle(head, size * 0.32, fur);
    c.drawCircle(head.translate(-size * 0.12, -size * 0.28), size * 0.1, dark);
    c.drawOval(Rect.fromCenter(center: head.translate(size * 0.26, size * 0.06), width: size * 0.3, height: size * 0.22),
        Paint()..color = const Color(0xff8d6e63));
    c.drawCircle(head.translate(size * 0.38, size * 0.02), size * 0.05, dark);
    c.drawCircle(head.translate(size * 0.08, -size * 0.06), size * 0.04, Paint()..color = Colors.black);
  }

  @override
  bool shouldRepaint(ForestScenePainter old) => old.t != t;
}

// --------------------------------------------------------------- glacier ---
class GlacierScenePainter extends CustomPainter {
  GlacierScenePainter(this.t);
  final double t;

  @override
  void paint(Canvas c, Size s) {
    final w = s.width, h = s.height;
    c.drawRect(
        Offset.zero & s,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xffd8ecfd), Color(0xfff4f9ff)],
          ).createShader(Offset.zero & s));
    void mountain(double cx, double peak, double width, Color rock) {
      final base = h * 0.82;
      final p = Path()
        ..moveTo(cx - width / 2, base)
        ..lineTo(cx, peak)
        ..lineTo(cx + width / 2, base)
        ..close();
      c.drawPath(p, Paint()..color = rock);
      final capH = (base - peak) * 0.38;
      final cap = Path()
        ..moveTo(cx, peak)
        ..lineTo(cx - width * 0.19, peak + capH)
        ..lineTo(cx - width * 0.08, peak + capH * 0.8)
        ..lineTo(cx, peak + capH * 1.05)
        ..lineTo(cx + width * 0.1, peak + capH * 0.78)
        ..lineTo(cx + width * 0.19, peak + capH)
        ..close();
      c.drawPath(cap, Paint()..color = Colors.white);
    }

    mountain(w * 0.25, h * 0.28, w * 0.6, const Color(0xff7aa7d6));
    mountain(w * 0.72, h * 0.18, w * 0.7, const Color(0xff5b8fd0));
    mountain(w * 0.5, h * 0.40, w * 0.5, const Color(0xff9cc2ea));
    // glacier tongue with moving shimmer
    final ice = Path()
      ..moveTo(w * 0.3, h * 0.82)
      ..quadraticBezierTo(w * 0.5, h * 0.62, w * 0.72, h * 0.82)
      ..close();
    c.drawPath(ice, Paint()..color = const Color(0xffe3f2fd));
    final band = Rect.fromLTWH(-w * 0.4 + t * w * 1.8, 0, w * 0.25, h);
    c.save();
    c.clipPath(ice);
    c.drawRect(
        band,
        Paint()
          ..shader = LinearGradient(colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.9),
            Colors.white.withValues(alpha: 0),
          ]).createShader(band));
    c.restore();
    // water / ground
    c.drawRect(Rect.fromLTWH(0, h * 0.82, w, h * 0.18), Paint()..color = const Color(0xff2f80ed).withValues(alpha: 0.85));
    for (var i = 0; i < 3; i++) {
      final y = h * (0.86 + i * 0.045);
      final path = Path()..moveTo(0, y);
      for (double x = 0; x <= w; x += w / 30) {
        path.lineTo(x, y + _wave(x / w * 3 + t, i / 3) * h * 0.008);
      }
      c.drawPath(path, Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5);
    }
    // floating ice blocks
    final block = Paint()..color = Colors.white;
    for (var i = 0; i < 3; i++) {
      final x = ((t * 0.3 + i / 3) % 1.0) * w;
      final y = h * 0.88 + _wave(t * 2, i / 3) * h * 0.01;
      c.drawPath(
          Path()
            ..moveTo(x, y)
            ..lineTo(x + h * 0.05, y - h * 0.03)
            ..lineTo(x + h * 0.09, y)
            ..close(),
          block);
    }
    // snowflakes
    final flake = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 26; i++) {
      final ft = (t + i * 0.137) % 1.0;
      final x = (i * 0.0731 % 1.0) * w + _wave(ft * 2, i * 0.3) * w * 0.02;
      final y = ft * h * 0.85;
      final r = 1.5 + (i % 3) * 1.2;
      for (var k = 0; k < 3; k++) {
        final a = k * math.pi / 3 + ft * 2;
        c.drawLine(Offset(x - math.cos(a) * r, y - math.sin(a) * r), Offset(x + math.cos(a) * r, y + math.sin(a) * r),
            flake..color = i.isEven ? Colors.white : const Color(0xffcfe6fb));
      }
    }
  }

  @override
  bool shouldRepaint(GlacierScenePainter old) => old.t != t;
}

// ------------------------------------------------------------ subsidence ---
class GroundScenePainter extends CustomPainter {
  GroundScenePainter(this.t);
  final double t;

  @override
  void paint(Canvas c, Size s) {
    final w = s.width, h = s.height;
    c.drawRect(Offset.zero & s, Paint()..color = const Color(0xfff8f3ee));
    // satellite + radar pulses
    final sat = Offset(w * 0.78, h * 0.14);
    for (var i = 0; i < 3; i++) {
      final pt = (t * 1.5 + i / 3) % 1.0;
      final r = pt * h * 0.8;
      c.drawArc(Rect.fromCircle(center: sat, radius: r), math.pi * 0.55, math.pi * 0.35, false,
          Paint()
            ..color = Palette.blueIce.withValues(alpha: (1 - pt) * 0.6)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
    }
    c.save();
    c.translate(sat.dx, sat.dy);
    c.rotate(0.5);
    c.drawRect(Rect.fromCenter(center: Offset.zero, width: h * 0.08, height: h * 0.06), Paint()..color = Palette.ink);
    c.drawRect(Rect.fromCenter(center: Offset(-h * 0.09, 0), width: h * 0.08, height: h * 0.04), Paint()..color = Palette.blueIce);
    c.drawRect(Rect.fromCenter(center: Offset(h * 0.09, 0), width: h * 0.08, height: h * 0.04), Paint()..color = Palette.blueIce);
    c.restore();
    // strata with a gentle subsidence bowl in the middle
    const colors = [Color(0xffc49a6c), Color(0xffa9774a), Color(0xff8a5a35), Color(0xff6b4226)];
    final dip = (0.5 + 0.5 * _wave(t)) * h * 0.05;
    for (var i = colors.length - 1; i >= 0; i--) {
      final top = h * (0.55 + i * 0.1);
      final p = Path()..moveTo(0, top);
      for (double x = 0; x <= w; x += w / 50) {
        final bowl = math.exp(-math.pow((x / w - 0.42) * 4, 2)) * dip * (1 - i * 0.18);
        p.lineTo(x, top + bowl);
      }
      p
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close();
      c.drawPath(p, Paint()..color = colors[i]);
    }
    // houses on the surface
    final house = Paint()..color = const Color(0xff4b5b55);
    for (var i = 0; i < 5; i++) {
      final x = w * (0.12 + i * 0.12);
      final bowl = math.exp(-math.pow((x / w - 0.42) * 4, 2)) * dip;
      final y = h * 0.55 + bowl;
      c.drawRect(Rect.fromLTWH(x, y - h * 0.07, h * 0.07, h * 0.07), house);
      c.drawPath(
          Path()
            ..moveTo(x - h * 0.01, y - h * 0.07)
            ..lineTo(x + h * 0.035, y - h * 0.11)
            ..lineTo(x + h * 0.08, y - h * 0.07)
            ..close(),
          Paint()..color = const Color(0xffb54708));
    }
    // measurement ruler
    final ruler = Paint()
      ..color = Palette.ink.withValues(alpha: 0.7)
      ..strokeWidth = 1.5;
    final rx = w * 0.06;
    c.drawLine(Offset(rx, h * 0.38), Offset(rx, h * 0.72), ruler);
    for (var k = 0; k <= 8; k++) {
      final y = h * 0.38 + k * h * 0.0425;
      c.drawLine(Offset(rx, y), Offset(rx + (k.isEven ? 10 : 5), y), ruler);
    }
    c.drawLine(Offset(rx - 4, h * 0.55 + dip * 0.3), Offset(rx + 14, h * 0.55 + dip * 0.3),
        Paint()
          ..color = Palette.error
          ..strokeWidth = 2.5);
  }

  @override
  bool shouldRepaint(GroundScenePainter old) => old.t != t;
}

// ------------------------------------------------------------ satellite ---
/// Splash scene: the Earth seen from orbit while the background cycles through
/// forest, ice and ground (the three things IMPACT observes).
class OrbitScenePainter extends CustomPainter {
  OrbitScenePainter(this.t);
  final double t;

  @override
  void paint(Canvas c, Size s) {
    final w = s.width, h = s.height;
    // background scenes cross-fade
    final scenes = <CustomPainter Function(double)>[
      (x) => ForestScenePainter(x, showBear: false),
      (x) => GlacierScenePainter(x),
      (x) => GroundScenePainter(x),
    ];
    final pos = t * scenes.length;
    final i = pos.floor() % scenes.length;
    final f = pos - pos.floor();
    scenes[i](t).paint(c, s);
    if (f > 0.8) {
      c.saveLayer(Offset.zero & s, Paint()..color = Colors.white.withValues(alpha: (f - 0.8) / 0.2));
      scenes[(i + 1) % scenes.length](t).paint(c, s);
      c.restore();
    }
    // dark veil for contrast
    c.drawRect(Offset.zero & s, Paint()..color = const Color(0xff0f2a1f).withValues(alpha: 0.55));
    // stars
    final star = Paint()..color = Colors.white.withValues(alpha: 0.7);
    for (var k = 0; k < 40; k++) {
      final x = (k * 0.6180339 % 1.0) * w;
      final y = (k * 0.3819660 % 1.0) * h * 0.5;
      c.drawCircle(Offset(x, y), 0.6 + (k % 3) * 0.5 * (0.6 + 0.4 * _wave(t * 4, k / 40)), star);
    }
    // Earth
    final r = math.min(w, h) * 0.26;
    final center = Offset(w / 2, h * 0.52);
    c.drawCircle(center, r * 1.08, Paint()..color = Palette.blueIce.withValues(alpha: 0.25));
    c.drawCircle(center, r, Paint()..color = Palette.green);
    c.save();
    c.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: r)));
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.09
      ..strokeCap = StrokeCap.round;
    final shift = t * r * 2;
    for (var k = 0; k < 2; k++) {
      final y = center.dy - r * 0.15 + k * r * 0.42;
      final p = Path()..moveTo(center.dx - r * 1.6 + shift % (r * 0.8), y);
      for (double x = -1.6; x <= 1.6; x += 0.1) {
        p.lineTo(center.dx + x * r + shift % (r * 0.8), y + math.sin(x * 3 + k) * r * 0.12);
      }
      c.drawPath(p, line..strokeWidth = r * (k == 0 ? 0.1 : 0.07));
    }
    c.drawRect(Rect.fromLTWH(center.dx - r, center.dy + r * 0.55, 2 * r, r), Paint()..color = Palette.blueIce);
    c.restore();
    // orbit + satellite with scanning beam
    final orbit = Rect.fromCenter(center: center, width: r * 3.2, height: r * 1.3);
    c.drawOval(orbit, Paint()
      ..color = Palette.blueIce.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5);
    final a = t * 2 * math.pi;
    final sat = Offset(center.dx + math.cos(a) * orbit.width / 2, center.dy + math.sin(a) * orbit.height / 2);
    final front = math.sin(a) > 0;
    if (front || (sat - center).distance > r) {
      final beam = Path()
        ..moveTo(sat.dx, sat.dy)
        ..lineTo(center.dx + (sat.dx - center.dx) * 0.35 - r * 0.15, center.dy + (sat.dy - center.dy) * 0.35)
        ..lineTo(center.dx + (sat.dx - center.dx) * 0.35 + r * 0.15, center.dy + (sat.dy - center.dy) * 0.35)
        ..close();
      c.drawPath(beam, Paint()..color = const Color(0xfffde68a).withValues(alpha: 0.35));
      c.save();
      c.translate(sat.dx, sat.dy);
      c.rotate(a + math.pi / 2);
      final u = r * 0.12;
      c.drawRect(Rect.fromCenter(center: Offset(-u * 1.6, 0), width: u * 1.6, height: u), Paint()..color = Palette.blueIce);
      c.drawRect(Rect.fromCenter(center: Offset(u * 1.6, 0), width: u * 1.6, height: u), Paint()..color = Palette.blueIce);
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: u * 1.4, height: u * 1.4), Radius.circular(u * 0.3)),
          Paint()..color = Colors.white);
      c.restore();
    }
  }

  @override
  bool shouldRepaint(OrbitScenePainter old) => old.t != t;
}

CustomPainter scenePainterFor(ModuleId id, double t) => switch (id) {
      ModuleId.bosques => ForestScenePainter(t),
      ModuleId.glaciares => GlacierScenePainter(t),
      ModuleId.hundimiento => GroundScenePainter(t),
    };

/// Loops `t` from 0..1 and paints [builder]. Static frame when motion is reduced.
class AnimatedScene extends StatefulWidget {
  const AnimatedScene({super.key, required this.builder, this.period = const Duration(seconds: 6), this.staticT = 0.3});
  final CustomPainter Function(double t) builder;
  final Duration period;
  final double staticT;

  @override
  State<AnimatedScene> createState() => _AnimatedSceneState();
}

class _AnimatedSceneState extends State<AnimatedScene> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.period);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = reduceMotion(context);
    return RepaintBoundary(
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => ClipRect(
            child: CustomPaint(painter: widget.builder(still ? widget.staticT : _c.value), size: Size.infinite),
          ),
        ),
      ),
    );
  }
}
