import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static const String _base = 'https://xissin-app-backend-production.up.railway.app';

  static Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  // ── Users ──────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> registerUser({
    required String userId,
    String? username,
    String? deviceInfo,
  }) async {
    final res = await http
        .post(
          Uri.parse('$_base/api/users/register'),
          headers: _headers,
          body: jsonEncode({
            'user_id': userId,
            'username': username,
            'device_info': deviceInfo,
          }),
        )
        .timeout(const Duration(seconds: 15));
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> checkUser(String userId) async {
    final res = await http
        .get(Uri.parse('$_base/api/users/check/$userId'), headers: _headers)
        .timeout(const Duration(seconds: 10));
    return jsonDecode(res.body);
  }

  // ── Keys ───────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> redeemKey({
    required String key,
    required String userId,
    String? username,
  }) async {
    final res = await http
        .post(
          Uri.parse('$_base/api/keys/redeem'),
          headers: _headers,
          body: jsonEncode({
            'key': key,
            'user_id': userId,
            'username': username,
          }),
        )
        .timeout(const Duration(seconds: 15));
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> keyStatus(String userId) async {
    final res = await http
        .get(Uri.parse('$_base/api/keys/status/$userId'), headers: _headers)
        .timeout(const Duration(seconds: 10));
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> validateKey(String key) async {
    final res = await http
        .get(Uri.parse('$_base/api/keys/validate/$key'), headers: _headers)
        .timeout(const Duration(seconds: 10));
    return jsonDecode(res.body);
  }

  // ── SMS Bomber ─────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> smsBomb({
    required String phone,
    required String userId,
    int rounds = 1,
  }) async {
    final res = await http
        .post(
          Uri.parse('$_base/api/sms/bomb'),
          headers: _headers,
          body: jsonEncode({
            'phone': phone,
            'user_id': userId,
            'rounds': rounds,
          }),
        )
        .timeout(const Duration(seconds: 60));
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> listServices() async {
    final res = await http
        .get(Uri.parse('$_base/api/sms/services'), headers: _headers)
        .timeout(const Duration(seconds: 10));
    return jsonDecode(res.body);
  }
}
