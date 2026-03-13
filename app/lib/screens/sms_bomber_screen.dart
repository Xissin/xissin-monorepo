import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:confetti/confetti.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../widgets/glass_neumorphic_card.dart';
import '../widgets/animated_counter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data model for a single attack history entry
// ─────────────────────────────────────────────────────────────────────────────
class _AttackRecord {
  final String phone;
  final int rounds;
  final int sent;
  final int failed;
  final int total;
  final DateTime time;
  final List<dynamic> results;

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
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────
class SmsBomberScreen extends StatefulWidget {
  final String userId;
  const SmsBomberScreen({super.key, required this.userId});

  @override
  State<SmsBomberScreen> createState() => _SmsBomberScreenState();
}

class _SmsBomberScreenState extends State<SmsBomberScreen> {
  final _phoneCtrl        = TextEditingController();
  final _confettiCtrl     = ConfettiController(duration: const Duration(seconds: 3));
  final _scrollCtrl       = ScrollController();

  int  _rounds      = 1;
  bool _loading     = false;
  bool _showConfetti = false;

  // history – newest first
  final List<_AttackRecord> _history = [];

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _confettiCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── validation + fire ───────────────────────────────────────────────────
  Future<void> _fire() async {
    final phone = _phoneCtrl.text.trim();

    if (phone.isEmpty) {
      _snack('Enter a phone number', error: true);
      return;
    }
    if (phone.length != 10 || !phone.startsWith('9') ||
        !RegExp(r'^9\d{9}$').hasMatch(phone)) {
      _snack('Use format 9XXXXXXXXX (10 digits, PH number)', error: true);
      return;
    }

    HapticFeedback.heavyImpact();
    setState(() {
      _loading      = true;
      _showConfetti = false;
    });

    try {
      final data = await ApiService.smsBomb(
        phone: phone,
        userId: widget.userId,
        rounds: _rounds,
      );

      final sent    = (data['total_sent']   as int?) ?? 0;
      final failed  = (data['total_failed'] as int?) ?? 0;
      final results = (data['results']      as List?) ?? [];
      final total   = sent + failed;

      final record = _AttackRecord(
        phone:   phone,
        rounds:  _rounds,
        sent:    sent,
        failed:  failed,
        total:   total,
        time:    DateTime.now(),
        results: results,
      );

      setState(() {
        _history.insert(0, record);
        if (sent > 0) {
          _showConfetti = true;
          _confettiCtrl.play();
        }
      });

      // scroll to results after a short delay
      await Future.delayed(const Duration(milliseconds: 300));
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOut,
        );
      }
    } on ApiException catch (e) {
      _snack(e.userMessage, error: true);
    } catch (e) {
      _snack('Request failed: $e', error: true);
    } finally {
      setState(() => _loading = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.error : AppColors.accent,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(12),
    ));
  }

  // ── attack-again helper ──────────────────────────────────────────────────
  void _repeatAttack(_AttackRecord r) {
    _phoneCtrl.text = r.phone;
    setState(() => _rounds = r.rounds.clamp(1, 5));
    _scrollCtrl.animateTo(
      0,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOut,
    );
    _snack('Phone pre-filled — tap FIRE when ready 🎯');
  }

  // ── build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: const Text('SMS Bomber'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            controller: _scrollCtrl,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Warning banner ─────────────────────────────────────
                GlassNeumorphicCard(
                  glowColor: c.error,
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: c.error, size: 18),
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

                // ── Target number ──────────────────────────────────────
                const Text('Target Number',
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500))
                    .animate(delay: 100.ms)
                    .fadeIn(duration: 400.ms),
                const SizedBox(height: 8),
                TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      letterSpacing: 1),
                  decoration: InputDecoration(
                    hintText: '9XXXXXXXXX',
                    prefixIcon: const Icon(Icons.phone_android_rounded,
                        color: AppColors.primary),
                    prefix: const Text('+63 ',
                        style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 15)),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear_rounded,
                          color: AppColors.textSecondary, size: 18),
                      onPressed: () => _phoneCtrl.clear(),
                    ),
                  ),
                )
                    .animate(delay: 150.ms)
                    .fadeIn(duration: 400.ms)
                    .slideX(begin: -0.1, end: 0, duration: 400.ms),

                const SizedBox(height: 26),

                // ── Rounds selector ────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Rounds',
                        style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500)),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$_rounds × 14 = ${_rounds * 14} SMS',
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ).animate(delay: 200.ms).fadeIn(duration: 400.ms),

                const SizedBox(height: 10),

                Row(
                  children: List.generate(5, (i) {
                    final n   = i + 1;
                    final sel = _rounds == n;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _rounds = n);
                        },
                        child: Container(
                          margin: EdgeInsets.only(right: i < 4 ? 8 : 0),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          decoration: BoxDecoration(
                            gradient: sel
                                ? const LinearGradient(colors: [
                                    AppColors.primary,
                                    AppColors.secondary,
                                  ])
                                : null,
                            color:
                                sel ? null : AppColors.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: sel
                                    ? AppColors.primary
                                    : AppColors.border),
                            boxShadow: sel
                                ? [
                                    BoxShadow(
                                        color: AppColors.primary
                                            .withOpacity(0.3),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4))
                                  ]
                                : null,
                          ),
                          child: Center(
                            child: Text(
                              '$n',
                              style: TextStyle(
                                color: sel
                                    ? Colors.white
                                    : AppColors.textSecondary,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ).animate(delay: 250.ms).fadeIn(duration: 400.ms),

                const SizedBox(height: 32),

                // ── FIRE button ────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _fire,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      disabledBackgroundColor:
                          AppColors.primary.withOpacity(0.4),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 6,
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.send_rounded,
                                  size: 18, color: Colors.white),
                              SizedBox(width: 8),
                              Text('FIRE',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 3,
                                      color: Colors.white)),
                            ],
                          ),
                  ),
                )
                    .animate(delay: 300.ms)
                    .fadeIn(duration: 400.ms)
                    .slideY(begin: 0.2, end: 0, duration: 400.ms),

                const SizedBox(height: 32),

                // ── Attack History ─────────────────────────────────────
                if (_history.isNotEmpty) ...[
                  Row(
                    children: [
                      const Icon(Icons.history_rounded,
                          color: AppColors.textSecondary, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'Attack History  (${_history.length})',
                        style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ).animate().fadeIn(duration: 400.ms),

                  const SizedBox(height: 12),

                  ...List.generate(_history.length, (i) {
                    return _HistoryCard(
                      record: _history[i],
                      index: i,
                      onAttackAgain: () => _repeatAttack(_history[i]),
                    ).animate(delay: Duration(milliseconds: 60 * i))
                        .fadeIn(duration: 350.ms)
                        .slideY(begin: 0.08, end: 0, duration: 350.ms);
                  }),

                  const SizedBox(height: 20),
                ],
              ],
            ),
          ),

          // ── Confetti ───────────────────────────────────────────────────
          if (_showConfetti)
            Align(
              alignment: Alignment.topCenter,
              child: ConfettiWidget(
                confettiController: _confettiCtrl,
                blastDirectionality: BlastDirectionality.explosive,
                shouldLoop: false,
                numberOfParticles: 30,
                colors: const [
                  AppColors.accent,
                  AppColors.primary,
                  Colors.white,
                  Colors.orange,
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// History Card
// ─────────────────────────────────────────────────────────────────────────────
class _HistoryCard extends StatefulWidget {
  final _AttackRecord record;
  final int index;
  final VoidCallback onAttackAgain;

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
    final r      = widget.record;
    final sucPct = (r.successPct * 100).toStringAsFixed(1);
    final failPct = (r.failedPct * 100).toStringAsFixed(1);

    return GlassNeumorphicCard(
      padding: const EdgeInsets.all(14),
      glowColor: r.sent > 0
          ? AppColors.accent.withOpacity(0.4)
          : AppColors.error.withOpacity(0.3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ─────────────────────────────────────────────
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '#${widget.index + 1}',
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '+63 ${r.phone}',
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
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

          // ── Stats row ──────────────────────────────────────────────
          Row(
            children: [
              _MiniStat(
                  label: 'Rounds', value: '${r.rounds}',
                  color: AppColors.primary),
              const SizedBox(width: 8),
              _MiniStat(
                  label: 'Total SMS',
                  value: '${r.total}',
                  color: AppColors.textSecondary),
              const SizedBox(width: 8),
              _MiniStat(
                  label: 'Sent', value: '${r.sent}', color: AppColors.accent),
              const SizedBox(width: 8),
              _MiniStat(
                  label: 'Failed',
                  value: '${r.failed}',
                  color: AppColors.error),
            ],
          ),

          // ── Progress bars (only when rounds >= 2) ─────────────────
          if (r.rounds >= 2 && r.total > 0) ...[
            const SizedBox(height: 12),
            _ProgressBar(
              label: 'Success',
              pct: r.successPct,
              pctLabel: '$sucPct%',
              color: AppColors.accent,
            ),
            const SizedBox(height: 6),
            _ProgressBar(
              label: 'Failed',
              pct: r.failedPct,
              pctLabel: '$failPct%',
              color: AppColors.error,
            ),
          ],

          const SizedBox(height: 12),

          // ── Action buttons ─────────────────────────────────────────
          Row(
            children: [
              // Details toggle
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Row(
                  children: [
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: AppColors.textSecondary,
                      size: 18,
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

              // Attack again
              SizedBox(
                height: 32,
                child: ElevatedButton.icon(
                  onPressed: widget.onAttackAgain,
                  icon: const Icon(Icons.replay_rounded, size: 14),
                  label: const Text('Attack Again',
                      style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 0),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    elevation: 2,
                  ),
                ),
              ),
            ],
          ),

          // ── Per-service detail rows ────────────────────────────────
          if (_expanded && r.results.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(height: 1, color: AppColors.border),
            const SizedBox(height: 10),
            ...r.results.asMap().entries.map(
              (e) => _ServiceRow(data: e.value, index: e.key),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Mini stat chip
// ─────────────────────────────────────────────────────────────────────────────
class _MiniStat extends StatelessWidget {
  final String label, value;
  final Color color;
  const _MiniStat(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    color: color,
                    fontSize: 15,
                    fontWeight: FontWeight.bold)),
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

// ─────────────────────────────────────────────────────────────────────────────
// Progress bar
// ─────────────────────────────────────────────────────────────────────────────
class _ProgressBar extends StatelessWidget {
  final String label, pctLabel;
  final double pct;
  final Color color;
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
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct.clamp(0.0, 1.0),
              minHeight: 7,
              backgroundColor: color.withOpacity(0.12),
              valueColor: AlwaysStoppedAnimation<Color>(color),
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
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Per-service result row
// ─────────────────────────────────────────────────────────────────────────────
class _ServiceRow extends StatelessWidget {
  final Map data;
  final int index;
  const _ServiceRow({required this.data, required this.index});

  @override
  Widget build(BuildContext context) {
    final ok  = data['success'] == true;
    final msg = (data['message'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: ok
              ? AppColors.accent.withOpacity(0.25)
              : AppColors.error.withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            ok
                ? Icons.check_circle_outline_rounded
                : Icons.cancel_outlined,
            size: 15,
            color: ok ? AppColors.accent : AppColors.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Text(
              data['service'] ?? '',
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
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
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    )
        .animate(delay: Duration(milliseconds: 40 * index))
        .fadeIn(duration: 250.ms)
        .slideX(begin: 0.05, end: 0, duration: 250.ms);
  }
}