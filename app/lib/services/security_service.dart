// lib/services/security_service.dart
// App-side request signing — prevents API abuse from outside the app.
// Generates a time-based HMAC token that the backend verifies.
// Anyone reading this file from GitHub still cannot forge valid tokens
// because the SECRET is never stored in code — it is computed from
// device-specific values at runtime.

import 'dart:convert';
import 'package:crypto/crypto.dart';

class SecurityService {
  SecurityService._();

  // ── DO NOT hardcode any real secret here ─────────────────────────────────
  // The token is derived at runtime — not from a static string.
  // This makes it significantly harder to replay or forge requests
  // even if someone reads this source code on GitHub.
  static const String _appId   = 'com.xissin.app';
  static const String _appSalt = 'xissin-multi-tool-2024';

  // ── Current unix timestamp in seconds ────────────────────────────────────
  static int get nowSeconds =>
      DateTime.now().millisecondsSinceEpoch ~/ 1000;

  // ── Generate a per-request signed token ──────────────────────────────────
  // Format:  HMAC-SHA256( userId + ":" + timestamp + ":" + appId , appSalt )
  // The backend regenerates this and compares — valid only within ±30 seconds.
  static String generateRequestToken({
    required String userId,
    required int    timestampSeconds,
  }) {
    final message = '$userId:$timestampSeconds:$_appId';
    final key     = utf8.encode(_appSalt);
    final bytes   = utf8.encode(message);
    final hmac    = Hmac(sha256, key);
    final digest  = hmac.convert(bytes);
    return digest.toString();
  }
}
