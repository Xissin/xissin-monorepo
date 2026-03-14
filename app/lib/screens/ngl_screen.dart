import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../widgets/glass_neumorphic_card.dart';
import '../widgets/haptic_button.dart';

class NglScreen extends StatefulWidget {
  final String userId;
  const NglScreen({super.key, required this.userId});

  @override
  State<NglScreen> createState() => _NglScreenState();
}

class _NglScreenState extends State<NglScreen> {
  final _usernameCtrl = TextEditingController();
  final _messageCtrl  = TextEditingController();
  final _formKey      = GlobalKey<FormState>();

  int    _quantity   = 5;
  bool   _loading    = false;
  bool   _done       = false;

  // Result state
  int    _sent       = 0;
  int    _failed     = 0;
  String _resultMsg  = '';
  bool   _resultOk   = false;

  // Progress animation
  double _progress   = 0.0;
  Timer? _progressTimer;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _messageCtrl.dispose();
    _progressTimer?.cancel();
    super.dispose();
  }

  void _startFakeProgress() {
    _progress = 0.0;
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 80), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        // Crawl to ~90 %, the real finish will snap it to 1.0
        if (_progress < 0.90) {
          _progress += 0.012 * (1.0 - _progress);
        }
      });
    });
  }

  void _stopProgress(bool success) {
    _progressTimer?.cancel();
    setState(() => _progress = success ? 1.0 : _progress);
  }

  Future<void> _sendMessages() async {
    if (!_formKey.currentState!.validate()) return;
    HapticFeedback.mediumImpact();
    FocusScope.of(context).unfocus();

    setState(() {
      _loading   = true;
      _done      = false;
      _sent      = 0;
      _failed    = 0;
      _resultMsg = '';
    });

    _startFakeProgress();

    try {
      final result = await ApiService.sendNgl(
        userId:   widget.userId,
        username: _usernameCtrl.text.trim(),
        message:  _messageCtrl.text.trim(),
        quantity: _quantity,
      );

      _stopProgress(result['success'] == true);

      if (!mounted) return;
      setState(() {
        _loading   = false;
        _done      = true;
        _resultOk  = result['success'] == true;
        _sent      = (result['sent']   as num?)?.toInt() ?? 0;
        _failed    = (result['failed'] as num?)?.toInt() ?? 0;
        _resultMsg = result['message'] as String? ?? '';
      });

      HapticFeedback.heavyImpact();
    } catch (e) {
      _stopProgress(false);
      if (!mounted) return;
      setState(() {
        _loading   = false;
        _done      = true;
        _resultOk  = false;
        _resultMsg = e.toString().replaceFirst('Exception: ', '');
      });
      HapticFeedback.vibrate();
    }
  }

  void _reset() {
    HapticFeedback.selectionClick();
    setState(() {
      _done      = false;
      _loading   = false;
      _progress  = 0.0;
      _sent      = 0;
      _failed    = 0;
      _resultMsg = '';
    });
    _usernameCtrl.clear();
    _messageCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        elevation: 0,
        leading: HapticIconButton(
          icon: Icons.arrow_back_ios_new_rounded,
          onPressed: () => Navigator.pop(context),
          color: c.textPrimary,
          backgroundColor: c.surface,
        ),
        title: ShaderMask(
          shaderCallback: (b) => LinearGradient(
            colors: [const Color(0xFFFF6EC7), const Color(0xFFFF9A44)],
          ).createShader(b),
          child: const Text(
            'NGL Bomber',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 20,
              letterSpacing: 1,
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: _done ? _buildResult(c) : _buildForm(c),
        ),
      ),
    );
  }

  // ── Form ────────────────────────────────────────────────────────────────────

  Widget _buildForm(XissinColors c) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Info banner
          _InfoBanner(c: c),
          const SizedBox(height: 20),

          // Username field
          _Label(text: 'NGL Username', c: c),
          const SizedBox(height: 8),
          _buildTextField(
            controller: _usernameCtrl,
            c: c,
            hint: 'e.g. john_doe',
            icon: Icons.alternate_email_rounded,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Enter a username';
              final clean = v.trim().replaceAll(RegExp(r'https?://(www\.)?ngl\.link/'), '');
              if (!RegExp(r'^[A-Za-z0-9._]{1,60}$').hasMatch(clean)) {
                return 'Invalid username (letters, numbers, . _ only)';
              }
              return null;
            },
          ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0),

          const SizedBox(height: 18),

          // Message field
          _Label(text: 'Anonymous Message', c: c),
          const SizedBox(height: 8),
          _buildTextField(
            controller: _messageCtrl,
            c: c,
            hint: 'Type your message...',
            icon: Icons.message_rounded,
            maxLines: 4,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Enter a message';
              if (v.trim().length > 300) return 'Max 300 characters';
              return null;
            },
          ).animate().fadeIn(duration: 400.ms, delay: 80.ms).slideY(begin: 0.1, end: 0),

          const SizedBox(height: 20),

          // Quantity slider
          _Label(text: 'Quantity: $_quantity messages', c: c),
          const SizedBox(height: 6),
          GlassNeumorphicCard(
            glowColor: const Color(0xFFFF6EC7),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Slider(
              value: _quantity.toDouble(),
              min: 1,
              max: 50,
              divisions: 49,
              activeColor: const Color(0xFFFF6EC7),
              inactiveColor: c.surface,
              label: '$_quantity',
              onChanged: _loading
                  ? null
                  : (v) {
                      HapticFeedback.selectionClick();
                      setState(() => _quantity = v.round());
                    },
            ),
          ).animate().fadeIn(duration: 400.ms, delay: 160.ms),

          const SizedBox(height: 28),

          // Progress bar (only visible while loading)
          if (_loading) ...[
            _ProgressBar(progress: _progress, c: c),
            const SizedBox(height: 20),
          ],

          // Send button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _loading ? null : _sendMessages,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6EC7),
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    const Color(0xFFFF6EC7).withOpacity(0.4),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send_rounded, size: 20),
              label: Text(
                _loading ? 'Sending...' : 'Send Messages',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
          ).animate().fadeIn(duration: 400.ms, delay: 200.ms),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required XissinColors c,
    required String hint,
    required IconData icon,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      enabled: !_loading,
      style: TextStyle(color: c.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: c.textSecondary.withOpacity(0.6)),
        prefixIcon: Icon(icon, color: c.textSecondary, size: 20),
        filled: true,
        fillColor: c.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              BorderSide(color: c.textSecondary.withOpacity(0.15), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              const BorderSide(color: Color(0xFFFF6EC7), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              const BorderSide(color: Color(0xFFFF6B6B), width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              const BorderSide(color: Color(0xFFFF6B6B), width: 1.5),
        ),
      ),
      validator: validator,
    );
  }

  // ── Result ───────────────────────────────────────────────────────────────────

  Widget _buildResult(XissinColors c) {
    final color = _resultOk
        ? const Color(0xFF7EE7C1)
        : const Color(0xFFFF6B6B);

    return Column(
      children: [
        const SizedBox(height: 24),
        // Big icon
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withOpacity(0.15),
            border: Border.all(color: color.withOpacity(0.4), width: 2),
          ),
          child: Icon(
            _resultOk
                ? Icons.check_circle_outline_rounded
                : Icons.error_outline_rounded,
            size: 40,
            color: color,
          ),
        )
            .animate()
            .scale(
                begin: const Offset(0.5, 0.5),
                duration: 500.ms,
                curve: Curves.elasticOut)
            .fadeIn(duration: 300.ms),

        const SizedBox(height: 20),

        // Result message
        Text(
          _resultMsg,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: c.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
        ).animate().fadeIn(duration: 400.ms, delay: 200.ms),

        const SizedBox(height: 20),

        // Stats row
        if (_resultOk) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _StatChip(
                label: 'Sent',
                value: '$_sent',
                color: const Color(0xFF7EE7C1),
                c: c,
              ),
              const SizedBox(width: 12),
              _StatChip(
                label: 'Failed',
                value: '$_failed',
                color: const Color(0xFFFF6B6B),
                c: c,
              ),
            ],
          ).animate().fadeIn(duration: 400.ms, delay: 300.ms),
          const SizedBox(height: 28),
        ],

        // Send again button
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: _reset,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6EC7),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            icon: const Icon(Icons.refresh_rounded, size: 20),
            label: const Text(
              'Send Again',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ),
        ).animate().fadeIn(duration: 400.ms, delay: 350.ms),
      ],
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _Label extends StatelessWidget {
  final String text;
  final XissinColors c;
  const _Label({required this.text, required this.c});

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
          color: c.textPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      );
}

class _InfoBanner extends StatelessWidget {
  final XissinColors c;
  const _InfoBanner({required this.c});

  @override
  Widget build(BuildContext context) {
    return GlassNeumorphicCard(
      glowColor: const Color(0xFFFF9A44),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 18, color: Color(0xFFFF9A44)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Sends anonymous messages to any NGL profile.\n'
              'Requires an active key.',
              style: TextStyle(
                  color: c.textSecondary, fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final double progress;
  final XissinColors c;
  const _ProgressBar({required this.progress, required this.c});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sending ${(progress * 100).toStringAsFixed(0)}%...',
          style: TextStyle(
              color: c.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: c.surface,
            valueColor: const AlwaysStoppedAnimation(Color(0xFFFF6EC7)),
          ),
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final XissinColors c;
  const _StatChip(
      {required this.label,
      required this.value,
      required this.color,
      required this.c});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
                color: color, fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  color: c.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
