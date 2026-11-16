import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Error with bilingual message coming from the backend (`detail`).
class ApiException implements Exception {
  ApiException(this.kind, this.messages, {this.retryable = false, this.status});
  final String kind; // invalid_input | no_data | provider_error | not_configured | timeout | expired | network ...
  final Map<String, String> messages;
  final bool retryable;
  final int? status;

  String message(String lang) => messages[lang] ?? messages['es'] ?? kind;

  factory ApiException.fromDetail(dynamic detail, int status) {
    if (detail is Map && detail['message'] is Map) {
      final m = (detail['message'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()));
      return ApiException(detail['kind']?.toString() ?? 'error', m,
          retryable: detail['retryable'] == true, status: status);
    }
    return ApiException('http_error', {
      'es': 'El servidor respondió con un error ($status).',
      'en': 'The server answered with an error ($status).',
    }, retryable: status >= 500, status: status);
  }

  static ApiException network() => ApiException('network', {
        'es': 'No se pudo conectar con el servidor. Comprueba tu conexión y vuelve a intentarlo.',
        'en': 'Could not reach the server. Check your connection and try again.',
      }, retryable: true);

  @override
  String toString() => message('es');
}

/// Job state reported by the backend while an analysis runs.
class JobStatus {
  JobStatus(this.json);
  final Map<String, dynamic> json;
  String get id => json['job_id'] as String;
  String get status => json['status'] as String;
  String get stage => json['stage'] as String? ?? 'queued';
  bool get done => status == 'done';
  bool get failed => status == 'error';
  Map<String, dynamic>? get result => json['result'] as Map<String, dynamic>?;
  ApiException? get error => failed ? ApiException.fromDetail(json['error'], 200) : null;
}

class ApiService {
  ApiService({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        baseUrl = (baseUrl ?? defaultBaseUrl).replaceFirst(RegExp(r'/+$'), '');

  /// Injected at build time: --dart-define=API_BASE_URL=https://api.example.com/api/v1
  static const _configuredUrl = String.fromEnvironment('API_BASE_URL');

  static String get defaultBaseUrl {
    if (_configuredUrl.isNotEmpty) return _configuredUrl;
    if (kIsWeb) return '${Uri.base.origin}/api/v1'; // same origin (single Render service)
    if (defaultTargetPlatform == TargetPlatform.android) return 'http://10.0.2.2:8000/api/v1';
    return 'http://127.0.0.1:8000/api/v1';
  }

  final http.Client _client;
  final String baseUrl;

  Future<Map<String, dynamic>> _send(String method, String path,
      {Map<String, dynamic>? body, Duration timeout = const Duration(seconds: 30)}) async {
    final uri = Uri.parse('$baseUrl$path');
    http.Response r;
    try {
      final headers = {'Content-Type': 'application/json'};
      final f = switch (method) {
        'POST' => _client.post(uri, headers: headers, body: jsonEncode(body ?? {})),
        'DELETE' => _client.delete(uri),
        _ => _client.get(uri),
      };
      r = await f.timeout(timeout);
    } on TimeoutException {
      throw ApiException('timeout', {
        'es': 'El servidor tardó demasiado en responder. Vuelve a intentarlo.',
        'en': 'The server took too long to answer. Please try again.',
      }, retryable: true);
    } catch (_) {
      throw ApiException.network();
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(r.bodyBytes));
    } on FormatException {
      throw ApiException('bad_response', {
        'es': 'El servidor devolvió una respuesta no válida (${r.statusCode}).',
        'en': 'The server returned an invalid response (${r.statusCode}).',
      }, retryable: true, status: r.statusCode);
    }
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw ApiException.fromDetail(decoded is Map ? decoded['detail'] : null, r.statusCode);
    }
    return decoded as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> health() => _send('GET', '/health', timeout: const Duration(seconds: 75));
  Future<Map<String, dynamic>> config() => _send('GET', '/config');

  Future<List<Map<String, dynamic>>> geocode(String q, String lang) async {
    final r = await _send('GET', '/geocode?q=${Uri.encodeQueryComponent(q)}&lang=$lang');
    return (r['results'] as List).cast<Map<String, dynamic>>();
  }

  Future<JobStatus> startAnalysis(Map<String, dynamic> payload) async =>
      JobStatus(await _send('POST', '/analyses', body: payload));

  Future<JobStatus> analysis(String jobId) async => JobStatus(await _send('GET', '/analyses/$jobId'));

  Future<void> cancel(String jobId) async {
    try {
      await _send('DELETE', '/analyses/$jobId');
    } catch (_) {}
  }

  /// Polls a job until it finishes. Emits every status so the UI can show the real stage.
  Stream<JobStatus> watch(JobStatus first, {Duration every = const Duration(milliseconds: 1500)}) async* {
    var current = first;
    yield current;
    var failures = 0;
    while (!current.done && !current.failed) {
      await Future<void>.delayed(every);
      try {
        current = await analysis(current.id);
        failures = 0;
      } on ApiException catch (e) {
        if (e.kind == 'network' || e.kind == 'timeout') {
          if (++failures >= 5) rethrow; // controlled retries, then give up with a clear message
          continue;
        }
        rethrow;
      }
      yield current;
    }
  }

  Future<Map<String, dynamic>> interpret(String resultId, String locale) =>
      _send('POST', '/interpret', body: {'result_id': resultId, 'locale': locale}, timeout: const Duration(seconds: 90));

  /// Gemini voice (WAV) for a result in [locale]. Generated on the server; may take a few seconds.
  /// Returns null when [part] does not exist (e.g. no explanation to read).
  Future<Uint8List?> speechAudio(String resultId, String locale, {int part = 0}) async {
    http.Response r;
    try {
      r = await _client
          .post(Uri.parse('$baseUrl/speech'),
              headers: {'Content-Type': 'application/json'}, body: jsonEncode({'result_id': resultId, 'locale': locale, 'part': part}))
          .timeout(const Duration(seconds: 120));
    } on TimeoutException {
      throw ApiException('timeout', {
        'es': 'La voz de Gemini tardó demasiado.',
        'en': 'The Gemini voice took too long.',
      }, retryable: true);
    } catch (_) {
      throw ApiException.network();
    }
    if (r.statusCode == 200 && (r.headers['content-type'] ?? '').startsWith('audio/')) return r.bodyBytes;
    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {}
    if (part > 0 && decoded is Map && (decoded['detail'] as Map?)?['kind'] == 'no_data') return null;
    throw ApiException.fromDetail(decoded is Map ? decoded['detail'] : null, r.statusCode);
  }

  void close() => _client.close();
}
