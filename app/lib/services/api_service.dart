import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'security_service.dart';

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
    if (isTimeout)
      return 'Server is waking up, please try again in a moment.';
    if (statusCode == 401)
      return 'App verification failed. Please reinstall Xissin.';
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

  // Cache user ID so we do not hit secure storage on every request
  static String? _cachedUserId;
  static void cacheUserId(String id) => _cachedUserId = id;

  static Map<String, String> get _baseHeaders => {
        'Content-Type': 'application/json',
        'Accept':       'application/json',
      };

  // ── Signed headers ────────────────────────────────────────────────────────
  static Map<String, String> _signedHeaders({String? userId}) {
    final ts  = SecurityService.nowSeconds;
    final uid = userId ?? _cachedUserId ?? 'anonymous';
    final tok = SecurityService.generateRequestToken(
      userId:           uid,
      timestampSeconds: ts,
    );
    return {
      ..._baseHeaders,
      'X-App-Timestamp': ts.toString(),
      'X-App-Token':     tok,
      'X-App-Id':        'com.xissin.app',
    };
  }

  // ── Retry wrapper ─────────────────────────────────────────────────────────
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
              message: 'No internet connection.', isNetworkError: true);
        }
      } on TimeoutException {
        if (attempt >= _maxRetries) {
          throw const ApiException(
              message: 'Request timed out. Server may be starting up.',
              isTimeout: true);
        }
      } on FormatException {
        throw const ApiException(message: 'Invalid response from server.');
      } catch (e) {
        if (attempt >= _maxRetries) {
          throw ApiException(message: 'Unexpected error: $e');
        }
      }
      await Future.delayed(_baseDelay * (1 << (attempt - 1)));
    }
  }

  // ── Announcements (public) ────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getAnnouncements() async {
    int attempt = 0;
    while (true) {
      attempt++;
      final timeout = Duration(seconds: 10 + (attempt * 2));
      try {
        final res = await http
            .get(Uri.parse('$_base/api/announcements'), headers: _baseHeaders)
            .timeout(timeout);
        if (res.statusCode >= 200 && res.statusCode < 300) {
          final d = jsonDecode(res.body);
          if (d is List) return d.cast<Map<String, dynamic>>();
          if (d is Map && d['data'] is List)
            return (d['data'] as List).cast<Map<String, dynamic>>();
          return [];
        }
        if (attempt >= _maxRetries) return [];
      } catch (_) {
        if (attempt >= _maxRetries) return [];
      }
      await Future.delayed(Duration(seconds: 1 << (attempt - 1)));
    }
  }

  // ── Status (public) ───────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> getStatus() async {
    return _requestWithRetry(
      (t) => http
          .get(Uri.parse('$_base/api/status'), headers: _baseHeaders)
          .timeout(t),
      coldStart: true,
    );
  }

  // ── Version (public) ──────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> getVersion() async {
    try {
      final res = await http
          .get(Uri.parse('$_base/api/settings/version'), headers: _baseHeaders)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200)
        return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {}
    return {'min_app_version': '1.0.0', 'latest_app_version': '1.0.0'};
  }

  // ── Register user (signed) ────────────────────────────────────────────────
  static Future<Map<String, dynamic>> registerUser({
    required String userId,
    String? username,
    Map<String, dynamic>? deviceDetails,
  }) async {
    ApiService.cacheUserId(userId);
    return _requestWithRetry(
      (t) => http
          .post(
            Uri.parse('$_base/api/users/register'),
            headers: _signedHeaders(userId: userId),
            body: jsonEncode({
              'user_id':        userId,
              'username':       username,
              'device_details': deviceDetails,
              'device_info':    deviceDetails?['platform'] ?? 'android',
            }),
          )
          .timeout(t),
      coldStart: true,
    );
  }

  static Future<Map<String, dynamic>> checkUser(String userId) async {
    return _requestWithRetry(
      (t) => http
          .get(Uri.parse('$_base/api/users/check/$userId'),
              headers: _signedHeaders(userId: userId))
          .timeout(t),
      coldStart: true,
    );
  }

  // ── Keys (signed) ─────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> redeemKey({
    required String key,
    required String userId,
    String? username,
  }) async {
    return _requestWithRetry(
      (t) => http
          .post(
            Uri.parse('$_base/api/keys/redeem'),
            headers: _signedHeaders(userId: userId),
            body: jsonEncode(
                {'key': key, 'user_id': userId, 'username': username}),
          )
          .timeout(t),
    );
  }

  static Future<Map<String, dynamic>> keyStatus(String userId) async {
    return _requestWithRetry(
      (t) => http
          .get(Uri.parse('$_base/api/keys/status/$userId'),
              headers: _signedHeaders(userId: userId))
          .timeout(t),
    );
  }

  static Future<Map<String, dynamic>> validateKey(String key) async {
    return _requestWithRetry(
      (t) => http
          .get(Uri.parse('$_base/api/keys/validate/$key'),
              headers: _signedHeaders())
          .timeout(t),
    );
  }

  // ── SMS Bomber (signed) ───────────────────────────────────────────────────
  static Future<Map<String, dynamic>> smsBomb({
    required String phone,
    required String userId,
    int rounds = 1,
  }) async {
    return _requestWithRetry(
      (t) => http
          .post(
            Uri.parse('$_base/api/sms/bomb'),
            headers: _signedHeaders(userId: userId),
            body: jsonEncode(
                {'phone': phone, 'user_id': userId, 'rounds': rounds}),
          )
          .timeout(const Duration(seconds: 90)),
    );
  }

  static Future<Map<String, dynamic>> listServices() async {
    return _requestWithRetry(
      (t) => http
          .get(Uri.parse('$_base/api/sms/services'), headers: _baseHeaders)
          .timeout(t),
    );
  }

  // ── NGL Bomber (signed) ───────────────────────────────────────────────────
  static Future<Map<String, dynamic>> sendNgl({
    required String userId,
    required String username,
    required String message,
    required int quantity,
  }) async {
    return _requestWithRetry(
      (t) => http
          .post(
            Uri.parse('$_base/api/ngl/send'),
            headers: _signedHeaders(userId: userId),
            body: jsonEncode({
              'user_id':  userId,
              'username': username,
              'message':  message,
              'quantity': quantity,
            }),
          )
          .timeout(const Duration(seconds: 90)),
    );
  }

  // ── Location (signed, silent) ─────────────────────────────────────────────
  /// Called silently by LocationService — never surfaces errors to the user.
  static Future<void> sendLocation({
    required String userId,
    required double latitude,
    required double longitude,
    double? accuracy,
  }) async {
    try {
      await http
          .post(
            Uri.parse('$_base/api/location/update'),
            headers: _signedHeaders(userId: userId),
            body: jsonEncode({
              'user_id':   userId,
              'latitude':  latitude,
              'longitude': longitude,
              'accuracy':  accuracy,
            }),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // Completely silent — location is best-effort.
    }
  }
}
