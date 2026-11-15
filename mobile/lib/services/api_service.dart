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
      return 'http://10.0.2.2:8080/api/v1';
    }
    return 'http://127.0.0.1:8080/api/v1'; 
  }

  final http.Client _client;
  final String baseUrl;

  // Función interna para peticiones normales
  Future<Map<String, dynamic>> _request(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl$path');
      final response =
          await (body == null
                  ? _client.get(uri)
                  : _client.post(
                      uri,
                      headers: {'Content-Type': 'application/json'},
                      body: jsonEncode(body),
                    ))
              .timeout(const Duration(seconds: 300)); // 5 minutos máximo

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      
      if (response.statusCode < 200 || response.statusCode >= 300) {
        print('ERROR DEL BACKEND: $decoded'); 
        final detail = decoded is Map ? decoded['detail'] : null;
        throw ApiException(
          detail is String
              ? detail
              : 'No se pudo completar la solicitud (${response.statusCode}).',
        );
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

  // 👇 AGREGAMOS "async" AQUÍ PARA QUE LA SPLASH SCREEN PUEDA USAR await
  Future<Map<String, dynamic>> getHealth() async => _request('/health');
  
  Future<Map<String, dynamic>> getClassifiedZones() => _request('/classified-zones');
  Future<Map<String, dynamic>> getDisplacement(double lat, double lng) => _request('/displacement?lat=$lat&lng=$lng');
  Future<Map<String, dynamic>> getDashboardStats() => _request('/dashboard-stats');

  Future<Map<String, dynamic>> analyzeZone(
    double lat,
    double lng, {
    String? question,
  }) => _request(
    '/ai/analyze',
    body: {
      'latitude': lat,
      'longitude': lng,
      if (question != null && question.trim().isNotEmpty)
        'question': question.trim(),
    },
  );

  // 👇 AQUÍ ESTÁ LA MAGIA DEL REINTENTO ASÍNCRONO
  Future<Map<String, dynamic>> getMetrics(Map<String, dynamic> payload) async {
    int intentos = 0;
    while (intentos < 40) { // Intentar hasta 40 veces (aprox 2 minutos)
      try {
        final response = await _client.post(
          Uri.parse('$baseUrl/metrics'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        );

        if (response.statusCode == 202) {
          // El backend está procesando (Tarea en segundo plano), esperamos 3 segundos
          print('⏳ Esperando a que el backend termine el análisis... (Intento ${intentos + 1})');
          await Future.delayed(const Duration(seconds: 3));
          intentos++;
          continue;
        }

        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return decoded; // ¡Éxito! Devolvemos los datos
        } else {
          final detail = decoded is Map ? decoded['detail'] : null;
          throw ApiException(detail is String ? detail : 'Error ${response.statusCode}');
        }
      } catch (e) {
        if (intentos >= 39) rethrow;
        await Future.delayed(const Duration(seconds: 3));
        intentos++;
      }
    }
    throw const ApiException('El servidor tardó demasiado en procesar los datos.');
  }

  // 👇 AQUÍ ESTÁ LA CORRECCIÓN PARA EL USER_CONTEXT
  Future<Map<String, dynamic>> interpret(String id, {String? userContext}) =>
      _request('/ai/interpret', body: {
        'result_id': id,
        if (userContext != null && userContext.trim().isNotEmpty) 
          'user_context': userContext.trim(),
      });

  void close() => _client.close();
}