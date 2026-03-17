import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../services/theme_service.dart';
import '../services/location_service.dart';
import '../services/ad_service.dart';
import '../widgets/glass_neumorphic_card.dart';
import '../widgets/shimmer_skeleton.dart';
import '../widgets/staggered_grid.dart';
import '../widgets/haptic_button.dart';
import 'sms_bomber_screen.dart';
import 'about_screen.dart';
import 'ngl_screen.dart';

class HomeScreen extends StatefulWidget {
  final String userId;
  const HomeScreen({super.key, required this.userId});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> _announcements = [];

  @override
  void initState() {
    super.initState();
    _loadAnnouncements();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      LocationService.tryCollectAndSend(widget.userId);
    });
  }

  // ── Data fetching ──────────────────────────────────────────────────────────

  Future<void> _loadAnnouncements() async {
    try {
      final list = await ApiService.getAnnouncements();
      if (!mounted) return;
      setState(() => _announcements = list);
    } catch (_) {}
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  void _goToSms() {
    HapticFeedback.mediumImpact();
    AdService.instance.showInterstitial();
    _pushSlide(SmsBomberScreen(userId: widget.userId));
  }

  void _goToNgl() {
    HapticFeedback.mediumImpact();
    AdService.instance.showInterstitial();
    _pushSlide(NglScreen(userId: widget.userId));
  }

  void _goToAbout() {
    HapticFeedback.selectionClick();
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => const AboutScreen()));
  }

  void _showComingSoon(String name) {
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior:         SnackBarBehavior.floating,
        backgroundColor:  AppColors.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: const Duration(seconds: 2),
        content: Row(children: [
          const Icon(Icons.construction_rounded,
              color: AppColors.gold, size: 18),
          const SizedBox(width: 10),
          Text(
            '$name — Coming Soon!',
            style: const TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w600),
          ),
        ]),
      ),
    );
  }

  // ── Slide page transition helper ───────────────────────────────────────────

  Future<T?> _pushSlide<T>(Widget page) {
    return Navigator.push<T>(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder:        (_, __, ___) => page,
        transitionsBuilder: (_, anim, __, child) => SlideTransition(
          position: Tween<Offset>(
                  begin: const Offset(1.0, 0.0), end: Offset.zero)
              .animate(CurvedAnimation(
                  parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    );
  }

  // ── Banner Ad widget ───────────────────────────────────────────────────────

  Widget _buildBannerAd() {
    return Consumer<AdService>(
      builder: (_, adService, __) {
        if (!adService.bannerReady || adService.bannerAd == null) {
          return const SizedBox.shrink();
        }
        return SafeArea(
          top: false,
          child: Container(
            alignment: Alignment.center,
            width:  adService.bannerAd!.size.width.toDouble(),
            height: adService.bannerAd!.size.height.toDouble(),
            child:  AdWidget(ad: adService.bannerAd!),
          ),
        );
      },
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    final dismissed  = <String>{};
    final visible    = _announcements
        .where((a) => !dismissed.contains(a['id']?.toString()))
        .toList();

    return Scaffold(
      backgroundColor:     c.background,
      bottomNavigationBar: _buildBannerAd(),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh:       _loadAnnouncements,
          color:           c.primary,
          backgroundColor: c.surface,
          displacement:    60,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // ── Header ─────────────────────────────────────────────────────
              SliverToBoxAdapter(child: _buildHeader(c)),

              // ── Announcements ──────────────────────────────────────────────
              if (visible.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Column(
                      children: List.generate(
                        visible.length,
                        (i) => _AnnouncementBanner(
                          announcement: visible[i],
                          onDismiss: () => setState(
                              () => dismissed.add(visible[i]['id']?.toString() ?? '')),
                          c:     c,
                          index: i,
                        ),
                      ),
                    ),
                  ),
                ),

              // ── Section heading ────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 28, 22, 14),
                  child: Row(
                    children: [
                      Text(
                        'Tools',
                        style: TextStyle(
                          color:      c.textPrimary,
                          fontSize:   18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: c.primary.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(AppRadius.full),
                        ),
                        child: Text(
                          '4',
                          style: TextStyle(
                            color:      c.primary,
                            fontSize:   11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Tools grid ─────────────────────────────────────────────────
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                sliver: SliverGrid(
                  delegate: SliverChildListDelegate([
                    _FeatureCard(
                      icon:      Icons.sms_rounded,
                      title:     'SMS Bomber',
                      subtitle:  '14 PH Services',
                      gradient:  AppColors.smsGradient,
                      glowColor: AppColors.primary,
                      onTap:     _goToSms,
                      index:     0,
                    ),
                    _FeatureCard(
                      icon:      Icons.chat_bubble_outline_rounded,
                      title:     'NGL Bomber',
                      subtitle:  'Anonymous Messages',
                      gradient:  AppColors.nglGradient,
                      glowColor: const Color(0xFFFF6EC7),
                      onTap:     _goToNgl,
                      index:     1,
                    ),
                    _FeatureCard(
                      icon:      Icons.info_outline_rounded,
                      title:     'About',
                      subtitle:  'App Info & Links',
                      gradient:  AppColors.aboutGradient,
                      glowColor: AppColors.secondary,
                      onTap:     _goToAbout,
                      index:     2,
                    ),
                    _FeatureCard(
                      icon:      Icons.location_on_rounded,
                      title:     'IP Tracker',
                      subtitle:  'Locate & Info',
                      gradient:  AppColors.comingSoon,
                      glowColor: AppColors.neonOrange,
                      onTap:     () => _showComingSoon('IP Tracker'),
                      index:     3,
                      comingSoon: true,
                    ),
                    _FeatureCard(
                      icon:      Icons.phonelink_ring_rounded,
                      title:     'Phone Info',
                      subtitle:  'Number Lookup',
                      gradient:  AppColors.comingSoon,
                      glowColor: AppColors.neonPink,
                      onTap:     () => _showComingSoon('Phone Info'),
                      index:     4,
                      comingSoon: true,
                    ),
                  ]),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount:   2,
                    mainAxisSpacing:  14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 0.88,
                  ),
                ),
              ),

              // ── Footer ─────────────────────────────────────────────────────
              SliverToBoxAdapter(child: _buildFooter(c)),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header widget ──────────────────────────────────────────────────────────

  Widget _buildHeader(XissinColors c) {
    final themeService = context.watch<ThemeService>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShaderMask(
                shaderCallback: (b) => LinearGradient(
                  colors: [c.primary, c.secondary],
                ).createShader(b),
                child: const Text(
                  'XISSIN',
                  style: TextStyle(
                    color:         Colors.white,
                    fontSize:      28,
                    fontWeight:    FontWeight.w900,
                    letterSpacing: 4,
                  ),
                ),
              ),
              Text(
                'Multi-Tool Suite',
                style: TextStyle(color: c.textSecondary, fontSize: 12),
              ),
            ],
          )
              .animate()
              .fadeIn(duration: 500.ms)
              .slideX(begin: -0.2, end: 0, duration: 500.ms),
          Row(
            children: [
              _TelegramButton(c: c)
                  .animate(delay: 100.ms)
                  .fadeIn(duration: 500.ms)
                  .scale(begin: const Offset(0.8, 0.8), duration: 400.ms),
              const SizedBox(width: 8),
              HapticIconButton(
                icon: themeService.isDark
                    ? Icons.light_mode_rounded
                    : Icons.dark_mode_rounded,
                onPressed: () {
                  HapticFeedback.selectionClick();
                  themeService.toggle();
                },
                color:           c.textSecondary,
                backgroundColor: c.surface,
              )
                  .animate(delay: 150.ms)
                  .fadeIn(duration: 500.ms)
                  .scale(begin: const Offset(0.8, 0.8), duration: 400.ms),
            ],
          ),
        ],
      ),
    );
  }

  // ── Footer ─────────────────────────────────────────────────────────────────

  Widget _buildFooter(XissinColors c) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bolt_rounded, size: 14, color: c.primary),
          const SizedBox(width: 4),
          Text(
            'Xissin — by Xissin',
            style: TextStyle(color: c.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ── Telegram quick-link button ───────────────────────────────────────────────

class _TelegramButton extends StatelessWidget {
  final XissinColors c;
  const _TelegramButton({required this.c});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        HapticFeedback.selectionClick();
        final uri = Uri.parse('https://t.me/Xissin_0');
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFF229ED9).withOpacity(0.15),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: const Color(0xFF229ED9).withOpacity(0.30),
            width: 1,
          ),
        ),
        child: const Icon(Icons.telegram, size: 20, color: Color(0xFF229ED9)),
      ),
    );
  }
}

