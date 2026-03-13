import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_neumorphic_card.dart';
import '../widgets/haptic_button.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  static const _appVersion = '1.0.0';
  bool _isLoadingTelegram = false;
  String? _loadingLink;

  Future<void> _openUrl(BuildContext context, String url, String label) async {
    setState(() {
      _isLoadingTelegram = true;
      _loadingLink = label;
    });
    
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
    } finally {
      setState(() {
        _isLoadingTelegram = false;
        _loadingLink = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;

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

            // Logo
            Hero(
              tag: 'app_logo',
              child: Container(
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
            )
                .animate()
                .fadeIn(duration: 500.ms)
                .scale(begin: const Offset(0.8, 0.8), duration: 500.ms),
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
            )
                .animate(delay: 100.ms)
                .fadeIn(duration: 400.ms)
                .slideY(begin: 0.2, end: 0, duration: 400.ms),
            const SizedBox(height: 6),
            Text(
              'Multi-Tool App  •  v$_appVersion',
              style: TextStyle(color: c.textSecondary, fontSize: 13),
            )
                .animate(delay: 200.ms)
                .fadeIn(duration: 400.ms),

            const SizedBox(height: 32),

            // Features
            _SectionTitle(text: 'Features', c: c)
                .animate(delay: 250.ms)
                .fadeIn(duration: 400.ms),
            const SizedBox(height: 12),
            GlassNeumorphicCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _FeatureRow(icon: Icons.sms_rounded,           label: 'SMS Bomber (14 PH Services)', c: c),
                  _FeatureRow(icon: Icons.vpn_key_rounded,       label: 'Key Manager & Activation', c: c),
                  _FeatureRow(icon: Icons.notifications_rounded, label: 'Key Expiry Notifications', c: c),
                  _FeatureRow(icon: Icons.dark_mode_rounded,     label: 'Dark / Light Theme', c: c),
                  _FeatureRow(icon: Icons.campaign_rounded,      label: 'Admin Announcements', c: c),
                ],
              ),
            )
                .animate(delay: 300.ms)
                .fadeIn(duration: 400.ms)
                .slideY(begin: 0.1, end: 0, duration: 400.ms),

            const SizedBox(height: 28),

            // Telegram
            _SectionTitle(text: 'Telegram', c: c)
                .animate(delay: 350.ms)
                .fadeIn(duration: 400.ms),
            const SizedBox(height: 12),
            _LinkCard(
              icon: Icons.campaign_rounded,
              label: 'Official Channel',
              sublabel: '@Xissin_0',
              gradient: [const Color(0xFF229ED9), const Color(0xFF0088CC)],
              onTap: () => _openUrl(context, 'https://t.me/Xissin_0', 'channel'),
              isLoading: _isLoadingTelegram && _loadingLink == 'channel',
            )
                .animate(delay: 400.ms)
                .fadeIn(duration: 400.ms)
                .slideX(begin: 0.1, end: 0, duration: 400.ms),
            const SizedBox(height: 10),
            _LinkCard(
              icon: Icons.forum_rounded,
              label: 'Discussion Group',
              sublabel: '@Xissin_1',
              gradient: [const Color(0xFF229ED9), const Color(0xFF0088CC)],
              onTap: () => _openUrl(context, 'https://t.me/Xissin_1', 'group'),
              isLoading: _isLoadingTelegram && _loadingLink == 'group',
            )
                .animate(delay: 450.ms)
                .fadeIn(duration: 400.ms)
                .slideX(begin: 0.1, end: 0, duration: 400.ms),
            const SizedBox(height: 10),
            _LinkCard(
              icon: Icons.person_rounded,
              label: 'Contact Admin',
              sublabel: '@QuitNat',
              gradient: [c.secondary, const Color(0xFF7B6FFF)],
              onTap: () => _openUrl(context, 'https://t.me/QuitNat', 'admin'),
              isLoading: _isLoadingTelegram && _loadingLink == 'admin',
            )
                .animate(delay: 500.ms)
                .fadeIn(duration: 400.ms)
                .slideX(begin: 0.1, end: 0, duration: 400.ms),

            const SizedBox(height: 32),
            Text(
              '© 2025 Xissin • All rights reserved\nUnauthorized distribution is prohibited.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.textSecondary.withOpacity(0.5),
                fontSize: 11,
                height: 1.7,
              ),
            )
                .animate(delay: 550.ms)
                .fadeIn(duration: 400.ms),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

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

class _LinkCard extends StatefulWidget {
  final IconData icon;
  final String label, sublabel;
  final List<Color> gradient;
  final VoidCallback onTap;
  final bool isLoading;

  const _LinkCard({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.gradient,
    required this.onTap,
    this.isLoading = false,
  });

  @override
  State<_LinkCard> createState() => _LinkCardState();
}

class _LinkCardState extends State<_LinkCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      lowerBound: 0.97,
      upperBound: 1.0,
      value: 1.0,
    );
    _scaleAnimation = _controller;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    
    return GestureDetector(
      onTapDown: (_) => _controller.reverse(),
      onTapUp: (_) {
        _controller.forward();
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      onTapCancel: () => _controller.forward(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: GlassNeumorphicCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          glowColor: widget.gradient.first,
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: widget.gradient),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: widget.gradient.first.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: widget.isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Icon(widget.icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.label,
                        style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                    Text(widget.sublabel,
                        style: TextStyle(color: c.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
              Icon(Icons.open_in_new_rounded, color: c.textSecondary, size: 16),
            ],
          ),
        ),
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
