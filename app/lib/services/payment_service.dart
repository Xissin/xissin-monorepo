// lib/services/payment_service.dart
// Handles Remove Ads purchase via PayMongo QRPh (scan-to-pay)

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';

class PaymentService {
  static const String _base =
      'https://xissin-app-backend-production.up.railway.app';

  // ── Check if user is premium ──────────────────────────────────────────────
  static Future<bool> isPremium(String userId) async {
    try {
      final res = await http
          .get(Uri.parse('$_base/api/payments/premium/$userId'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['premium'] == true;
      }
    } catch (_) {}
    return false;
  }

  // ── Create QRPh payment source ────────────────────────────────────────────
  static Future<Map<String, dynamic>?> createPayment(String userId) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_base/api/payments/create'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'user_id': userId}),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  // ── Poll payment status ───────────────────────────────────────────────────
  static Future<bool> checkPaymentStatus({
    required String sourceId,
    required String userId,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_base/api/payments/status'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'source_id': sourceId, 'user_id': userId}),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['paid'] == true;
      }
    } catch (_) {}
    return false;
  }

  // ── Show Remove Ads purchase dialog ──────────────────────────────────────
  static Future<bool> showRemoveAdsDialog({
    required BuildContext context,
    required String userId,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _RemoveAdsDialog(userId: userId),
    );
    return result == true;
  }
}

// ── Remove Ads Bottom Sheet Dialog ───────────────────────────────────────────

class _RemoveAdsDialog extends StatefulWidget {
  final String userId;
  const _RemoveAdsDialog({required this.userId});

  @override
  State<_RemoveAdsDialog> createState() => _RemoveAdsDialogState();
}

class _RemoveAdsDialogState extends State<_RemoveAdsDialog> {
  _Step _step = _Step.intro;

  String? _sourceId;
  String? _qrImageUrl;
  String? _errorMessage;
  bool    _isLoading   = false;
  Timer?  _pollTimer;
  int     _pollSeconds = 0;
  static const int _pollTimeout = 300; // 5 minutes

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  // ── Start payment ─────────────────────────────────────────────────────────
  Future<void> _startPayment() async {
    setState(() {
      _isLoading    = true;
      _errorMessage = null;
    });

    final data = await PaymentService.createPayment(widget.userId);

    if (!mounted) return;

    if (data == null) {
      setState(() {
        _isLoading    = false;
        _errorMessage = 'Could not connect to payment server. Try again.';
      });
      return;
    }

    if (data['already_premium'] == true) {
      Navigator.pop(context, true);
      return;
    }

    setState(() {
      _isLoading   = false;
      _sourceId    = data['source_id'] as String?;
      _qrImageUrl  = data['qr_image_url'] as String?;
      _step        = _Step.qr;
    });

    _startPolling();
  }

  // ── Poll every 5 seconds ──────────────────────────────────────────────────
  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      _pollSeconds += 5;

      if (_pollSeconds >= _pollTimeout) {
        _pollTimer?.cancel();
        if (mounted) {
          setState(() {
            _step         = _Step.intro;
            _errorMessage = 'Payment timed out. Please try again.';
          });
        }
        return;
      }

      final paid = await PaymentService.checkPaymentStatus(
        sourceId: _sourceId!,
        userId:   widget.userId,
      );

