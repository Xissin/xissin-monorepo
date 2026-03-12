import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const _appVersion = '1.0.0';

  Future<void> _openUrl(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not open: $url'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(12),
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error opening link: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(12),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: const Text('About'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 16),

            // ── Logo ──────────────────────────────────────────────────────
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [c.primary, c.secondary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: c.primary.withOpacity(0.4),
                    blurRadius: 30,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: const Icon(Icons.bolt_rounded, size: 52, color: Colors.white),
            ),
            const SizedBox(height: 18),
            ShaderMask(
              shaderCallback: (b) => LinearGradient(
                colors: [c.primary, c.secondary],
              ).createShader(b),
              child: const Text(
                'XISSIN',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 8,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Multi-Tool App  •  v$_appVersion',
              style: TextStyle(color: c.textSecondary, fontSize: 13),
            ),

            const SizedBox(height: 32),

            // ── Features ──────────────────────────────────────────────────
            _SectionTitle(text: 'Features', c: c),
            const SizedBox(height: 12),
            _InfoCard(c: c, children: [
              _FeatureRow(icon: Icons.sms_rounded,           label: 'SMS Bomber (14 PH Services)', c: c),
              _FeatureRow(icon: Icons.vpn_key_rounded,       label: 'Key Manager & Activation', c: c),
              _FeatureRow(icon: Icons.notifications_rounded, label: 'Key Expiry Notifications', c: c),
              _FeatureRow(icon: Icons.dark_mode_rounded,     label: 'Dark / Light Theme', c: c),
              _FeatureRow(icon: Icons.campaign_rounded,      label: 'Admin Announcements', c: c),
            ]),

            const SizedBox(height: 28),

            // ── Telegram ──────────────────────────────────────────────────
            _SectionTitle(text: 'Telegram', c: c),
            const SizedBox(height: 12),
            _LinkCard(
              icon: Icons.campaign_rounded,
              label: 'Official Channel',
              sublabel: '@Xissin_0',
              gradient: [const Color(0xFF229ED9), const Color(0xFF0088CC)],
              onTap: () => _openUrl(context, 'https://t.me/Xissin_0'),
            ),
            const SizedBox(height: 10),
            _LinkCard(
              icon: Icons.forum_rounded,
              label: 'Discussion Group',
              sublabel: '@Xissin_1',
              gradient: [const Color(0xFF229ED9), const Color(0xFF0088CC)],
              onTap: () => _openUrl(context, 'https://t.me/Xissin_1'),
            ),
            const SizedBox(height: 10),
            _LinkCard(
              icon: Icons.person_rounded,
              label: 'Contact Admin',
              sublabel: '@QuitNat',
              gradient: [c.secondary, const Color(0xFF7B6FFF)],
              onTap: () => _openUrl(context, 'https://t.me/QuitNat'),
            ),

            const SizedBox(height: 32),
            Text(
              '© 2025 Xissin • All rights reserved\nUnauthorized distribution is prohibited.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.textSecondary.withOpacity(0.5),
                fontSize: 11,
                height: 1.7,
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ── Shared widgets ─────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String text;
  final XissinColors c;
  const _SectionTitle({required this.text, required this.c});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: TextStyle(
          color: c.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _LinkCard extends StatelessWidget {
  final IconData icon;
  final String label, sublabel;
  final List<Color> gradient;
  final VoidCallback onTap;

  const _LinkCard({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.border),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: gradient),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  Text(sublabel,
                      style: TextStyle(color: c.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.open_in_new_rounded, color: c.textSecondary, size: 16),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final XissinColors c;
  final List<Widget> children;
  const _InfoCard({required this.c, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final XissinColors c;
  const _FeatureRow({required this.icon, required this.label, required this.c});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, color: c.primary, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: TextStyle(color: c.textPrimary, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
