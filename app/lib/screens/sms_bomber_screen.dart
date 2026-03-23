import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../services/ad_service.dart';
import '../services/api_service.dart';
import '../services/sms_service.dart';
import '../widgets/glass_neumorphic_card.dart';

const _kSmsRed    = Color(0xFFFF4E4E);
const _kSmsOrange = Color(0xFFFF9A44);

// ── Data model ────────────────────────────────────────────────────────────────

class _AttackRecord {
  final String phone;
  final int rounds;
  final int sent;
  final int failed;
  final int total;
  final DateTime time;
  final List<SmsResult> results;

  double get successPct => total == 0 ? 0 : sent / total;
  double get failedPct  => total == 0 ? 0 : failed / total;

  _AttackRecord({
    required this.phone,
    required this.rounds,
    required this.sent,
    required this.failed,
    required this.total,
    required this.time,
    required this.results,
  });

  Map<String, dynamic> toJson() => {
        'phone':   phone,
        'rounds':  rounds,
        'sent':    sent,
        'failed':  failed,
        'total':   total,
        'time':    time.toIso8601String(),
        'results': results.map((r) => r.toJson()).toList(),
      };

  factory _AttackRecord.fromJson(Map<String, dynamic> j) => _AttackRecord(
        phone:   j['phone']  as String,
        rounds:  j['rounds'] as int,
        sent:    j['sent']   as int,
        failed:  j['failed'] as int,
        total:   j['total']  as int,
        time:    DateTime.parse(j['time'] as String),
        results: ((j['results'] as List?) ?? [])
            .map((e) => SmsResult(
                  service: (e['service'] ?? '') as String,
                  success: (e['success'] ?? false) as bool,
                  message: (e['message'] ?? '') as String,
                ))
            .toList(),
      );
}

// ── Constants ─────────────────────────────────────────────────────────────────

const _kHistoryKey   = 'sms_bomb_history';
const _kLastFireKey  = 'sms_bomb_last_fire';

/// Free-tier cooldown: 45 minutes between fires.
/// Premium users have NO cooldown.
const _kCooldown = Duration(minutes: 45);

const _kMaxHistory = 10;

// ── Screen ────────────────────────────────────────────────────────────────────

class SmsBomberScreen extends StatefulWidget {
  final String userId;
  const SmsBomberScreen({super.key, required this.userId});

  @override
  State<SmsBomberScreen> createState() => _SmsBomberScreenState();
}

class _SmsBomberScreenState extends State<SmsBomberScreen> {
  final _phoneCtrl  = TextEditingController();
  final _scrollCtrl = ScrollController();

  int  _rounds  = 1;
  bool _loading = false;

  List<SmsResult> _liveResults = [];
  int             _liveSent    = 0;
  int             _liveFailed  = 0;

  List<_AttackRecord> _history = [];

  DateTime? _lastFire;
  Duration  _remaining = Duration.zero;

  // ── Part 2: Ad gate for free users ───────────────────────────────────────
  // _adGranted = true after watching an ad → allows exactly 1 fire.
  // Resets to false after each fire.
  // Premium users bypass this entirely.
  bool _adGranted = false;

  // Free-tier cooldown: only active when NOT premium
  bool get _onCooldown {
    if (AdService.instance.adsRemoved) return false; // premium: no cooldown
    return _remaining > Duration.zero;
  }

  // ── Local Banner Ad ───────────────────────────────────────────────────────
  BannerAd? _bannerAd;
  bool      _bannerReady = false;

  @override
  void initState() {
    super.initState();
    AdService.instance.init();
    _loadPersistedData();
    AdService.instance.addListener(_onAdServiceChanged);
    _initBanner();
  }

