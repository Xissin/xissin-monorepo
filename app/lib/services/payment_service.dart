// lib/services/payment_service.dart
//
// Premium Key System — replaces PayMongo completely.
//
// Flow:
//   1. User taps "Get Premium"
//   2. Dialog shows benefits + how to get a key
//   3. User contacts @QuitNat on Telegram, pays via GCash
//   4. Developer sends a key (e.g. XISSIN-A3B2-C9D1)
//   5. User enters key in dialog → premium granted instantly

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'api_service.dart';

class PaymentService {
  static const String _base =
      'https://xissin-app-backend-production.up.railway.app';

  // ── Check if user is premium ────────────────────────────────────────────────
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

  // ── Show the "Get Premium" dialog ───────────────────────────────────────────
  // Returns true if the key was successfully redeemed.
  // Kept as showRemoveAdsDialog for backward compat with home_screen.dart.
  static Future<bool> showRemoveAdsDialog({
    required BuildContext context,
    required String userId,
  }) async {
    final result = await showDialog<bool>(
      context:          context,
      barrierDismissible: true,
      builder: (ctx) => _PremiumKeyDialog(userId: userId),
    );
    return result == true;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Premium Key Dialog
// ─────────────────────────────────────────────────────────────────────────────

class _PremiumKeyDialog extends StatefulWidget {
  final String userId;
  const _PremiumKeyDialog({required this.userId});

  @override
  State<_PremiumKeyDialog> createState() => _PremiumKeyDialogState();
}

class _PremiumKeyDialogState extends State<_PremiumKeyDialog> {
  final _keyCtrl  = TextEditingController();
  String?  _error;
  bool     _loading = false;
  bool     _success = false;

  static const _telegramUrl = 'https://t.me/QuitNat';

  static const _benefits = [
    {'icon': '🚫', 'text': 'No ads — banner & interstitial gone forever'},
    {'icon': '💬', 'text': 'SMS Bomber — 50 batches, zero cooldown'},
    {'icon': '📩', 'text': 'NGL Bomber — up to 100 attacks, zero cooldown'},
    {'icon': '📁', 'text': 'URL & Dup Remover — unlimited file lines'},
    {'icon': '🔍', 'text': 'IP & Username Tracker — no reward ads needed'},
    {'icon': '📊', 'text': 'Live progress bars on all tools'},
    {'icon': '🚀', 'text': 'All future premium features included'},
  ];

  // Key validation regex (matches XISSIN-XXXX-XXXX)
  static final _keyRe = RegExp(r'^XISSIN-[A-Z0-9]{4}-[A-Z0-9]{4}$');

  @override
  void dispose() {
    _keyCtrl.dispose();
    super.dispose();
  }

  // ── Redeem key ──────────────────────────────────────────────────────────────
  Future<void> _redeemKey() async {
    final key = _keyCtrl.text.trim().toUpperCase();

    if (!_keyRe.hasMatch(key)) {
      setState(() =>
          _error = 'Invalid format. Expected: XISSIN-XXXX-XXXX');
      return;
    }

    setState(() { _loading = true; _error = null; });

    try {
      final result = await ApiService.redeemKey(
        userId: widget.userId,
        key:    key,
      );

      if (!mounted) return;

      if (result['success'] == true) {
        setState(() { _loading = false; _success = true; });
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) Navigator.pop(context, true);
      } else {
        setState(() {
          _loading = false;
          _error   = result['message'] as String? ?? 'Failed to redeem key.';
        });
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.userMessage; });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error   = 'Could not connect. Check your internet and try again.';
      });
    }
  }

  Future<void> _openTelegram() async {
    HapticFeedback.selectionClick();
    final uri = Uri.parse(_telegramUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF12122A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _success ? _buildSuccess() : _buildMain(),
          ),
        ),
      ),
    );
  }

  // ── Main view ───────────────────────────────────────────────────────────────
  Widget _buildMain() {
    return Column(
      key: const ValueKey('main'),
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Header ───────────────────────────────────────────────────────────
        const Text('⭐', style: TextStyle(fontSize: 38)),
        const SizedBox(height: 8),
        const Text(
          'Get Premium',
          style: TextStyle(
            color:      Colors.white,
            fontSize:   22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Unlock all features — one-time, lifetime',
          style: TextStyle(color: Colors.white54, fontSize: 13),
        ),

        const SizedBox(height: 20),

        // ── Benefits ─────────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color:        Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(14),
            border:       Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Column(
            children: _benefits.map((b) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3.5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(b['icon']!, style: const TextStyle(fontSize: 15)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      b['text']!,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            )).toList(),
          ),
        ),

        const SizedBox(height: 18),

        // ── How to get a key ─────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color:        const Color(0xFF229ED9).withOpacity(0.07),
            borderRadius: BorderRadius.circular(14),
            border:       Border.all(
                color: const Color(0xFF229ED9).withOpacity(0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'How to get a key:',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              _StepRow(n: '1', text: 'Tap "Chat on Telegram" below'),
              _StepRow(n: '2', text: 'Message @QuitNat to purchase'),
              _StepRow(n: '3', text: 'Pay via GCash → receive your key'),
              _StepRow(n: '4', text: 'Enter the key below and tap Redeem'),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // ── Telegram button ───────────────────────────────────────────────────
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF229ED9),
              side: const BorderSide(color: Color(0xFF229ED9), width: 1.5),
              padding:
                  const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _openTelegram,
            icon:  const Icon(Icons.telegram, size: 20),
            label: const Text(
              'Chat @QuitNat on Telegram  ↗',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
        ),

        const SizedBox(height: 22),

        // ── Divider ───────────────────────────────────────────────────────────
        Row(children: [
          Expanded(
              child: Divider(color: Colors.white.withOpacity(0.10))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'Already have a key?',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ),
          Expanded(
              child: Divider(color: Colors.white.withOpacity(0.10))),
        ]),

        const SizedBox(height: 16),

        // ── Key input ─────────────────────────────────────────────────────────
        TextField(
          controller:           _keyCtrl,
          maxLength:            16,           // XISSIN-XXXX-XXXX = 16 chars
          textCapitalization:   TextCapitalization.characters,
          style: const TextStyle(
            color:        Colors.white,
            fontFamily:   'monospace',
            fontSize:     15,
            letterSpacing: 1.5,
          ),
          decoration: InputDecoration(
            hintText: 'XISSIN-XXXX-XXXX',
            hintStyle: const TextStyle(
              color:        Colors.white24,
              fontFamily:   'monospace',
              fontSize:     14,
              letterSpacing: 1.5,
            ),
            filled:    true,
            fillColor: Colors.white.withOpacity(0.05),
            counterStyle:
                const TextStyle(color: Colors.white38, fontSize: 11),
            prefixIcon: const Icon(Icons.key_rounded,
                color: Color(0xFFFFD700), size: 20),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: Colors.white.withOpacity(0.15)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: Colors.white.withOpacity(0.15)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                  color: Color(0xFFFFD700), width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.redAccent),
            ),
          ),
          onChanged: (_) => setState(() => _error = null),
        ),

        // ── Error ─────────────────────────────────────────────────────────────
        if (_error != null) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _error!,
              style: const TextStyle(
                  color: Colors.redAccent, fontSize: 12),
            ),
          ),
        ],

        const SizedBox(height: 14),

        // ── Redeem button ─────────────────────────────────────────────────────
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor:         const Color(0xFFFFD700),
              foregroundColor:         Colors.black87,
              disabledBackgroundColor: Colors.white10,
              disabledForegroundColor: Colors.white30,
              padding:
                  const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              textStyle: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 15),
            ),
            onPressed: (_loading ||
                    _keyCtrl.text.trim().length < 16)
                ? null
                : _redeemKey,
            icon: _loading
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.black54))
                : const Icon(
                    Icons.workspace_premium_rounded,
                    size: 20),
            label: Text(
                _loading ? 'Redeeming...' : 'Redeem Key'),
          ),
        ),

        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Maybe later',
              style: TextStyle(color: Colors.white38, fontSize: 13)),
        ),
      ],
    );
  }

  // ── Success view ─────────────────────────────────────────────────────────────
  Widget _buildSuccess() {
    return Column(
      key: const ValueKey('success'),
      mainAxisSize: MainAxisSize.min,
      children: const [
        SizedBox(height: 16),
        Text('🎉', style: TextStyle(fontSize: 60)),
        SizedBox(height: 16),
        Text(
          'Premium Activated!',
          style: TextStyle(
            color:      Color(0xFFFFD700),
            fontSize:   24,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Welcome to the premium experience!\nEnjoy all features of Xissin.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.5),
        ),
        SizedBox(height: 28),
      ],
    );
  }
}

// ── Step row widget ───────────────────────────────────────────────────────────
class _StepRow extends StatelessWidget {
  final String n;
  final String text;
  const _StepRow({required this.n, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 20, height: 20,
            alignment:  Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xFF229ED9),
              shape: BoxShape.circle,
            ),
            child: Text(n,
                style: const TextStyle(
                  color:      Colors.white,
                  fontSize:   11,
                  fontWeight: FontWeight.bold,
                )),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 12.5)),
          ),
        ],
      ),
    );
  }
}
