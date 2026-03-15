import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

// Brand colours for About screen
const _kPurple = Color(0xFF7B2FBE);
const _kBlue   = Color(0xFF4776E6);

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _version = '';
  String _buildNumber = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    setState(() {
      _version = info.version;
      _buildNumber = info.buildNumber;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080818),
      appBar: AppBar(
        backgroundColor: const Color(0xFF080818),
        title: ShaderMask(
          shaderCallback: (b) => const LinearGradient(
            colors: [_kPurple, _kBlue],
          ).createShader(b),
          child: const Text(
            'About',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 20,
              letterSpacing: 0.5,
            ),
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      // ── Fix: SingleChildScrollView prevents overflow ──
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // App Icon + Name
            Center(
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.asset(
                      'assets/icon/icon.png',
                      width: 100,
                      height: 100,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Xissin',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Version Badge
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_kPurple, _kBlue],
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _version.isEmpty
                          ? 'Loading...'
                          : 'v$_version (Build $_buildNumber)',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 40),

            // Info Cards
            _infoCard(Icons.info_outline, 'App Name', 'Xissin Multi-Tool'),
            _infoCard(Icons.tag, 'Version',
                _version.isEmpty ? 'Loading...' : 'v$_version'),
            _infoCard(Icons.build_outlined, 'Build Number',
                _buildNumber.isEmpty ? 'Loading...' : _buildNumber),
            // ── Developer: name hidden, only shows Telegram handle ──
            _infoCard(Icons.person_outline, 'Developer', '@QuitNat'),
            _infoCard(Icons.language, 'Channel', '@Xissin_0'),
            _infoCard(Icons.forum_outlined, 'Discussion', '@Xissin_1'),

            const SizedBox(height: 40),

            // Description
            const Text(
              'Xissin is a multi-tool app designed to provide useful utilities in one place.',
              style: TextStyle(
                color: Colors.white60,
                fontSize: 14,
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),

            // Bottom padding so last item isn't flush against nav bar
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _infoCard(IconData icon, String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Icon(icon, color: _kPurple, size: 20),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(color: Colors.white60, fontSize: 13),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
