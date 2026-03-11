import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import 'sms_bomber_screen.dart';
import 'key_screen.dart';

class HomeScreen extends StatefulWidget {
  final String userId;
  const HomeScreen({super.key, required this.userId});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _hasKey = false;
  bool _loading = true;
  String? _expiresAt;

  @override
  void initState() {
    super.initState();
    _refreshKeyStatus();
  }

  Future<void> _refreshKeyStatus() async {
    setState(() => _loading = true);
    try {
      final data = await ApiService.keyStatus(widget.userId);
      setState(() {
        _hasKey    = data['active'] == true;
        _expiresAt = data['expires_at'];
        _loading   = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

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

  void _showNoKeyDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Key Required',
            style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        content: const Text(
          'You need an active key to use this feature.\nGo to Key Manager to redeem one.',
          style: TextStyle(color: AppColors.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () { Navigator.pop(context); _goToKeys(); },
            child: const Text('Get Key'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 8),
            _buildKeyBanner(),
            const SizedBox(height: 28),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 22),
              child: Text(
                'Features',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 0.88,
                  children: [
                    _FeatureCard(
                      icon: Icons.sms_rounded,
                      title: 'SMS Bomber',
                      subtitle: '14 PH Services',
                      gradient: [AppColors.primary, AppColors.secondary],
                      glowColor: AppColors.primary,
                      locked: !_hasKey,
                      onTap: _goToSms,
                    ),
                    _FeatureCard(
                      icon: Icons.vpn_key_rounded,
                      title: 'Key Manager',
                      subtitle: _hasKey ? 'Key Active ✓' : 'Redeem Key',
                      gradient: [AppColors.secondary, const Color(0xFF7B6FFF)],
                      glowColor: AppColors.secondary,
                      locked: false,
                      onTap: _goToKeys,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShaderMask(
                shaderCallback: (b) => const LinearGradient(
                  colors: [AppColors.primary, AppColors.secondary],
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
              const Text(
                'Multi-Tool',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
          ),
          // Refresh button
          GestureDetector(
            onTap: _refreshKeyStatus,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                    )
                  : const Icon(Icons.refresh_rounded, color: AppColors.textSecondary, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyBanner() {
    if (_loading) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: _hasKey
              ? AppColors.accent.withOpacity(0.1)
              : AppColors.error.withOpacity(0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _hasKey
                ? AppColors.accent.withOpacity(0.35)
                : AppColors.error.withOpacity(0.3),
          ),
        ),
        child: Row(
          children: [
            Icon(
              _hasKey ? Icons.verified_rounded : Icons.lock_outline,
              size: 16,
              color: _hasKey ? AppColors.accent : AppColors.error,
            ),
            const SizedBox(width: 8),
            Text(
              _hasKey
                  ? 'Key active${_expiresAt != null ? ' · Expires $_expiresAt' : ''}'
                  : 'No active key — tap Key Manager to redeem',
              style: TextStyle(
                color: _hasKey ? AppColors.accent : AppColors.error,
                fontSize: 12,
                fontWeight: FontWeight.w500,
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
  final String title;
  final String subtitle;
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
    return GestureDetector(
      onTapDown: (_) => _ctrl.reverse(),
      onTapUp: (_) { _ctrl.forward(); widget.onTap(); },
      onTapCancel: () => _ctrl.forward(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.border, width: 1),
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
                // Icon box
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
                  const Padding(
                    padding: EdgeInsets.only(bottom: 6),
                    child: Icon(Icons.lock_outline, color: AppColors.textSecondary, size: 15),
                  ),
                Text(
                  widget.title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  widget.subtitle,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
