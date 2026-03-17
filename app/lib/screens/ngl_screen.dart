import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../widgets/glass_neumorphic_card.dart';
import '../widgets/haptic_button.dart';

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

  int    _sent       = 0;
  int    _failed     = 0;
  String _resultMsg  = '';
  bool   _resultOk   = false;

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

  // ── Progress ───────────────────────────────────────────────────────────────

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
      final err = e is ApiException
          ? e.userMessage
          : e.toString().replaceFirst('Exception: ', '');
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
      _progress  = 0;
      _sent = _failed = 0;
      _resultMsg = '';
      _charCount = 0;
    });
    _usernameCtrl.clear();
    _messageCtrl.clear();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

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

          // Username
          _Label('NGL Username', c),
          const SizedBox(height: 8),
          _buildUsernameField(c)
              .animate()
              .fadeIn(duration: 350.ms)
              .slideY(begin: 0.08, end: 0),
          const SizedBox(height: 18),

          // Message + char counter
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

          // Quantity
          _QuantityLabel(quantity: _quantity, c: c),
          const SizedBox(height: 6),
          _buildQuantitySlider(c)
              .animate()
              .fadeIn(duration: 350.ms, delay: 120.ms),
          const SizedBox(height: 28),

          // Progress bar while loading
          if (_loading) ...[
            _GradientProgressBar(progress: _progress, c: c)
                .animate()
                .fadeIn(duration: 300.ms),
            const SizedBox(height: 20),
          ],

          // Send button
          _SendButton(loading: _loading, onPressed: _send)
              .animate()
              .fadeIn(duration: 350.ms, delay: 160.ms),

          const SizedBox(height: 24),

          // Tips section
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
      maxLines: 4,
      maxLength:  300,
      buildCounter: (_, {required currentLength, required isFocused, maxLength}) =>
          const SizedBox.shrink(), // hide default counter (we show our own)
      decoration: _inputDecoration(c).copyWith(
        hintText: 'Enter your anonymous message...',
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

  Widget _buildQuantitySlider(XissinColors c) {
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
            value: _quantity.toDouble(),
            min:   1,
            max:   50,
            divisions: 49,
            onChanged: (v) => setState(() => _quantity = v.toInt()),
          ),
        ),
        // Tick marks
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [1, 10, 20, 30, 40, 50]
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
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        borderSide:
            BorderSide(color: c.textSecondary.withOpacity(0.12), width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        borderSide: const BorderSide(color: _kPink, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        borderSide: const BorderSide(color: _kRed, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        borderSide: const BorderSide(color: _kRed, width: 1.5),
      ),
    );
  }

  // ── Result ─────────────────────────────────────────────────────────────────

  Widget _buildResult(XissinColors c) {
    final color = _resultOk ? _kGreen : _kRed;
    return Column(
      children: [
        const SizedBox(height: 32),

        // Icon circle with double glow
        Container(
          width:  96,
          height: 96,
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
            size:  48,
            color: color,
          ),
        )
            .animate()
            .scale(
                begin:    const Offset(0.4, 0.4),
                duration: 550.ms,
                curve:    Curves.elasticOut)
            .fadeIn(duration: 300.ms),

        const SizedBox(height: 24),

        // Title
        Text(
          _resultOk ? '🎉  Done!' : '❌  Failed',
          style: TextStyle(
              color:      color,
              fontSize:   24,
              fontWeight: FontWeight.w800),
        ).animate().fadeIn(duration: 350.ms, delay: 150.ms),

        const SizedBox(height: 10),

        // Message
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            _resultMsg,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: c.textSecondary, fontSize: 14, height: 1.5),
          ),
        ).animate().fadeIn(duration: 350.ms, delay: 200.ms),

        const SizedBox(height: 28),

        // Stats
        if (_resultOk) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _StatChip(label: 'Sent',   value: '$_sent',   color: _kGreen, c: c),
              const SizedBox(width: 16),
              _StatChip(label: 'Failed', value: '$_failed', color: _kRed,   c: c),
            ],
          ).animate().fadeIn(duration: 350.ms, delay: 280.ms),
          const SizedBox(height: 32),
        ],

        // Send again button
        SizedBox(
          width:  double.infinity,
          height: 52,
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

class _QuantityLabel extends StatelessWidget {
  final int quantity;
  final XissinColors c;
  const _QuantityLabel({required this.quantity, required this.c});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Text(
            'Quantity: ',
            style: TextStyle(
                color: c.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color:        _kPink.withOpacity(0.15),
              borderRadius: BorderRadius.circular(AppRadius.full),
              border:       Border.all(color: _kPink.withOpacity(0.35), width: 1),
            ),
            child: Text(
              '$quantity msg${quantity == 1 ? '' : 's'}',
              style: const TextStyle(
                color:      _kPink,
                fontSize:   12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      );
}

// Character counter with color ring
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
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              value:           count / max,
              strokeWidth:     2.5,
              backgroundColor: c.border,
              valueColor:      AlwaysStoppedAnimation<Color>(_color),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count / $max',
            style: TextStyle(
              color:      _color,
              fontSize:   11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
}

class _InfoBanner extends StatelessWidget {
  final XissinColors c;
  const _InfoBanner({required this.c});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kOrange.withOpacity(0.07),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: _kOrange.withOpacity(0.25), width: 1),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, size: 18, color: _kOrange),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Sends anonymous messages to any NGL profile.\n'
              'Max 50 messages per send.',
              style: TextStyle(
                  color: c.textSecondary, fontSize: 12, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

// Gradient progress bar
class _GradientProgressBar extends StatelessWidget {
  final double progress;
  final XissinColors c;
  const _GradientProgressBar({required this.progress, required this.c});

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
                    color:      c.textSecondary,
                    fontSize:   12,
                    fontWeight: FontWeight.w500)),
            Text('$pct%',
                style: const TextStyle(
                    color:      _kPink,
                    fontSize:   12,
                    fontWeight: FontWeight.w700)),
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
                    gradient: LinearGradient(
                      colors: [_kPink, _kOrange],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// Tips card
class _TipsCard extends StatelessWidget {
  final XissinColors c;
  const _TipsCard({required this.c});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:        c.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border:       Border.all(color: c.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.lightbulb_outline_rounded,
                size: 15, color: _kOrange),
            const SizedBox(width: 6),
            Text('Tips',
                style: TextStyle(
                  color:      c.textPrimary,
                  fontSize:   13,
                  fontWeight: FontWeight.bold,
                )),
          ]),
          const SizedBox(height: 10),
          _tip('Enter only the username, not the full ngl.link URL', c),
          _tip('Use the paste button to auto-clean copied links', c),
          _tip('Max 50 messages per send to avoid rate limits', c),
        ],
      ),
    );
  }

  Widget _tip(String text, XissinColors c) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('• ', style: TextStyle(color: _kPink, fontSize: 13)),
            Expanded(
              child: Text(text,
                  style: TextStyle(
                      color: c.textSecondary, fontSize: 12, height: 1.4)),
            ),
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
      width:  double.infinity,
      height: 54,
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
            ? const SizedBox(
                width:  18,
                height: 18,
                child:  CircularProgressIndicator(
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
  final Color  color;
  final XissinColors c;
  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      decoration: BoxDecoration(
        color:        color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border:       Border.all(color: color.withOpacity(0.30), width: 1),
        boxShadow:    AppShadows.glow(color, intensity: 0.10, blur: 12),
      ),
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  color:      color,
                  fontSize:   28,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                  color:      c.textSecondary,
                  fontSize:   12,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}