  @override
  void dispose() {
    AdService.instance.removeListener(_onAdServiceChanged);
    _bannerAd?.dispose();
    _phoneCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onAdServiceChanged() {
    if (!mounted) return;
    if (AdService.instance.adsRemoved && _bannerAd != null) {
      _bannerAd?.dispose();
      setState(() { _bannerAd = null; _bannerReady = false; });
    }
  }

  void _initBanner() {
    if (AdService.instance.adsRemoved) return;
    _bannerAd?.dispose();
    _bannerAd    = null;
    _bannerReady = false;
    final ad = AdService.instance.createBannerAd(
      onLoaded: () {
        if (!mounted || AdService.instance.adsRemoved) {
          _bannerAd?.dispose(); _bannerAd = null; return;
        }
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

  // ── Persistence ────────────────────────────────────────────────────────────

  Future<void> _loadPersistedData() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kHistoryKey);
    if (raw != null) {
      try {
        final list = (jsonDecode(raw) as List)
            .map((e) => _AttackRecord.fromJson(e as Map<String, dynamic>))
            .toList();
        if (mounted) setState(() => _history = list);
      } catch (_) {}
    }
    final lastMs = prefs.getInt(_kLastFireKey);
    if (lastMs != null) {
      _lastFire = DateTime.fromMillisecondsSinceEpoch(lastMs);
      _tickCooldown();
    }
  }

  Future<void> _saveHistory() async {
    final prefs   = await SharedPreferences.getInstance();
    final trimmed = _history.take(_kMaxHistory).toList();
    await prefs.setString(
        _kHistoryKey,
        jsonEncode(trimmed.map((r) => r.toJson()).toList()));
  }

  Future<void> _saveLastFire() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLastFireKey, _lastFire!.millisecondsSinceEpoch);
  }

  // ── Cooldown ───────────────────────────────────────────────────────────────

  void _tickCooldown() {
    if (_lastFire == null || !mounted) return;
    final elapsed = DateTime.now().difference(_lastFire!);
    final rem     = _kCooldown - elapsed;
    if (rem <= Duration.zero) {
      if (mounted) setState(() => _remaining = Duration.zero);
      return;
    }
    if (mounted) setState(() => _remaining = rem);
    Future.delayed(const Duration(seconds: 1), _tickCooldown);
  }

