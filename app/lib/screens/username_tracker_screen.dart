// ─────────────────────────────────────────────────────────────────────────────
// app/lib/screens/username_tracker_screen.dart
// Username Tracker — checks 28 platforms from the user's phone (not server)
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:http/http.dart' as http;
import '../theme/app_theme.dart';
import '../services/ad_service.dart';

// ── Data models ────────────────────────────────────────────────────────────────

class _Platform {
  final String name;
  final String urlTemplate; // {u} replaced with the username
  final String category;
  final String? notFoundBody; // body substring → means NOT found (200 sites)

  const _Platform({
    required this.name,
    required this.urlTemplate,
    required this.category,
    this.notFoundBody,
  });
}

enum _Status { idle, checking, found, notFound, error }

class _Result {
  final _Platform platform;
  _Status status;
  String? profileUrl;

  _Result({required this.platform, this.status = _Status.idle});
}

// ── Screen ─────────────────────────────────────────────────────────────────────

class UsernameTrackerScreen extends StatefulWidget {
  const UsernameTrackerScreen({super.key});

  @override
  State<UsernameTrackerScreen> createState() => _UsernameTrackerScreenState();
}

class _UsernameTrackerScreenState extends State<UsernameTrackerScreen> {
  // ── Ad fields ──────────────────────────────────────────────────────────────
  BannerAd? _bannerAd;
  bool      _bannerReady = false;

  // ── State ──────────────────────────────────────────────────────────────────
  final _controller       = TextEditingController();
  final _scrollController = ScrollController();
  String _currentUsername  = '';
  bool   _isSearching      = false;
  String _selectedCategory = 'All';

  late List<_Result> _results;

  // ── Stats helpers ──────────────────────────────────────────────────────────
  int get _found   => _results.where((r) => r.status == _Status.found).length;
  int get _checked => _results.where(
      (r) => r.status != _Status.idle && r.status != _Status.checking).length;

