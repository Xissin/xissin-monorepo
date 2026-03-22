import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../services/ad_service.dart';
import '../services/api_service.dart';
import '../services/ngl_service.dart';
import '../widgets/glass_neumorphic_card.dart';
import '../widgets/haptic_button.dart';

const _kPink   = Color(0xFFFF6EC7);
const _kOrange = Color(0xFFFF9A44);
const _kGreen  = Color(0xFF7EE7C1);
const _kRed    = Color(0xFFFF6B6B);

// ── Part 2 constants ──────────────────────────────────────────────────────────
const _kNglLastSendKey = 'ngl_bomb_last_send';

/// Free-tier cooldown: 30 minutes between sends.
/// Premium users have NO cooldown.
const _kNglCooldown = Duration(minutes: 30);

class NglScreen extends StatefulWidget {
  final String userId;
  const NglScreen({super.key, required this.userId});

  @override
  State<NglScreen> createState() => _NglScreenState();
}

class _NglScreenState extends State<NglScreen> {
  final _usernameCtrl = TextEditingController();
  final _messageCtrl  = TextEditingController();
  final _scrollCtrl   = ScrollController();
  final _formKey      = GlobalKey<FormState>();

  int    _quantity   = 5;
  bool   _loading    = false;
  bool   _done       = false;
  int    _charCount  = 0;

  int    _sent       = 0;
  int    _failed     = 0;
  String _resultMsg  = '';
  bool   _resultOk   = false;

  List<NglResult> _liveResults = [];
  int             _liveSent    = 0;
  int             _liveFailed  = 0;

  double _progress = 0.0;

