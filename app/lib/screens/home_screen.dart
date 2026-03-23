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
import '../services/payment_service.dart';
import '../widgets/glass_neumorphic_card.dart';
import '../widgets/shimmer_skeleton.dart';
import '../widgets/staggered_grid.dart';
import '../widgets/haptic_button.dart';
import 'sms_bomber_screen.dart';
import 'about_screen.dart';
import 'ngl_screen.dart';
import 'url_remover_screen.dart';
import 'duplicate_remover_screen.dart';
import 'ip_tracker_screen.dart';
import 'username_tracker_screen.dart';
import 'codm_checker_screen.dart';

// UPDATE THIS CONSTANT WHEN ADDING NEW TOOLS TO THE GRID
const int _kToolCount = 7;

class HomeScreen extends StatefulWidget {
  final String userId;
  final String nickname;

  const HomeScreen({
    super.key,
    required this.userId,
    this.nickname = '',
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> _announcements = [];
  final Set<String> _dismissed = {};

  BannerAd? _bannerAd;
  bool      _bannerReady = false;

  @override
  void initState() {
    super.initState();
    _loadAnnouncements();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      LocationService.tryCollectAndSend(widget.userId);
    });

    // FIX: init() is fire-and-forget — do NOT call _initBanner() inside
    // .then() because _initBanner() already runs on the next line.
    // The old code called _initBanner() twice, creating 2 banner ad objects.
    AdService.instance.init(userId: widget.userId);
    AdService.instance.addListener(_onAdServiceChanged);
    _initBanner();
  }

  @override
  void dispose() {
    AdService.instance.removeListener(_onAdServiceChanged);
    _bannerAd?.dispose();
    super.dispose();
  }

  void _onAdServiceChanged() {
    if (!mounted) return;
    if (AdService.instance.adsRemoved && _bannerAd != null) {
      _bannerAd?.dispose();
      setState(() { _bannerAd = null; _bannerReady = false; });
    }
  }

