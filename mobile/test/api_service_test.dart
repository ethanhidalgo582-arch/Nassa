import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/services/api_service.dart';

void main() {
  test('starts an analysis and polls until done (real stages, no invented progress)', () async {
    var polls = 0;
    final api = ApiService(
      baseUrl: 'http://x/api/v1/',
      client: MockClient((r) async {
        if (r.method == 'POST') {
          expect(r.url.path, '/api/v1/analyses');
          expect(jsonDecode(r.body)['module'], 'bosques');
          return http.Response(jsonEncode({'job_id': 'j1', 'status': 'running', 'stage': 'searching'}), 202);
        }
        polls++;
        return http.Response(
            jsonEncode(polls < 2
                ? {'job_id': 'j1', 'status': 'running', 'stage': 'processing'}
                : {'job_id': 'j1', 'status': 'done', 'stage': 'done', 'result': {'result_id': 'r'}}),
            200);
      }),
    );
    final first = await api.startAnalysis({'module': 'bosques', 'polygon': []});
    final stages = await api.watch(first, every: Duration.zero).map((s) => s.stage).toList();
    expect(stages, ['searching', 'processing', 'done']);
  });

  test('keeps bilingual backend error messages and kinds', () async {
    final api = ApiService(client: MockClient((r) async => http.Response(
        jsonEncode({'detail': {'kind': 'no_data', 'message': {'es': 'Sin datos', 'en': 'No data'}, 'retryable': false}}), 422,
        headers: {'content-type': 'application/json; charset=utf-8'})));
    try {
      await api.startAnalysis({});
      fail('should throw');
    } on ApiException catch (e) {
      expect(e.kind, 'no_data');
      expect(e.message('en'), 'No data');
      expect(e.message('es'), 'Sin datos');
    }
  });

  test('server restart (404) is reported as expired, not as a crash', () async {
    final api = ApiService(client: MockClient((r) async => http.Response(
        jsonEncode({'detail': {'kind': 'expired', 'message': {'es': 'expiró', 'en': 'expired'}, 'retryable': true}}), 404,
        headers: {'content-type': 'application/json; charset=utf-8'})));
    expect(api.analysis('x'), throwsA(isA<ApiException>().having((e) => e.kind, 'kind', 'expired')));
  });

  test('non-JSON responses are handled', () async {
    final api = ApiService(client: MockClient((r) async => http.Response('<html>502</html>', 502)));
    expect(api.health(), throwsA(isA<ApiException>()));
  });

  test('no secrets are sent by the client', () async {
    final api = ApiService(client: MockClient((r) async {
      expect(r.headers.keys.any((k) => k.toLowerCase().contains('key')), isFalse);
      return http.Response(jsonEncode({'result_id': 'r', 'locale': 'en', 'answer': {}}), 200);
    }));
    await api.interpret('r', 'en');
  });
}
