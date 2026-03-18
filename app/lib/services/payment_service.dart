// lib/services/payment_service.dart
// Handles Remove Ads purchase via PayMongo QRPh (scan-to-pay)
// Uses NEW Payment Intent workflow — NOT the deprecated /sources API
// QR image is returned as base64 string, rendered with Image.memory()

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class PaymentService {
  static const String _base =
      'https://xissin-app-backend-production.up.railway.app';

  // ── Fetch Remove Ads product info from backend ────────────────────────────
  static Future<Map<String, dynamic>> getRemoveAdsInfo() async {
    try {
      final res = await http
          .get(Uri.parse('$_base/api/payments/remove-ads-info'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    // Fallback defaults
    return {
      'price':       9900,
      'price_php':   99.0,
      'label':       'Remove Ads — ₱99 Lifetime',
      'subtitle':    'Pay once via GCash · No ads forever',
      'description': 'Enjoy Xissin completely ad-free — forever.',
      'benefits':    [
        'No more banner ads',
        'No more interstitial ads',
        'One-time payment — lifetime',
        'Pay via GCash / QRPh QR code',
      ],
    };
  }

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

  // ── Create QRPh payment (Payment Intent workflow) ─────────────────────────
  // Returns: { payment_intent_id, qr_image_url (base64), amount, amount_php }
  static Future<Map<String, dynamic>?> createPayment(String userId) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_base/api/payments/create'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'user_id': userId}),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  // ── Poll payment status ───────────────────────────────────────────────────
  // Sends payment_intent_id (NOT source_id — that was the old API)
  // Returns: { paid, premium, expired?, intent_status? }
  static Future<Map<String, dynamic>> checkPaymentStatus({
    required String paymentIntentId,
    required String userId,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_base/api/payments/status'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'payment_intent_id': paymentIntentId,
              'user_id':           userId,
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return {'paid': false, 'premium': false};
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

// ── Remove Ads Dialog ─────────────────────────────────────────────────────────

class _RemoveAdsDialog extends StatefulWidget {
  final String userId;
  const _RemoveAdsDialog({required this.userId});

  @override
  State<_RemoveAdsDialog> createState() => _RemoveAdsDialogState();
}

class _RemoveAdsDialogState extends State<_RemoveAdsDialog> {
  _Step _step = _Step.intro;

  // Product info (loaded from backend)
  double       _pricePHP    = 99.0;
  int          _priceCents  = 9900;
  String       _label       = 'Remove Ads';
  String       _description = 'Enjoy Xissin completely ad-free — forever.';
  List<String> _benefits    = [];
  bool         _infoLoaded  = false;

  // ── NEW: payment_intent_id replaces source_id ──────────────────────────────
  String?      _paymentIntentId;
  Uint8List?   _qrImageBytes;   // decoded base64 QR image bytes
  String?      _errorMessage;
  bool         _isLoading   = false;
  Timer?       _pollTimer;
  int          _pollSeconds = 0;

  // QRPh codes expire after 30 minutes per PayMongo docs
  static const int _pollTimeout = 1800;

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadInfo() async {
    final info = await PaymentService.getRemoveAdsInfo();
    if (!mounted) return;
    setState(() {
      _priceCents  = (info['price']     as num?)?.toInt()    ?? 9900;
      _pricePHP    = (info['price_php'] as num?)?.toDouble() ?? 99.0;
      _label       = info['label']       as String? ?? 'Remove Ads';
      _description = info['description'] as String? ?? 'Enjoy Xissin completely ad-free — forever.';
      final raw = info['benefits'];
      _benefits    = raw is List ? raw.map((e) => e.toString()).toList() : [];
      _infoLoaded  = true;
    });
  }

  // ── Start payment ─────────────────────────────────────────────────────────
  Future<void> _startPayment() async {
    setState(() {
      _isLoading    = true;
      _errorMessage = null;
      _qrImageBytes = null;
      _paymentIntentId = null;
      _pollSeconds  = 0;
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

    // Decode the base64 QR image string from backend
    // Format: "data:image/png;base64,iVBORw0K..."
    Uint8List? imageBytes;
    final rawQr = data['qr_image_url'] as String? ?? '';
    if (rawQr.isNotEmpty) {
      try {
        final base64Str = rawQr.contains(',')
            ? rawQr.split(',').last   // strip "data:image/png;base64," prefix
            : rawQr;
        imageBytes = base64Decode(base64Str);
      } catch (e) {
        debugPrint('QR decode error: $e');
      }
    }

    setState(() {
      _isLoading       = false;
      _paymentIntentId = data['payment_intent_id'] as String?;
      _qrImageBytes    = imageBytes;
      _step            = _Step.qr;
    });

    _startPolling();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      _pollSeconds += 5;

      // Hard timeout (matches QRPh 30-min expiry)
      if (_pollSeconds >= _pollTimeout) {
        _pollTimer?.cancel();
        if (mounted) {
          setState(() {
            _step         = _Step.intro;
            _errorMessage = 'QR code expired after 30 minutes. Please try again.';
          });
        }
        return;
      }

      if (_paymentIntentId == null) return;

      final result = await PaymentService.checkPaymentStatus(
        paymentIntentId: _paymentIntentId!,
        userId: widget.userId,
      );

      if (!mounted) return;

      if (result['paid'] == true) {
        _pollTimer?.cancel();
        setState(() => _step = _Step.success);
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) Navigator.pop(context, true);
        return;
      }

      // QR expired on PayMongo side — prompt user to regenerate
      if (result['expired'] == true) {
        _pollTimer?.cancel();
        setState(() {
          _step         = _Step.intro;
          _errorMessage = 'QR code expired. Please tap the button to generate a new one.';
        });
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
      case _Step.intro:   return _buildIntro();
      case _Step.qr:      return _buildQrStep();
      case _Step.success: return _buildSuccess();
    }
  }

  // ── Step 1: Intro ─────────────────────────────────────────────────────────
  Widget _buildIntro() {
    final priceLabel = '₱${_pricePHP % 1 == 0 ? _pricePHP.toInt() : _pricePHP.toStringAsFixed(2)}';

    return Column(
      key: const ValueKey('intro'),
      mainAxisSize: MainAxisSize.min,
      children: [
        // Icon
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF6C63FF), Color(0xFFFF6B9D)]),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(Icons.block_rounded, color: Colors.white, size: 32),
        ),
        const SizedBox(height: 16),

        Text(
          _label,
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          _description,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white60, fontSize: 13),
        ),
        const SizedBox(height: 20),

        // Benefits list — dynamic from backend
        if (!_infoLoaded)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: SizedBox(
              width: 20, height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Color(0xFF6C63FF)),
            ),
          )
        else ...[
          for (final benefit in _benefits)
            _BenefitRow(icon: _iconForBenefit(benefit), text: benefit),
        ],

        const SizedBox(height: 20),

        // Price badge — dynamic
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF6C63FF).withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: const Color(0xFF6C63FF).withOpacity(0.40)),
          ),
          child: Text(
            '$priceLabel  —  One-time',
            style: const TextStyle(
              color: Color(0xFF6C63FF),
              fontSize: 18,
              fontWeight: FontWeight.bold,
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
              _isLoading
                  ? 'Generating QR...'
                  : 'Pay $priceLabel with GCash / QRPh',
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

  // Map benefit text to icon
  IconData _iconForBenefit(String text) {
    final t = text.toLowerCase();
    if (t.contains('banner'))                        return Icons.block;
    if (t.contains('interstitial'))                  return Icons.skip_next;
    if (t.contains('lifetime') || t.contains('one-time')) return Icons.all_inclusive;
    if (t.contains('gcash') || t.contains('qr'))    return Icons.qr_code;
    if (t.contains('codm') || t.contains('check'))  return Icons.gamepad_rounded;
    if (t.contains('mlbb') || t.contains('mobile')) return Icons.sports_esports_rounded;
    return Icons.check_circle_outline_rounded;
  }

  // ── Step 2: QR Code ───────────────────────────────────────────────────────
  Widget _buildQrStep() {
    final priceLabel = '₱${_pricePHP % 1 == 0 ? _pricePHP.toInt() : _pricePHP.toStringAsFixed(2)}';
    final remaining  = _pollTimeout - _pollSeconds;
    final mins       = remaining ~/ 60;
    final secs       = remaining % 60;
    final timeStr    = '$mins:${secs.toString().padLeft(2, '0')}';

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
        Text(
          'Open GCash → Scan QR → Pay $priceLabel',
          style: const TextStyle(color: Colors.white60, fontSize: 13),
        ),
        const SizedBox(height: 20),

        // ── QR Image (base64 decoded) ─────────────────────────────────────
        Container(
          width: 220, height: 220,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: _qrImageBytes != null
                ? Image.memory(
                    _qrImageBytes!,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                        Icons.qr_code_2_rounded,
                        size: 120, color: Colors.black87),
                  )
                : const Center(
                    child: CircularProgressIndicator(
                        color: Color(0xFF6C63FF))),
          ),
        ),

        const SizedBox(height: 16),

        // Countdown timer
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
              'Waiting for payment... ($timeStr)',
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
              _errorMessage = null;
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
        const Text('🎉 Ads Removed!',
            style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold)),
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

// ── Benefit row ───────────────────────────────────────────────────────────────
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
          Expanded(
            child: Text(text,
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

enum _Step { intro, qr, success }