  // ── Platform list ──────────────────────────────────────────────────────────
  // All checks run on the USER'S PHONE — avoiding datacenter IP blocks from
  // Instagram, TikTok, Facebook, etc.
  static const _platforms = <_Platform>[
    // ── Social ────────────────────────────────────────────────────────────────
    _Platform(
      name: 'Instagram',
      urlTemplate: 'https://www.instagram.com/{u}/',
      category: 'Social',
      notFoundBody: "Sorry, this page isn't available",
    ),
    _Platform(
      name: 'TikTok',
      urlTemplate: 'https://www.tiktok.com/@{u}',
      category: 'Social',
      notFoundBody: 'user-not-found',
    ),
    _Platform(
      name: 'Twitter / X',
      urlTemplate: 'https://twitter.com/{u}',
      category: 'Social',
    ),
    _Platform(
      name: 'Facebook',
      urlTemplate: 'https://www.facebook.com/{u}',
      category: 'Social',
    ),
    _Platform(
      name: 'Pinterest',
      urlTemplate: 'https://www.pinterest.com/{u}/',
      category: 'Social',
    ),
    _Platform(
      name: 'Tumblr',
      urlTemplate: 'https://{u}.tumblr.com/',
      category: 'Social',
    ),
    _Platform(
      name: 'Reddit',
      urlTemplate: 'https://www.reddit.com/user/{u}',
      category: 'Social',
    ),
    _Platform(
      name: 'Snapchat',
      urlTemplate: 'https://www.snapchat.com/add/{u}',
      category: 'Social',
    ),
    // ── Video ─────────────────────────────────────────────────────────────────
    _Platform(
      name: 'YouTube',
      urlTemplate: 'https://www.youtube.com/@{u}',
      category: 'Video',
    ),
    _Platform(
      name: 'Twitch',
      urlTemplate: 'https://www.twitch.tv/{u}',
      category: 'Video',
    ),
    _Platform(
      name: 'Dailymotion',
      urlTemplate: 'https://www.dailymotion.com/{u}',
      category: 'Video',
    ),
    // ── Dev ───────────────────────────────────────────────────────────────────
    _Platform(
      name: 'GitHub',
      urlTemplate: 'https://github.com/{u}',
      category: 'Dev',
    ),
    _Platform(
      name: 'GitLab',
      urlTemplate: 'https://gitlab.com/{u}',
      category: 'Dev',
    ),
    _Platform(
      name: 'Dev.to',
      urlTemplate: 'https://dev.to/{u}',
      category: 'Dev',
    ),
    _Platform(
      name: 'Replit',
      urlTemplate: 'https://replit.com/@{u}',
      category: 'Dev',
    ),
    _Platform(
      name: 'CodePen',
      urlTemplate: 'https://codepen.io/{u}',
      category: 'Dev',
    ),
    // ── Gaming ────────────────────────────────────────────────────────────────
    _Platform(
      name: 'Steam',
      urlTemplate: 'https://steamcommunity.com/id/{u}',
      category: 'Gaming',
    ),
    _Platform(
      name: 'Roblox',
      urlTemplate: 'https://www.roblox.com/user.aspx?username={u}',
      category: 'Gaming',
    ),
    _Platform(
      name: 'Chess.com',
      urlTemplate: 'https://www.chess.com/member/{u}',
      category: 'Gaming',
    ),
    // ── Music ─────────────────────────────────────────────────────────────────
    _Platform(
      name: 'SoundCloud',
      urlTemplate: 'https://soundcloud.com/{u}',
      category: 'Music',
    ),
    _Platform(
      name: 'Last.fm',
      urlTemplate: 'https://www.last.fm/user/{u}',
      category: 'Music',
    ),
    _Platform(
      name: 'Spotify',
      urlTemplate: 'https://open.spotify.com/user/{u}',
      category: 'Music',
    ),
    // ── Other ─────────────────────────────────────────────────────────────────
    _Platform(
      name: 'Medium',
      urlTemplate: 'https://medium.com/@{u}',
      category: 'Other',
    ),
    _Platform(
      name: 'Patreon',
      urlTemplate: 'https://www.patreon.com/{u}',
      category: 'Other',
    ),
    _Platform(
      name: 'Telegram',
      urlTemplate: 'https://t.me/{u}',
      category: 'Other',
    ),
    _Platform(
      name: 'Keybase',
      urlTemplate: 'https://keybase.io/{u}',
      category: 'Other',
    ),
    _Platform(
      name: 'Substack',
      urlTemplate: 'https://{u}.substack.com',
      category: 'Other',
    ),
    _Platform(
      name: 'Gravatar',
      urlTemplate: 'https://en.gravatar.com/{u}',
      category: 'Other',
    ),
  ];

