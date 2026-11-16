import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/app.dart';
import 'package:mobile/services/api_service.dart';
import 'package:mobile/services/speech.dart';
import 'package:mobile/widgets/map_panel.dart';

ApiService fakeApi() => ApiService(
      baseUrl: 'http://x/api/v1',
      client: MockClient((r) async {
        if (r.url.path.endsWith('/config')) {
          return http.Response(
              jsonEncode({
                'gemini_configured': false,
                'earthdata_configured': false,
                'limits': {'max_area_km2': 20000},
                'tiles': {'carto_key': null},
                'modules': {
                  'bosques': {'first_year': 2001, 'last_year': 2025, 'default': {'start_year': 2016, 'end_year': 2025}},
                  'hundimiento': {'first_date': '2025-10-28', 'default': {'start_date': '2025-10-28', 'end_date': '2026-11-15'}},
                  'glaciares': {'first_date': '2025-10-28', 'default': {'start_date': '2026-07-18', 'end_date': '2026-11-15'}},
                },
              }),
              200);
        }
        return http.Response(jsonEncode({'status': 'ok'}), 200);
      }),
    );

Future<void> pumpApp(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ImpactApp(api: fakeApi(), skipSplash: true));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(() => MapPanel.offlineTiles = true);
  testWidgets('desktop: navigation with icon + text to every module, no overflow', (tester) async {
    await pumpApp(tester, const Size(1400, 900));
    expect(find.text('Bosques'), findsWidgets);
    for (final name in ['Bosques', 'Hundimiento', 'Glaciares', 'Inicio']) {
      await tester.tap(find.descendant(of: find.byType(NavigationRail), matching: find.text(name)));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(seconds: 2)); // module intro ends
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('phone: bottom navigation and analysis flow layout', (tester) async {
    await pumpApp(tester, const Size(390, 844));
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Glaciares')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 2));
    final scroll = tester.state<ScrollableState>(
        find.descendant(of: find.byType(CustomScrollView), matching: find.byType(Scrollable)).first);
    for (var i = 0; i < 6 && find.text('Analizar zona').evaluate().isEmpty; i++) {
      scroll.position.jumpTo(scroll.position.pixels + 400);
      await tester.pump();
    }
    expect(find.text('Analizar zona'), findsOneWidget); // primary action reachable on a phone
    expect(tester.takeException(), isNull);
  });

  testWidgets('language switch translates the interface', (tester) async {
    await pumpApp(tester, const Size(1400, 900));
    await tester.tap(find.text('EN').first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Forests'), findsWidgets);
    expect(find.textContaining('See how the land changes'), findsOneWidget);
  });

  test('speech splits text into sentences and refuses silently on unsupported platforms', () async {
    expect(SpeechController.sentences('Uno. Dos: tres; cuatro!'), ['Uno.', 'Dos:', 'tres;', 'cuatro!']);
    final s = SpeechController();
    await s.speak('Hola.', 'es', owner: 'a');
    expect(s.problem, 'unsupported'); // VM test: no browser speech engine, text stays available
    expect(s.state, SpeechState.idle);
  });

  test('Gemini voice failure falls back to the browser voice with a visible reason', () async {
    final s = SpeechController();
    await s.speak('Hola.', 'es', owner: 'a', fetchAudio: (_) async => throw ApiException('provider_error', {'es': 'cuota', 'en': 'quota'}));
    expect(s.geminiError?.message('es'), 'cuota');
    expect(s.problem, 'gemini_fallback');
    expect(s.engine, SpeechEngine.browser);
    expect(s.state, SpeechState.idle);
  });

  test('stopping while Gemini audio is generating never plays late audio', () async {
    final s = SpeechController();
    final gate = Completer<Uint8List?>();
    final f = s.speak('Hola.', 'es', owner: 'a', fetchAudio: (_) => gate.future);
    expect(s.state, SpeechState.starting);
    s.stop();
    gate.complete(Uint8List(4));
    await f;
    expect(s.state, SpeechState.idle);
  });
}
