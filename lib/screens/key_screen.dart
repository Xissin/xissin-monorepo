import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';

class KeyScreen extends StatefulWidget {
  final String userId;
  const KeyScreen({super.key, required this.userId});

  @override
  State<KeyScreen> createState() => _KeyScreenState();
}

class _KeyScreenState extends State<KeyScreen> {
  final _keyCtrl = TextEditingController();
  bool _redeeming = false;
  bool _checking  = true;
  Map<String, dynamic>? _status;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    super.dispose();
  }

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

    setState(() => _redeeming = true);
    try {
      final data = await ApiService.redeemKey(key: key, userId: widget.userId);
      if (data['success'] == true) {
        _snack('Key redeemed! 🎉 Welcome to Xissin.');
        _keyCtrl.clear();
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
      content: Text(msg),
      backgroundColor: error ? AppColors.error : AppColors.accent,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

  @override
  Widget build(BuildContext context) {
    final isActive = _status?['active'] == true;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Key Manager'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
            onPressed: _loadStatus,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status card
            _checking
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(color: AppColors.primary),
                    ),
                  )
                : _StatusCard(isActive: isActive, status: _status, fmtDate: _fmtDate),

            const SizedBox(height: 32),

            // Redeem section
            const Text(
              'Redeem a Key',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Enter your activation key below.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _keyCtrl,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontFamily: 'monospace',
                letterSpacing: 1.5,
                fontSize: 14,
              ),
              decoration: const InputDecoration(
                hintText: 'XISSIN-XXXX-XXXX-XXXX-XXXX',
                prefixIcon: Icon(Icons.vpn_key_rounded, color: AppColors.secondary),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _redeeming ? null : _redeem,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.secondary,
                  disabledBackgroundColor: AppColors.secondary.withOpacity(0.4),
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
                child: _redeeming
                    ? const SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                      )
                    : const Text(
                        'Redeem Key',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),

            const SizedBox(height: 30),
            _InfoBox(),
          ],
        ),
      ),
    );
  }
}

// ── Status card ───────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final bool isActive;
  final Map<String, dynamic>? status;
  final String Function(String?) fmtDate;

  const _StatusCard({required this.isActive, required this.status, required this.fmtDate});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isActive
              ? [AppColors.accent.withOpacity(0.12), AppColors.primary.withOpacity(0.08)]
              : [AppColors.error.withOpacity(0.1), AppColors.surface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isActive ? AppColors.accent.withOpacity(0.35) : AppColors.error.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: isActive
                      ? AppColors.accent.withOpacity(0.18)
                      : AppColors.error.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isActive ? Icons.verified_rounded : Icons.lock_outline,
                  color: isActive ? AppColors.accent : AppColors.error,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isActive ? 'Key Active' : 'No Active Key',
                    style: TextStyle(
                      color: isActive ? AppColors.accent : AppColors.error,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    isActive ? 'All features unlocked' : 'Redeem a key to unlock features',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
          if (isActive && status != null) ...[
            const SizedBox(height: 16),
            const Divider(color: AppColors.border, height: 1),
            const SizedBox(height: 14),
            _InfoRow(label: 'Key', value: status!['key'] ?? '—', mono: true),
            const SizedBox(height: 8),
            _InfoRow(label: 'Expires', value: fmtDate(status!['expires_at'])),
          ] else if (!isActive) ...[
            const SizedBox(height: 10),
            const Text(
              'Contact the admin or check Xissin channel for keys.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label, value;
  final bool mono;
  const _InfoRow({required this.label, required this.value, this.mono = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
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

class _InfoBox extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('How to get a key?',
              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
          SizedBox(height: 8),
          Text(
            '1. Join the Xissin Telegram channel\n'
            '2. Contact the admin\n'
            '3. Keys are in XISSIN-XXXX-XXXX-XXXX-XXXX format',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.7),
          ),
        ],
      ),
    );
  }
}