  // ── Part 2: Ad gate + cooldown ────────────────────────────────────────────
  bool      _adGranted = false;    // true after watching ad → 1 send allowed
  DateTime? _lastSend;
  Duration  _remaining = Duration.zero;

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
    _messageCtrl.addListener(() {
      final len = _messageCtrl.text.length;
      if (len != _charCount) setState(() => _charCount = len);
    });
    _loadPersistedCooldown();
    AdService.instance.addListener(_onAdChanged);
    _initBanner();
  }

  @override
  void dispose() {
    AdService.instance.removeListener(_onAdChanged);
    _bannerAd?.dispose();
    _usernameCtrl.dispose();
    _messageCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── Ad helpers ─────────────────────────────────────────────────────────────

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

  // ── Part 2: Cooldown persistence ───────────────────────────────────────────

  Future<void> _loadPersistedCooldown() async {
    final prefs  = await SharedPreferences.getInstance();
    final lastMs = prefs.getInt(_kNglLastSendKey);
    if (lastMs != null) {
      _lastSend = DateTime.fromMillisecondsSinceEpoch(lastMs);
      _tickCooldown();
    }
  }

  Future<void> _saveLastSend() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kNglLastSendKey, _lastSend!.millisecondsSinceEpoch);
  }

  void _tickCooldown() {
    if (_lastSend == null || !mounted) return;
    final elapsed = DateTime.now().difference(_lastSend!);
    final rem     = _kNglCooldown - elapsed;
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

  // ── Part 2: Watch ad to unlock ─────────────────────────────────────────────

  void _watchAdToSend() {
    HapticFeedback.selectionClick();
    if (!_formKey.currentState!.validate()) return;
    AdService.instance.showGatedInterstitial(
      onGranted: () {
        if (mounted) {
          setState(() => _adGranted = true);
          _snack('🔓 Unlocked! Tap Send to fire.');
        }
      },
    );
  }

  // ── Paste username ─────────────────────────────────────────────────────────

  Future<void> _pasteUsername() async {
    final data = await Clipboard.getData('text/plain');
    if (data?.text != null && data!.text!.isNotEmpty) {
      HapticFeedback.selectionClick();
      final raw   = data.text!.trim();
      final clean = raw
          .replaceAll(RegExp(r'https?://(www\.)?ngl\.link/'), '')
          .replaceAll('@', '')
          .trim();
      _usernameCtrl.text = clean;
      _usernameCtrl.selection =
          TextSelection.fromPosition(TextPosition(offset: clean.length));
    }
  }

  // ── Send ───────────────────────────────────────────────────────────────────

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;

    final isPremium = AdService.instance.adsRemoved;

    // Free-tier gate: must watch ad first
    if (!isPremium && !_adGranted) {
      _snack('Watch an ad to send 🔒', error: true);
      return;
    }

    HapticFeedback.mediumImpact();
    FocusScope.of(context).unfocus();

    final username = _usernameCtrl.text.trim();
    final message  = _messageCtrl.text.trim();

    setState(() {
      _loading     = true;
      _done        = false;
      _sent        = 0;
      _failed      = 0;
      _liveSent    = 0;
      _liveFailed  = 0;
      _liveResults = [];
      _resultMsg   = '';
      _progress    = 0.0;
    });

    try {
      final result = await NglService.bombAll(
        username:  username,
        message:   message,
        quantity:  _quantity,
        onMessageDone: (r, sent, failed) {
          if (!mounted) return;
          setState(() {
            _liveResults.add(r);
            _liveSent   = sent;
            _liveFailed = failed;
            _progress   = (sent + failed) / _quantity;
          });
        },
      );

      if (!mounted) return;

      // Start 30-min cooldown for free users after each send
      if (!isPremium) {
        _lastSend = DateTime.now();
        await _saveLastSend();
        _tickCooldown();
      }

      final success = result.sent > 0;
      setState(() {
        _adGranted = false; // ← reset ad grant after each send
        _loading   = false;
        _done      = true;
        _resultOk  = success;
        _sent      = result.sent;
        _failed    = result.failed;
        _resultMsg = success
            ? 'Sent ${result.sent}/$_quantity messages to @$username!'
            : 'All $_quantity messages failed. "@$username" may not exist or NGL is blocking requests.';
      });
      HapticFeedback.heavyImpact();

      ApiService.logNgl(
        userId:   widget.userId,
        username: username,
        message:  message,
        quantity: _quantity,
        sent:     result.sent,
        failed:   result.failed,
        results:  result.results.map((r) => r.toJson()).toList(),
      ).catchError((_) {});

      Future.delayed(const Duration(milliseconds: 600), () {
        if (!AdService.instance.adsRemoved) AdService.instance.showInterstitial();
      });

    } catch (e) {
      if (!mounted) return;
      final err = e.toString().replaceFirst('Exception: ', '');
      setState(() {
        _loading   = false;
        _done      = true;
        _resultOk  = false;
        _resultMsg = err;
      });
      HapticFeedback.vibrate();
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      backgroundColor: error ? AppColors.error : AppColors.accent,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      margin: const EdgeInsets.all(12),
    ));
  }

  void _reset() {
    HapticFeedback.selectionClick();
    if (!AdService.instance.adsRemoved) AdService.instance.showInterstitial();
    setState(() {
      _done = _loading = false;
      _progress    = 0;
      _sent        = _failed = 0;
      _liveSent    = _liveFailed = 0;
      _liveResults = [];
      _resultMsg   = '';
      _charCount   = 0;
      _adGranted   = false; // also reset on "Send Again"
    });
    _usernameCtrl.clear();
    _messageCtrl.clear();
  }

  // ── Part 2: Send area (ad gate + send button) ──────────────────────────────

  Widget _buildSendArea(XissinColors c) {
    final isPremium = AdService.instance.adsRemoved;

    // Premium: normal send button, no gate
    if (isPremium) {
      return _SendButton(loading: _loading, onPressed: _send);
    }

    // Free + ad granted: send button (1 use)
    if (_adGranted) {
      return Column(
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color:        AppColors.accent.withOpacity(0.10),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.accent.withOpacity(0.30)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_outline_rounded,
                    color: AppColors.accent, size: 14),
                SizedBox(width: 6),
                Text('🔓 Ad watched — send ready!',
                    style: TextStyle(
                        color:      AppColors.accent,
                        fontSize:   12,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          _SendButton(loading: _loading, onPressed: _send),
        ],
      );
    }

    // Free + cooldown active: show countdown + bypass option
    if (_onCooldown) {
      return Column(
        children: [
          // Cooldown button (disabled)
          SizedBox(
            width: double.infinity, height: 54,
            child: ElevatedButton(
              onPressed: null,
              style: ElevatedButton.styleFrom(
                disabledBackgroundColor: c.surface,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.lg)),
                elevation: 0,
                side: BorderSide(color: _kPink.withOpacity(0.4)),
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
                        letterSpacing: 1),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          // Cooldown progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.xs),
            child: LinearProgressIndicator(
              value: 1.0 - (_remaining.inMilliseconds / _kNglCooldown.inMilliseconds),
              minHeight: 5,
              backgroundColor: _kPink.withOpacity(0.12),
              valueColor: const AlwaysStoppedAnimation<Color>(_kPink),
            ),
          ),
          const SizedBox(height: 12),
          // Watch ad to bypass
          GestureDetector(
            onTap: _watchAdToSend,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color:        _kOrange.withOpacity(0.08),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: _kOrange.withOpacity(0.35)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.play_circle_outline_rounded,
                      color: _kOrange, size: 18),
                  SizedBox(width: 8),
                  Text('Watch an ad to send now →',
                      style: TextStyle(
                          color:      _kOrange,
                          fontSize:   13,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // Free + no cooldown + no ad grant: Watch Ad to Send
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
                  'Free: Watch a short ad to send • Premium: no ads, no cooldown',
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      height:   1.4),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          width: double.infinity, height: 54,
          child: ElevatedButton.icon(
            onPressed: _watchAdToSend,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kOrange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.lg)),
              elevation: 0,
            ),
            icon:  const Icon(Icons.play_circle_rounded, size: 20),
            label: const Text('Watch Ad to Send',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      backgroundColor:    c.background,
      bottomNavigationBar: _buildBannerAd(),
      appBar: _buildAppBar(c),
      body: SafeArea(
        child: SingleChildScrollView(
          controller: _scrollCtrl,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          child: _done ? _buildResult(c) : _buildForm(c),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(XissinColors c) {
    return AppBar(
      backgroundColor: c.background,
      elevation: 0,
      leading: HapticIconButton(
        icon: Icons.arrow_back_ios_new_rounded,
        onPressed: () => Navigator.pop(context),
        color: c.textPrimary,
        backgroundColor: c.surface,
      ),
      title: ShaderMask(
        shaderCallback: (b) => const LinearGradient(
          colors: [_kPink, _kOrange],
        ).createShader(b),
        child: const Text(
          'NGL Bomber',
          style: TextStyle(
            color:         Colors.white,
            fontWeight:    FontWeight.w800,
            fontSize:      20,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  // ── Form ───────────────────────────────────────────────────────────────────

  Widget _buildForm(XissinColors c) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoBanner(c: c),
          const SizedBox(height: 22),

          _Label('NGL Username', c),
          const SizedBox(height: 8),
          _buildUsernameField(c)
              .animate()
              .fadeIn(duration: 350.ms)
              .slideY(begin: 0.08, end: 0),
          const SizedBox(height: 18),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _Label('Anonymous Message', c),
              _CharCounter(count: _charCount, max: 300, c: c),
            ],
          ),
          const SizedBox(height: 8),
          _buildMessageField(c)
              .animate()
              .fadeIn(duration: 350.ms, delay: 60.ms)
              .slideY(begin: 0.08, end: 0),
          const SizedBox(height: 20),

          _QuantityLabel(quantity: _quantity, c: c),
          const SizedBox(height: 6),
          _buildQuantitySlider(c)
              .animate()
              .fadeIn(duration: 350.ms, delay: 120.ms),
          const SizedBox(height: 28),

          // Live progress while sending
          if (_loading) ...[
            _GradientProgressBar(
              progress: _progress,
              sent:     _liveSent,
              failed:   _liveFailed,
              total:    _quantity,
              c:        c,
            ).animate().fadeIn(duration: 300.ms),
            const SizedBox(height: 12),
            if (_liveResults.isNotEmpty)
              _LiveResultsList(results: _liveResults, c: c)
                  .animate()
                  .fadeIn(duration: 250.ms),
            const SizedBox(height: 20),
          ],

          // ── Part 2: Ad-gated send area ────────────────────────────────
          _buildSendArea(c)
              .animate()
              .fadeIn(duration: 350.ms, delay: 160.ms),

          const SizedBox(height: 24),

          if (!_loading)
            _TipsCard(c: c)
                .animate(delay: 300.ms)
                .fadeIn(duration: 400.ms),
        ],
      ),
    );
  }

  Widget _buildUsernameField(XissinColors c) {
    return TextFormField(
      controller: _usernameCtrl,
      style: TextStyle(color: c.textPrimary, fontSize: 15),
      decoration: _inputDecoration(c).copyWith(
        hintText: 'ngl_username',
        prefixIcon: const Icon(Icons.alternate_email_rounded,
            color: _kPink, size: 20),
        suffixIcon: IconButton(
          icon: Icon(Icons.content_paste_rounded,
              color: c.textSecondary, size: 20),
          onPressed: _pasteUsername,
          tooltip: 'Paste',
        ),
      ),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Enter a username';
        if (v.trim().length < 2) return 'Username too short';
        return null;
      },
    );
  }

  Widget _buildMessageField(XissinColors c) {
    return TextFormField(
      controller: _messageCtrl,
      style: TextStyle(color: c.textPrimary, fontSize: 14, height: 1.5),
      maxLines:   4,
      maxLength:  300,
      buildCounter: (_, {required currentLength, required isFocused, maxLength}) =>
          const SizedBox.shrink(),
      decoration: _inputDecoration(c).copyWith(
        hintText:           'Enter your anonymous message...',
        alignLabelWithHint: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Enter a message';
        if (v.trim().length < 3) return 'Message too short';
        return null;
      },
    );
  }

  // ── Part 2: slider max = 50 free / 100 premium ────────────────────────────
  Widget _buildQuantitySlider(XissinColors c) {
    final isPremium = AdService.instance.adsRemoved;
    final maxQty    = isPremium ? 100 : 50;
    // Clamp quantity if user just lost premium
    if (_quantity > maxQty) _quantity = maxQty;

    return Column(
      children: [
        SliderTheme(
          data: SliderThemeData(
            trackHeight:        4,
            activeTrackColor:   _kPink,
            inactiveTrackColor: c.border,
            thumbColor:         _kPink,
            thumbShape:
                const RoundSliderThumbShape(enabledThumbRadius: 10),
            overlayColor: _kPink.withOpacity(0.2),
            overlayShape:
                const RoundSliderOverlayShape(overlayRadius: 20),
          ),
          child: Slider(
            value:     _quantity.toDouble(),
            min:       1,
            max:       maxQty.toDouble(),
            divisions: maxQty - 1,
            onChanged: (v) => setState(() => _quantity = v.toInt()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: (isPremium
                    ? [1, 20, 40, 60, 80, 100]
                    : [1, 10, 20, 30, 40, 50])
                .map((n) => Text(
                      '$n',
                      style: TextStyle(
                        color: _quantity == n
                            ? _kPink
                            : c.textSecondary,
                        fontSize: 10,
                        fontWeight: _quantity == n
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ))
                .toList(),
          ),
        ),
        if (isPremium)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '⭐ Premium: up to 100 messages, no cooldown',
              style: TextStyle(
                  color:      c.gold,
                  fontSize:   10,
                  fontWeight: FontWeight.w500),
            ),
          ),
      ],
    );
  }

  InputDecoration _inputDecoration(XissinColors c) {
    return InputDecoration(
      filled:    true,
      fillColor: c.surface,
      hintStyle: TextStyle(color: c.textSecondary),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        borderSide:   BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        borderSide:
            BorderSide(color: c.textSecondary.withOpacity(0.12), width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        borderSide:   const BorderSide(color: _kPink, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        borderSide:   const BorderSide(color: _kRed, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        borderSide:   const BorderSide(color: _kRed, width: 1.5),
      ),
    );
  }

  // ── Result screen ──────────────────────────────────────────────────────────

  Widget _buildResult(XissinColors c) {
    final color = _resultOk ? _kGreen : _kRed;
    return Column(
      children: [
        const SizedBox(height: 32),

        Container(
          width: 96, height: 96,
          decoration: BoxDecoration(
            shape:     BoxShape.circle,
            color:     color.withOpacity(0.10),
            border:    Border.all(color: color.withOpacity(0.40), width: 2),
            boxShadow: AppShadows.doubleGlow(color),
          ),
          child: Icon(
            _resultOk
                ? Icons.check_circle_outline_rounded
                : Icons.error_outline_rounded,
            size: 48, color: color,
          ),
        )
            .animate()
            .scale(begin: const Offset(0.4, 0.4), duration: 550.ms, curve: Curves.elasticOut)
            .fadeIn(duration: 300.ms),

        const SizedBox(height: 24),

        Text(
          _resultOk ? '🎉  Done!' : '❌  Failed',
          style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.w800),
        ).animate().fadeIn(duration: 350.ms, delay: 150.ms),

        const SizedBox(height: 10),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            _resultMsg,
            textAlign: TextAlign.center,
            style: TextStyle(color: c.textSecondary, fontSize: 14, height: 1.5),
          ),
        ).animate().fadeIn(duration: 350.ms, delay: 200.ms),

        const SizedBox(height: 28),

        if (_resultOk) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _StatChip(label: 'Sent',   value: '$_sent',   color: _kGreen, c: c),
              const SizedBox(width: 16),
              _StatChip(label: 'Failed', value: '$_failed', color: _kRed,   c: c),
            ],
          ).animate().fadeIn(duration: 350.ms, delay: 280.ms),
          const SizedBox(height: 28),
        ],

        if (_liveResults.isNotEmpty) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Message Breakdown',
                style: TextStyle(
                    color:      c.textPrimary,
                    fontSize:   13,
                    fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 10),
          ...(_liveResults.take(20).toList().asMap().entries.map(
                (e) => _NglResultRow(result: e.value, index: e.key, c: c),
              )),
          if (_liveResults.length > 20)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('+ ${_liveResults.length - 20} more messages',
                  style: TextStyle(color: c.textSecondary, fontSize: 11)),
            ),
          const SizedBox(height: 28),
        ],

        SizedBox(
          width: double.infinity, height: 52,
          child: ElevatedButton.icon(
            onPressed: _reset,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPink,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.lg)),
              elevation: 0,
            ),
            icon:  const Icon(Icons.refresh_rounded, size: 20),
            label: const Text('Send Again',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ).animate().fadeIn(duration: 350.ms, delay: 320.ms),
      ],
    );
  }
}

