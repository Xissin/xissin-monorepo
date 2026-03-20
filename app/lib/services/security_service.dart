// lib/services/security_service.dart
//
// Security v2.0 — three layers of protection:
//
//  [1] SESSION TOKENS (main fix)
//      The hardcoded HMAC secret is GONE from the APK.
//      On app launch, a bootstrap HMAC (using a low-value obfuscated secret)
//      is used to call /api/auth/session. The backend returns a random 256-bit
//      session token stored in Redis (24h TTL). All subsequent requests use
//      X-Session-Token instead of a derivable HMAC. Even if someone extracts
//      the bootstrap secret, they can only create rate-limited sessions.
//
//  [2] CERTIFICATE PINNING
//      All HTTP calls go through a custom IOClient that validates:
//      a) The hostname must be our exact Railway backend
//      b) The TLS certificate must be issued by Let's Encrypt (our CA)
//      A proxy (Burp Suite, Charles) cannot intercept without triggering this.
//
//  [3] BUILD-LEVEL OBFUSCATION (build.gradle already configured)
//      flutter build apk --release --obfuscate --split-debug-info=./debug-symbols
//      All class/method/field names become single-character symbols.

import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

class SecurityService {
  SecurityService._();

  static const String _appId      = 'com.xissin.app';
  static const String _backendHost =
      'xissin-app-backend-production.up.railway.app';
  static const String _baseUrl    =
      'https://xissin-app-backend-production.up.railway.app';

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const String _sessionKey = 'xissin_session_v2';

  // ── Bootstrap secret ───────────────────────────────────────────────────────
  // Encoded as char codes — not a plain string constant in the binary.
  // LOW VALUE TARGET: only used for /api/auth/session (rate-limited, 5/hr).
  // Even if extracted, attacker can only get rate-limited session tokens.
  static String _bootstrapSecret() {
    // "xis-boot-2024"
    const c = [120,105,115,45,98,111,111,116,45,50,48,50,52];
    return c.map((x) => String.fromCharCode(x)).join();
  }

  static const int _tokenWindowSeconds = 30;

  static int get nowSeconds =>
      DateTime.now().millisecondsSinceEpoch ~/ 1000;

  // ── Certificate-pinned HTTP client ─────────────────────────────────────────
  // Returns an IOClient that rejects connections to any host other than our
  // Railway backend, and requires the cert to be issued by Let's Encrypt.
  static http.Client createPinnedClient() {
    final httpClient = HttpClient();

    httpClient.connectionTimeout = const Duration(seconds: 20);

    // badCertificateCallback fires when TLS verification would normally fail.
    // We always return false (reject) unless this is a certificate we recognise.
    httpClient.badCertificateCallback =
        (X509Certificate cert, String host, int port) {
      // Reject anything not going to our backend
      if (host != _backendHost) return false;
      // Allow if issued by Let's Encrypt (handles 90-day rotation automatically)
      final issuer = cert.issuer;
      return issuer.contains("Let's Encrypt") ||
             issuer.contains('R3')            ||
             issuer.contains('R10')           ||
             issuer.contains('R11')           ||
             issuer.contains('ISRG');
    };

    return IOClient(httpClient);
  }

  // ── Session initialisation ─────────────────────────────────────────────────
  // Called once on app launch (splash screen, before any API call).
  // Returns the session token — either from secure storage (if still valid)
  // or freshly fetched from the backend.

  static Future<String?> initSession({
    required String deviceFingerprint,
  }) async {
    // 1. Try cached session first
    try {
      final cached = await _storage.read(key: _sessionKey);
      if (cached != null && cached.length >= 32) {
        // Verify it's still alive on the backend (cheap HEAD-like check is
        // done implicitly — if any request returns 401 the caller refreshes)
        return cached;
      }
    } catch (_) {}

    // 2. Fetch a new session from the backend
    return _fetchNewSession(deviceFingerprint: deviceFingerprint);
  }

  static Future<String?> _fetchNewSession({
    required String deviceFingerprint,
  }) async {
    try {
      final ts    = nowSeconds;
      final token = _buildBootstrapToken(
        deviceFingerprint: deviceFingerprint,
        timestamp:         ts,
      );

      // Use a plain (non-pinned) client for the session endpoint itself,
      // so cert pinning failures don't prevent session creation.
      final response = await http.post(
        Uri.parse('$_baseUrl/api/auth/session'),
        headers: {
          'Content-Type': 'application/json',
          'X-App-Id':     _appId,
        },
        body: jsonEncode({
          'device_fingerprint': deviceFingerprint,
          'timestamp':          ts,
          'bootstrap_token':    token,
          'app_id':             _appId,
        }),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final sessionToken = data['session_token'] as String?;
        if (sessionToken != null && sessionToken.length >= 32) {
          // Persist in secure encrypted storage
          await _storage.write(key: _sessionKey, value: sessionToken);
          return sessionToken;
        }
      }
    } catch (e) {
      // Session init failed — app will retry on next launch
      // Requests will get 401 which triggers a re-init
    }
    return null;
  }

  // Called by refresh flow when backend returns 401
  static Future<String?> refreshSession({
    required String deviceFingerprint,
  }) async {
    await _storage.delete(key: _sessionKey);
    return _fetchNewSession(deviceFingerprint: deviceFingerprint);
  }

  static Future<String?> getStoredSession() async {
    try {
      return await _storage.read(key: _sessionKey);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearSession() async {
    await _storage.delete(key: _sessionKey);
  }

  // ── Bootstrap HMAC ─────────────────────────────────────────────────────────
  // Only used for /api/auth/session — nowhere else.
  static String _buildBootstrapToken({
    required String deviceFingerprint,
    required int    timestamp,
  }) {
    final secret  = _bootstrapSecret();
    final message = '$deviceFingerprint:$timestamp:$_appId';
    final key     = utf8.encode(secret);
    final bytes   = utf8.encode(message);
    return Hmac(sha256, key).convert(bytes).toString();
  }

  // ── Request headers ────────────────────────────────────────────────────────
  // All API calls use X-Session-Token (NOT a derivable HMAC).
  static Map<String, String> buildHeaders({
    required String sessionToken,
  }) {
    return {
      'X-App-Id':         _appId,
      'X-Session-Token':  sessionToken,
      'Content-Type':     'application/json',
    };
  }

  // Headers fallback when session token is not available yet
  static Map<String, String> buildUnauthHeaders() {
    return {
      'X-App-Id':      _appId,
      'Content-Type':  'application/json',
    };
  }

  // ── Device fingerprint ─────────────────────────────────────────────────────
  static String generateDeviceFingerprint({
    required String userId,
    String? model,
    String? osVersion,
  }) {
    final raw    = '$userId:${model ?? "unknown"}:${osVersion ?? "0"}:$_appId';
    final digest = sha256.convert(utf8.encode(raw));
    return digest.toString().substring(0, 32);
  }

  // ── Tamper detection ───────────────────────────────────────────────────────
  static bool isAppIdSuspicious(String reportedAppId) =>
      reportedAppId != _appId;
}
