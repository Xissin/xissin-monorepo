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
import 'key_screen.dart';
import 'about_screen.dart';
import 'ngl_screen.dart';

class HomeScreen extends StatefulWidget {
  final String userId;
  const HomeScreen({super.key, required this.userId});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _hasKey        = false;
  bool _loading       = true;
  List<Map<String, dynamic>> _announcements = [];
  final Set<String> _dismissedIds           = {};

  @override
  void initState() {
    super.initState();
    _refreshAll();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      LocationService.tryCollectAndSend(widget.userId);
    });
  }

  // ── Data fetching ──────────────────────────────────────────────────────────

  Future<void> _refreshAll() async {
    await Future.wait([
      _refreshKeyStatus(),
      _loadAnnouncements(),
    ]);
  }

  Future<void> _refreshKeyStatus() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final data = await ApiService.keyStatus(widget.userId);
      if (!mounted) return;
      setState(() {
        _hasKey  = data['active'] == true;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _loadAnnouncements() async {
    try {
      final list = await ApiService.getAnnouncements();
      if (!mounted) return;
      setState(() => _announcements = list);
    } catch (_) {}
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  void _goToSms() {
    if (!_hasKey) { _showNoKeyDialog(); return; }
    HapticFeedback.mediumImpact();
    // Show interstitial ad before opening the tool
    AdService.instance.showInterstitial();
    _pushSlide(SmsBomberScreen(userId: widget.userId));
  }

  void _goToNgl() {
    if (!_hasKey) { _showNoKeyDialog(); return; }
    HapticFeedback.mediumImpact();
    // Show interstitial ad before opening the tool
    AdService.instance.showInterstitial();
    _pushSlide(NglScreen(userId: widget.userId));
  }

  Future<void> _goToKeys() async {
    HapticFeedback.selectionClick();
    await _pushSlide(KeyScreen(userId: widget.userId));
    _refreshKeyStatus();
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

  // ── Dialogs ────────────────────────────────────────────────────────────────

  void _showNoKeyDialog() {
    final c = context.c;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: c.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text(
          '🔑  Key Required',
          style: TextStyle(
              color: c.textPrimary, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'You need an active key to use this feature.\n'
          'Go to Key Manager to redeem one.',
          style: TextStyle(color: c.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                Text('Cancel', style: TextStyle(color: c.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _goToKeys();
            },
            child: const Text('Get Key'),
          ),
        ],
      ),
    );
  }

  // ── Banner Ad widget ───────────────────────────────────────────────────────

  Widget _buildBannerAd() {
    return Consumer<AdService>(
      builder: (_, adService, __) {
        if (!adService.bannerReady || adService.bannerAd == null) {
          // Return an invisible zero-height widget when not ready
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

    final visible = _announcements
        .where((a) => !_dismissedIds.contains(a['id']?.toString()))
        .toList();

    return Scaffold(
      backgroundColor:    c.background,
      // ── Sticky banner ad at the very bottom ────────────────────────────────
      bottomNavigationBar: _buildBannerAd(),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh:       _refreshAll,
          color:           c.primary,
          backgroundColor: c.surface,
          displacement:    60,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // ── Header ─────────────────────────────────────────────────────
              SliverToBoxAdapter(child: _buildHeader(c)),

              // ── Key status pill ────────────────────────────────────────────
              SliverToBoxAdapter(child: _buildKeyStatusRow(c)),

              // ── Announcements ──────────────────────────────────────────────
              if (visible.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Column(
                      children: List.generate(
                        visible.length,
                        (i) => _AnnouncementBanner(
                          announcement: visible[i],
                          onDismiss: () => setState(() => _dismissedIds
                              .add(visible[i]['id']?.toString() ?? '')),
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
                          '6',
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

              // ── Tools grid (2 × 3) ─────────────────────────────────────────
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
                      locked:    !_hasKey,
                      loading:   _loading,
                      onTap:     _goToSms,
                      index:     0,
                    ),
                    _FeatureCard(
                      icon:      Icons.chat_bubble_outline_rounded,
                      title:     'NGL Bomber',
                      subtitle:  'Anonymous Messages',
                      gradient:  AppColors.nglGradient,
                      glowColor: const Color(0xFFFF6EC7),
                      locked:    !_hasKey,
                      loading:   _loading,
                      onTap:     _goToNgl,
                      index:     1,
                    ),
                    _FeatureCard(
                      icon:      Icons.vpn_key_rounded,
                      title:     'Key Manager',
                      subtitle:  'Redeem & Manage',
                      gradient:  AppColors.keyGradient,
                      glowColor: const Color(0xFF00C9FF),
                      locked:    false,
                      loading:   _loading,
                      onTap:     _goToKeys,
                      index:     2,
                    ),
                    _FeatureCard(
                      icon:      Icons.info_outline_rounded,
                      title:     'About',
                      subtitle:  'App Info & Links',
                      gradient:  AppColors.aboutGradient,
                      glowColor: AppColors.secondary,
                      locked:    false,
                      loading:   _loading,
                      onTap:     _goToAbout,
                      index:     3,
                    ),
                    // ── Coming soon cards ───────────────────────────────────
                    _FeatureCard(
                      icon:      Icons.location_on_rounded,
                      title:     'IP Tracker',
                      subtitle:  'Locate & Info',
                      gradient:  AppColors.comingSoon,
                      glowColor: AppColors.neonOrange,
                      locked:    false,
                      loading:   false,
                      onTap:     () => _showComingSoon('IP Tracker'),
                      index:     4,
                      comingSoon: true,
                    ),
                    _FeatureCard(
                      icon:      Icons.phonelink_ring_rounded,
                      title:     'Phone Info',
                      subtitle:  'Number Lookup',
                      gradient:  AppColors.comingSoon,
                      glowColor: AppColors.neonPink,
                      locked:    false,
                      loading:   false,
                      onTap:     () => _showComingSoon('Phone Info'),
                      index:     5,
                      comingSoon: true,
                    ),
                  ]),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount:  2,
                    mainAxisSpacing: 14,
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
          // Brand
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
                    color:        Colors.white,
                    fontSize:     28,
                    fontWeight:   FontWeight.w900,
                    letterSpacing: 4,
                  ),
                ),
              ),
              Text(
                'Multi-Tool Suite',
                style: TextStyle(
                    color: c.textSecondary, fontSize: 12),
              ),
            ],
          )
              .animate()
              .fadeIn(duration: 500.ms)
              .slideX(begin: -0.2, end: 0, duration: 500.ms),

          // Right side: Telegram + theme toggle
          Row(
            children: [
              // Telegram channel quick link
              _TelegramButton(c: c)
                  .animate(delay: 100.ms)
                  .fadeIn(duration: 500.ms)
                  .scale(begin: const Offset(0.8, 0.8), duration: 400.ms),

              const SizedBox(width: 8),

              // Theme toggle
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

  // ── Key status row ─────────────────────────────────────────────────────────

  Widget _buildKeyStatusRow(XissinColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 0),
      child: GestureDetector(
        onTap: _goToKeys,
        child: AnimatedContainer(
          duration: AppDurations.normal,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _loading
                ? c.surfaceAlt
                : _hasKey
                    ? AppColors.neonGreen.withOpacity(0.08)
                    : c.error.withOpacity(0.08),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: _loading
                  ? c.border
                  : _hasKey
                      ? AppColors.neonGreen.withOpacity(0.35)
                      : c.error.withOpacity(0.35),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              if (_loading)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: c.textSecondary),
                )
              else
                Icon(
                  _hasKey
                      ? Icons.verified_rounded
                      : Icons.lock_outline_rounded,
                  size:  16,
                  color: _hasKey
                      ? AppColors.neonGreen
                      : c.error,
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _loading
                      ? 'Checking key status...'
                      : _hasKey
                          ? 'Key Active — All tools unlocked'
                          : 'No active key — Tap to redeem',
                  style: TextStyle(
                    color: _loading
                        ? c.textSecondary
                        : _hasKey
                            ? AppColors.neonGreen
                            : c.error,
                    fontSize:   13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  size: 16, color: c.textSecondary),
            ],
          ),
        )
            .animate()
            .fadeIn(duration: 400.ms, delay: 200.ms)
            .slideY(begin: -0.15, end: 0, duration: 400.ms),
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
            style: TextStyle(
              color:    c.textSecondary,
              fontSize: 12,
            ),
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
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFF229ED9).withOpacity(0.15),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: const Color(0xFF229ED9).withOpacity(0.30),
            width: 1,
          ),
        ),
        child: const Icon(
          Icons.telegram,
          size:  20,
          color: Color(0xFF229ED9),
        ),
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
    final type  = announcement['type']  as String? ?? 'info';
    final title = announcement['title'] as String? ?? 'Announcement';
    final msg   = announcement['message'] as String? ?? '';
    final color = _typeColor(type);
    final icon  = _typeIcon(type);

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
      child: Container(
        decoration: BoxDecoration(
          color:        c.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border(
            left: BorderSide(color: color, width: 3),
            right:  BorderSide(color: c.border, width: 1),
            top:    BorderSide(color: c.border, width: 1),
            bottom: BorderSide(color: c.border, width: 1),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
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
                    Text(
                      title,
                      style: TextStyle(
                        color:      color,
                        fontSize:   12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (msg.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        msg,
                        style: TextStyle(
                            color:    c.textSecondary,
                            fontSize: 12,
                            height:   1.4),
                      ),
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
    )
        .animate(delay: Duration(milliseconds: 50 + 100 * index))
        .fadeIn(duration: 400.ms)
        .slideY(begin: -0.2, end: 0, duration: 400.ms);
  }
}

// ── Feature card ──────────────────────────────────────────────────────────────

class _FeatureCard extends StatelessWidget {
  final IconData       icon;
  final String         title;
  final String         subtitle;
  final List<Color>    gradient;
  final Color          glowColor;
  final bool           locked;
  final bool           loading;
  final VoidCallback   onTap;
  final int            index;
  final bool           comingSoon;

  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradient,
    required this.glowColor,
    required this.locked,
    required this.loading,
    required this.onTap,
    required this.index,
    this.comingSoon = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return GlassNeumorphicCard(
      glowColor: comingSoon ? Colors.transparent : glowColor,
      onTap: loading ? null : onTap,
      padding: const EdgeInsets.all(18),
      child: Stack(
        children: [
          // Main content
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon container
              GlassIconContainer(
                icon:      icon,
                gradient:  comingSoon
                    ? [c.border, c.surfaceAlt]
                    : gradient,
                glowColor: comingSoon ? Colors.transparent : glowColor,
              ),

              const Spacer(),

              // Lock / loading / coming soon indicator
              if (locked && !loading && !comingSoon)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Icon(Icons.lock_outline_rounded,
                      color: c.textSecondary, size: 15),
                ),
              if (loading)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: SizedBox(
                    width:  14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: c.textSecondary),
                  ),
                ),

              // Title
              Text(
                title,
                style: TextStyle(
                  color:      comingSoon
                      ? c.textSecondary
                      : c.textPrimary,
                  fontSize:   15,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 3),

              // Subtitle
              Text(
                subtitle,
                style: TextStyle(
                    color:    c.textSecondary,
                    fontSize: 12),
              ),
            ],
          ),

          // Coming Soon overlay badge
          if (comingSoon)
            Positioned(
              top:   0,
              right: 0,
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
            begin:  0.2,
            end:    0,
            duration: 400.ms,
            curve:  Curves.easeOutCubic);
  }
}
