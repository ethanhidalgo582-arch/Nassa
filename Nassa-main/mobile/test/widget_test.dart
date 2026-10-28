import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/ai_analysis_panel.dart';
import 'package:mobile/services/api_service.dart';

class FakeApi extends ApiService {
  final pending = Completer<Map<String, dynamic>>();
  int calls = 0;

  @override
  Future<Map<String, dynamic>> analyzeZone(double lat, double lng,
      {String? question}) {
    calls++;
    return pending.future;
  }
}

const report = <String, dynamic>{
  'notice': 'Datos simulados para probar la aplicación.',
  'analysis': {
    'summary': 'Resumen de la zona seleccionada',
    'observations': ['Observación'],
    'limitations': ['Sin mediciones reales'],
    'suggested_next_steps': ['Validar datos'],
  },
};

Widget panel(ApiService api, {bool configured = true, double latitude = 14.63}) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: AiAnalysisPanel(
          api: api,
          latitude: latitude,
          longitude: -90.50,
          configured: configured,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('muestra el resultado y evita solicitudes duplicadas', (tester) async {
    final api = FakeApi();
    addTearDown(api.close);
    await tester.pumpWidget(panel(api));
    await tester.tap(find.text('Analizar con Gemini'));
    await tester.pump();
    expect(api.calls, 1);
    expect(find.text('Analizando…'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byWidgetPredicate((widget) => widget is FilledButton));
    expect(button.onPressed, isNull);
    api.pending.complete(report);
    await tester.pumpAndSettle();
    expect(find.text('Resumen de la zona seleccionada'), findsOneWidget);
    expect(find.text('Datos simulados para probar la aplicación.'), findsOneWidget);
  });

  testWidgets('deshabilita Gemini cuando falta configuración', (tester) async {
    final api = FakeApi();
    addTearDown(api.close);
    await tester.pumpWidget(panel(api, configured: false));
    final button = tester.widget<FilledButton>(find.byWidgetPredicate((widget) => widget is FilledButton));
    expect(button.onPressed, isNull);
    expect(api.calls, 0);
  });

  testWidgets('descarta respuestas de una selección anterior', (tester) async {
    final api = FakeApi();
    addTearDown(api.close);
    await tester.pumpWidget(panel(api));
    await tester.tap(find.text('Analizar con Gemini'));
    await tester.pump();
    await tester.pumpWidget(panel(api, latitude: 14.65));
    api.pending.complete(report);
    await tester.pumpAndSettle();
    expect(find.text('Resumen de la zona seleccionada'), findsNothing);
    expect(find.text('Analizar con Gemini'), findsOneWidget);
  });
}

