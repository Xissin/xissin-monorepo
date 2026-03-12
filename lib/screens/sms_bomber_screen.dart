import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';

class SmsBomberScreen extends StatefulWidget {
  final String userId;
  const SmsBomberScreen({super.key, required this.userId});

  @override
  State<SmsBomberScreen> createState() => _SmsBomberScreenState();
}

class _SmsBomberScreenState extends State<SmsBomberScreen> {
  final _phoneCtrl = TextEditingController();
  int _rounds = 1;
  bool _loading = false;
  Map<String, dynamic>? _result;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _fire() async {
    final phone = _phoneCtrl.text.trim();

    // ✅ Client-side validation — must be exactly 10 digits starting with 9
    if (phone.isEmpty) {
      _snack('Enter a phone number', error: true);
      return;
    }
    if (phone.length != 10) {
      _snack('Number must be exactly 10 digits (9XXXXXXXXX)', error: true);
      return;
    }
    if (!phone.startsWith('9')) {
      _snack('Philippine numbers must start with 9', error: true);
      return;
    }
    if (!RegExp(r'^9\d{9}$').hasMatch(phone)) {
      _snack('Invalid number format. Use 9XXXXXXXXX', error: true);
      return;
    }

    setState(() {
      _loading = true;
      _result = null;
    });
    try {
      final data = await ApiService.smsBomb(
        phone: phone,
        userId: widget.userId,
        rounds: _rounds,
      );
      setState(() => _result = data);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('SMS Bomber'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Warning banner
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.error.withOpacity(0.25)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: AppColors.error, size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'For educational use only. PH numbers (9XXXXXXXXX) only.',
                      style: TextStyle(
                          color: AppColors.error, fontSize: 12, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 26),

            // Phone number
            const Text('Target Number',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
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
            ),
            const SizedBox(height: 26),

            // Rounds
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Rounds',
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500)),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
            ),
            const SizedBox(height: 10),
            Row(
              children: List.generate(5, (i) {
                final n = i + 1;
                final sel = _rounds == n;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _rounds = n),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: EdgeInsets.only(right: i < 4 ? 8 : 0),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
                        gradient: sel
                            ? const LinearGradient(
                                colors: [
                                  AppColors.primary,
                                  AppColors.secondary
                                ],
                              )
                            : null,
                        color: sel ? null : AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color:
                                sel ? AppColors.primary : AppColors.border),
                        boxShadow: sel
                            ? [
                                BoxShadow(
                                    color:
                                        AppColors.primary.withOpacity(0.3),
                                    blurRadius: 8)
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
            ),
            const SizedBox(height: 32),

            // Fire button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _fire,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  backgroundColor: AppColors.primary,
                  disabledBackgroundColor:
                      AppColors.primary.withOpacity(0.4),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18)),
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
                          Icon(Icons.send_rounded, size: 18),
                          SizedBox(width: 8),
                          Text('FIRE',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 3)),
                        ],
                      ),
              ),
            ),

            // Results
            if (_result != null) ...[
              const SizedBox(height: 30),
              _ResultSection(result: _result!),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Results section ───────────────────────────────────────────────────────────

class _ResultSection extends StatelessWidget {
  final Map<String, dynamic> result;
  const _ResultSection({required this.result});

  @override
  Widget build(BuildContext context) {
    final sent = result['total_sent'] ?? 0;
    final failed = result['total_failed'] ?? 0;
    final results = (result['results'] as List?) ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Results',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
                child: _StatBox(
                    label: 'Sent', value: '$sent', color: AppColors.accent)),
            const SizedBox(width: 12),
            Expanded(
                child: _StatBox(
                    label: 'Failed',
                    value: '$failed',
                    color: AppColors.error)),
          ],
        ),
        const SizedBox(height: 16),
        ...results.map((r) => _ServiceRow(data: r)),
      ],
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label, value;
  final Color color;
  const _StatBox(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 26,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}

class _ServiceRow extends StatelessWidget {
  final Map data;
  const _ServiceRow({required this.data});

  @override
  Widget build(BuildContext context) {
    final ok = data['success'] == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
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
            size: 16,
            color: ok ? AppColors.accent : AppColors.error,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              data['service'] ?? '',
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            data['message'] ?? '',
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 11),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