  void _initBanner() {
    if (AdService.instance.adsRemoved) return;
    _bannerAd?.dispose();
    _bannerAd    = null;
    _bannerReady = false;
    final ad = AdService.instance.createBannerAd(
      onLoaded: () {
        if (!mounted || AdService.instance.adsRemoved) {
          _bannerAd?.dispose(); _bannerAd = null; return;
        }
        setState(() => _bannerReady = true);
      },
      onFailed: () {
        if (mounted) setState(() { _bannerAd = null; _bannerReady = false; });
        Future.delayed(const Duration(seconds: 30), () {
          if (mounted && !AdService.instance.adsRemoved) _initBanner();
        });
      },
    );
    if (ad == null) return;
    _bannerAd = ad;
    _bannerAd!.load();
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
    if (!AdService.instance.adsRemoved) AdService.instance.showInterstitial();
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => const AboutScreen()));
  }

  void _goToUrlRemover() {
    HapticFeedback.mediumImpact();
    AdService.instance.showInterstitial();
    _pushSlide(UrlRemoverScreen(userId: widget.userId));
  }

  void _goToDupRemover() {
    HapticFeedback.mediumImpact();
    AdService.instance.showInterstitial();
    _pushSlide(DuplicateRemoverScreen(userId: widget.userId));
  }

  void _goToIpTracker() {
    HapticFeedback.mediumImpact();
    AdService.instance.showInterstitial();
    _pushSlide(IpTrackerScreen(userId: widget.userId));
  }

  void _goToUsernameTracker() {
    HapticFeedback.mediumImpact();
    AdService.instance.showInterstitial();
    _pushSlide(UsernameTrackerScreen(userId: widget.userId));
  }

  void _goToCodm() {
    HapticFeedback.mediumImpact();
    AdService.instance.showInterstitial();
    _pushSlide(CodmCheckerScreen(userId: widget.userId));
  }

  // ── Get Premium ─────────────────────────────────────────────────────────────

  Future<void> _onRemoveAdsTap() async {
    HapticFeedback.mediumImpact();
    final adService = AdService.instance;
    final c = context.c;

    if (adService.adsRemoved) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior:        SnackBarBehavior.floating,
          backgroundColor: c.surface,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md)),
          margin:   const EdgeInsets.fromLTRB(16, 0, 16, 16),
          duration: const Duration(seconds: 3),
          content: Row(children: [
            const Icon(Icons.workspace_premium_rounded,
                color: Color(0xFFFFD700), size: 18),
            const SizedBox(width: 10),
            Text('✨ You\'re already Premium! Enjoy Xissin!',
                style: TextStyle(
                    color: c.textPrimary, fontWeight: FontWeight.w600)),
          ]),
        ),
      );
      return;
    }

    final purchased = await PaymentService.showRemoveAdsDialog(
      context: context,
      userId:  widget.userId,
    );

    if (purchased == true && mounted) {
      await adService.onPurchaseComplete(widget.userId);
      if (mounted) setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior:        SnackBarBehavior.floating,
          backgroundColor: c.surface,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md)),
          margin:   const EdgeInsets.fromLTRB(16, 0, 16, 16),
          duration: const Duration(seconds: 4),
          content: Row(children: [
            const Icon(Icons.check_circle_rounded,
                color: Color(0xFFFFD700), size: 18),
            const SizedBox(width: 10),
            Text('🎉 Premium activated! Enjoy Xissin!',
                style: TextStyle(
                    color: c.textPrimary, fontWeight: FontWeight.w600)),
          ]),
        ),
      );
    }
  }

  Future<T?> _pushSlide<T>(Widget page) {
    return Navigator.push<T>(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 350),
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

  Widget _buildBannerAd() {
    if (AdService.instance.adsRemoved || !_bannerReady || _bannerAd == null) {
      return const SizedBox.shrink();
    }
    return SafeArea(
      top: false,
      child: Container(
        alignment: Alignment.center,
        width:  _bannerAd!.size.width.toDouble(),
        height: _bannerAd!.size.height.toDouble(),
        child:  AdWidget(ad: _bannerAd!),
      ),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final visible = _announcements
        .where((a) => !_dismissed.contains(a['id']?.toString()))
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
              SliverToBoxAdapter(child: _buildHeader(c)),

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
                            () => _dismissed.add(
                                visible[i]['id']?.toString() ?? ''),
                          ),
                          c: c, index: i,
                        ),
                      ),
                    ),
                  ),
                ),

              // Premium / Get Premium banner
              SliverToBoxAdapter(
                child: Consumer<AdService>(
                  builder: (_, adService, __) {
                    if (adService.adsRemoved) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(22, 16, 22, 0),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [
                              const Color(0xFFFFD700).withOpacity(0.12),
                              const Color(0xFFFF9F43).withOpacity(0.12),
                            ]),
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            border: Border.all(
                                color: const Color(0xFFFFD700).withOpacity(0.35)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.workspace_premium_rounded,
                                  color: Color(0xFFFFD700), size: 16),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  '⭐  Premium Active — Thank you for supporting Xissin!',
                                  style: TextStyle(
                                      color:      c.gold,
                                      fontSize:   12,
                                      fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                            ],
                          ),
                        ).animate().fadeIn(duration: 400.ms),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(22, 16, 22, 0),
                      child: GestureDetector(
                        onTap: _onRemoveAdsTap,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [
                              c.primary.withOpacity(0.12),
                              c.secondary.withOpacity(0.08),
                            ]),
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            border: Border.all(
                                color: c.primary.withOpacity(0.35)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.workspace_premium_rounded,
                                  color: c.primary, size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Get Premium',
                                        style: TextStyle(
                                            color:      c.primary,
                                            fontSize:   13,
                                            fontWeight: FontWeight.bold)),
                                    Text('Tap to see benefits & redeem a key',
                                        style: TextStyle(
                                            color: c.textHint, fontSize: 11)),
                                  ],
                                ),
                              ),
                              Icon(Icons.chevron_right_rounded,
                                  color: c.primary, size: 20),
                            ],
                          ),
                        ),
                      ).animate(delay: 200.ms).fadeIn(duration: 400.ms),
                    );
                  },
                ),
              ),

              // Section heading
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 28, 22, 14),
                  child: Row(
                    children: [
                      Text('Tools',
                          style: TextStyle(
                            color:      c.textPrimary,
                            fontSize:   18,
                            fontWeight: FontWeight.bold,
                          )),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color:        c.primary.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(AppRadius.full),
                        ),
                        child: Text('$_kToolCount',
                            style: TextStyle(
                              color:      c.primary,
                              fontSize:   11,
                              fontWeight: FontWeight.bold,
                            )),
                      ),
                    ],
                  ),
                ),
              ),

              // Tools grid
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                sliver: SliverGrid(
                  delegate: SliverChildListDelegate([
                    _FeatureCard(
                      icon: Icons.sms_rounded, title: 'SMS Bomber',
                      subtitle: '14 PH Services', gradient: AppColors.smsGradient,
                      glowColor: c.primary, onTap: _goToSms, index: 0,
                    ),
                    _FeatureCard(
                      icon: Icons.chat_bubble_outline_rounded, title: 'NGL Bomber',
                      subtitle: 'Anonymous Messages', gradient: AppColors.nglGradient,
                      glowColor: const Color(0xFFFF6EC7), onTap: _goToNgl, index: 1,
                    ),
                    _FeatureCard(
                      icon: Icons.link_off_rounded, title: 'URL Remover',
                      subtitle: 'Clean Combo Lists',
                      gradient: const [Color(0xFF7B8CDE), Color(0xFF4A5BAA)],
                      glowColor: const Color(0xFF7B8CDE), onTap: _goToUrlRemover, index: 2,
                    ),
                    _FeatureCard(
                      icon: Icons.filter_list_off_rounded, title: 'Dup Remover',
                      subtitle: 'Remove Duplicates',
                      gradient: const [Color(0xFFFFA94D), Color(0xFFE67E22)],
                      glowColor: const Color(0xFFFFA94D), onTap: _goToDupRemover, index: 3,
                    ),
                    _FeatureCard(
                      icon: Icons.location_on_rounded, title: 'IP Tracker',
                      subtitle: 'Locate & Info',
                      gradient: const [Color(0xFF00B4D8), Color(0xFF0077B6)],
                      glowColor: const Color(0xFF00B4D8), onTap: _goToIpTracker, index: 4,
                    ),
                    _FeatureCard(
                      icon: Icons.manage_accounts_rounded, title: 'User Tracker',
                      subtitle: '30+ Platforms',
                      gradient: const [Color(0xFF9B59B6), Color(0xFF6C3483)],
                      glowColor: const Color(0xFF9B59B6), onTap: _goToUsernameTracker, index: 5,
                    ),
                    _FeatureCard(
                      icon: Icons.sports_esports_rounded, title: 'CODM Checker',
                      subtitle: 'Garena Account',
                      gradient: const [Color(0xFFFF6B35), Color(0xFFC0392B)],
                      glowColor: const Color(0xFFFF6B35), onTap: _goToCodm, index: 6,
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

              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader(XissinColors c) {
    final subtitle = widget.nickname.isNotEmpty
        ? 'Hi, ${widget.nickname}! 👋'
        : 'Multi-Tool Suite';

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Selector<AdService, bool>(
            selector: (_, s) => s.adsRemoved,
            builder: (_, adsRemoved, __) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShaderMask(
                  shaderCallback: (b) => LinearGradient(
                      colors: [c.primary, c.secondary]).createShader(b),
                  child: const Text('XISSIN',
                      style: TextStyle(
                          color: Colors.white, fontSize: 28,
                          fontWeight: FontWeight.w900, letterSpacing: 4)),
                ),
                Row(
                  children: [
                    Text(subtitle,
                        style: TextStyle(color: c.textSecondary, fontSize: 12)),
                    if (adsRemoved) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFD700).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: const Color(0xFFFFD700).withOpacity(0.40)),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.workspace_premium_rounded,
                              color: Color(0xFFFFD700), size: 9),
                          const SizedBox(width: 3),
                          Text('PRO',
                              style: TextStyle(
                                  color: c.gold, fontSize: 9,
                                  fontWeight:    FontWeight.bold,
                                  letterSpacing: 0.5)),
                        ]),
                      ),
                    ],
                  ],
                ),
              ],
            )
                .animate()
                .fadeIn(duration: 500.ms)
                .slideX(begin: -0.2, end: 0, duration: 500.ms),
          ),
          ),

          Row(
            children: [
              // Get Premium (hidden when premium)
              Selector<AdService, bool>(
                selector: (_, s) => s.adsRemoved,
                builder: (_, adsRemoved, __) => adsRemoved
                    ? const SizedBox.shrink()
                    : GestureDetector(
                        onTap: _onRemoveAdsTap,
                        child: Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            color: c.primary.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            border: Border.all(
                                color: c.primary.withOpacity(0.30), width: 1),
                          ),
                          child: Icon(Icons.workspace_premium_rounded,
                              size: 16, color: c.primary),
                        ),
                      )
                        .animate(delay: 50.ms)
                        .fadeIn(duration: 500.ms)
                        .scale(begin: const Offset(0.8, 0.8), duration: 400.ms),
              ),
              const SizedBox(width: 6),

              // Telegram
              _TelegramButton(c: c)
                  .animate(delay: 100.ms)
                  .fadeIn(duration: 500.ms)
                  .scale(begin: const Offset(0.8, 0.8), duration: 400.ms),
              const SizedBox(width: 6),

              // About ⓘ
              GestureDetector(
                onTap: _goToAbout,
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color:        c.surface,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border:       Border.all(color: c.border),
                  ),
                  child: Icon(Icons.info_outline_rounded,
                      size: 16, color: c.textSecondary),
                ),
              )
                  .animate(delay: 120.ms)
                  .fadeIn(duration: 500.ms)
                  .scale(begin: const Offset(0.8, 0.8), duration: 400.ms),
              const SizedBox(width: 6),

              // Theme toggle
              Selector<ThemeService, bool>(
                selector: (_, s) => s.isDark,
                builder: (_, isDark, __) => HapticIconButton(
                  icon: isDark
                      ? Icons.light_mode_rounded
                      : Icons.dark_mode_rounded,
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    context.read<ThemeService>().toggle();
                  },
                  color:           c.textSecondary,
                  backgroundColor: c.surface,
                ),
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
}

