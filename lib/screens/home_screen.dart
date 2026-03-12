import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../services/theme_service.dart';
import 'sms_bomber_screen.dart';
import 'key_screen.dart';
import 'about_screen.dart';

class HomeScreen extends StatefulWidget {
  final String userId;
  const HomeScreen({super.key, required this.userId});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _hasKey = false;
  bool _loading = true;

  // Announcements
  List<Map<String, dynamic>> _announcements = [];
  final Set<String> _dismissedIds = {};

  // ── Init ──────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      _refreshKeyStatus(),
      _loadAnnouncements(),
    ]);
  }

  Future<void> _refreshKeyStatus() async {
    setState(() => _loading = true);
    try {
      final data = await ApiService.keyStatus(widget.userId);
      setState(() {
        _hasKey = data['active'] == true;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadAnnouncements() async {
    try {
      final list = await ApiService.getAnnouncements();
      if (mounted) setState(() => _announcements = list);
    } catch (_) {}
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  void _goToSms() {
    if (!_hasKey) { _showNoKeyDialog(); return; }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SmsBomberScreen(userId: widget.userId)),
    );
  }

  void _goToKeys() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => KeyScreen(userId: widget.userId)),
    );
    _refreshKeyStatus();
  }

  void _goToAbout() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutScreen()));
  }

  void _showNoKeyDialog() {
    final c = AppColors.of(context);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text('Key Required',
            style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold)),
        content: Text(
          'You need an active key to use this feature.\nGo to Key Manager to redeem one.',
          style: TextStyle(color: c.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: c.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () { Navigator.pop(context); _goToKeys(); },
            child: const Text('Get Key'),
          ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    // Visible (non-dismissed) announcements
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
              // ── Header ────────────────────────────────────────────────────
              SliverToBoxAdapter(child: _buildHeader(c)),

              // ── Announcements ─────────────────────────────────────────────
              if (visible.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      children: visible
                          .map((a) => _AnnouncementBanner(
                                announcement: a,
                                onDismiss: () => setState(() =>
                                    _dismissedIds.add(a['id']?.toString() ?? '')),
                                c: c,
                              ))
                          .toList(),
                    ),
                  ),
                ),

              // ── Features label ─────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 28, 22, 14),
                  child: Text(
                    'Features',
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              // ── Feature grid ───────────────────────────────────────────────
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
                      onTap: _goToSms,
                    ),
                    _FeatureCard(
                      icon: Icons.vpn_key_rounded,
                      title: 'Key Manager',
                      subtitle: _hasKey ? 'Key Active ✓' : 'Redeem Key',
                      gradient: [c.secondary, const Color(0xFF7B6FFF)],
                      glowColor: c.secondary,
                      locked: false,
                      onTap: _goToKeys,
                    ),
                    _FeatureCard(
                      icon: Icons.info_outline_rounded,
                      title: 'About',
                      subtitle: 'Links & Info',
                      gradient: [const Color(0xFFFFA726), const Color(0xFFFF7043)],
                      glowColor: const Color(0xFFFFA726),
                      locked: false,
                      onTap: _goToAbout,
                    ),
                  ]),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
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

  // ── Header ────────────────────────────────────────────────────────────────

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
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4,
                  ),
                ),
              ),
              Text(
                'Multi-Tool',
                style: TextStyle(color: c.textSecondary, fontSize: 13),
              ),
            ],
          ),
          // 🌙 Theme toggle only — pull-to-refresh replaces the refresh button
          GestureDetector(
            onTap: () => themeService.toggle(),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.border),
              ),
              child: Icon(
                themeService.isDark
                    ? Icons.light_mode_rounded
                    : Icons.dark_mode_rounded,
                color: c.textSecondary,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Announcement Banner ───────────────────────────────────────────────────────

class _AnnouncementBanner extends StatelessWidget {
  final Map<String, dynamic> announcement;
  final VoidCallback onDismiss;
  final XissinColors c;

  const _AnnouncementBanner({
    required this.announcement,
    required this.onDismiss,
    required this.c,
  });

  Color _typeColor(String? type) {
    switch (type) {
      case 'warning': return const Color(0xFFFFA726);
      case 'error':   return const Color(0xFFFF6B6B);
      case 'success': return const Color(0xFF7EE7C1);
      default:        return const Color(0xFF5B8CFF); // info
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
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 0),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
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
                      style: TextStyle(color: c.textSecondary, fontSize: 12, height: 1.4),
                    ),
                  ],
                ],
              ),
            ),
            GestureDetector(
              onTap: onDismiss,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.close_rounded, size: 14, color: c.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Feature Card ──────────────────────────────────────────────────────────────

class _FeatureCard extends StatefulWidget {
  final IconData icon;
  final String title, subtitle;
  final List<Color> gradient;
  final Color glowColor;
  final bool locked;
  final VoidCallback onTap;

  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradient,
    required this.glowColor,
    required this.locked,
    required this.onTap,
  });

  @override
  State<_FeatureCard> createState() => _FeatureCardState();
}

class _FeatureCardState extends State<_FeatureCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      lowerBound: 0.95,
      upperBound: 1.0,
      value: 1.0,
    );
    _scale = _ctrl;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return GestureDetector(
      onTapDown: (_) => _ctrl.reverse(),
      onTapUp: (_) { _ctrl.forward(); widget.onTap(); },
      onTapCancel: () => _ctrl.forward(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: c.border, width: 1),
            boxShadow: [
              BoxShadow(
                color: widget.glowColor.withOpacity(0.12),
                blurRadius: 20,
                spreadRadius: 2,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: widget.gradient),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: widget.glowColor.withOpacity(0.4),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(widget.icon, color: Colors.white, size: 26),
                ),
                const Spacer(),
                if (widget.locked)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Icon(Icons.lock_outline, color: c.textSecondary, size: 15),
                  ),
                Text(
                  widget.title,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  widget.subtitle,
                  style: TextStyle(color: c.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
