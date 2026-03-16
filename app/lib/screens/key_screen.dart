import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:confetti/confetti.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../widgets/glass_neumorphic_card.dart';
import '../widgets/shimmer_skeleton.dart';

const _kGold   = Color(0xFFFFD166);
const _kTeal   = Color(0xFF00C9FF);
const _kGreen  = Color(0xFF7EE7C1);

class KeyScreen extends StatefulWidget {
  final String userId;
  const KeyScreen({super.key, required this.userId});

  @override
  State<KeyScreen> createState() => _KeyScreenState();
}

class _KeyScreenState extends State<KeyScreen> {
  final _keyCtrl = TextEditingController();
  final _confettiController =
      ConfettiController(duration: const Duration(seconds: 3));

  bool _redeeming   = false;
  bool _checking    = true;
  bool _showSuccess = false;
  bool _obscureKey  = true;
  Map<String, dynamic>? _status;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  // ── Data ───────────────────────────────────────────────────────────────────

  Future<void> _loadStatus() async {
    setState(() => _checking = true);
    try {
      final data = await ApiService.keyStatus(widget.userId);
      setState(() { _status = data; _checking = false; });
    } catch (_) {
      setState(() => _checking = false);
    }
  }

  Future<void> _redeem() async {
    final key = _keyCtrl.text.trim().toUpperCase();
    if (key.isEmpty) { _snack('Enter a key', error: true); return; }

    HapticFeedback.heavyImpact();
    setState(() => _redeeming = true);

    try {
      final data = await ApiService.redeemKey(key: key, userId: widget.userId);
      if (data['success'] == true) {
        setState(() => _showSuccess = true);
        _confettiController.play();
        _snack('Key redeemed! 🎉 Welcome to Xissin.');
        _keyCtrl.clear();
        await Future.delayed(const Duration(milliseconds: 500));
        _loadStatus();
      } else {
        final msg = data['detail'] ?? data['message'] ?? 'Failed to redeem key.';
        _snack(msg, error: true);
      }
    } catch (e) {
      _snack('Connection error: $e', error: true);
    } finally {
      setState(() => _redeeming = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600)),
      backgroundColor: error ? AppColors.error : AppColors.accent,
      behavior:        SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md)),
      margin: const EdgeInsets.all(12),
    ));
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _fmtDate(String? iso) {
    if (iso == null) return '—';
    try {
      final dt = DateTime.parse(iso);
      return '${dt.day.toString().padLeft(2, '0')}/'
          '${dt.month.toString().padLeft(2, '0')}/'
          '${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) { return iso; }
  }

  Duration? _timeRemaining(String? iso) {
    if (iso == null) return null;
    try {
      return DateTime.parse(iso).difference(DateTime.now());
    } catch (_) { return null; }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c        = context.c;
    final isActive = _status?['active'] == true;

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: ShaderMask(
          shaderCallback: (b) => const LinearGradient(
            colors: [_kTeal, _kGold],
          ).createShader(b),
          child: const Text(
            'Key Manager',
            style: TextStyle(
              color:         Colors.white,
              fontWeight:    FontWeight.w800,
              fontSize:      20,
              letterSpacing: 0.5,
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded,
                color: AppColors.textSecondary),
            onPressed: () {
              HapticFeedback.selectionClick();
              _loadStatus();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ── Status card ────────────────────────────────────────────
                _checking
                    ? const ShimmerStatusCard()
                    : _StatusCard(
                        isActive:      isActive,
                        status:        _status,
                        fmtDate:       _fmtDate,
                        timeRemaining: _timeRemaining(_status?['expires_at']),
                      ),

                const SizedBox(height: 32),

                // ── Redeem heading ─────────────────────────────────────────
                Text(
                  'Redeem a Key',
                  style: TextStyle(
                      color:      c.textPrimary,
                      fontSize:   16,
                      fontWeight: FontWeight.bold),
                ).animate().fadeIn(duration: 400.ms),

                const SizedBox(height: 6),

                Text(
                  'Enter your activation key below to unlock all features.',
                  style: TextStyle(color: c.textSecondary, fontSize: 13),
                ).animate(delay: 50.ms).fadeIn(duration: 400.ms),

                const SizedBox(height: 14),

                // ── Key text field ─────────────────────────────────────────
                TextField(
                  controller: _keyCtrl,
                  textCapitalization: TextCapitalization.characters,
                  obscureText: _obscureKey,
                  style: TextStyle(
                    color:        c.textPrimary,
                    fontFamily:   'monospace',
                    letterSpacing: 1.5,
                    fontSize:     14,
                  ),
                  onSubmitted: (_) => _redeeming ? null : _redeem(),
                  decoration: InputDecoration(
                    hintText: 'XISSIN-XXXX-XXXX-XXXX-XXXX',
                    hintStyle: TextStyle(color: c.textSecondary),
                    filled:    true,
                    fillColor: c.surface,
                    prefixIcon: Icon(Icons.vpn_key_rounded,
                        color: _kTeal, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureKey
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        color: c.textSecondary,
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => _obscureKey = !_obscureKey),
                    ),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        borderSide: BorderSide(color: c.border, width: 1)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        borderSide:
                            const BorderSide(color: _kTeal, width: 1.5)),
                  ),
                )
                    .animate(delay: 100.ms)
                    .fadeIn(duration: 400.ms)
                    .slideX(begin: -0.1, end: 0, duration: 400.ms),

                const SizedBox(height: 16),

                // ── Redeem button ──────────────────────────────────────────
                SizedBox(
                  width:  double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _redeeming ? null : _redeem,
                    style: ElevatedButton.styleFrom(
                      backgroundColor:         _kGreen,
                      disabledBackgroundColor: _kGreen.withOpacity(0.5),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.lg)),
                      elevation: 0,
                    ),
                    child: _redeeming
                        ? const SizedBox(
                            width: 22, height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.lock_open_rounded,
                                  color: Colors.white, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Redeem Key',
                                style: TextStyle(
                                  fontSize:   16,
                                  fontWeight: FontWeight.bold,
                                  color:      Colors.white,
                                ),
                              ),
                            ],
                          ),
                  ),
                )
                    .animate(delay: 150.ms)
                    .fadeIn(duration: 400.ms)
                    .slideY(begin: 0.2, end: 0, duration: 400.ms),

                const SizedBox(height: 30),

                // ── Info box ───────────────────────────────────────────────
                _InfoBox(onTelegram: () => _openUrl('https://t.me/Xissin_0')),
              ],
            ),
          ),

          // ── Confetti ───────────────────────────────────────────────────────
          if (_showSuccess)
            Align(
              alignment: Alignment.topCenter,
              child: ConfettiWidget(
                confettiController:  _confettiController,
                blastDirectionality: BlastDirectionality.explosive,
                shouldLoop:          false,
                colors: const [
                  AppColors.accent,
                  AppColors.primary,
                  Colors.white,
                  _kGold,
                ],
                numberOfParticles: 35,
              ),
            ),

          // ── Success overlay ────────────────────────────────────────────────
          if (_showSuccess)
            Center(
              child: GlassNeumorphicCard(
                glowColor: AppColors.accent,
                padding:   const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 80, height: 80,
                      decoration: BoxDecoration(
                        shape:     BoxShape.circle,
                        color:     _kGreen.withOpacity(0.15),
                        boxShadow: AppShadows.doubleGlow(_kGreen),
                      ),
                      child: const Icon(Icons.verified_rounded,
                          color: _kGreen, size: 44),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      '🎉  Key Activated!',
                      style: TextStyle(
                          color:      AppColors.textPrimary,
                          fontSize:   20,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'All features are now unlocked.',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 14),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () => setState(() => _showSuccess = false),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kGreen,
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppRadius.md)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 12),
                      ),
                      child: const Text('Got it!',
                          style: TextStyle(
                              color:      Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize:   15)),
                    ),
                  ],
                ),
              )
                  .animate()
                  .scale(
                      begin:    const Offset(0.5, 0.5),
                      duration: 400.ms,
                      curve:    Curves.elasticOut),
            ),
        ],
      ),
    );
  }
}

