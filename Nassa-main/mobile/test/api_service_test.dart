import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/services/api_service.dart';

void main() {
  test('consulta la ruta de zonas que ofrece el servidor', () async {
    final api = ApiService(
      baseUrl: 'http://localhost:8000/api/v1/',
      client: MockClient((request) async {
        expect(request.url.path, '/api/v1/classified-zones');
        return http.Response('{"features":[]}', 200);
      }),
    );
    addTearDown(api.close);
    expect((await api.getClassifiedZones())['features'], isEmpty);
  });

  test('envía coordenadas y pregunta, sin clave ni mediciones del cliente', () async {
    final api = ApiService(client: MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/api/v1/ai/analyze');
      expect(request.headers['content-type'], 'application/json');
      expect(jsonDecode(request.body), {
        'latitude': 14.63,
        'longitude': -90.50,
        'question': '¿Qué significa?',
      });
      expect(request.headers.containsKey('x-goog-api-key'), isFalse);
      return http.Response('{"analysis":{}}', 200);
    }));
    addTearDown(api.close);
    await api.analyzeZone(14.63, -90.50, question: ' ¿Qué significa? ');
  });

  test('conserva los mensajes de error del servidor en español', () async {
    final api = ApiService(client: MockClient((request) async {
      return http.Response(
        jsonEncode({'detail': 'Gemini aún no está configurado.'}),
        503,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }));
    addTearDown(api.close);
    await expectLater(
      api.analyzeZone(14.63, -90.50),
      throwsA(isA<ApiException>().having(
          (error) => error.message, 'message', 'Gemini aún no está configurado.')),
    );
  });

  test('maneja una respuesta que no sea JSON', () async {
    final api = ApiService(client: MockClient((request) async =>
        http.Response('<html>error</html>', 502)));
    addTearDown(api.close);
    await expectLater(api.getHealth(), throwsA(isA<ApiException>()));
  });
}

