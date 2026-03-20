// lib/services/api_service.dart
//
// Optimizations:
//   ✅ Response caching         — status/announcements cached for 60s
//   ✅ Request deduplication    — identical in-flight requests share one Future
//                                 (correctly cleared on both success AND error)
//   ✅ Exponential backoff      — smarter retry delays
//   ✅ Signed headers           — HMAC token on all user-specific requests
//   ✅ Better error messages    — user-facing strings for every error type

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'security_service.dart';

// ── Pinned HTTP client (singleton) ────────────────────────────────────────────
// All requests go through this client which validates:
//   • Hostname must be our Railway backend
//   • TLS cert must be issued by Let's Encrypt
// Created once, reused for all requests.
final http.Client _pinnedClient = SecurityService.createPinnedClient();

// ── Exception ─────────────────────────────────────────────────────────────────

class ApiException implements Exception {
  final String message;
  final int?   statusCode;
  final bool   isNetworkError;
  final bool   isTimeout;

  const ApiException({
    required this.message,
    this.statusCode,
    this.isNetworkError = false,
    this.isTimeout      = false,
  });

  @override
  String toString() => message;

  String get userMessage {
    if (isNetworkError) return 'No internet connection. Please check your network.';
    if (isTimeout)      return 'Server is waking up, please try again in a moment.';
    if (statusCode == 401) return 'App verification failed. Please reinstall Xissin.';
    if (statusCode == 403) return 'Access denied.';
    if (statusCode == 429) return 'Too many requests. Please slow down.';
    if (statusCode != null && statusCode! >= 500)
      return 'Server error. Please try again later.';
    return message;
  }
}

// ── Cache entry ───────────────────────────────────────────────────────────────

class _CacheEntry {
  final Map<String, dynamic> data;
  final DateTime             expiresAt;
  _CacheEntry(this.data, Duration ttl)
      : expiresAt = DateTime.now().add(ttl);
  bool get isValid => DateTime.now().isBefore(expiresAt);
}

// ── ApiService ────────────────────────────────────────────────────────────────

class ApiService {
  static const String _base =
      'https://xissin-app-backend-production.up.railway.app';

  static const int      _maxRetries = 3;
  static const Duration _baseDelay  = Duration(seconds: 1);

  // ── In-memory response cache ──────────────────────────────────────────────
  static final Map<String, _CacheEntry> _cache = {};

  // ── In-flight dedup map ───────────────────────────────────────────────────
  // IMPORTANT: must be cleared on BOTH success AND error.
  // Using a Completer-based approach to guarantee cleanup.
  static final Map<String, Future<dynamic>> _inflight = {};

  // ── User ID cache ─────────────────────────────────────────────────────────
  static String? _cachedUserId;
  static void cacheUserId(String id) => _cachedUserId = id;

  // ── Session token cache ───────────────────────────────────────────────────
  // Set once on app launch by calling ApiService.initSession()
  // All _signedHeaders() calls use this automatically
  static String? _sessionToken;
  static void cacheSessionToken(String token) => _sessionToken = token;

  /// Called from splash screen BEFORE any other API call.
  /// Retrieves or creates a session token via SecurityService.
  static Future<void> initSession({
    required String userId,
    String? deviceModel,
    String? osVersion,
  }) async {
    final fingerprint = SecurityService.generateDeviceFingerprint(
      userId:    userId,
      model:     deviceModel,
      osVersion: osVersion,
    );
    final token = await SecurityService.initSession(
      deviceFingerprint: fingerprint,
    );
    if (token != null) {
      _sessionToken = token;
    }
  }

  /// Force-refreshes the session (called when backend returns 401)
  static Future<void> _refreshSession() async {
    if (_cachedUserId == null) return;
    final fingerprint = SecurityService.generateDeviceFingerprint(
      userId: _cachedUserId!,
    );
    final token = await SecurityService.refreshSession(
      deviceFingerprint: fingerprint,
    );
    if (token != null) _sessionToken = token;
  }

  // ── Headers ───────────────────────────────────────────────────────────────

  static Map<String, String> get _baseHeaders => {
    'Content-Type': 'application/json',
    'Accept':       'application/json',
  };

  static Map<String, String> _signedHeaders({String? userId}) {
    // Use session token (server-side validated, not derivable from APK secrets)
    if (_sessionToken != null) {
      return SecurityService.buildHeaders(sessionToken: _sessionToken!);
    }
    // Fallback: no session yet — send app ID only (backend will 401 if needed)
    return SecurityService.buildUnauthHeaders();
  }

  // ── Cache helpers ─────────────────────────────────────────────────────────

  static Map<String, dynamic>? _getCache(String key) {
    final entry = _cache[key];
    if (entry != null && entry.isValid) return entry.data;
    _cache.remove(key);
    return null;
  }