      if (paid && mounted) {
        _pollTimer?.cancel();
        setState(() => _step = _Step.success);
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) Navigator.pop(context, true);
      }
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0F0F1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _buildStep(),
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case _Step.intro:
        return _buildIntro();
      case _Step.qr:
        return _buildQrStep();
      case _Step.success:
        return _buildSuccess();
    }
  }

  // ── Step 1: Intro / purchase prompt ──────────────────────────────────────
  Widget _buildIntro() {
    return Column(
      key: const ValueKey('intro'),
      mainAxisSize: MainAxisSize.min,
      children: [
        // Icon
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF6C63FF), Color(0xFFFF6B9D)],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(Icons.block_rounded, color: Colors.white, size: 32),
        ),
        const SizedBox(height: 16),

        const Text(
          'Remove Ads',
          style: TextStyle(
            color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Enjoy Xissin completely ad-free — forever.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white60, fontSize: 13),
        ),
        const SizedBox(height: 20),

        // Benefits
        _BenefitRow(icon: Icons.block,        text: 'No more banner ads'),
        _BenefitRow(icon: Icons.skip_next,    text: 'No more interstitial ads'),
        _BenefitRow(icon: Icons.all_inclusive, text: 'One-time payment — lifetime'),
        _BenefitRow(icon: Icons.qr_code,      text: 'Pay via GCash / QRPh QR code'),

        const SizedBox(height: 20),

        // Price badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF6C63FF).withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.40)),
          ),
          child: const Text(
            '₱99.00  —  One-time',
            style: TextStyle(
              color: Color(0xFF6C63FF), fontSize: 18, fontWeight: FontWeight.bold,
            ),
          ),
        ),

        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.redAccent, fontSize: 12),
          ),
        ],

        const SizedBox(height: 20),

        // Buttons
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6C63FF),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _isLoading ? null : _startPayment,
            icon: _isLoading
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.qr_code_rounded, size: 20),
            label: Text(
              _isLoading ? 'Generating QR...' : 'Pay ₱99 with GCash / QRPh',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
        ),

        const SizedBox(height: 10),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Maybe later',
              style: TextStyle(color: Colors.white38, fontSize: 13)),
        ),
      ],
    );
  }

  // ── Step 2: QR Code ───────────────────────────────────────────────────────
  Widget _buildQrStep() {
    return Column(
      key: const ValueKey('qr'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Scan to Pay',
          style: TextStyle(
              color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        const Text(
          'Open GCash → Scan QR → Pay ₱99',
          style: TextStyle(color: Colors.white60, fontSize: 13),
        ),
        const SizedBox(height: 20),

        // QR code
        Container(
          width: 220, height: 220,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: _qrImageUrl != null && _qrImageUrl!.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl:   _qrImageUrl!,
                    fit:        BoxFit.contain,
                    placeholder: (_, __) => const Center(
                        child: CircularProgressIndicator(
                            color: Color(0xFF6C63FF))),
                    errorWidget: (_, __, ___) => const Icon(
                        Icons.qr_code_2_rounded,
                        size: 120, color: Colors.black87),
                  )
                : const Icon(Icons.qr_code_2_rounded,
                    size: 120, color: Colors.black87),
          ),
        ),

        const SizedBox(height: 16),

        // Polling indicator
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 14, height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Color(0xFF6C63FF)),
            ),
            const SizedBox(width: 8),
            Text(
              'Waiting for payment... (${_pollTimeout - _pollSeconds}s)',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),

        const SizedBox(height: 6),
        const Text(
          'Works with GCash, Maya, BPI, UnionBank & more',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white38, fontSize: 11),
        ),

        const SizedBox(height: 16),
        TextButton(
          onPressed: () {
            _pollTimer?.cancel();
            setState(() {
              _step        = _Step.intro;
              _pollSeconds = 0;
            });
          },
          child: const Text('Cancel',
              style: TextStyle(color: Colors.white38, fontSize: 13)),
        ),
      ],
    );
  }

  // ── Step 3: Success ───────────────────────────────────────────────────────
  Widget _buildSuccess() {
    return Column(
      key: const ValueKey('success'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle_rounded,
            color: Color(0xFF7EE7C1), size: 72),
        const SizedBox(height: 16),
        const Text(
          '🎉 Ads Removed!',
          style: TextStyle(
              color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Payment confirmed.\nEnjoy Xissin ad-free forever!',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white60, fontSize: 13),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

// ── Benefit row widget ────────────────────────────────────────────────────────

class _BenefitRow extends StatelessWidget {
  final IconData icon;
  final String   text;
  const _BenefitRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: const Color(0xFF7EE7C1)),
          const SizedBox(width: 10),
          Text(text,
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ],
      ),
    );
  }
}

enum _Step { intro, qr, success }