  String _fmtCooldown(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ── Part 2: Watch ad to unlock ────────────────────────────────────────────

  void _watchAdToFire() {
    HapticFeedback.selectionClick();
    _snack('Loading ad... please wait', error: false);
    AdService.instance.showGatedInterstitial(
      onGranted: () {
        if (mounted) {
          setState(() => _adGranted = true);
          _snack('🔓 Unlocked! Tap FIRE to send.', error: false);
        }
      },
    );
  }

  // ── Fire ───────────────────────────────────────────────────────────────────

  Future<void> _fire() async {
    final isPremium = AdService.instance.adsRemoved;

    // Free-tier gate: must watch ad first
    if (!isPremium && !_adGranted) {
      _snack('Watch an ad to fire 🔒', error: true);
      return;
    }

    // Free-tier cooldown gate (after already having adGranted before)
    if (_onCooldown) {
      _snack('Cooldown active — wait ${_fmtCooldown(_remaining)}', error: true);
      return;
    }

    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty) { _snack('Enter a phone number', error: true); return; }
    if (phone.length != 10 ||
        !phone.startsWith('9') ||
        !RegExp(r'^9\d{9}$').hasMatch(phone)) {
      _snack('Use format 9XXXXXXXXX (10 digits, PH number)', error: true);
      return;
    }

    HapticFeedback.heavyImpact();
    setState(() {
      _loading     = true;
      _liveResults = [];
      _liveSent    = 0;
      _liveFailed  = 0;
    });

    try {
      final result = await SmsService.bombAll(
        phone:  phone,
        rounds: _rounds,
        onServiceDone: (smsResult, sent, failed) {
          if (!mounted) return;
          setState(() {
            _liveResults = [..._liveResults, smsResult];
            _liveSent    = sent;
            _liveFailed  = failed;
          });
        },
      );

      final record = _AttackRecord(
        phone:   phone,
        rounds:  _rounds,
        sent:    result.sent,
        failed:  result.failed,
        total:   result.sent + result.failed,
        time:    DateTime.now(),
        results: result.results,
      );

      // Start 45-min cooldown for free users after each fire
      if (!isPremium) {
        _lastFire = DateTime.now();
        await _saveLastFire();
        _tickCooldown();
      }

      setState(() {
        _adGranted = false;  // ← reset ad grant after each fire
        _history.insert(0, record);
        if (_history.length > _kMaxHistory) {
          _history = _history.take(_kMaxHistory).toList();
        }
        _liveResults = [];
        _liveSent    = 0;
        _liveFailed  = 0;
      });

      await _saveHistory();

      // Interstitial after successful attack (non-gated)
      AdService.instance.showInterstitial();

      // Log to admin panel (fire-and-forget)
      ApiService.logSmsBomb(
        userId:      widget.userId,
        phone:       phone,
        rounds:      _rounds,
        totalSent:   result.sent,
        totalFailed: result.failed,
        results:     result.results
            .map((r) => {
                  'service': r.service,
                  'success': r.success,
                  'message': r.message,
                })
            .toList(),
      );

      _snack('Done! ${result.sent} sent, ${result.failed} failed');
    } catch (e) {
      _snack('Request failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      backgroundColor: error ? AppColors.error : AppColors.accent,
      behavior:        SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md)),
      margin: const EdgeInsets.all(12),
    ));
  }

  void _repeatAttack(_AttackRecord r) {
    _phoneCtrl.text = r.phone;
    setState(() => _rounds = r.rounds.clamp(1, 3));
    _scrollCtrl.animateTo(0,
        duration: const Duration(milliseconds: 500), curve: Curves.easeOut);
    _snack('Phone pre-filled — tap FIRE when ready 🎯');
  }

  // ── Banner Ad ──────────────────────────────────────────────────────────────

  Widget _buildBannerAd() {
    if (AdService.instance.adsRemoved || !_bannerReady || _bannerAd == null) {
      return const SizedBox.shrink();
    }
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

  // ── Live progress panel ────────────────────────────────────────────────────

  Widget _buildLivePanel() {
    if (!_loading && _liveResults.isEmpty) return const SizedBox.shrink();

    final total = _liveSent + _liveFailed;
    final pct   = total == 0 ? 0.0 : _liveSent / total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Row(
          children: [
            const Icon(Icons.bolt_rounded, color: _kSmsOrange, size: 16),
            const SizedBox(width: 6),
            const Text('Live Results',
                style: TextStyle(
                    color:      AppColors.textSecondary,
                    fontSize:   13,
                    fontWeight: FontWeight.w600)),
            const Spacer(),
            if (_loading)
              const SizedBox(
                width: 12, height: 12,
                child: CircularProgressIndicator(
                    strokeWidth: 1.5, color: _kSmsOrange),
              ),
            const SizedBox(width: 8),
            Text('$_liveSent sent  •  $_liveFailed failed',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 11)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.xs),
          child: LinearProgressIndicator(
            value:           _loading && total == 0 ? null : pct.clamp(0.0, 1.0),
            minHeight:       5,
            backgroundColor: AppColors.error.withOpacity(0.18),
            valueColor:      const AlwaysStoppedAnimation<Color>(AppColors.accent),
          ),
        ),
        const SizedBox(height: 10),
        ...List.generate(_liveResults.length, (i) {
          final r = _liveResults[i];
          return _ServiceRow(
            data:  {'service': r.service, 'success': r.success, 'message': r.message},
            index: i,
          );
        }),
      ],
    ).animate().fadeIn(duration: 300.ms);
  }

  // ── Part 2: Action area (ad gate + fire button) ───────────────────────────

  Widget _buildActionArea(XissinColors c) {
    final isPremium = AdService.instance.adsRemoved;

    // ── Premium: fire button, no cooldown, no ad gate
    if (isPremium) {
      return _buildFireButton(c, onPressed: _loading ? null : _fire);
    }

    // ── Free + ad granted: FIRE button (1 use)
    if (_adGranted) {
      return Column(
        children: [
          // "1 use ready" badge
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color:        AppColors.accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.accent.withOpacity(0.35)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_outline_rounded,
                    color: AppColors.accent, size: 14),
                SizedBox(width: 6),
                Text(
                  '🔓 Ad watched — 1 fire ready!',
                  style: TextStyle(
                      color:      AppColors.accent,
                      fontSize:   12,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          _buildFireButton(c, onPressed: _loading ? null : _fire),
        ],
      );
    }

    // ── Free + cooldown active: show countdown + watch-ad link
    if (_onCooldown) {
      return Column(
        children: [
          // Cooldown button (disabled)
          SizedBox(
            width: double.infinity, height: 56,
            child: ElevatedButton(
              onPressed: null,
              style: ElevatedButton.styleFrom(
                disabledBackgroundColor: c.surface,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.lg)),
                elevation: 0,
                side: BorderSide(color: c.primary.withOpacity(0.4)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.timer_outlined, size: 18, color: c.textSecondary),
                  const SizedBox(width: 8),
                  Text(
                    'Cooldown  ${_fmtCooldown(_remaining)}',
                    style: TextStyle(
                      fontSize:   15,
                      fontWeight: FontWeight.bold,
                      color:      c.textSecondary,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Cooldown progress bar
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.xs),
            child: LinearProgressIndicator(
              value: 1.0 - (_remaining.inMilliseconds / _kCooldown.inMilliseconds),
              minHeight: 5,
              backgroundColor: c.primary.withOpacity(0.12),
              valueColor: AlwaysStoppedAnimation<Color>(c.primary),
            ),
          ),
          // Watch ad to bypass cooldown
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _watchAdToFire,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color:        _kSmsOrange.withOpacity(0.08),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: _kSmsOrange.withOpacity(0.35)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.play_circle_outline_rounded,
                      color: _kSmsOrange, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Watch an ad to fire now →',
                    style: TextStyle(
                      color:      _kSmsOrange,
                      fontSize:   13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // ── Free + no cooldown + no ad grant: Watch Ad to Fire
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color:        c.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: c.border),
          ),
          child: Row(
            children: [
              const Icon(Icons.lock_outline_rounded,
                  color: AppColors.textSecondary, size: 15),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Free: Watch a short ad to fire • Premium: no ads, no cooldown',
                  style: TextStyle(
                      color:    AppColors.textSecondary,
                      fontSize: 11,
                      height:   1.4),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          width: double.infinity, height: 56,
          child: ElevatedButton.icon(
            onPressed: _watchAdToFire,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kSmsOrange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.lg)),
              elevation: 0,
            ),
            icon:  const Icon(Icons.play_circle_rounded, size: 20),
            label: const Text(
              'Watch Ad to Fire',
              style: TextStyle(
                  fontSize:      16,
                  fontWeight:    FontWeight.w800,
                  letterSpacing: 1),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFireButton(XissinColors c, {VoidCallback? onPressed}) {
    return SizedBox(
      width: double.infinity, height: 56,
      child: AnimatedContainer(
        duration: AppDurations.normal,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: onPressed != null
              ? AppShadows.doubleGlow(AppColors.primary)
              : null,
        ),
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor:         AppColors.primary,
            disabledBackgroundColor: AppColors.primary.withOpacity(0.4),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg)),
            elevation: 0,
          ),
          child: _loading
              ? const SizedBox(
                  width: 22, height: 22,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2.5),
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.send_rounded, size: 18, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      'FIRE',
                      style: TextStyle(
                        fontSize:      16,
                        fontWeight:    FontWeight.w900,
                        letterSpacing: 3,
                        color:         Colors.white,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return Scaffold(
      backgroundColor: c.background,
      bottomNavigationBar: _buildBannerAd(),
      appBar: AppBar(
        backgroundColor: c.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: ShaderMask(
          shaderCallback: (b) => const LinearGradient(
            colors: [_kSmsRed, _kSmsOrange],
          ).createShader(b),
          child: const Text(
            'SMS Bomber',
            style: TextStyle(
              color:         Colors.white,
              fontWeight:    FontWeight.w800,
              fontSize:      20,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        controller: _scrollCtrl,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Warning banner ──────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color:        c.error.withOpacity(0.07),
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: c.error.withOpacity(0.30), width: 1),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: c.error, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'For educational use only. PH numbers (9XXXXXXXXX) only.',
                      style: TextStyle(
                          color: c.error, fontSize: 12, height: 1.4),
                    ),
                  ),
                ],
              ),
            )
                .animate()
                .fadeIn(duration: 400.ms)
                .slideY(begin: -0.1, end: 0, duration: 400.ms),

            const SizedBox(height: 26),

            // ── Target number ───────────────────────────────────────────
            Text('Target Number',
                style: TextStyle(
                    color:      c.textSecondary,
                    fontSize:   13,
                    fontWeight: FontWeight.w500))
                .animate(delay: 100.ms).fadeIn(duration: 400.ms),

            const SizedBox(height: 8),

            TextField(
              controller:   _phoneCtrl,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
              style: TextStyle(
                  color: c.textPrimary, fontSize: 16, letterSpacing: 1),
              decoration: InputDecoration(
                hintText: '9XXXXXXXXX',
                hintStyle: TextStyle(color: c.textSecondary),
                filled:    true,
                fillColor: c.surface,
                prefixIcon: Icon(Icons.phone_android_rounded, color: c.primary),
                prefix: Text('+63 ',
                    style: TextStyle(
                        color:      c.primary,
                        fontWeight: FontWeight.bold,
                        fontSize:   15)),
                suffixIcon: IconButton(
                  icon: Icon(Icons.clear_rounded,
                      color: c.textSecondary, size: 18),
                  onPressed: () => _phoneCtrl.clear(),
                ),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    borderSide: BorderSide(color: c.border, width: 1)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    borderSide: BorderSide(color: c.primary, width: 1.5)),
              ),
            )
                .animate(delay: 150.ms)
                .fadeIn(duration: 400.ms)
                .slideX(begin: -0.1, end: 0, duration: 400.ms),

            const SizedBox(height: 26),

            // ── Rounds selector ─────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Rounds',
                    style: TextStyle(
                        color:      c.textSecondary,
                        fontSize:   13,
                        fontWeight: FontWeight.w500)),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: c.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(
                    '$_rounds × 14 = ${_rounds * 14} SMS',
                    style: TextStyle(
                        color:      c.primary,
                        fontSize:   12,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ).animate(delay: 200.ms).fadeIn(duration: 400.ms),

            const SizedBox(height: 10),

            Row(
              children: List.generate(3, (i) {
                final n   = i + 1;
                final sel = _rounds == n;
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _rounds = n);
                    },
                    child: AnimatedContainer(
                      duration: AppDurations.fast,
                      margin:  EdgeInsets.only(right: i < 2 ? 10 : 0),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        gradient: sel
                            ? const LinearGradient(
                                colors: [AppColors.primary, AppColors.secondary])
                            : null,
                        color: sel ? null : c.surface,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(
                            color: sel ? AppColors.primary : c.border),
                        boxShadow: sel
                            ? AppShadows.glow(AppColors.primary,
                                intensity: 0.35, blur: 14)
                            : null,
                      ),
                      child: Column(
                        children: [
                          Text(
                            '$n',
                            style: TextStyle(
                              color:      sel ? Colors.white : c.textSecondary,
                              fontWeight: FontWeight.bold,
                              fontSize:   18,
                            ),
                          ),
                          Text(
                            '${n * 14} SMS',
                            style: TextStyle(
                              color:    sel
                                  ? Colors.white.withOpacity(0.75)
                                  : c.textSecondary,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ).animate(delay: 250.ms).fadeIn(duration: 400.ms),

            const SizedBox(height: 32),

            // ── Action area (Part 2: ad gate + fire button) ─────────────
            _buildActionArea(c)
                .animate(delay: 300.ms)
                .fadeIn(duration: 400.ms)
                .slideY(begin: 0.2, end: 0, duration: 400.ms),

            // ── Live results panel ──────────────────────────────────────
            _buildLivePanel(),

            const SizedBox(height: 32),

            // ── Attack History ──────────────────────────────────────────
            if (_history.isNotEmpty) ...[
              Row(
                children: [
                  Icon(Icons.history_rounded,
                      color: AppColors.textSecondary, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'Attack History  (${_history.length}/$_kMaxHistory)',
                    style: const TextStyle(
                        color:      AppColors.textSecondary,
                        fontSize:   13,
                        fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _confirmClearHistory,
                    child: const Row(
                      children: [
                        Icon(Icons.delete_outline_rounded,
                            color: AppColors.error, size: 14),
                        SizedBox(width: 4),
                        Text('Clear',
                            style: TextStyle(
                                color:    AppColors.error,
                                fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ).animate().fadeIn(duration: 400.ms),

              const SizedBox(height: 12),

              ...List.generate(_history.length, (i) {
                return _HistoryCard(
                  record:        _history[i],
                  index:         i,
                  onAttackAgain: () => _repeatAttack(_history[i]),
                )
                    .animate(delay: Duration(milliseconds: 60 * i.clamp(0, 8)))
                    .fadeIn(duration: 350.ms)
                    .slideY(begin: 0.08, end: 0, duration: 350.ms);
              }),

              const SizedBox(height: 20),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirmClearHistory() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.xl)),
        title: const Text('Clear History',
            style: TextStyle(color: AppColors.textPrimary)),
        content: const Text('Delete all attack history?',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel',
                  style: TextStyle(color: AppColors.textSecondary))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete',
                  style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (ok == true) {
      setState(() => _history.clear());
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kHistoryKey);
    }
  }
}

// ── History Card ──────────────────────────────────────────────────────────────

class _HistoryCard extends StatefulWidget {
  final _AttackRecord record;
  final int           index;
  final VoidCallback  onAttackAgain;

  const _HistoryCard({
    required this.record,
    required this.index,
    required this.onAttackAgain,
  });

  @override
  State<_HistoryCard> createState() => _HistoryCardState();
}

class _HistoryCardState extends State<_HistoryCard> {
  bool _expanded = false;

  String _fmtTime(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    final s = t.second.toString().padLeft(2, '0');
    return '${t.month}/${t.day}  $h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final r       = widget.record;
    final sucPct  = (r.successPct * 100).toStringAsFixed(1);
    final failPct = (r.failedPct  * 100).toStringAsFixed(1);

    return GlassNeumorphicCard(
      padding:   const EdgeInsets.all(14),
      glowColor: r.sent > 0
          ? AppColors.accent.withOpacity(0.4)
          : AppColors.error.withOpacity(0.3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color:        AppColors.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: Text(
                  '#${widget.index + 1}',
                  style: const TextStyle(
                      color:      AppColors.primary,
                      fontSize:   11,
                      fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '+63 ${r.phone}',
                  style: const TextStyle(
                      color:      AppColors.textPrimary,
                      fontSize:   14,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace'),
                ),
              ),
              Text(
                _fmtTime(r.time),
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 10),
              ),
            ],
          ),

          const SizedBox(height: 10),

          Row(
            children: [
              _MiniStat(label: 'Rounds',    value: '${r.rounds}', color: AppColors.primary),
              const SizedBox(width: 8),
              _MiniStat(label: 'Total SMS', value: '${r.total}',  color: AppColors.textSecondary),
              const SizedBox(width: 8),
              _MiniStat(label: 'Sent',      value: '${r.sent}',   color: AppColors.accent),
              const SizedBox(width: 8),
              _MiniStat(label: 'Failed',    value: '${r.failed}', color: AppColors.error),
            ],
          ),

          if (r.rounds >= 2 && r.total > 0) ...[
            const SizedBox(height: 12),
            _ProgressBar(
              label:    'Success',
              pct:      r.successPct,
              pctLabel: '$sucPct%',
              color:    AppColors.accent,
            ),
            const SizedBox(height: 6),
            _ProgressBar(
              label:    'Failed',
              pct:      r.failedPct,
              pctLabel: '$failPct%',
              color:    AppColors.error,
            ),
          ],

          const SizedBox(height: 12),

          Row(
            children: [
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Row(
                  children: [
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: AppColors.textSecondary,
                      size:  18,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _expanded ? 'Hide details' : 'Show details',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              SizedBox(
                height: 32,
                child: ElevatedButton.icon(
                  onPressed: widget.onAttackAgain,
                  icon:  const Icon(Icons.replay_rounded, size: 14),
                  label: const Text('Attack Again',
                      style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 0),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm)),
                    elevation: 2,
                  ),
                ),
              ),
            ],
          ),

          if (_expanded && r.results.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(height: 1, color: AppColors.border),
            const SizedBox(height: 10),
            ...r.results.asMap().entries.map(
                  (e) => _ServiceRow(
                    data: {
                      'service': e.value.service,
                      'success': e.value.success,
                      'message': e.value.message,
                    },
                    index: e.key,
                  ),
                ),
          ],
        ],
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _MiniStat extends StatelessWidget {
  final String label, value;
  final Color  color;
  const _MiniStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color:        color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    color: color, fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final String label, pctLabel;
  final double pct;
  final Color  color;
  const _ProgressBar({
    required this.label,
    required this.pct,
    required this.pctLabel,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 11)),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.xs),
            child: LinearProgressIndicator(
              value:            pct.clamp(0.0, 1.0),
              minHeight:        7,
              backgroundColor:  color.withOpacity(0.12),
              valueColor:       AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 40,
          child: Text(
            pctLabel,
            textAlign: TextAlign.right,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}

class _ServiceRow extends StatelessWidget {
  final Map  data;
  final int  index;
  const _ServiceRow({required this.data, required this.index});

  @override
  Widget build(BuildContext context) {
    final ok  = data['success'] == true;
    final msg = (data['message'] ?? '').toString();

    return Container(
      margin:  const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color:        AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: ok
              ? AppColors.accent.withOpacity(0.25)
              : AppColors.error.withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle_outline_rounded : Icons.cancel_outlined,
            size:  15,
            color: ok ? AppColors.accent : AppColors.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Text(
              (data['service'] ?? '').toString(),
              style: const TextStyle(
                  color:      AppColors.textPrimary,
                  fontSize:   12,
                  fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              msg,
              style: TextStyle(
                  color: ok
                      ? AppColors.accent
                      : AppColors.error.withOpacity(0.8),
                  fontSize: 11),
              overflow:  TextOverflow.ellipsis,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    )
        .animate(delay: Duration(milliseconds: 40 * index.clamp(0, 20)))
        .fadeIn(duration: 250.ms)
        .slideX(begin: 0.05, end: 0, duration: 250.ms);
  }
}
