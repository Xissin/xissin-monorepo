import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:confetti/confetti.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../widgets/glass_neumorphic_card.dart';
import '../widgets/shimmer_skeleton.dart';

// Brand colours for Key Manager
const _kGold   = Color(0xFFFFD166);
const _kPurple = Color(0xFF7B2FBE);

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
  bool _redeeming = false;
  bool _checking = true;
  bool _showSuccess = false;
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

  Future<void> _loadStatus() async {
    setState(() => _checking = true);
    try {
      final data = await ApiService.keyStatus(widget.userId);
      setState(() {
        _status = data;
        _checking = false;
      });
    } catch (_) {
      setState(() => _checking = false);
    }
  }

  Future<void> _redeem() async {
    final key = _keyCtrl.text.trim().toUpperCase();
    if (key.isEmpty) {
      _snack('Enter a key', error: true);
      return;
    }

    HapticFeedback.heavyImpact();
    setState(() => _redeeming = true);

    try {
      final data =
          await ApiService.redeemKey(key: key, userId: widget.userId);
      if (data['success'] == true) {
        setState(() => _showSuccess = true);
        _confettiController.play();
        _snack('Key redeemed! 🎉 Welcome to Xissin.');
        _keyCtrl.clear();
        await Future.delayed(const Duration(milliseconds: 500));
        _loadStatus();
      } else {
        final msg =
            data['detail'] ?? data['message'] ?? 'Failed to redeem key.';
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
      content: Text(msg),
      backgroundColor: error ? AppColors.error : AppColors.accent,
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(12),
    ));
  }

  String _fmtDate(String? iso) {
    if (iso == null) return '—';
    try {
      final dt = DateTime.parse(iso);
      return '${dt.day.toString().padLeft(2, '0')}/'
          '${dt.month.toString().padLeft(2, '0')}/'
          '${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  Duration? _timeRemaining(String? iso) {
    if (iso == null) return null;
    try {
      final expiry = DateTime.parse(iso);
      final now = DateTime.now();
      return expiry.difference(now);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
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
            colors: [_kGold, _kPurple],
          ).createShader(b),
          child: const Text(
            'Key Manager',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 20,
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
                // ── Status card ──────────────────────────────
                _checking
                    ? const ShimmerStatusCard()
                    : _StatusCard(
                        isActive: isActive,
                        status: _status,
                        fmtDate: _fmtDate,
                        timeRemaining:
                            _timeRemaining(_status?['expires_at']),
                      ),

                const SizedBox(height: 32),

                // ── Redeem section ───────────────────────────
                Text(
                  'Redeem a Key',
                  style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold),
                ).animate().fadeIn(duration: 400.ms),

                const SizedBox(height: 6),

                Text(
                  'Enter your activation key below.',
                  style:
                      TextStyle(color: c.textSecondary, fontSize: 13),
                ).animate(delay: 50.ms).fadeIn(duration: 400.ms),

                const SizedBox(height: 14),

                // ── Key text field ───────────────────────────
                TextField(
                  controller: _keyCtrl,
                  textCapitalization: TextCapitalization.characters,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontFamily: 'monospace',
                    letterSpacing: 1.5,
                    fontSize: 14,
                  ),
                  onSubmitted: (_) => _redeeming ? null : _redeem(),
                  decoration: InputDecoration(
                    hintText: 'XISSIN-XXXX-XXXX-XXXX-XXXX',
                    prefixIcon:
                        Icon(Icons.vpn_key_rounded, color: c.secondary),
                  ),
                )
                    .animate(delay: 100.ms)
                    .fadeIn(duration: 400.ms)
                    .slideX(begin: -0.1, end: 0, duration: 400.ms),

                const SizedBox(height: 16),

                // ── Redeem button ────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _redeeming ? null : _redeem,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      disabledBackgroundColor:
                          AppColors.accent.withOpacity(0.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 4,
                    ),
                    child: _redeeming
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Text(
                            'Redeem Key',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                  ),
                )
                    .animate(delay: 150.ms)
                    .fadeIn(duration: 400.ms)
                    .slideY(begin: 0.2, end: 0, duration: 400.ms),

                const SizedBox(height: 30),
                _InfoBox(),
              ],
            ),
          ),

          // ── Confetti overlay ─────────────────────────────
          if (_showSuccess)
            Align(
              alignment: Alignment.topCenter,
              child: ConfettiWidget(
                confettiController: _confettiController,
                blastDirectionality: BlastDirectionality.explosive,
                shouldLoop: false,
                colors: const [
                  AppColors.accent,
                  AppColors.primary,
                  Colors.white,
                  _kGold,
                ],
                numberOfParticles: 30,
              ),
            ),

          // ── Success overlay card ──────────────────────────
          if (_showSuccess)
            Center(
              child: GlassNeumorphicCard(
                glowColor: AppColors.accent,
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.verified_rounded,
                        color: AppColors.accent, size: 56),
                    const SizedBox(height: 16),
                    const Text(
                      '🎉 Key Activated!',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'All features are now unlocked.',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 14),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () =>
                          setState(() => _showSuccess = false),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Got it!',
                          style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              )
                  .animate()
                  .scale(
                      begin: const Offset(0.5, 0.5),
                      duration: 400.ms,
                      curve: Curves.elasticOut),
            ),
        ],
      ),
    );
  }
}