// ── Status Card ───────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final bool isActive;
  final Map<String, dynamic>? status;
  final String Function(String?) fmtDate;
  final Duration? timeRemaining;

  const _StatusCard({
    required this.isActive,
    required this.status,
    required this.fmtDate,
    this.timeRemaining,
  });

  @override
  Widget build(BuildContext context) {
    final glowColor = isActive ? _kGreen : AppColors.error;

    return GlassNeumorphicCard(
      glowColor:   glowColor,
      enablePulse: isActive,
      padding:     const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color:  glowColor.withOpacity(0.15),
                  shape:  BoxShape.circle,
                  boxShadow: isActive
                      ? AppShadows.glow(glowColor, intensity: 0.20)
                      : null,
                ),
                child: Icon(
                  isActive
                      ? Icons.verified_rounded
                      : Icons.lock_outline_rounded,
                  color: glowColor,
                  size:  22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isActive ? 'Key Active' : 'No Active Key',
                      style: TextStyle(
                        color:      glowColor,
                        fontSize:   17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      isActive
                          ? 'All features unlocked'
                          : 'Redeem a key to unlock features',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              // Active badge
              if (isActive)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color:        _kGreen.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    border:       Border.all(
                        color: _kGreen.withOpacity(0.35), width: 1),
                  ),
                  child: const Text(
                    'ACTIVE',
                    style: TextStyle(
                      color:         _kGreen,
                      fontSize:      9,
                      fontWeight:    FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
            ],
          ),

          if (isActive && status != null) ...[
            const SizedBox(height: 16),
            Container(height: 1, color: AppColors.border),
            const SizedBox(height: 14),
            _InfoRow(label: 'Key',     value: status!['key'] ?? '—', mono: true),
            const SizedBox(height: 8),
            _InfoRow(label: 'Expires', value: fmtDate(status!['expires_at'])),
            if (timeRemaining != null) ...[
              const SizedBox(height: 8),
              _CountdownTimer(duration: timeRemaining!),
            ],
          ] else if (!isActive) ...[
            const SizedBox(height: 10),
            const Text(
              'Contact the admin or check the Xissin channel to get a key.',
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 12, height: 1.5),
            ),
          ],
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 400.ms)
        .slideY(begin: 0.1, end: 0, duration: 400.ms);
  }
}