  static const _categories = [
    'All', 'Social', 'Video', 'Dev', 'Gaming', 'Music', 'Other',
  ];

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    AdService.instance.init();
    AdService.instance.addListener(_onAdChanged);
    _initBanner();
    _results = _platforms.map((p) => _Result(platform: p)).toList();
  }

  @override
  void dispose() {
    AdService.instance.removeListener(_onAdChanged);
    _bannerAd?.dispose();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── Ad helpers (mandatory pattern) ────────────────────────────────────────

  void _onAdChanged() {
    if (!mounted) return;
    if (AdService.instance.adsRemoved && _bannerAd != null) {
      _bannerAd?.dispose();
      setState(() { _bannerAd = null; _bannerReady = false; });
    }
  }

  void _initBanner() {
    if (AdService.instance.adsRemoved) return;
    _bannerAd?.dispose(); _bannerAd = null; _bannerReady = false;
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

  // ── Filtered list ──────────────────────────────────────────────────────────

  List<_Result> get _filtered {
    if (_selectedCategory == 'All') return _results;
    return _results
        .where((r) => r.platform.category == _selectedCategory)
        .toList();
  }

  // ── Search ─────────────────────────────────────────────────────────────────

  Future<void> _startSearch() async {
    final username = _controller.text.trim().replaceAll('@', '');
    if (username.isEmpty || _isSearching) return;

    HapticFeedback.mediumImpact();
    FocusScope.of(context).unfocus();

    setState(() {
      _currentUsername = username;
      _isSearching     = true;
      for (final r in _results) {
        r.status     = _Status.idle;
        r.profileUrl = null;
      }
    });

    for (int i = 0; i < _results.length; i++) {
      if (!mounted || !_isSearching) break;

      setState(() => _results[i].status = _Status.checking);
      await _checkPlatform(_results[i], username);
      if (mounted) setState(() {});

      if (i < _results.length - 1) {
        await Future.delayed(const Duration(milliseconds: 120));
      }
    }

    if (mounted) {
      setState(() => _isSearching = false);
      HapticFeedback.mediumImpact();

      // Interstitial fires after all checks complete
      Future.delayed(const Duration(milliseconds: 600), () {
        if (!AdService.instance.adsRemoved) AdService.instance.showInterstitial();
      });
    }
  }

  Future<void> _checkPlatform(_Result result, String username) async {
    final url = result.platform.urlTemplate.replaceAll('{u}', username);
    result.profileUrl = url;

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 11; Infinix Hot11s) '
              'AppleWebKit/537.36 (KHTML, like Gecko) '
              'Chrome/120.0.0.0 Mobile Safari/537.36',
          'Accept-Language': 'en-US,en;q=0.9',
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        },
      ).timeout(const Duration(seconds: 9));

      if (response.statusCode == 200) {
        final notFound = result.platform.notFoundBody;
        if (notFound != null && response.body.contains(notFound)) {
          result.status = _Status.notFound;
        } else {
          result.status = _Status.found;
        }
      } else if (response.statusCode == 404 || response.statusCode == 410) {
        result.status = _Status.notFound;
      } else {
        // 302, 403, 429, etc. — treat as error (inconclusive)
        result.status = _Status.error;
      }
    } catch (_) {
      result.status = _Status.error;
    }
  }

  void _stopSearch() {
    HapticFeedback.lightImpact();
    setState(() => _isSearching = false);
  }

  void _reset() {
    HapticFeedback.mediumImpact();
    if (!AdService.instance.adsRemoved) AdService.instance.showInterstitial();
    _controller.clear();
    setState(() {
      _currentUsername  = '';
      _isSearching      = false;
      _selectedCategory = 'All';
      for (final r in _results) {
        r.status     = _Status.idle;
        r.profileUrl = null;
      }
    });
  }

  void _copyResults() {
    if (!AdService.instance.adsRemoved) AdService.instance.showInterstitial();

    final found =
        _results.where((r) => r.status == _Status.found).toList();
    if (found.isEmpty) {
      _snack('No results found yet.');
      return;
    }

    final buf = StringBuffer()
      ..writeln('Username: @$_currentUsername')
      ..writeln('Found on ${found.length} / ${_platforms.length} platforms:\n');
    for (final r in found) {
      buf.writeln('✅ ${r.platform.name}: ${r.profileUrl}');
    }

    Clipboard.setData(ClipboardData(text: buf.toString()));
    HapticFeedback.selectionClick();
    _snack('Copied ${found.length} results!');
  }

  void _snack(String msg) {
    if (!mounted) return;
    final c = context.c;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior:        SnackBarBehavior.floating,
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md)),
      margin:   const EdgeInsets.fromLTRB(16, 0, 16, 16),
      duration: const Duration(seconds: 2),
      content:  Text(msg, style: TextStyle(color: c.textPrimary)),
    ));
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return Scaffold(
      backgroundColor:     c.background,
      bottomNavigationBar: _buildBannerAd(),
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(c),
            Expanded(
              child: CustomScrollView(
                controller: _scrollController,
                physics:    const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: _buildSearchBar(c)),
                  if (_currentUsername.isNotEmpty) ...[
                    SliverToBoxAdapter(child: _buildStats(c)),
                    SliverToBoxAdapter(child: _buildCategoryFilter(c)),
                    const SliverToBoxAdapter(child: SizedBox(height: 12)),
                  ],
                  if (_currentUsername.isEmpty)
                    SliverFillRemaining(
                        hasScrollBody: false, child: _buildEmptyState(c)),
                  if (_currentUsername.isNotEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (_, i) => _buildTile(_filtered[i], c, i),
                          childCount: _filtered.length,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── App bar ────────────────────────────────────────────────────────────────

  Widget _buildAppBar(XissinColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color:        c.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border:       Border.all(color: c.border),
              ),
              child: Icon(Icons.arrow_back_ios_new_rounded,
                  size: 18, color: c.textPrimary),
            ),
          ),
          const SizedBox(width: 14),
          ShaderMask(
            shaderCallback: (b) =>
                LinearGradient(colors: [c.primary, c.secondary])
                    .createShader(b),
            child: const Text(
              'Username Tracker',
              style: TextStyle(
                color:      Colors.white,
                fontSize:   20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Spacer(),
          if (_currentUsername.isNotEmpty) ...[
            _IconBtn(
              icon: Icons.copy_rounded,
              c:    c,
              onTap: _copyResults,
            ),
            const SizedBox(width: 8),
            _IconBtn(
              icon: Icons.refresh_rounded,
              c:    c,
              onTap: _reset,
            ),
          ],
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 400.ms)
        .slideY(begin: -0.1, end: 0, duration: 400.ms);
  }

  // ── Search bar ─────────────────────────────────────────────────────────────

  Widget _buildSearchBar(XissinColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                color:        c.surface,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border:       Border.all(color: c.border),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  Text(
                    '@',
                    style: TextStyle(
                      color:      c.primary,
                      fontSize:   18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller:      _controller,
                      enabled:         !_isSearching,
                      style:           TextStyle(color: c.textPrimary, fontSize: 15),
                      textInputAction: TextInputAction.search,
                      onSubmitted:     (_) => _startSearch(),
                      decoration: InputDecoration(
                        hintText:  'Enter username...',
                        hintStyle: TextStyle(color: c.textHint, fontSize: 14),
                        border:    InputBorder.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _isSearching ? _stopSearch : _startSearch,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 52, height: 52,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _isSearching
                      ? [Colors.red.shade400, Colors.red.shade700]
                      : [c.primary, c.secondary],
                ),
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: Icon(
                _isSearching
                    ? Icons.stop_rounded
                    : Icons.person_search_rounded,
                color: Colors.white,
                size:  22,
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms, delay: 100.ms);
  }

  // ── Stats bar ──────────────────────────────────────────────────────────────

  Widget _buildStats(XissinColors c) {
    final total    = _platforms.length;
    final progress = _checked / total;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color:        c.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border:       Border.all(color: c.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _StatChip(
                  label: 'Found',
                  value: '$_found',
                  color: const Color(0xFF2ECC71),
                ),
                const SizedBox(width: 8),
                _StatChip(
                  label: 'Checked',
                  value: '$_checked / $total',
                  color: c.primary,
                ),
                const Spacer(),
                if (_isSearching)
                  SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:  AlwaysStoppedAnimation(c.primary),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value:           progress,
                backgroundColor: c.border,
                valueColor:      AlwaysStoppedAnimation(c.primary),
                minHeight:       4,
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  // ── Category filter ────────────────────────────────────────────────────────

  Widget _buildCategoryFilter(XissinColors c) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding:         const EdgeInsets.symmetric(horizontal: 16),
        itemCount:       _categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final cat      = _categories[i];
          final selected = cat == _selectedCategory;
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _selectedCategory = cat);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: selected
                    ? c.primary.withOpacity(0.15)
                    : c.surface,
                borderRadius: BorderRadius.circular(AppRadius.full),
                border: Border.all(
                  color: selected ? c.primary : c.border,
                ),
              ),
              child: Text(
                cat,
                style: TextStyle(
                  color:      selected ? c.primary : c.textSecondary,
                  fontSize:   12,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Result tile ────────────────────────────────────────────────────────────

  Widget _buildTile(_Result result, XissinColors c, int index) {
    Color    statusColor;
    IconData statusIcon;
    String   statusText;

    switch (result.status) {
      case _Status.found:
        statusColor = const Color(0xFF2ECC71);
        statusIcon  = Icons.check_circle_rounded;
        statusText  = 'Found';
        break;
      case _Status.notFound:
        statusColor = c.textHint;
        statusIcon  = Icons.cancel_rounded;
        statusText  = 'Not Found';
        break;
      case _Status.checking:
        statusColor = c.primary;
        statusIcon  = Icons.hourglass_empty_rounded;
        statusText  = 'Checking...';
        break;
      case _Status.error:
        statusColor = const Color(0xFFFFA726);
        statusIcon  = Icons.error_outline_rounded;
        statusText  = 'Timeout';
        break;
      case _Status.idle:
        statusColor = c.textHint.withOpacity(0.35);
        statusIcon  = Icons.radio_button_unchecked_rounded;
        statusText  = 'Waiting';
        break;
    }

    final isFound = result.status == _Status.found;

    return GestureDetector(
      onTap: isFound && result.profileUrl != null
          ? () {
              Clipboard.setData(
                  ClipboardData(text: result.profileUrl!));
              HapticFeedback.selectionClick();
              _snack('${result.platform.name} URL copied!');
            }
          : null,
      child: Container(
        margin:  const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color:        c.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: isFound
                ? const Color(0xFF2ECC71).withOpacity(0.35)
                : c.border,
          ),
        ),
        child: Row(
          children: [
            // Icon / spinner
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color:        statusColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: result.status == _Status.checking
                  ? Padding(
                      padding: const EdgeInsets.all(10),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:  AlwaysStoppedAnimation(c.primary),
                      ),
                    )
                  : Icon(statusIcon, color: statusColor, size: 18),
            ),
            const SizedBox(width: 12),
            // Name + category
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.platform.name,
                    style: TextStyle(
                      color:      c.textPrimary,
                      fontSize:   14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    result.platform.category,
                    style: TextStyle(color: c.textHint, fontSize: 11),
                  ),
                ],
              ),
            ),
            // Status label
            Text(
              statusText,
              style: TextStyle(
                color:      statusColor,
                fontSize:   12,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (isFound) ...[
              const SizedBox(width: 6),
              Icon(Icons.copy_rounded, size: 13, color: c.textHint),
            ],
          ],
        ),
      ),
    ).animate(delay: Duration(milliseconds: 20 * index))
        .fadeIn(duration: 200.ms);
  }

  // ── Empty state ────────────────────────────────────────────────────────────

  Widget _buildEmptyState(XissinColors c) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 84, height: 84,
              decoration: BoxDecoration(
                color:  c.primary.withOpacity(0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.person_search_rounded,
                size:  44,
                color: c.primary.withOpacity(0.70),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Username Tracker',
              style: TextStyle(
                color:      c.textPrimary,
                fontSize:   20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Find where a username exists across '
              '${_platforms.length} platforms instantly.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: c.textSecondary, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 10),
            Text(
              'Social · Video · Dev · Gaming · Music',
              style: TextStyle(color: c.textHint, fontSize: 12),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 500.ms, delay: 200.ms);
  }
}

// ── Helper widgets ────────────────────────────────────────────────────────────

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final XissinColors c;
  final VoidCallback onTap;

  const _IconBtn({required this.icon, required this.c, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color:        c.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border:       Border.all(color: c.border),
        ),
        child: Icon(icon, size: 18, color: c.textSecondary),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color  color;

  const _StatChip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color:        color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(width: 4),
          Text(label,
              style:
                  TextStyle(color: color.withOpacity(0.7), fontSize: 11)),
        ],
      ),
    );
  }
}