// ── Announcement banner ──────────────────────────────────────────────────────

class _AnnouncementBanner extends StatelessWidget {
  final Map<String, dynamic> announcement;
  final VoidCallback          onDismiss;
  final XissinColors          c;
  final int                   index;

  const _AnnouncementBanner({
    required this.announcement,
    required this.onDismiss,
    required this.c,
    required this.index,
  });

  Color _typeColor(String? type) {
    switch (type) {
      case 'warning': return const Color(0xFFFFA726);
      case 'error':   return const Color(0xFFFF6B6B);
      case 'success': return const Color(0xFF7EE7C1);
      default:        return const Color(0xFF5B8CFF);
    }
  }

  IconData _typeIcon(String? type) {
    switch (type) {
      case 'warning': return Icons.warning_amber_rounded;
      case 'error':   return Icons.error_outline_rounded;
      case 'success': return Icons.check_circle_outline_rounded;
      default:        return Icons.campaign_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final type  = announcement['type']    as String? ?? 'info';
    final title = announcement['title']   as String? ?? 'Announcement';
    final msg   = announcement['message'] as String? ?? '';
    final color = _typeColor(type);
    final icon  = _typeIcon(type);

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          decoration: BoxDecoration(
            color:        c.surfaceAlt,
            border:       Border.all(color: c.border, width: 1),
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 4, color: color),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(icon, size: 16, color: color),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title,
                                  style: TextStyle(
                                      color: color, fontSize: 12,
                                      fontWeight: FontWeight.bold)),
                              if (msg.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(msg,
                                    style: TextStyle(
                                        color: c.textSecondary,
                                        fontSize: 12, height: 1.4)),
                              ],
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            onDismiss();
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(Icons.close_rounded,
                                size: 14, color: c.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    )
        .animate(delay: Duration(milliseconds: 50 + 100 * index))
        .fadeIn(duration: 400.ms)
        .slideY(begin: -0.2, end: 0, duration: 400.ms);
  }
}