// ── Static widgets (unchanged) ────────────────────────────────────────────────

class _LiveResultsList extends StatelessWidget {
  final List<NglResult> results;
  final XissinColors    c;
  const _LiveResultsList({required this.results, required this.c});

  @override
  Widget build(BuildContext context) {
    final visible = results.length <= 6
        ? results
        : results.sublist(results.length - 6);
    return Container(
      padding:    const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color:        c.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border:       Border.all(color: c.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: visible
            .asMap()
            .entries
            .map((e) => _NglResultRow(result: e.value, index: e.key, c: c))
            .toList(),
      ),
    );
  }
}

class _NglResultRow extends StatelessWidget {
  final NglResult    result;
  final int          index;
  final XissinColors c;
  const _NglResultRow({required this.result, required this.index, required this.c});

  @override
  Widget build(BuildContext context) {
    final ok    = result.success;
    final color = ok ? _kGreen : _kRed;
    return Container(
      margin:  const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color:        color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: color.withOpacity(0.20), width: 1),
      ),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle_outline_rounded : Icons.cancel_outlined,
              size: 14, color: color),
          const SizedBox(width: 8),
          Text('Msg #${result.index + 1}',
              style: TextStyle(color: c.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
          const Spacer(),
          Text(result.message,
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w500)),
        ],
      ),
    )
        .animate(delay: Duration(milliseconds: 30 * index.clamp(0, 10)))
        .fadeIn(duration: 200.ms)
        .slideX(begin: 0.05, end: 0, duration: 200.ms);
  }
}

