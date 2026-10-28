import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  const ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ApiService {
  ApiService({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        baseUrl = (baseUrl ?? defaultBaseUrl).replaceFirst(RegExp(r'/+$'), '');

  static const _configuredUrl = String.fromEnvironment('API_BASE_URL');
      static String get defaultBaseUrl {
    if (_configuredUrl.isNotEmpty) return _configuredUrl;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000/api/v1'; 
    }
    return 'http://127.0.0.1:8000/api/v1'; // <--- Asegúrate de que termine en /api/v1
  }

  final http.Client _client;
  final String baseUrl;

  Future<Map<String, dynamic>> _request(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl$path');
      final response = await (body == null
              ? _client.get(uri)
              : _client.post(
                  uri,
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode(body),
                ))
          .timeout(Duration(seconds: body == null ? 15 : 60));
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final detail = decoded is Map ? decoded['detail'] : null;
        throw ApiException(detail is String
            ? detail
            : 'No se pudo completar la solicitud (${response.statusCode}).');
      }
      if (decoded is! Map<String, dynamic>) {
        throw const ApiException('El servidor devolvió una respuesta inesperada.');
      }
      return decoded;
    } on TimeoutException {
      throw const ApiException('La solicitud tardó demasiado. Intenta de nuevo.');
    } on http.ClientException {
      throw const ApiException('No se pudo conectar con el servidor.');
    } on FormatException {
      throw const ApiException('El servidor devolvió una respuesta no válida.');
    }
  }

  Future<Map<String, dynamic>> getClassifiedZones() =>
      _request('/classified-zones');

  Future<Map<String, dynamic>> getDisplacement(double lat, double lng) =>
      _request('/displacement?lat=$lat&lng=$lng');

  Future<Map<String, dynamic>> getDashboardStats() => _request('/dashboard-stats');

  Future<Map<String, dynamic>> getHealth() => _request('/health');

  Future<Map<String, dynamic>> analyzeZone(
    double lat,
    double lng, {
    String? question,
  }) =>
      _request('/ai/analyze', body: {
        'latitude': lat,
        'longitude': lng,
        if (question != null && question.trim().isNotEmpty)
          'question': question.trim(),
      });

  void close() => _client.close();
}

