import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final bool isNetworkError;
  final bool isTimeout;

  const ApiException({
    required this.message,
    this.statusCode,
    this.isNetworkError = false,
    this.isTimeout = false,
  });

  @override
  String toString() => message;

  String get userMessage {
    if (isNetworkError)
      return 'No internet connection. Please check your network.';
    if (isTimeout) return 'Server is waking up, please try again in a moment.';
    if (statusCode == 429) return 'Too many requests. Please slow down.';
    if (statusCode == 403) return 'Access denied. Your key may be expired.';
    if (statusCode != null && statusCode! >= 500)
      return 'Server error. Please try again.';
    return message;
  }
}

class ApiService {
  static const String _base =
      'https://xissin-app-backend-production.up.railway.app';

  static const int _maxRetries = 3;
  static const Duration _baseDelay = Duration(seconds: 1);

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  static Future<Map<String, dynamic>> _requestWithRetry(
    Future<http.Response> Function(Duration timeout) request, {
    bool coldStart = false,
  }) async {
    int attempt = 0;

    while (true) {
      attempt++;

      final timeout = (attempt == 1 && coldStart)
          ? const Duration(seconds: 20)
          : Duration(seconds: 10 + (attempt * 2));

      try {
        final res = await request(timeout);

        if (res.statusCode >= 200 && res.statusCode < 300) {
          return jsonDecode(res.body) as Map<String, dynamic>;
        }

        Map<String, dynamic> body = {};
        try {
          body = jsonDecode(res.body) as Map<String, dynamic>;
        } catch (_) {}

        final serverMsg = body['detail'] as String? ??
            body['message'] as String? ??
            'Request failed (${res.statusCode})';

        if (res.statusCode >= 400 && res.statusCode < 500) {
          throw ApiException(message: serverMsg, statusCode: res.statusCode);
        }

        if (attempt >= _maxRetries) {
          throw ApiException(message: serverMsg, statusCode: res.statusCode);
        }
      } on ApiException {
        rethrow;
      } on SocketException {
        if (attempt >= _maxRetries) {
          throw const ApiException(
            message: 'No internet connection.',
            isNetworkError: true,
          );
        }
      } on TimeoutException {
        if (attempt >= _maxRetries) {
          throw const ApiException(
            message: 'Request timed out. Server may be starting up.',
            isTimeout: true,
          );
        }
      } on FormatException {
        throw const ApiException(message: 'Invalid response from server.');
      } catch (e) {
        if (attempt >= _maxRetries) {
          throw ApiException(message: 'Unexpected error: $e');
        }
      }

      final delay = _baseDelay * (1 << (attempt - 1));
      await Future.delayed(delay);
    }
  }

  // ── Announcements ─────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getAnnouncements() async {
    int attempt = 0;
    while (true) {
      attempt++;
      final timeout = Duration(seconds: 10 + (attempt * 2));
      try {
        final res = await http
            .get(Uri.parse('$_base/api/announcements'), headers: _headers)
            .timeout(timeout);
        if (res.statusCode >= 200 && res.statusCode < 300) {
          final decoded = jsonDecode(res.body);
          if (decoded is List) {
            return decoded.cast<Map<String, dynamic>>();
          }
          if (decoded is Map && decoded['data'] is List) {
            return (decoded['data'] as List).cast<Map<String, dynamic>>();
          }
          return [];
        }
        if (attempt >= _maxRetries) return [];
      } catch (_) {
        if (attempt >= _maxRetries) return [];
      }
      await Future.delayed(Duration(seconds: 1 << (attempt - 1)));
    }
  }

  // ── Status ────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getStatus() async {
    return _requestWithRetry(
      (timeout) => http
          .get(Uri.parse('$_base/api/status'), headers: _headers)
          .timeout(timeout),
      coldStart: true,
    );
  }

  // ── Users ─────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> registerUser({
    required String userId,
    String? username,
    String? deviceInfo,
  }) async {
    return _requestWithRetry(
      (timeout) => http
          .post(
            Uri.parse('$_base/api/users/register'),
            headers: _headers,
            body: jsonEncode({
              'user_id': userId,
              'username': username,
              'device_info': deviceInfo,
            }),
          )
          .timeout(timeout),
      coldStart: true,
    );
  }

  static Future<Map<String, dynamic>> checkUser(String userId) async {
    return _requestWithRetry(
      (timeout) => http
          .get(Uri.parse('$_base/api/users/check/$userId'), headers: _headers)
          .timeout(timeout),
      coldStart: true,
    );
  }

  // ── Keys ──────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> redeemKey({
    required String key,
    required String userId,
    String? username,
  }) async {
    return _requestWithRetry(
      (timeout) => http
          .post(
            Uri.parse('$_base/api/keys/redeem'),
            headers: _headers,
            body: jsonEncode({
              'key': key,
              'user_id': userId,
              'username': username,
            }),
          )
          .timeout(timeout),
    );
  }

  static Future<Map<String, dynamic>> keyStatus(String userId) async {
    return _requestWithRetry(
      (timeout) => http
          .get(Uri.parse('$_base/api/keys/status/$userId'), headers: _headers)
          .timeout(timeout),
    );
  }

  static Future<Map<String, dynamic>> validateKey(String key) async {
    return _requestWithRetry(
      (timeout) => http
          .get(Uri.parse('$_base/api/keys/validate/$key'), headers: _headers)
          .timeout(timeout),
    );
  }

  // ── SMS Bomber ────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> smsBomb({
    required String phone,
    required String userId,
    int rounds = 1,
  }) async {
    return _requestWithRetry(
      (timeout) => http
          .post(
            Uri.parse('$_base/api/sms/bomb'),
            headers: _headers,
            body: jsonEncode({
              'phone': phone,
              'user_id': userId,
              'rounds': rounds,
            }),
          )
          .timeout(const Duration(seconds: 90)),
    );
  }

  static Future<Map<String, dynamic>> listServices() async {
    return _requestWithRetry(
      (timeout) => http
          .get(Uri.parse('$_base/api/sms/services'), headers: _headers)
          .timeout(timeout),
    );
  }
}
