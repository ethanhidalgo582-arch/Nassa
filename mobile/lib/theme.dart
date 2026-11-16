import 'package:flutter/material.dart';

import 'services/speech.dart';

/// Brand palette (kept from the original project) and per-module accents.
class Palette {
  static const green = Color(0xff16834a);
  static const greenDark = Color(0xff0f5c34);
  static const ink = Color(0xff0f2a1f);
  static const muted = Color(0xff4b5b55);
  static const surface = Color(0xfff3f7f4);
  static const card = Colors.white;
  static const line = Color(0xffdde5e0);
  static const blueIce = Color(0xff2f80ed);
  static const iceLight = Color(0xffe3f0fd);
  static const ground = Color(0xff7a4b2a);
  static const groundLight = Color(0xfff6ede4);
  static const forestLight = Color(0xffe6f4ec);
  static const error = Color(0xffb42318);
  static const warning = Color(0xffb54708);
  static const noData = Color(0xff6b7280);
}

enum ModuleId { bosques, hundimiento, glaciares }

class ModuleStyle {
  const ModuleStyle(this.id, this.color, this.light, this.icon);
  final ModuleId id;
  final Color color;
  final Color light;
  final IconData icon;

  String get key => id.name;
  String get route => '/${id.name}';

  static const forest = ModuleStyle(ModuleId.bosques, Palette.green, Palette.forestLight, Icons.forest_rounded);
  static const subsidence =
      ModuleStyle(ModuleId.hundimiento, Palette.ground, Palette.groundLight, Icons.layers_rounded);
  static const glacier = ModuleStyle(ModuleId.glaciares, Palette.blueIce, Palette.iceLight, Icons.ac_unit_rounded);
  static const all = [forest, subsidence, glacier];

  static ModuleStyle of(ModuleId id) => all.firstWhere((m) => m.id == id);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Palette.green,
    primary: Palette.green,
    secondary: Palette.blueIce,
    surface: Palette.card,
    error: Palette.error,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, scaffoldBackgroundColor: Palette.surface);
  final text = base.textTheme.apply(bodyColor: Palette.ink, displayColor: Palette.ink);
  return base.copyWith(
    textTheme: text.copyWith(
      headlineMedium: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
      headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      bodyLarge: text.bodyLarge?.copyWith(height: 1.45),
      bodyMedium: text.bodyMedium?.copyWith(height: 1.45),
    ),
    cardTheme: CardThemeData(
      color: Palette.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Palette.line),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    chipTheme: base.chipTheme.copyWith(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
    focusColor: Palette.blueIce.withValues(alpha: 0.25),
    visualDensity: VisualDensity.standard,
  );
}

/// True when the user asked the OS/browser to reduce motion.
bool reduceMotion(BuildContext context) =>
    (MediaQuery.maybeOf(context)?.disableAnimations ?? false) || platformPrefersReducedMotion();
