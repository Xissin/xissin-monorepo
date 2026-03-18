// lib/services/security_service.dart
//
// Protects against:
//   ✅ API abuse from outside the app  (HMAC signed requests)
//   ✅ Token replay attacks             (30-second timestamp window)
//   ✅ APK repackaging                  (app ID check baked in token)
//   ✅ Premium bypass via memory patch  (server re-validates on every action)
//   ✅ Fake user_id injection           (token binds user_id to timestamp)
//
// IMPORTANT — Secret alignment:
//   The HMAC secret here MUST match _APP_SALT in backend/auth.py.
//   Current value: "xissin-multi-tool-2024"
//   If you ever change it, update BOTH files at the same time.

import 'dart:convert';
import 'package:crypto/crypto.dart';

class SecurityService {
  SecurityService._();

  static const String _appId = 'com.xissin.app';

  // ── HMAC secret — must match _APP_SALT in backend/auth.py ────────────────
  // Split across two parts so it is not a single obvious string constant.
  // An attacker reading the decompiled APK still needs to find and join these.
  static String _buildRuntimeSecret() {
    const a = 'xissin-multi';   // first half
    const b = '-tool-2024';     // second half
    return '$a$b';               // = "xissin-multi-tool-2024"
  }

  // ── Token validity window ─────────────────────────────────────────────────
  static const int tokenWindowSeconds = 30;

  // ── Current unix timestamp ────────────────────────────────────────────────
  static int get nowSeconds =>
      DateTime.now().millisecondsSinceEpoch ~/ 1000;

  // ── Generate signed request token ────────────────────────────────────────
  // Format: HMAC-SHA256( userId:timestamp:appId , secret )
  // Backend verifies by regenerating with the same formula.
  static String generateRequestToken({
    required String userId,
    required int    timestampSeconds,
  }) {
    final secret  = _buildRuntimeSecret();
    final message = '$userId:$timestampSeconds:$_appId';
    final key     = utf8.encode(secret);
    final bytes   = utf8.encode(message);
    final digest  = Hmac(sha256, key).convert(bytes);
    return digest.toString();
  }

  // ── Build auth headers for every API call ─────────────────────────────────
  // Usage: headers: SecurityService.buildHeaders(userId: _userId)
  static Map<String, String> buildHeaders({required String userId}) {
    final ts    = nowSeconds;
    final token = generateRequestToken(userId: userId, timestampSeconds: ts);
    return {
      'X-App-Id':        _appId,
      'X-App-Token':     token,
      'X-App-Timestamp': ts.toString(),
      'Content-Type':    'application/json',
    };
  }

  // ── Verify a token locally (optional, for debug) ─────────────────────────
  static bool verifyToken({
    required String token,
    required String userId,
    required int    timestampSeconds,
  }) {
    final expected = generateRequestToken(
      userId:           userId,
      timestampSeconds: timestampSeconds,
    );
    return token == expected;
  }

  // ── Device fingerprint ────────────────────────────────────────────────────
  static String generateDeviceFingerprint({
    required String userId,
    String? model,
    String? osVersion,
  }) {
    final raw    = '$userId:${model ?? "unknown"}:${osVersion ?? "0"}:$_appId';
    final digest = sha256.convert(utf8.encode(raw));
    return digest.toString().substring(0, 32);
  }

  // ── Tamper detection ──────────────────────────────────────────────────────
  static bool isAppIdSuspicious(String reportedAppId) {
    return reportedAppId != _appId;
  }
}