// ── Status Card ────────────────────────────────────────────────────────────

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
    final glowColor = isActive ? AppColors.accent : AppColors.error;

    return GlassNeumorphicCard(
      glowColor: glowColor,
      enablePulse: isActive,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: glowColor.withOpacity(0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isActive
                      ? Icons.verified_rounded
                      : Icons.lock_outline,
                  color: glowColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isActive ? 'Key Active' : 'No Active Key',
                      style: TextStyle(
                        color: glowColor,
                        fontSize: 17,
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
            ],
          ),
          if (isActive && status != null) ...[
            const SizedBox(height: 16),
            Container(height: 1, color: AppColors.border),
            const SizedBox(height: 14),
            _InfoRow(
                label: 'Key', value: status!['key'] ?? '—', mono: true),
            const SizedBox(height: 8),
            _InfoRow(
                label: 'Expires',
                value: fmtDate(status!['expires_at'])),
            if (timeRemaining != null) ...[
              const SizedBox(height: 8),
              _CountdownTimer(duration: timeRemaining!),
            ],
          ] else if (!isActive) ...[
            const SizedBox(height: 10),
            const Text(
              'Contact the admin or check Xissin channel for keys.',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  height: 1.5),
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

// ── Countdown Timer ────────────────────────────────────────────────────────

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
        setState(
            () => _remaining = _remaining - const Duration(seconds: 1));
        _startTimer();
      }
    });
  }

  String _formatDuration(Duration d) {
    if (d.isNegative) return 'Expired';
    final days = d.inDays;
    final hours = d.inHours % 24;
    final minutes = d.inMinutes % 60;
    if (days > 0) return '$days days';
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    final isExpiringSoon = _remaining.inDays < 3;

    return Row(
      children: [
        const SizedBox(
          width: 60,
          child: Text('Time Left',
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
        ),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: (isExpiringSoon ? AppColors.error : AppColors.accent)
                .withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            _formatDuration(_remaining),
            style: TextStyle(
              color: isExpiringSoon ? AppColors.error : AppColors.accent,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Info Row ───────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final String label, value;
  final bool mono;
  const _InfoRow(
      {required this.label, required this.value, this.mono = false});

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
              color: AppColors.textPrimary,
              fontSize: 12,
              fontFamily: mono ? 'monospace' : null,
              letterSpacing: mono ? 0.8 : null,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ── Info Box ───────────────────────────────────────────────────────────────

class _InfoBox extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return GlassNeumorphicCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('How to get a key?',
              style: TextStyle(
                  color: c.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 14)),
          const SizedBox(height: 8),
          Text(
            '1. Join the Xissin Telegram channel\n'
            '2. Contact the admin\n'
            '3. Keys are in XISSIN-XXXX-XXXX-XXXX-XXXX format',
            style: TextStyle(
                color: c.textSecondary, fontSize: 13, height: 1.7),
          ),
        ],
      ),
    )
        .animate(delay: 200.ms)
        .fadeIn(duration: 400.ms)
        .slideY(begin: 0.1, end: 0, duration: 400.ms);
  }
}
