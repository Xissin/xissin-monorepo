import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../services/ad_service.dart';
import '../services/api_service.dart';
import '../services/update_service.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _version     = '';
  String _buildNumber = '';

  // ── Update check state ─────────────────────────────────────────────────────
  bool    _checkingUpdate  = false;
  bool    _updateChecked   = false;
  bool    _updateAvailable = false;
  String  _latestVersion   = '';
  String  _apkUrl          = '';
  String? _versionNotes;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _version     = info.version;
        _buildNumber = info.buildNumber;
      });
    }
  }

  // ── Check for updates ──────────────────────────────────────────────────────
  Future<void> _checkForUpdates() async {
    if (_checkingUpdate) return;
    HapticFeedback.mediumImpact();

    setState(() {
      _checkingUpdate  = true;
      _updateChecked   = false;
      _updateAvailable = false;
    });

    try {
      final data = await ApiService.getVersion();

      final latest      = data['latest_app_version'] as String? ?? '';
      final apkUrl      = data['apk_download_url']   as String? ?? '';
      final notes       = data['apk_version_notes']  as String?;

      final hasUpdate = latest.isNotEmpty &&
          _version.isNotEmpty &&
          _isNewerVersion(latest, _version) &&
          apkUrl.isNotEmpty;

      if (mounted) {
        setState(() {
          _checkingUpdate  = false;
          _updateChecked   = true;
          _updateAvailable = hasUpdate;
          _latestVersion   = latest;
          _apkUrl          = apkUrl;
          _versionNotes    = notes;
        });
      }

      if (hasUpdate && mounted) {
        UpdateService.showUpdateDialog(
          context:        context,
          currentVersion: _version,
          latestVersion:  latest,
          apkUrl:         apkUrl,
          versionNotes:   notes,
          forceUpdate:    false,
        );
      } else if (!hasUpdate && mounted) {
        _showUpToDateSnack();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _checkingUpdate = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Could not check for updates. Try again.',
              style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.redAccent,
          behavior:        SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md)),
          margin: const EdgeInsets.all(12),
        ));
      }
    }
  }

  bool _isNewerVersion(String a, String b) {
    try {
      final pa = a.split('.').map(int.parse).toList();
      final pb = b.split('.').map(int.parse).toList();
      for (int i = 0; i < 3; i++) {
        final va = i < pa.length ? pa[i] : 0;
        final vb = i < pb.length ? pb[i] : 0;
        if (va > vb) return true;
        if (va < vb) return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  void _showUpToDateSnack() {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle_rounded,
            color: Color(0xFF7EE7C1), size: 18),
        const SizedBox(width: 10),
        Text(
          'You\'re on the latest version (v$_version) 🎉',
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ]),
      backgroundColor: const Color(0xFF1A2740),
      behavior:        SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md)),
      margin:   const EdgeInsets.all(12),
      duration: const Duration(seconds: 3),
    ));
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$label copied!',
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600)),
      backgroundColor: AppColors.accent,
      behavior:        SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md)),
      margin:   const EdgeInsets.all(12),
      duration: const Duration(seconds: 2),
    ));
  }

  // ── Banner Ad ──────────────────────────────────────────────────────────────

  Widget _buildBannerAd() {
    return Consumer<AdService>(
      builder: (_, adService, __) {
        if (adService.adsRemoved) return const SizedBox.shrink();
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

  @override
  Widget build(BuildContext context) {
    final c    = context.c;
    final year = DateTime.now().year;

    return Scaffold(
      backgroundColor: c.background,
      bottomNavigationBar: _buildBannerAd(), // ✅ banner ad at bottom
      appBar: AppBar(
        backgroundColor: c.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded, color: c.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: ShaderMask(
          shaderCallback: (b) => LinearGradient(
            colors: [c.secondary, c.accent],
          ).createShader(b),
          child: const Text(
            'About',
            style: TextStyle(
              color:         Colors.white,
              fontWeight:    FontWeight.w800,
              fontSize:      20,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Hero section ─────────────────────────────────────────────────
            Center(
              child: Column(
                children: [
                  Container(
                    width:  110,
                    height: 110,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      boxShadow:    AppShadows.doubleGlow(c.primary),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: Image.asset(
                        'assets/icon/icon.png',
                        width:  110,
                        height: 110,
                        fit:    BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors:  [c.primary, c.secondary],
                              begin:   Alignment.topLeft,
                              end:     Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(28),
                          ),
                          child: const Icon(Icons.bolt_rounded,
                              size: 56, color: Colors.white),
                        ),
                      ),
                    ),
                  )
                      .animate()
                      .fadeIn(duration: 500.ms)
                      .scale(begin: const Offset(0.8, 0.8), duration: 500.ms,
                             curve: Curves.easeOutBack),

                  const SizedBox(height: 18),

                  ShaderMask(
                    shaderCallback: (b) => LinearGradient(
                      colors: [c.primary, c.secondary],
                    ).createShader(b),
                    child: const Text(
                      'Xissin',
                      style: TextStyle(
                        color:         Colors.white,
                        fontSize:      30,
                        fontWeight:    FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                  )
                      .animate(delay: 100.ms)
                      .fadeIn(duration: 400.ms)
                      .slideY(begin: 0.2, end: 0, duration: 400.ms),

                  const SizedBox(height: 6),

                  Text(
                    'Multi-Tool Suite',
                    style: TextStyle(color: c.textSecondary, fontSize: 14),
                  )
                      .animate(delay: 150.ms)
                      .fadeIn(duration: 400.ms),

                  const SizedBox(height: 14),

                  // Version badge
                  GestureDetector(
                    onTap: () => _buildNumber.isNotEmpty
                        ? _copyToClipboard(
                            'v$_version (Build $_buildNumber)', 'Version')
                        : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [c.primary, c.secondary],
                        ),
                        borderRadius:
                            BorderRadius.circular(AppRadius.full),
                        boxShadow:
                            AppShadows.glow(c.primary, intensity: 0.25),
                      ),
                      child: Text(
                        _version.isEmpty
                            ? 'Loading...'
                            : 'v$_version  •  Build $_buildNumber',
                        style: const TextStyle(
                          color:         Colors.white,
                          fontSize:      12,
                          fontWeight:    FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  )
                      .animate(delay: 200.ms)
                      .fadeIn(duration: 400.ms),
                ],
              ),
            ),

            const SizedBox(height: 36),

            // ── Stats row ─────────────────────────────────────────────────────
            Row(
              children: [
                _StatBox(label: 'Tools',    value: '5',  color: c.primary,   c: c),
                const SizedBox(width: 12),
                _StatBox(label: 'PH SMS',   value: '14', color: c.secondary, c: c),
                const SizedBox(width: 12),
                _StatBox(
                  label: 'Platform',
                  value: 'v${_version.isEmpty ? '?' : _version}',
                  color: c.accent,
                  c:     c,
                ),
              ],
            )
                .animate(delay: 250.ms)
                .fadeIn(duration: 400.ms)
                .slideY(begin: 0.15, end: 0, duration: 400.ms),

            const SizedBox(height: 28),

            // ── App Info section ──────────────────────────────────────────────
            _SectionLabel('App Info', c),
            const SizedBox(height: 12),

            _infoCard(Icons.apps_rounded,          'App Name', 'Xissin Multi-Tool', c),
            _infoCard(Icons.tag_rounded,           'Version',  _version.isEmpty ? 'Loading...' : 'v$_version', c),
            _infoCard(Icons.build_rounded,         'Build',    _buildNumber.isEmpty ? 'Loading...' : _buildNumber, c),
            _infoCard(Icons.phone_android_rounded, 'Platform', 'Android & iOS', c),

            const SizedBox(height: 24),

            // ── Developer section ─────────────────────────────────────────────
            _SectionLabel('Developer', c),
            const SizedBox(height: 12),

            _infoCard(
              Icons.person_outline_rounded,
              'Developer',
              '@QuitNat',
              c,
              onTap: () => _copyToClipboard('@QuitNat', 'Username'),
            ),

            const SizedBox(height: 24),

            // ── Community section ─────────────────────────────────────────────
            _SectionLabel('Community', c),
            const SizedBox(height: 12),

            _linkCard(
              icon:      Icons.telegram,
              iconColor: const Color(0xFF229ED9),
              label:     'Telegram Channel',
              value:     '@Xissin_0',
              c:         c,
              onTap:     () => _openUrl('https://t.me/Xissin_0'),
            ),
            _linkCard(
              icon:      Icons.forum_rounded,
              iconColor: c.secondary,
              label:     'Discussion Group',
              value:     '@Xissin_1',
              c:         c,
              onTap:     () => _openUrl('https://t.me/Xissin_1'),
            ),

            // ── Check for Updates card ────────────────────────────────────────
            _CheckUpdateCard(
              c:               c,
              checking:        _checkingUpdate,
              checked:         _updateChecked,
              updateAvailable: _updateAvailable,
              latestVersion:   _latestVersion,
              onCheck:         _checkForUpdates,
              onDownload: _updateAvailable
                  ? () => UpdateService.showUpdateDialog(
                        context:        context,
                        currentVersion: _version,
                        latestVersion:  _latestVersion,
                        apkUrl:         _apkUrl,
                        versionNotes:   _versionNotes,
                        forceUpdate:    false,
                      )
                  : null,
            ),

            const SizedBox(height: 28),

            // ── Description ───────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color:        c.surfaceAlt,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border:       Border.all(color: c.border, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.info_outline_rounded, size: 15, color: c.primary),
                    const SizedBox(width: 6),
                    Text(
                      'About Xissin',
                      style: TextStyle(
                          color:      c.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize:   13),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  Text(
                    'Xissin is a multi-tool app designed to provide useful '
                    'utilities in one place. Features include SMS Bomber '
                    'for PH numbers, NGL anonymous messaging, and more '
                    'tools coming soon.',
                    style: TextStyle(
                        color: c.textSecondary, fontSize: 13, height: 1.6),
                  ),
                ],
              ),
            )
                .animate(delay: 300.ms)
                .fadeIn(duration: 400.ms),

            const SizedBox(height: 32),

            // ── Footer ────────────────────────────────────────────────────────
            Center(
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.bolt_rounded, size: 14, color: c.primary),
                      const SizedBox(width: 4),
                      Text(
                        'Made with ❤️ by @QuitNat',
                        style: TextStyle(
                            color: c.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '© $year Xissin. All rights reserved.',
                    style: TextStyle(
                        color:    c.textSecondary.withOpacity(0.5),
                        fontSize: 10),
                  ),
                ],
              ),
            )
                .animate(delay: 350.ms)
                .fadeIn(duration: 400.ms),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ── Builders ──────────────────────────────────────────────────────────────

  Widget _infoCard(
      IconData icon, String label, String value, XissinColors c,
      {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin:  const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color:        c.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border:       Border.all(color: c.border, width: 1),
        ),
        child: Row(
          children: [
            Icon(icon, color: c.primary, size: 18),
            const SizedBox(width: 12),
            Text(label,
                style: TextStyle(color: c.textSecondary, fontSize: 13)),
            const Spacer(),
            Text(
              value,
              style: TextStyle(
                color:      c.textPrimary,
                fontSize:   13,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 6),
              Icon(Icons.copy_rounded, size: 13, color: c.textSecondary),
            ],
          ],
        ),
      ),
    );
  }

  Widget _linkCard({
    required IconData     icon,
    required Color        iconColor,
    required String       label,
    required String       value,
    required XissinColors c,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        margin:  const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color:        c.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border:       Border.all(color: c.border, width: 1),
        ),
        child: Row(
          children: [
            Container(
              width:  34,
              height: 34,
              decoration: BoxDecoration(
                color:        iconColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          color: c.textSecondary, fontSize: 11)),
                  Text(value,
                      style: TextStyle(
                        color:      c.textPrimary,
                        fontSize:   13,
                        fontWeight: FontWeight.w600,
                      )),
                ],
              ),
            ),
            Icon(Icons.open_in_new_rounded,
                size: 15, color: c.textSecondary),
          ],
        ),
      ),
    );
  }
}