class _GradientProgressBar extends StatelessWidget {
  final double       progress;
  final int          sent;
  final int          failed;
  final int          total;
  final XissinColors c;
  const _GradientProgressBar({
    required this.progress, required this.sent,
    required this.failed, required this.total, required this.c,
  });

  @override
  Widget build(BuildContext context) {
    final done = sent + failed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Sending from your phone...',
                style: TextStyle(color: c.textSecondary, fontSize: 12, fontWeight: FontWeight.w500)),
            Text('$done / $total',
                style: const TextStyle(color: _kPink, fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Stack(
            children: [
              Container(height: 8, color: c.surface),
              FractionallySizedBox(
                widthFactor: progress.clamp(0.0, 1.0),
                child: Container(
                  height: 8,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: [_kPink, _kOrange]),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _MiniChip(label: '✓ $sent sent',     color: _kGreen),
            const SizedBox(width: 8),
            _MiniChip(label: '✗ $failed failed', color: _kRed),
          ],
        ),
      ],
    );
  }
}

class _MiniChip extends StatelessWidget {
  final String label;
  final Color  color;
  const _MiniChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color:        color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Text(label,
            style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
      );
}

class _Label extends StatelessWidget {
  final String text;
  final XissinColors c;
  const _Label(this.text, this.c);
  @override
  Widget build(BuildContext context) => Text(text,
      style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600, fontSize: 14));
}