// ── Telegram button ───────────────────────────────────────────────────────────

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
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: const Color(0xFF229ED9).withOpacity(0.15),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
              color: const Color(0xFF229ED9).withOpacity(0.30), width: 1),
        ),
        child: const Icon(Icons.telegram, size: 18, color: Color(0xFF229ED9)),
      ),
    );
  }
}

// ── Announcement banner ───────────────────────────────────────────────────────

class _AnnouncementBanner extends StatelessWidget {
  final Map<String, dynamic> announcement;
  final VoidCallback          onDismiss;
  final XissinColors          c;
  final int                   index;

  const _AnnouncementBanner({
    required this.announcement, required this.onDismiss,
    required this.c, required this.index,
  });

  Color _typeColor(String? type) {
    switch (type) {
      case 'warning': return const Color(0xFFFFA726);
      case 'error':   return const Color(0xFFFF6B6B);
      case 'success': return const Color(0xFF2ECC71);
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
            color:        c.surface,
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
                                  style: TextStyle(color: color, fontSize: 12,
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
    required this.icon, required this.title, required this.subtitle,
    required this.gradient, required this.glowColor,
    required this.onTap, required this.index, this.comingSoon = false,
  });

  @override
  Widget build(BuildContext context) {
    final c      = context.c;
    final isDark = context.isDark;

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
                icon: icon, gradient: gradient,
                glowColor: comingSoon ? Colors.transparent : glowColor,
              ),
              const Spacer(),
              Text(title,
                  style: TextStyle(
                    color: comingSoon
                        ? c.textSecondary
                        : (isDark ? Colors.white : c.textPrimary),
                    fontSize: 15, fontWeight: FontWeight.bold,
                  )),
              const SizedBox(height: 3),
              Text(subtitle,
                  style: TextStyle(color: c.textSecondary, fontSize: 12)),
            ],
          ),
          if (comingSoon)
            Positioned(
              top: 0, right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color:        glowColor.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: glowColor.withOpacity(0.40), width: 1),
                ),
                child: Text('SOON',
                    style: TextStyle(
                        color: glowColor, fontSize: 9,
                        fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              ),
            ),
        ],
      ),
    )
        .animate(delay: Duration(milliseconds: 80 + 100 * index))
        .fadeIn(duration: 400.ms)
        .slideY(begin: 0.2, end: 0, duration: 400.ms, curve: Curves.easeOutCubic);
  }
}