// ── Check Update Card ─────────────────────────────────────────────────────────

class _CheckUpdateCard extends StatelessWidget {
  final XissinColors  c;
  final bool          checking;
  final bool          checked;
  final bool          updateAvailable;
  final String        latestVersion;
  final VoidCallback  onCheck;
  final VoidCallback? onDownload;

  const _CheckUpdateCard({
    required this.c,
    required this.checking,
    required this.checked,
    required this.updateAvailable,
    required this.latestVersion,
    required this.onCheck,
    this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final Color iconBg;
    final Color iconColor;
    final String statusLabel;
    final String statusValue;
    final IconData statusIcon;

    if (checking) {
      iconBg      = Colors.white.withOpacity(0.06);
      iconColor   = Colors.white54;
      statusLabel = 'Checking for updates...';
      statusValue = 'Please wait';
      statusIcon  = Icons.sync_rounded;
    } else if (checked && updateAvailable) {
      iconBg      = const Color(0xFF6C63FF).withOpacity(0.15);
      iconColor   = const Color(0xFF6C63FF);
      statusLabel = 'Update Available!';
      statusValue = 'v$latestVersion — Tap Download';
      statusIcon  = Icons.system_update_rounded;
    } else if (checked && !updateAvailable) {
      iconBg      = const Color(0xFF7EE7C1).withOpacity(0.12);
      iconColor   = const Color(0xFF7EE7C1);
      statusLabel = 'App is up to date';
      statusValue = 'No update needed';
      statusIcon  = Icons.check_circle_outline_rounded;
    } else {
      iconBg      = const Color(0xFF6C63FF).withOpacity(0.12);
      iconColor   = const Color(0xFF6C63FF);
      statusLabel = 'Check for Updates';
      statusValue = 'Tap to check';
      statusIcon  = Icons.update_rounded;
    }

    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        if (updateAvailable && onDownload != null) {
          onDownload!();
        } else {
          onCheck();
        }
      },
      child: Container(
        margin:  const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: updateAvailable
              ? const Color(0xFF6C63FF).withOpacity(0.08)
              : c.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: updateAvailable
                ? const Color(0xFF6C63FF).withOpacity(0.40)
                : c.border,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width:  34,
              height: 34,
              decoration: BoxDecoration(
                color:        iconBg,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: checking
                  ? Padding(
                      padding: const EdgeInsets.all(8),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color:       iconColor,
                      ),
                    )
                  : Icon(statusIcon, color: iconColor, size: 18),
            ),

            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    statusLabel,
                    style: TextStyle(
                      color:      updateAvailable
                          ? const Color(0xFF6C63FF)
                          : c.textSecondary,
                      fontSize:   11,
                      fontWeight: updateAvailable
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  Text(
                    statusValue,
                    style: TextStyle(
                      color:      c.textPrimary,
                      fontSize:   13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

            if (updateAvailable)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF6C63FF),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: const Text(
                  'Download',
                  style: TextStyle(
                    color:      Colors.white,
                    fontSize:   11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            else
              Icon(
                Icons.chevron_right_rounded,
                size:  18,
                color: c.textSecondary,
              ),
          ],
        ),
      ),
    );
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String       text;
  final XissinColors c;
  const _SectionLabel(this.text, this.c);

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width:  3,
            height: 16,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors:    [c.primary, c.secondary],
                  begin:     Alignment.topCenter,
                  end:       Alignment.bottomCenter),
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              color:      c.textPrimary,
              fontSize:   14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      );
}

class _StatBox extends StatelessWidget {
  final String       label, value;
  final Color        color;
  final XissinColors c;
  const _StatBox({
    required this.label,
    required this.value,
    required this.color,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color:        c.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: color.withOpacity(0.25), width: 1),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                color:      color,
                fontSize:   20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(color: c.textSecondary, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