// ── Countdown Timer ───────────────────────────────────────────────────────────

class _CountdownTimer extends StatefulWidget {
  final Duration duration;
  const _CountdownTimer({required this.duration});

  @override
  State<_CountdownTimer> createState() => _CountdownTimerState();
}

class _CountdownTimerState extends State<_CountdownTimer> {
  late Duration _remaining;

  @override
  void initState() {
    super.initState();
    _remaining = widget.duration;
    _startTimer();
  }

  void _startTimer() {
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && _remaining.inSeconds > 0) {
        setState(() => _remaining -= const Duration(seconds: 1));
        _startTimer();
      }
    });
  }

  String _formatDuration(Duration d) {
    if (d.isNegative) return 'Expired';
    final days    = d.inDays;
    final hours   = d.inHours % 24;
    final minutes = d.inMinutes % 60;
    if (days > 0)  return '$days days';
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    final isExpiringSoon = _remaining.inDays < 3;
    final color = isExpiringSoon ? AppColors.error : _kGreen;

    return Row(
      children: [
        const SizedBox(
          width: 60,
          child: Text('Time Left',
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color:        color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(AppRadius.xs),
            border:       Border.all(color: color.withOpacity(0.30), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isExpiringSoon
                    ? Icons.timer_off_rounded
                    : Icons.timer_rounded,
                size:  13,
                color: color,
              ),
              const SizedBox(width: 4),
              Text(
                _formatDuration(_remaining),
                style: TextStyle(
                  color:      color,
                  fontSize:   12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Info Row ──────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final String label, value;
  final bool   mono;
  const _InfoRow({required this.label, required this.value, this.mono = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color:         AppColors.textPrimary,
              fontSize:      12,
              fontFamily:    mono ? 'monospace' : null,
              letterSpacing: mono ? 0.8 : null,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ── Info Box ──────────────────────────────────────────────────────────────────

class _InfoBox extends StatelessWidget {
  final VoidCallback onTelegram;
  const _InfoBox({required this.onTelegram});

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return GlassNeumorphicCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.help_outline_rounded,
                size: 16, color: _kTeal),
            const SizedBox(width: 8),
            Text(
              'How to get a key?',
              style: TextStyle(
                  color:      c.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize:   14),
            ),
          ]),
          const SizedBox(height: 12),
          _step('1', 'Join the Xissin Telegram channel', c),
          _step('2', 'Contact the admin @QuitNat', c),
          _step('3', 'Keys use the format XISSIN-XXXX-XXXX-XXXX-XXXX', c),
          const SizedBox(height: 14),
          // Telegram quick link
          GestureDetector(
            onTap: onTelegram,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF229ED9).withOpacity(0.12),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                    color: const Color(0xFF229ED9).withOpacity(0.30),
                    width: 1),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.telegram,
                      color: Color(0xFF229ED9), size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Join @Xissin_0 on Telegram',
                    style: TextStyle(
                      color:      Color(0xFF229ED9),
                      fontSize:   13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    )
        .animate(delay: 200.ms)
        .fadeIn(duration: 400.ms)
        .slideY(begin: 0.1, end: 0, duration: 400.ms);
  }

  Widget _step(String n, String text, XissinColors c) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width:  20,
              height: 20,
              margin: const EdgeInsets.only(top: 1, right: 10),
              decoration: BoxDecoration(
                color:        _kTeal.withOpacity(0.15),
                shape:        BoxShape.circle,
                border:       Border.all(
                    color: _kTeal.withOpacity(0.40), width: 1),
              ),
              child: Center(
                child: Text(n,
                    style: const TextStyle(
                        color:      _kTeal,
                        fontSize:   10,
                        fontWeight: FontWeight.bold)),
              ),
            ),
            Expanded(
              child: Text(text,
                  style: TextStyle(
                      color:  c.textSecondary,
                      fontSize: 13,
                      height: 1.5)),
            ),
          ],
        ),
      );
}
