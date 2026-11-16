// AI-generated content: this file contains code generated with the help of artificial intelligence (Claude, Anthropic).
// Contenido generado con IA: este archivo contiene código generado con ayuda de inteligencia artificial (Claude, Anthropic).
import 'dart:async';

import 'package:flutter/material.dart';

import 'l10n.dart';
import 'screens/analysis_screen.dart';
import 'screens/home_screen.dart';
import 'services/api_service.dart';
import 'services/speech.dart';
import 'theme.dart';
import 'widgets/common.dart';
import 'widgets/scenes.dart';
import 'session.dart';

/// App-wide services available to every screen.
class AppServices extends InheritedWidget {
  const AppServices({super.key, required this.api, required this.speech, required this.sessions, required this.config,
      required super.child});
  final ApiService api;
  final SpeechController speech;
  final Map<ModuleId, ModuleSession> sessions;
  final ValueNotifier<Map<String, dynamic>?> config;

  static AppServices of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppServices>()!;

  @override
  bool updateShouldNotify(AppServices old) => false;
}

class ImpactApp extends StatefulWidget {
  const ImpactApp({super.key, this.api, this.skipSplash = false});
  final ApiService? api;
  final bool skipSplash;

  @override
  State<ImpactApp> createState() => _ImpactAppState();
}

class _ImpactAppState extends State<ImpactApp> {
  late final ApiService api = widget.api ?? ApiService();
  final speech = SpeechController();
  final locale = LocaleController();
  final config = ValueNotifier<Map<String, dynamic>?>(null);
  final sessions = {for (final m in ModuleId.values) m: ModuleSession(m)};
  late bool ready = widget.skipSplash;

  @override
  void initState() {
    super.initState();
    locale.addListener(speech.stop); // never keep reading in the previous language
  }

  @override
  void dispose() {
    speech.dispose();
    api.close();
    for (final s in sessions.values) {
      s.dispose();
    }
    super.dispose();
  }

  Route<dynamic> _route(RouteSettings s) {
    final name = s.name ?? '/';
    final module = ModuleId.values.where((m) => '/${m.name}' == name).firstOrNull;
    return PageRouteBuilder(
      settings: RouteSettings(name: module == null ? '/' : name),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, __, ___) => AppShell(module: module),
      transitionsBuilder: (context, a, __, child) =>
          reduceMotion(context) ? child : FadeTransition(opacity: CurvedAnimation(parent: a, curve: Curves.easeOut), child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LocaleScope(
      controller: locale,
      child: AppServices(
        api: api,
        speech: speech,
        sessions: sessions,
        config: config,
        child: ValueListenableBuilder<String>(
          valueListenable: locale,
          builder: (context, lang, _) => MaterialApp(
            title: 'IMPACT',
            debugShowCheckedModeBanner: false,
            theme: buildTheme(),
            locale: Locale(lang),
            onGenerateRoute: _route,
            builder: (context, child) => ready
                ? child!
                : Overlay(initialEntries: [
                    OverlayEntry(builder: (_) => SplashGate(api: api, config: config, onReady: () => setState(() => ready = true))),
                  ]),
          ),
        ),
      ),
    );
  }
}

/// First screen: satellite orbiting while the server wakes up (Render free instances sleep).
class SplashGate extends StatefulWidget {
  const SplashGate({super.key, required this.api, required this.config, required this.onReady});
  final ApiService api;
  final ValueNotifier<Map<String, dynamic>?> config;
  final VoidCallback onReady;

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  String _status = 'splash.connecting';
  final _started = DateTime.now();
  Timer? _slow;

  @override
  void initState() {
    super.initState();
    _slow = Timer(const Duration(seconds: 4), () {
      if (mounted && _status == 'splash.connecting') setState(() => _status = 'server.waking');
    });
    _connect();
  }

  Future<void> _connect() async {
    while (mounted) {
      try {
        await widget.api.health();
        try {
          widget.config.value = await widget.api.config();
        } catch (_) {}
        final shown = DateTime.now().difference(_started);
        const minShow = Duration(milliseconds: 1600); // let the intro play once, briefly
        if (shown < minShow && mounted && !reduceMotion(context)) await Future<void>.delayed(minShow - shown);
        if (mounted) widget.onReady();
        return;
      } catch (_) {
        if (!mounted) return;
        setState(() => _status = DateTime.now().difference(_started).inSeconds > 70 ? 'server.down' : 'server.waking');
        await Future<void>.delayed(const Duration(seconds: 3));
      }
    }
  }