// ── Feature card ──────────────────────────────────────────────────────────────

class _FeatureCard extends StatelessWidget {
  final IconData     icon;
  final String       title;
  final String       subtitle;
  final List<Color>  gradient;
  final Color        glowColor;
  final VoidCallback onTap;
  final int          index;
  final bool         comingSoon;

  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradient,
    required this.glowColor,
    required this.onTap,
    required this.index,
    this.comingSoon = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return GlassNeumorphicCard(
      glowColor: comingSoon ? Colors.transparent : glowColor,
      onTap:     onTap,
      padding:   const EdgeInsets.all(18),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GlassIconContainer(
                icon:      icon,
                gradient:  comingSoon ? [c.border, c.surfaceAlt] : gradient,
                glowColor: comingSoon ? Colors.transparent : glowColor,
              ),
              const Spacer(),
              Text(
                title,
                style: TextStyle(
                  color:      comingSoon ? c.textSecondary : c.textPrimary,
                  fontSize:   15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 3),
              Text(subtitle,
                  style: TextStyle(color: c.textSecondary, fontSize: 12)),
            ],
          ),
          if (comingSoon)
            Positioned(
              top: 0, right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: glowColor.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(
                      color: glowColor.withOpacity(0.40), width: 1),
                ),
                child: Text(
                  'SOON',
                  style: TextStyle(
                    color:         glowColor,
                    fontSize:      9,
                    fontWeight:    FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
        ],
      ),
    )
        .animate(delay: Duration(milliseconds: 80 + 100 * index))
        .fadeIn(duration: 400.ms)
        .slideY(
            begin:    0.2,
            end:      0,
            duration: 400.ms,
            curve:    Curves.easeOutCubic);
  }
}
