import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../widgets/glass_neumorphic_card.dart';
import '../widgets/haptic_button.dart';

// Pink/orange brand colours for NGL
const _kPink   = Color(0xFFFF6EC7);
const _kOrange = Color(0xFFFF9A44);
const _kGreen  = Color(0xFF7EE7C1);
const _kRed    = Color(0xFFFF6B6B);

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
  int    _charCount  = 0;

  // Result
  int    _sent       = 0;
  int    _failed     = 0;
  String _resultMsg  = '';
  bool   _resultOk   = false;

  // Animated progress
  double _progress   = 0.0;
  Timer? _progressTimer;

  @override
  void initState() {
    super.initState();
    _messageCtrl.addListener(() {
      final len = _messageCtrl.text.length;
      if (len != _charCount) setState(() => _charCount = len);
    });
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _messageCtrl.dispose();
    _progressTimer?.cancel();
    super.dispose();
  }

  // ── Progress helpers ────────────────────────────────────────────────────────

  void _startFakeProgress() {
    _progress = 0.0;
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 60), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        if (_progress < 0.88) _progress += 0.015 * (1.0 - _progress);
      });
    });
  }

  void _stopProgress(bool success) {
    _progressTimer?.cancel();
    if (!mounted) return;
    setState(() => _progress = success ? 1.0 : _progress);
  }

  // ── Clipboard paste ─────────────────────────────────────────────────────────

  Future<void> _pasteUsername() async {
    final data = await Clipboard.getData('text/plain');
    if (data?.text != null && data!.text!.isNotEmpty) {
      HapticFeedback.selectionClick();
      final raw = data.text!.trim();
      // Strip ngl.link/ URL if the user copied a full link
      final clean = raw
          .replaceAll(RegExp(r'https?://(www\.)?ngl\.link/'), '')
          .replaceAll('@', '')
          .trim();
      _usernameCtrl.text = clean;
      _usernameCtrl.selection = TextSelection.fromPosition(
        TextPosition(offset: clean.length),
      );
    }
  }

  // ── Send ────────────────────────────────────────────────────────────────────

  Future<void> _send() async {
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
      final err = e is ApiException ? e.userMessage : e.toString().replaceFirst('Exception: ', '');
      setState(() {
        _loading   = false;
        _done      = true;
        _resultOk  = false;
        _resultMsg = err;
      });
      HapticFeedback.vibrate();
    }
  }

  void _reset() {
    HapticFeedback.selectionClick();
    setState(() {
      _done = _loading = false;
      _progress = 0;
      _sent = _failed = 0;
      _resultMsg = '';
      _charCount = 0;
    });
    _usernameCtrl.clear();
    _messageCtrl.clear();
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      backgroundColor: c.background,
      appBar: _buildAppBar(c),
      body: SafeArea(
        child: SingleChildScrollView(
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
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 20,
            letterSpacing: 0.5,
          ),
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
          _InfoBanner(c: c),
          const SizedBox(height: 22),

          // ── Username ──
          _Label('NGL Username', c),
          const SizedBox(height: 8),
          _buildUsernameField(c)
              .animate().fadeIn(duration: 350.ms).slideY(begin: 0.08, end: 0),
          const SizedBox(height: 18),

          // ── Message ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _Label('Anonymous Message', c),
              Text(
                '$_charCount / 300',
                style: TextStyle(
                  color: _charCount > 270
                      ? _kRed
                      : _charCount > 240
                          ? _kOrange
                          : c.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildMessageField(c)
              .animate().fadeIn(duration: 350.ms, delay: 60.ms).slideY(begin: 0.08, end: 0),
          const SizedBox(height: 20),

          // ── Quantity slider ──
          _Label('Quantity: $_quantity message${_quantity == 1 ? '' : 's'}', c),
          const SizedBox(height: 6),
          _buildQuantitySlider(c)
              .animate().fadeIn(duration: 350.ms, delay: 120.ms),
          const SizedBox(height: 28),

          // ── Progress bar (while loading) ──
          if (_loading) ...[
            _ProgressBar(progress: _progress, c: c)
                .animate().fadeIn(duration: 300.ms),
            const SizedBox(height: 20),
          ],

          // ── Send button ──
          _SendButton(loading: _loading, onPressed: _send)
              .animate().fadeIn(duration: 350.ms, delay: 160.ms),
        ],
      ),
    );
  }

  Widget _buildUsernameField(XissinColors c) {
    return TextFormField(
      controller: _usernameCtrl,
      enabled: !_loading,
      style: TextStyle(color: c.textPrimary),
      decoration: _inputDeco(
        c: c,
        hint: 'e.g. john_doe  or  ngl.link/john_doe',
        icon: Icons.alternate_email_rounded,
        suffix: IconButton(
          icon: Icon(Icons.content_paste_rounded,
              size: 18, color: c.textSecondary),
          tooltip: 'Paste',
          onPressed: _pasteUsername,
        ),
      ),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Enter a username';
        final clean = v.trim()
            .replaceAll(RegExp(r'https?://(www\.)?ngl\.link/'), '')
            .replaceAll('@', '');
        if (!RegExp(r'^[A-Za-z0-9._]{1,60}$').hasMatch(clean)) {
          return 'Only letters, numbers, dots and underscores allowed';
        }
        return null;
      },
    );
  }

  Widget _buildMessageField(XissinColors c) {
    return TextFormField(
      controller: _messageCtrl,
      enabled: !_loading,
      maxLines: 4,
      maxLength: 300,
      buildCounter: (_, {required currentLength, required isFocused, maxLength}) =>
          const SizedBox.shrink(), // hide default counter — we have our own
      style: TextStyle(color: c.textPrimary),
      decoration: _inputDeco(
        c: c,
        hint: 'Type your anonymous message...',
        icon: Icons.message_rounded,
      ),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Enter a message';
        if (v.trim().length > 300) return 'Max 300 characters';
        return null;
      },
    );
  }

  Widget _buildQuantitySlider(XissinColors c) {
    return GlassNeumorphicCard(
      glowColor: _kPink,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.remove_rounded, size: 18),
            color: _kPink,
            onPressed: _loading || _quantity <= 1
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    setState(() => _quantity = (_quantity - 1).clamp(1, 50));
                  },
          ),
          Expanded(
            child: Slider(
              value: _quantity.toDouble(),
              min: 1,
              max: 50,
              divisions: 49,
              activeColor: _kPink,
              inactiveColor: c.surface,
              onChanged: _loading
                  ? null
                  : (v) {
                      HapticFeedback.selectionClick();
                      setState(() => _quantity = v.round());
                    },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_rounded, size: 18),
            color: _kPink,
            onPressed: _loading || _quantity >= 50
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    setState(() => _quantity = (_quantity + 1).clamp(1, 50));
                  },
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDeco({
    required XissinColors c,
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: c.textSecondary.withOpacity(0.55), fontSize: 13),
      prefixIcon: Icon(icon, color: c.textSecondary, size: 19),
      suffixIcon: suffix,
      filled: true,
      fillColor: c.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c.textSecondary.withOpacity(0.12), width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _kPink, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _kRed, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _kRed, width: 1.5),
      ),
    );
  }

  // ── Result ───────────────────────────────────────────────────────────────────

  Widget _buildResult(XissinColors c) {
    final color = _resultOk ? _kGreen : _kRed;
    return Column(
      children: [
        const SizedBox(height: 32),

        // Icon circle
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withOpacity(0.12),
            border: Border.all(color: color.withOpacity(0.4), width: 2),
          ),
          child: Icon(
            _resultOk
                ? Icons.check_circle_outline_rounded
                : Icons.error_outline_rounded,
            size: 44,
            color: color,
          ),
        )
            .animate()
            .scale(
                begin: const Offset(0.4, 0.4),
                duration: 550.ms,
                curve: Curves.elasticOut)
            .fadeIn(duration: 300.ms),

        const SizedBox(height: 22),

        // Result text
        Text(
          _resultOk ? '🎉 Done!' : '❌ Failed',
          style: TextStyle(
              color: color, fontSize: 22, fontWeight: FontWeight.w800),
        ).animate().fadeIn(duration: 350.ms, delay: 150.ms),

        const SizedBox(height: 10),

        Text(
          _resultMsg,
          textAlign: TextAlign.center,
          style: TextStyle(
              color: c.textSecondary, fontSize: 14, height: 1.5),
        ).animate().fadeIn(duration: 350.ms, delay: 200.ms),

        const SizedBox(height: 24),

        // Stats
        if (_resultOk) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _StatChip(label: 'Sent',   value: '$_sent',   color: _kGreen,  c: c),
              const SizedBox(width: 14),
              _StatChip(label: 'Failed', value: '$_failed', color: _kRed,    c: c),
            ],
          ).animate().fadeIn(duration: 350.ms, delay: 280.ms),
          const SizedBox(height: 30),
        ],

        // Send again
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: _reset,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPink,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            icon: const Icon(Icons.refresh_rounded, size: 20),
            label: const Text('Send Again',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ).animate().fadeIn(duration: 350.ms, delay: 320.ms),
      ],
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _Label extends StatelessWidget {
  final String text;
  final XissinColors c;
  const _Label(this.text, this.c);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
            color: c.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
      );
}

class _InfoBanner extends StatelessWidget {
  final XissinColors c;
  const _InfoBanner({required this.c});

  @override
  Widget build(BuildContext context) {
    return GlassNeumorphicCard(
      glowColor: _kOrange,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, size: 18, color: _kOrange),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Sends anonymous messages to any NGL profile.\n'
              'Requires an active key. Max 50 messages per send.',
              style: TextStyle(
                  color: c.textSecondary, fontSize: 12, height: 1.45),
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
    final pct = (progress * 100).toStringAsFixed(0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Sending messages...',
                style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500)),
            Text('$pct%',
                style: const TextStyle(
                    color: _kPink,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: c.surface,
            valueColor: const AlwaysStoppedAnimation(_kPink),
          ),
        ),
      ],
    );
  }
}

class _SendButton extends StatelessWidget {
  final bool loading;
  final VoidCallback onPressed;
  const _SendButton({required this.loading, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: _kPink,
          foregroundColor: Colors.white,
          disabledBackgroundColor: _kPink.withOpacity(0.4),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
        ),
        icon: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.send_rounded, size: 20),
        label: Text(
          loading ? 'Sending...' : 'Send Messages',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 26,
                  fontWeight: FontWeight.w800)),
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