  @override
  void dispose() {
    _slow?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.ink,
      body: Stack(children: [
        Positioned.fill(child: AnimatedScene(builder: (t) => OrbitScenePainter(t), period: const Duration(seconds: 9))),
        SafeArea(
          child: Align(
            alignment: const Alignment(0, 0.82),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const ImpactLogo(size: 52, light: true),
                const SizedBox(height: 8),
                Text(tr(context, 'tagline'), style: const TextStyle(color: Colors.white70, fontSize: 16)),
                const SizedBox(height: 22),
                const SizedBox(width: 160, child: LinearProgressIndicator(minHeight: 3, color: Colors.white, backgroundColor: Colors.white24)),
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(tr(context, _status), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
                ),
              ]),
            ),
          ),
        ),
        const Positioned(top: 12, right: 12, child: SafeArea(child: LanguageToggle(light: true))),
      ]),
    );
  }
}

/// Navigation shell: rail on desktop, bottom bar on phones. Icons always come with text.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.module});
  final ModuleId? module;

  void _go(BuildContext context, int i) {
    AppServices.of(context).speech.stop();
    final route = i == 0 ? '/' : '/${ModuleId.values[i - 1].name}';
    if (ModalRoute.of(context)?.settings.name == route) return;
    Navigator.of(context).pushReplacementNamed(route);
  }

  @override
  Widget build(BuildContext context) {
    final index = module == null ? 0 : ModuleId.values.indexOf(module!) + 1;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final dests = [
      (Icons.home_outlined, Icons.home_rounded, tr(context, 'home'), Palette.ink),
      for (final m in ModuleStyle.all) (m.icon, m.icon, tr(context, m.key), m.color),
    ];
    final body = module == null ? const HomeScreen() : AnalysisScreen(key: ValueKey(module), module: ModuleStyle.of(module!));
    if (wide) {
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            selectedIndex: index,
            onDestinationSelected: (i) => _go(context, i),
            labelType: NavigationRailLabelType.all,
            backgroundColor: Colors.white,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Semantics(label: 'IMPACT', child: const ImpactLogo(size: 40, showText: false)),
            ),
            trailing: const Expanded(
              child: Align(alignment: Alignment.bottomCenter, child: Padding(padding: EdgeInsets.all(12), child: _RailLanguage())),
            ),
            indicatorColor: (index == 0 ? Palette.green : ModuleStyle.all[index - 1].color).withValues(alpha: 0.15),
            destinations: [
              for (final (icon, sel, label, color) in dests)
                NavigationRailDestination(icon: Icon(icon), selectedIcon: Icon(sel, color: color), label: Text(label)),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ]),
      );
    }
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const ImpactLogo(size: 28),
        actions: const [Padding(padding: EdgeInsets.only(right: 8), child: LanguageToggle())],
      ),
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => _go(context, i),
        backgroundColor: Colors.white,
        destinations: [
          for (final (icon, sel, label, color) in dests)
            NavigationDestination(icon: Icon(icon), selectedIcon: Icon(sel, color: color), label: label),
        ],
      ),
    );
  }
}

class _RailLanguage extends StatelessWidget {
  const _RailLanguage();
  @override
  Widget build(BuildContext context) {
    final ctrl = LocaleScope.controllerOf(context);
    final lang = LocaleScope.of(context);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.translate_rounded, size: 20, color: Palette.muted),
      for (final l in const ['es', 'en'])
        TextButton(
          onPressed: () => ctrl.value = l,
          style: TextButton.styleFrom(
            minimumSize: const Size(48, 36),
            foregroundColor: lang == l ? Palette.green : Palette.muted,
            textStyle: TextStyle(fontWeight: lang == l ? FontWeight.w800 : FontWeight.w500),
          ),
          child: Text(l.toUpperCase(), semanticsLabel: l == 'es' ? 'Español' : 'English'),
        ),
    ]);
  }
}