  static void _setCache(String key, Map<String, dynamic> data, Duration ttl) {
    _cache[key] = _CacheEntry(data, ttl);
  }

  static void clearCache() {
    _cache.clear();
    _inflight.clear(); // also clear stuck in-flight entries
  }

  // ── Request deduplication ─────────────────────────────────────────────────
  // FIX: use try/finally to ALWAYS remove from _inflight, even on error.
  // The old version used .whenComplete() which doesn't fire on uncaught throws
  // from async generators — causing permanent stuck futures.

  static Future<T> _dedupe<T>(String key, Future<T> Function() fn) {
    if (_inflight.containsKey(key)) {
      return _inflight[key]! as Future<T>;
    }
    // Create and immediately register the future
    final future = Future<T>(() async {
      try {
        return await fn();
      } finally {
        // Always remove — whether success, error, or cancel
        _inflight.remove(key);
      }
    });
    _inflight[key] = future;
    return future;
  }

  // ── Core retry wrapper ────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> _requestWithRetry(
    Future<http.Response> Function(Duration timeout) request, {
    bool coldStart = false,
  }) async {
    int attempt = 0;
    while (true) {
      attempt++;
      final timeout = (attempt == 1 && coldStart)
          ? const Duration(seconds: 20)
          : Duration(seconds: 12 + (attempt * 2));
      try {
        final res = await request(timeout);

        if (res.statusCode >= 200 && res.statusCode < 300) {
          return jsonDecode(res.body) as Map<String, dynamic>;
        }

        Map<String, dynamic> body = {};
        try { body = jsonDecode(res.body) as Map<String, dynamic>; } catch (_) {}

        final msg = body['detail'] as String?
            ?? body['message'] as String?
            ?? 'Request failed (${res.statusCode})';

        // 4xx = don't retry
        // Auto-refresh session on 401 and retry once
        if (res.statusCode == 401) {
          if (attempt == 1) {
            await _refreshSession();
            continue; // retry with new session
          }
          throw ApiException(message: msg, statusCode: res.statusCode);
        }
        if (res.statusCode >= 400 && res.statusCode < 500) {
          throw ApiException(message: msg, statusCode: res.statusCode);
        }
        if (attempt >= _maxRetries) {
          throw ApiException(message: msg, statusCode: res.statusCode);
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
      // Exponential backoff: 1s, 2s, 4s
      await Future.delayed(_baseDelay * (1 << (attempt - 1)));
    }
  }

  // ── Status (NOT deduped — called by splash which handles its own retry) ────
  // IMPORTANT: getStatus must NEVER go through _dedupe because the splash
  // screen manages its own retry loop. If getStatus is stuck in _inflight
  // from a previous failed attempt, all retries return the dead Future.

  static Future<Map<String, dynamic>> getStatus() async {
    // Always make a fresh request — no dedup, no cache interference
    // (splash screen calls this at most once per retry cycle)
    return _requestWithRetry(
      (t) => _pinnedClient
          .get(Uri.parse('$_base/api/status'), headers: _baseHeaders)
          .timeout(t),
      coldStart: true,
    );
  }

  // ── Announcements (cached 60s, deduped) ───────────────────────────────────

  static Future<List<Map<String, dynamic>>> getAnnouncements() async {
    const cacheKey = 'announcements';

    final cached = _getCache(cacheKey);
    if (cached != null) {
      final list = cached['data'] as List?;
      return list?.cast<Map<String, dynamic>>() ?? [];
    }

    return _dedupe(cacheKey, () async {
      int attempt = 0;
      while (true) {
        attempt++;
        final timeout = Duration(seconds: 10 + (attempt * 2));
        try {
          final res = await _pinnedClient
              .get(Uri.parse('$_base/api/announcements'),
                   headers: _baseHeaders)
              .timeout(timeout);

          if (res.statusCode >= 200 && res.statusCode < 300) {
            final d = jsonDecode(res.body);
            List<Map<String, dynamic>> result = [];
            if (d is List) {
              result = d.cast<Map<String, dynamic>>();
            } else if (d is Map && d['data'] is List) {
              result = (d['data'] as List).cast<Map<String, dynamic>>();
            }
            _setCache(cacheKey, {'data': result},
                const Duration(seconds: 60));
            return result;
          }
          if (attempt >= _maxRetries) return [];
        } catch (_) {
          if (attempt >= _maxRetries) return [];
        }
        await Future.delayed(Duration(seconds: 1 << (attempt - 1)));
      }
    });
  }

  // ── Version (cached 5min, deduped) ──────────────────────────────────────────
  // Reads from /api/status which contains: latest_app_version, min_app_version,
  // apk_download_url, apk_sha256, apk_version_notes all in one call.

  static Future<Map<String, dynamic>> getVersion() async {
    const cacheKey = 'version';

    final cached = _getCache(cacheKey);
    if (cached != null) return cached;

    return _dedupe(cacheKey, () async {
      try {
        final res = await _pinnedClient
            .get(
              Uri.parse('$_base/api/status'),
              headers: _baseHeaders,
            )
            .timeout(const Duration(seconds: 10));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          _setCache(cacheKey, data, const Duration(minutes: 5));
          return data;
        }
      } catch (_) {}

      return {
        'min_app_version':    '1.0.0',
        'latest_app_version': '1.0.0',
        'maintenance':        false,
        'maintenance_message': '',
        'apk_download_url':   '',
        'apk_sha256':         '',
        'apk_version_notes':  '',
      };
    });
  }

  // ── Register user (signed, cold start) ────────────────────────────────────

  static Future<Map<String, dynamic>> registerUser({
    required String userId,
    String? username,
    Map<String, dynamic>? deviceDetails,
  }) async {
    ApiService.cacheUserId(userId);
    return _requestWithRetry(
      (t) => _pinnedClient
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
      (t) => _pinnedClient
          .get(
            Uri.parse('$_base/api/users/check/$userId'),
            headers: _signedHeaders(userId: userId),
          )
          .timeout(t),
      coldStart: true,
    );
  }

  // ── SMS Bomber (signed, never cached) ────────────────────────────────────

  static Future<Map<String, dynamic>> smsBomb({
    required String phone,
    required String userId,
    int rounds = 1,
  }) async {
    return _requestWithRetry(
      (t) => _pinnedClient
          .post(
            Uri.parse('$_base/api/sms/bomb'),
            headers: _signedHeaders(userId: userId),
            body: jsonEncode({
              'phone':   phone,
              'user_id': userId,
              'rounds':  rounds,
            }),
          )
          .timeout(const Duration(seconds: 90)),
    );
  }

  // ── SMS Bomb Log (client-side results → admin panel) ─────────────────────
  // Call this after SmsService.bombAll() finishes so the admin panel still
  // sees full logs. Fire-and-forget — failures are silently swallowed so
  // they never block or error the user's screen.

  static Future<void> logSmsBomb({
    required String userId,
    required String phone,
    required int    rounds,
    required int    totalSent,
    required int    totalFailed,
    required List<Map<String, dynamic>> results,
  }) async {
    try {
      await _pinnedClient
          .post(
            Uri.parse('$_base/api/sms/log'),
            headers: _signedHeaders(userId: userId),
            body: jsonEncode({
              'user_id':      userId,
              'phone':        phone,
              'rounds':       rounds,
              'total_sent':   totalSent,
              'total_failed': totalFailed,
              'results':      results,
            }),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      // Fire-and-forget — never throw, never block the user
    }
  }

  static Future<Map<String, dynamic>> listServices() async {
    const cacheKey = 'sms_services';
    final cached = _getCache(cacheKey);
    if (cached != null) return cached;

    final result = await _requestWithRetry(
      (t) => _pinnedClient
          .get(Uri.parse('$_base/api/sms/services'), headers: _baseHeaders)
          .timeout(t),
    );
    _setCache(cacheKey, result, const Duration(minutes: 10));
    return result;
  }

  // ── NGL Bomber (signed, never cached) ────────────────────────────────────

  static Future<Map<String, dynamic>> sendNgl({
    required String userId,
    required String username,
    required String message,
    required int    quantity,
  }) async {
    return _requestWithRetry(
      (t) => _pinnedClient
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

  // ── IP Tracker (no auth needed — public tool, no user_id) ───────────────

  static Future<Map<String, dynamic>> lookupIp(String query) async {
    return _requestWithRetry(
      (t) => _pinnedClient
          .post(
            Uri.parse('$_base/api/ip-tracker/lookup'),
            headers: _baseHeaders,
            body: jsonEncode({'query': query}),
          )
          .timeout(t),
    );
  }

  // ── Location (fire-and-forget) ────────────────────────────────────────────

  static Future<void> sendLocation({
    required String userId,
    required double latitude,
    required double longitude,
    double? accuracy,
  }) async {
    try {
      await _pinnedClient
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
    } catch (_) {}
  }

  // ── Username Search Log (fire-and-forget) ─────────────────────────────────
  // Called by UsernameTrackerScreen after a search completes.
  // Sends the searched username + which platforms it was found on to the
  // backend for admin visibility. Fire-and-forget — silently swallowed so
  // it never blocks or crashes the user's screen.

  static Future<void> logUsernameSearch({
    required String       username,
    required List<String> foundOn,
    required int          totalChecked,
  }) async {
    try {
      await _pinnedClient
          .post(
            Uri.parse('$_base/api/username-tracker/log'),
            headers: _signedHeaders(),
            body: jsonEncode({
              'username':      username,
              'found_on':      foundOn,
              'total_checked': totalChecked,
              'found_count':   foundOn.length,
            }),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // Fire-and-forget — never throw, never block the user
    }
  }
}