class _QuantityLabel extends StatelessWidget {
  final int quantity;
  final XissinColors c;
  const _QuantityLabel({required this.quantity, required this.c});
  @override
  Widget build(BuildContext context) => Row(
        children: [
          Text('Quantity: ',
              style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color:        _kPink.withOpacity(0.15),
              borderRadius: BorderRadius.circular(AppRadius.full),
              border: Border.all(color: _kPink.withOpacity(0.35), width: 1),
            ),
            child: Text('$quantity msg${quantity == 1 ? '' : 's'}',
                style: const TextStyle(color: _kPink, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      );
}

class _CharCounter extends StatelessWidget {
  final int count;
  final int max;
  final XissinColors c;
  const _CharCounter({required this.count, required this.max, required this.c});
  Color get _color {
    final ratio = count / max;
    if (ratio > 0.9) return _kRed;
    if (ratio > 0.8) return _kOrange;
    return c.textSecondary;
  }
  @override
  Widget build(BuildContext context) => Row(
        children: [
          SizedBox(
            width: 20, height: 20,
            child: CircularProgressIndicator(
              value:           count / max,
              strokeWidth:     2.5,
              backgroundColor: c.border,
              valueColor:      AlwaysStoppedAnimation<Color>(_color),
            ),
          ),
          const SizedBox(width: 6),
          Text('$count / $max',
              style: TextStyle(color: _color, fontSize: 11, fontWeight: FontWeight.w500)),
        ],
      );
}

class _InfoBanner extends StatelessWidget {
  final XissinColors c;
  const _InfoBanner({required this.c});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding:    const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:        _kOrange.withOpacity(0.07),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border:       Border.all(color: _kOrange.withOpacity(0.25), width: 1),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, size: 18, color: _kOrange),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Sends anonymous messages to any NGL profile.\n'
              'Fires directly from your phone — max 50 per send.',
              style: TextStyle(color: c.textSecondary, fontSize: 12, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _TipsCard extends StatelessWidget {
  final XissinColors c;
  const _TipsCard({required this.c});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding:    const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:        c.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border:       Border.all(color: c.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.lightbulb_outline_rounded, size: 15, color: _kOrange),
            const SizedBox(width: 6),
            Text('Tips', style: TextStyle(color: c.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 10),
          _tip('Enter only the username, not the full ngl.link URL', c),
          _tip('Use the paste button to auto-clean copied links', c),
          _tip('Requests fire from your phone — not blocked by Railway IP', c),
          _tip('Max 50 messages (free) / 100 messages (premium) per send', c),
        ],
      ),
    );
  }
  Widget _tip(String text, XissinColors c) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('• ', style: TextStyle(color: _kPink, fontSize: 13)),
            Expanded(child: Text(text,
                style: TextStyle(color: c.textSecondary, fontSize: 12, height: 1.4))),
          ],
        ),
      );
}

class _SendButton extends StatelessWidget {
  final bool         loading;
  final VoidCallback onPressed;
  const _SendButton({required this.loading, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity, height: 54,
      child: ElevatedButton.icon(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor:         _kPink,
          foregroundColor:         Colors.white,
          disabledBackgroundColor: _kPink.withOpacity(0.4),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg)),
          elevation: 0,
        ),
        icon: loading
            ? const SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.send_rounded, size: 20),
        label: Text(loading ? 'Sending...' : 'Send Messages',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label, value;
  final Color  color;
  final XissinColors c;
  const _StatChip({required this.label, required this.value, required this.color, required this.c});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:    const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      decoration: BoxDecoration(
        color:        color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border:       Border.all(color: color.withOpacity(0.30), width: 1),
        boxShadow:    AppShadows.glow(color, intensity: 0.10, blur: 12),
      ),
      child: Column(
        children: [
          Text(value, style: TextStyle(color: color, fontSize: 28, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: c.textSecondary, fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
