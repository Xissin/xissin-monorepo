// ─────────────────────────────────────────────────────────────────────────────
// app/lib/screens/username_tracker_screen.dart
// Username Tracker v3.0
//   • Auto-converts spaces → _ and capital letters → lowercase while typing
//   • Smart variant search: underscore / hyphen / no-sep / dot / camelCase
//   • Each platform tries ALL variants — shows which one matched
//   • Search history (last 5 searches, tap to re-run)
//   • Variant summary bar after search completes
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../services/ad_service.dart';
import '../services/api_service.dart';

// ── Platform model ────────────────────────────────────────────────────────────

class _Platform {
  final String       name;
  final String       urlTemplate;
  final String       category;
  final String?      notFoundBody;
  final List<String> notFoundBodyAny;
  final Duration     timeout;
  final bool         mobileCheck;

  const _Platform({
    required this.name,
    required this.urlTemplate,
    required this.category,
    this.notFoundBody,
    this.notFoundBodyAny = const [],
    this.timeout         = const Duration(seconds: 10),
    this.mobileCheck     = false,
  });
}

// ── Result model ──────────────────────────────────────────────────────────────

enum _Status { idle, checking, found, notFound, error }

class _Result {
  final _Platform platform;
  _Status status;
  String? profileUrl;
  String? foundVariant; // which variant was matched (e.g. "nathaniel-reformina")

  _Result({required this.platform, this.status = _Status.idle});
}

// ── Screen ────────────────────────────────────────────────────────────────────

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

  // variants generated from the typed username
  List<String> _variants = [];

  // search history (in-memory, last 5)
  final List<String> _history = [];

  late List<_Result> _results;

  // ── Stats ──────────────────────────────────────────────────────────────────
  int get _found    => _results.where((r) => r.status == _Status.found).length;
  int get _notFound => _results.where((r) => r.status == _Status.notFound).length;
  int get _errors   => _results.where((r) => r.status == _Status.error).length;
  int get _checked  => _results.where(
      (r) => r.status != _Status.idle && r.status != _Status.checking).length;

  // ── Platform list ──────────────────────────────────────────────────────────
  static const _platforms = <_Platform>[
    // ── Social ────────────────────────────────────────────────────────────────
    _Platform(
      name: 'Instagram',
      urlTemplate: 'https://www.instagram.com/{u}/',
      category: 'Social',
      notFoundBody: "Sorry, this page isn't available",
      timeout: Duration(seconds: 12),
    ),
    _Platform(
      name: 'TikTok',
      urlTemplate: 'https://www.tiktok.com/@{u}',
      category: 'Social',
      notFoundBody: 'user-not-found',
      timeout: Duration(seconds: 12),
    ),
    _Platform(
      name: 'Twitter / X',
      urlTemplate: 'https://twitter.com/{u}',
      category: 'Social',
      timeout: Duration(seconds: 12),
    ),
    _Platform(
      name: 'Facebook',
      urlTemplate: 'https://m.facebook.com/{u}',
      category: 'Social',
      notFoundBodyAny: [
        "isn't available",
        'Page Not Found',
        'This content isn',
        'not available',
        'page you requested cannot be found',
        'profile is unavailable',
      ],
      timeout: Duration(seconds: 18),
      mobileCheck: true,
    ),
    _Platform(
      name: 'Pinterest',
      urlTemplate: 'https://www.pinterest.com/{u}/',
      category: 'Social',
      notFoundBodyAny: [
        "Sorry! We couldn",
        "This page doesn",
        "Hmm...we couldn",
        "couldn't find that page",
      ],
      timeout: Duration(seconds: 12),
    ),
    _Platform(
      name: 'Tumblr',
      urlTemplate: 'https://{u}.tumblr.com/',
      category: 'Social',
      notFoundBodyAny: ["There's nothing here.", 'Not Found'],
      timeout: Duration(seconds: 10),
    ),
    _Platform(
      name: 'Reddit',
      urlTemplate: 'https://www.reddit.com/user/{u}',
      category: 'Social',
      notFoundBodyAny: [
        'page not found',
        "Sorry, nobody on Reddit goes by that name",
      ],
      timeout: Duration(seconds: 10),
    ),
    _Platform(
      name: 'Snapchat',
      urlTemplate: 'https://www.snapchat.com/add/{u}',
      category: 'Social',
      notFoundBodyAny: [
        "Sorry, we can't find that page",
        'Page Not Found',
        'not found',
      ],
      timeout: Duration(seconds: 12),
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

  static const Map<String, IconData> _catIcons = {
    'Social': Icons.people_alt_rounded,
    'Video':  Icons.play_circle_rounded,
    'Dev':    Icons.code_rounded,
    'Gaming': Icons.sports_esports_rounded,
    'Music':  Icons.music_note_rounded,
    'Other':  Icons.more_horiz_rounded,
  };

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

  // ── Ad helpers ─────────────────────────────────────────────────────────────

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

  // ── Smart variant generation ───────────────────────────────────────────────
  //
  // Input "nathaniel reformina"  or  "nathaniel_reformina"  or  "NathanielReformina"
  // → splits into word parts → generates up to 5 variants
  //
  // Rules:
  //  1. Split on: spaces, underscores, hyphens, dots
  //  2. Also split CamelCase: "NathanielReformina" → ["nathaniel","reformina"]
  //  3. Generate: underscore, hyphen, no-separator, dot, camelCase variants
  //  4. Deduplicate + remove empty

  List<String> _generateVariants(String raw) {
    // Normalise: trim, remove leading @
    String input = raw.trim().replaceAll('@', '');
    if (input.isEmpty) return [];

    // Split CamelCase FIRST (before lowercasing)
    // "NathanielReformina" → "Nathaniel_Reformina"
    final camelSplit = input.replaceAllMapped(
      RegExp(r'(?<=[a-z])([A-Z])'),
      (m) => '_${m.group(1)}',
    );

    // Lowercase everything
    final lower = camelSplit.toLowerCase();

    // Split on any separator: space, _, -, .
    final parts = lower
        .split(RegExp(r'[\s_\-\.]+'))
        .where((p) => p.isNotEmpty)
        .toList();

    if (parts.isEmpty) return [lower];

    // Only generate multi-variants when there are 2+ parts
    if (parts.length == 1) return [parts[0]];

    final noSep      = parts.join('');
    final underscore = parts.join('_');
    final hyphen     = parts.join('-');
    final dot        = parts.join('.');
    // camelCase: nathanielReformina
    final camel = parts[0] +
        parts.skip(1).map((p) {
          if (p.isEmpty) return '';
          return p[0].toUpperCase() + p.substring(1);
        }).join('');

    // Return in priority order — try underscore first (most common)
    final seen   = <String>{};
    final result = <String>[];
    for (final v in [underscore, hyphen, noSep, dot, camel]) {
      if (v.isNotEmpty && seen.add(v)) result.add(v);
    }
    return result;
  }

  // ── Sorting helpers ────────────────────────────────────────────────────────

  static const Map<_Status, int> _sortOrder = {
    _Status.found:    0,
    _Status.checking: 1,
    _Status.notFound: 2,
    _Status.error:    3,
    _Status.idle:     4,
  };

  List<_Result> _resultsForCategory(String cat) {
    final list = _results
        .where((r) => r.platform.category == cat)
        .toList()
      ..sort((a, b) =>
          (_sortOrder[a.status] ?? 4).compareTo(_sortOrder[b.status] ?? 4));
    return list;
  }

  List<String> get _activeCategories =>
      _categories.where((c) => c != 'All').toList();

  // ── Variant hit summary ────────────────────────────────────────────────────
  // Returns map of variant → how many platforms found it

  Map<String, int> get _variantHits {
    final map = <String, int>{};
    for (final r in _results) {
      if (r.status == _Status.found && r.foundVariant != null) {
        map[r.foundVariant!] = (map[r.foundVariant!] ?? 0) + 1;
      }
    }
    return map;
  }

  // ── Search ─────────────────────────────────────────────────────────────────

  Future<void> _startSearch([String? overrideInput]) async {
    final raw = (overrideInput ?? _controller.text).trim().replaceAll('@', '');
    if (raw.isEmpty || _isSearching) return;

    final variants = _generateVariants(raw);
    if (variants.isEmpty) {
      _snack('Could not parse username. Try again.');
      return;
    }

    HapticFeedback.mediumImpact();
    FocusScope.of(context).unfocus();

    // Update controller to show cleaned primary variant
    if (overrideInput == null) {
      _controller.text = variants.first;
      _controller.selection =
          TextSelection.collapsed(offset: variants.first.length);
    }

    // Add to history
    final histKey = variants.first;
    _history.remove(histKey);
    _history.insert(0, histKey);
    if (_history.length > 5) _history.removeLast();

    setState(() {
      _currentUsername  = variants.first;
      _variants         = variants;
      _isSearching      = true;
      _selectedCategory = 'All';
      for (final r in _results) {
        r.status       = _Status.idle;
        r.profileUrl   = null;
        r.foundVariant = null;
      }
    });

    // Search each platform sequentially, trying all variants per platform
    for (int i = 0; i < _results.length; i++) {
      if (!mounted || !_isSearching) break;
      setState(() => _results[i].status = _Status.checking);
      await _checkPlatformVariants(_results[i], variants);
      if (mounted) setState(() {});
      if (i < _results.length - 1) {
        await Future.delayed(const Duration(milliseconds: 80));
      }
    }

    if (mounted) {
      setState(() => _isSearching = false);
      HapticFeedback.mediumImpact();

      final foundOn = _results
          .where((r) => r.status == _Status.found)
          .map((r) => r.platform.name)
          .toList();
      ApiService.logUsernameSearch(
        username:     variants.first,
        foundOn:      foundOn,
        totalChecked: _results.length,
      );

      Future.delayed(const Duration(milliseconds: 600), () {
        if (!AdService.instance.adsRemoved) {
          AdService.instance.showInterstitial();
        }
      });
    }
  }

  // ── Per-platform variant check ─────────────────────────────────────────────
  // Tries each variant in order — stops at the first found.
  // On timeout / error for one variant, continues to the next.

  Future<void> _checkPlatformVariants(
      _Result result, List<String> variants) async {
    for (final variant in variants) {
      final status = await _tryVariant(result.platform, variant);

      if (status == _Status.found) {
        final displayUrl = result.platform.urlTemplate
            .replaceAll('{u}', variant)
            .replaceAll('m.facebook.com', 'www.facebook.com');
        result.profileUrl   = displayUrl;
        result.foundVariant = variant;
        result.status       = _Status.found;
        return;
      }
      if (status == _Status.notFound) {
        // Not found with this variant → try next variant
        continue;
      }
      // Error / timeout → also try next variant
    }

    // None of the variants found it
    // Check if last variant returned notFound or error
    final lastStatus = await _tryVariant(result.platform, variants.last);
    if (lastStatus == _Status.notFound) {
      result.status = _Status.notFound;
    } else {
      // Set a fallback URL using primary variant
      result.profileUrl = result.platform.urlTemplate
          .replaceAll('{u}', variants.first)
          .replaceAll('m.facebook.com', 'www.facebook.com');
      result.status = _Status.error;
    }
  }

  // ── Single variant HTTP check ──────────────────────────────────────────────

  Future<_Status> _tryVariant(_Platform platform, String username) async {
    final requestUrl = platform.urlTemplate.replaceAll('{u}', username);

    final headers = <String, String>{
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 11; Infinix X689B) '
          'AppleWebKit/537.36 (KHTML, like Gecko) '
          'Chrome/120.0.6099.144 Mobile Safari/537.36',
      'Accept-Language': 'en-US,en;q=0.9',
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,'
          'image/avif,image/webp,*/*;q=0.8',
      'Accept-Encoding': 'gzip, deflate',
      'Connection':      'keep-alive',
      if (platform.mobileCheck) ...{
        'X-Requested-With': 'com.facebook.katana',
        'Sec-Fetch-Dest':   'document',
        'Sec-Fetch-Mode':   'navigate',
      },
    };

    try {
      final response = await http
          .get(Uri.parse(requestUrl), headers: headers)
          .timeout(platform.timeout);

      final body = response.body;
      final code = response.statusCode;

      if (code == 200) {
        final nf = platform.notFoundBody;
        if (nf != null && body.contains(nf)) return _Status.notFound;

        final anyList = platform.notFoundBodyAny;
        if (anyList.isNotEmpty) {
          final bodyLower = body.toLowerCase();
          if (anyList.any((s) => bodyLower.contains(s.toLowerCase()))) {
            return _Status.notFound;
          }
        }
        return _Status.found;

      } else if (code == 301 || code == 302) {
        final location = response.headers['location'] ?? '';
        if (platform.mobileCheck) {
          return (location.contains('login') || location.contains('/r.php'))
              ? _Status.error
              : _Status.found;
        }
        return _Status.error;

      } else if (code == 404 || code == 410) {
        return _Status.notFound;

      } else if (code == 429) {
        await Future.delayed(const Duration(seconds: 3));
        try {
          final retry = await http
              .get(Uri.parse(requestUrl), headers: headers)
              .timeout(platform.timeout);
          if (retry.statusCode == 200) return _Status.found;
          if (retry.statusCode == 404) return _Status.notFound;
        } catch (_) {}
        return _Status.error;

      } else {
        return _Status.error;
      }
    } catch (_) {
      return _Status.error;
    }
  }

  // ── Actions ────────────────────────────────────────────────────────────────

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
      _variants         = [];
      _isSearching      = false;
      _selectedCategory = 'All';
      for (final r in _results) {
        r.status       = _Status.idle;
        r.profileUrl   = null;
        r.foundVariant = null;
      }
    });
  }

  void _copyResults() {
    if (!AdService.instance.adsRemoved) AdService.instance.showInterstitial();
    final found = _results.where((r) => r.status == _Status.found).toList();
    if (found.isEmpty) { _snack('No results found yet.'); return; }

    final buf = StringBuffer()
      ..writeln('Xissin Username Tracker')
      ..writeln('Primary  : @$_currentUsername')
      ..writeln('Variants : ${_variants.join(' | ')}')
      ..writeln('Found on : ${found.length} / ${_platforms.length} platforms\n');

    for (final cat in _categories.where((c) => c != 'All')) {
      final catFound =
          found.where((r) => r.platform.category == cat).toList();
      if (catFound.isEmpty) continue;
      buf.writeln('-- $cat --');
      for (final r in catFound) {
        final varLabel = r.foundVariant != null
            ? ' (as @${r.foundVariant})'
            : '';
        buf.writeln('${r.platform.name}$varLabel');
        buf.writeln('  ${r.profileUrl}');
      }
      buf.writeln();
    }

    Clipboard.setData(ClipboardData(text: buf.toString()));
    HapticFeedback.selectionClick();
    _snack('Copied ${found.length} results!');
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _snack('Could not open URL.');
    }
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

                  // History chips (only when no active search)
                  if (_currentUsername.isEmpty && _history.isNotEmpty)
                    SliverToBoxAdapter(child: _buildHistory(c)),

                  if (_currentUsername.isNotEmpty) ...[
                    SliverToBoxAdapter(child: _buildStats(c)),
                    // Variant pills
                    if (_variants.length > 1)
                      SliverToBoxAdapter(child: _buildVariantPills(c)),
                    // Variant summary (only when done)
                    if (!_isSearching && _found > 0)
                      SliverToBoxAdapter(child: _buildVariantSummary(c)),
                    SliverToBoxAdapter(child: _buildCategoryFilter(c)),
                    const SliverToBoxAdapter(child: SizedBox(height: 8)),
                  ],

                  if (_currentUsername.isEmpty)
                    SliverFillRemaining(
                        hasScrollBody: false,
                        child: _buildEmptyState(c)),

                  if (_currentUsername.isNotEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate(
                          _buildGroupedResults(c),
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
                  color: Colors.white, fontSize: 20,
                  fontWeight: FontWeight.bold),
            ),
          ),
          const Spacer(),
          if (_currentUsername.isNotEmpty) ...[
            _IconBtn(icon: Icons.copy_rounded,    c: c, onTap: _copyResults),
            const SizedBox(width: 8),
            _IconBtn(icon: Icons.refresh_rounded, c: c, onTap: _reset),
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
    // Live preview of what variants will be searched
    final previewText = _controller.text.isEmpty
        ? null
        : _generateVariants(_controller.text);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                      Text('@',
                          style: TextStyle(
                              color: c.primary, fontSize: 18,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          controller:      _controller,
                          enabled:         !_isSearching,
                          style:           TextStyle(
                              color: c.textPrimary, fontSize: 15),
                          textInputAction: TextInputAction.search,
                          onSubmitted:     (_) => _startSearch(),
                          onChanged:       (_) => setState(() {}),
                          // Smart formatter:
                          //   • space  → underscore
                          //   • capital → lowercase
                          inputFormatters: [
                            TextInputFormatter.withFunction(
                              (oldValue, newValue) {
                                final cleaned = newValue.text
                                    .toLowerCase()
                                    .replaceAll(' ', '_');
                                return newValue.copyWith(
                                  text: cleaned,
                                  selection: TextSelection.collapsed(
                                      offset: cleaned.length),
                                );
                              },
                            ),
                          ],
                          decoration: InputDecoration(
                            hintText: 'e.g. nathaniel_reformina',
                            hintStyle: TextStyle(
                                color: c.textHint, fontSize: 13),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      // Clear button
                      if (_controller.text.isNotEmpty && !_isSearching)
                        GestureDetector(
                          onTap: () {
                            _controller.clear();
                            setState(() {});
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Icon(Icons.close_rounded,
                                size: 16, color: c.textHint),
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
                    color: Colors.white, size: 22,
                  ),
                ),
              ),
            ],
          ),

          // Live variant preview (shown while typing, before search)
          if (previewText != null &&
              previewText.length > 1 &&
              _currentUsername.isEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                Text(
                  'Will search:',
                  style: TextStyle(color: c.textHint, fontSize: 11),
                ),
                ...previewText.map((v) => Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: c.primary.withOpacity(0.10),
                    borderRadius:
                        BorderRadius.circular(AppRadius.full),
                    border: Border.all(
                        color: c.primary.withOpacity(0.25)),
                  ),
                  child: Text(
                    '@$v',
                    style: TextStyle(
                        color:      c.primary,
                        fontSize:   11,
                        fontWeight: FontWeight.w600),
                  ),
                )),
              ],
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(
                'Auto-fixes spaces & caps  •  Checks ${_platforms.length} platforms',
                style: TextStyle(color: c.textHint, fontSize: 11),
              ),
            ),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 400.ms, delay: 100.ms);
  }

  // ── Search history ─────────────────────────────────────────────────────────

  Widget _buildHistory(XissinColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history_rounded, size: 14, color: c.textHint),
              const SizedBox(width: 6),
              Text(
                'Recent searches',
                style: TextStyle(color: c.textHint, fontSize: 12),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _history.clear()),
                child: Text(
                  'Clear',
                  style: TextStyle(
                      color: c.primary, fontSize: 11,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: _history.map((h) {
              return GestureDetector(
                onTap: () {
                  _controller.text = h;
                  _controller.selection =
                      TextSelection.collapsed(offset: h.length);
                  setState(() {});
                  _startSearch(h);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color:        c.surface,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    border:       Border.all(color: c.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history_rounded,
                          size: 12, color: c.textHint),
                      const SizedBox(width: 6),
                      Text(
                        '@$h',
                        style: TextStyle(
                            color:      c.textSecondary,
                            fontSize:   12,
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  // ── Stats bar ──────────────────────────────────────────────────────────────

  Widget _buildStats(XissinColors c) {
    final total    = _platforms.length;
    final progress = total == 0 ? 0.0 : _checked / total;
    final pct      = (progress * 100).round();

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
                Icon(Icons.person_search_rounded,
                    size: 15, color: c.textHint),
                const SizedBox(width: 6),
                Text(
                  '@$_currentUsername',
                  style: TextStyle(
                      color: c.textPrimary, fontSize: 14,
                      fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_isSearching) ...[
                  SizedBox(
                    width: 13, height: 13,
                    child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(c.primary)),
                  ),
                  const SizedBox(width: 6),
                  Text('Scanning...',
                      style: TextStyle(color: c.primary, fontSize: 12)),
                ] else if (_checked == total) ...[
                  const Icon(Icons.check_circle_rounded,
                      size: 15, color: Color(0xFF2ECC71)),
                  const SizedBox(width: 5),
                  const Text('Done',
                      style: TextStyle(
                          color: Color(0xFF2ECC71), fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value:           progress,
                      backgroundColor: c.border,
                      valueColor:      AlwaysStoppedAnimation(c.primary),
                      minHeight:       5,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '$_checked/$total ($pct%)',
                  style: TextStyle(
                      color: c.textHint, fontSize: 11,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _StatChip(
                  icon:  Icons.check_circle_rounded,
                  label: 'Found',
                  value: '$_found',
                  color: const Color(0xFF2ECC71),
                ),
                const SizedBox(width: 8),
                _StatChip(
                  icon:  Icons.cancel_rounded,
                  label: 'Not Found',
                  value: '$_notFound',
                  color: c.textHint,
                ),
                const SizedBox(width: 8),
                _StatChip(
                  icon:  Icons.error_outline_rounded,
                  label: 'Timeout',
                  value: '$_errors',
                  color: const Color(0xFFFFA726),
                ),
              ],
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  // ── Variant pills (shown during and after search) ─────────────────────────

  Widget _buildVariantPills(XissinColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_fix_high_rounded,
                  size: 13, color: c.textHint),
              const SizedBox(width: 5),
              Text(
                'Searching ${_variants.length} variants simultaneously',
                style: TextStyle(color: c.textHint, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _variants.map((v) {
              final hits = _variantHits[v] ?? 0;
              final isTop = hits > 0 &&
                  hits ==
                      (_variantHits.values.isEmpty
                          ? 0
                          : _variantHits.values.reduce((a, b) => a > b ? a : b));
              return Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: hits > 0
                      ? const Color(0xFF2ECC71).withOpacity(0.10)
                      : c.surface,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  border: Border.all(
                    color: hits > 0
                        ? const Color(0xFF2ECC71).withOpacity(0.35)
                        : c.border,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isTop)
                      const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: Icon(Icons.star_rounded,
                            size: 10, color: Color(0xFF2ECC71)),
                      ),
                    Text(
                      '@$v',
                      style: TextStyle(
                        color: hits > 0
                            ? const Color(0xFF2ECC71)
                            : c.textSecondary,
                        fontSize:   11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (hits > 0) ...[
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2ECC71).withOpacity(0.20),
                          borderRadius:
                              BorderRadius.circular(AppRadius.full),
                        ),
                        child: Text(
                          '$hits',
                          style: const TextStyle(
                              color:      Color(0xFF2ECC71),
                              fontSize:   10,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 250.ms);
  }

  // ── Variant summary bar (shown after search if found > 0) ─────────────────

  Widget _buildVariantSummary(XissinColors c) {
    final hits    = _variantHits;
    if (hits.isEmpty) return const SizedBox.shrink();

    // Sort by hit count desc
    final sorted = hits.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top    = sorted.first;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF2ECC71).withOpacity(0.07),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
              color: const Color(0xFF2ECC71).withOpacity(0.25)),
        ),
        child: Row(
          children: [
            const Icon(Icons.insights_rounded,
                size: 15, color: Color(0xFF2ECC71)),
            const SizedBox(width: 8),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: TextStyle(
                      color: c.textSecondary, fontSize: 12),
                  children: [
                    const TextSpan(text: 'Best match: '),
                    TextSpan(
                      text: '@${top.key}',
                      style: const TextStyle(
                          color:      Color(0xFF2ECC71),
                          fontWeight: FontWeight.bold),
                    ),
                    TextSpan(
                        text:
                            ' found on ${top.value} platform${top.value > 1 ? 's' : ''}'),
                    if (sorted.length > 1) ...[
                      const TextSpan(text: '  ·  '),
                      TextSpan(
                        text: '${sorted.length} variants matched',
                        style: TextStyle(color: c.textHint),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 300.ms, delay: 200.ms);
  }

  // ── Category filter ────────────────────────────────────────────────────────

  Widget _buildCategoryFilter(XissinColors c) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection:  Axis.horizontal,
        padding:          const EdgeInsets.symmetric(horizontal: 16),
        itemCount:        _categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final cat      = _categories[i];
          final selected = cat == _selectedCategory;
          final foundCount = cat == 'All'
              ? _found
              : _results.where((r) =>
                  r.platform.category == cat &&
                  r.status == _Status.found).length;

          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _selectedCategory = cat);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding:  const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: selected
                    ? c.primary.withOpacity(0.15)
                    : c.surface,
                borderRadius:
                    BorderRadius.circular(AppRadius.full),
                border: Border.all(
                    color: selected ? c.primary : c.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    cat,
                    style: TextStyle(
                      color: selected
                          ? c.primary
                          : c.textSecondary,
                      fontSize:   12,
                      fontWeight: selected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  if (foundCount > 0) ...[
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2ECC71)
                            .withOpacity(0.18),
                        borderRadius:
                            BorderRadius.circular(AppRadius.full),
                      ),
                      child: Text(
                        '$foundCount',
                        style: const TextStyle(
                            color:      Color(0xFF2ECC71),
                            fontSize:   10,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Grouped results ────────────────────────────────────────────────────────

  List<Widget> _buildGroupedResults(XissinColors c) {
    final widgets = <Widget>[];

    if (_selectedCategory != 'All') {
      final list = _resultsForCategory(_selectedCategory);
      for (int i = 0; i < list.length; i++) {
        widgets.add(_buildTile(list[i], c, i));
      }
      return widgets;
    }

    int globalIdx = 0;
    for (final cat in _activeCategories) {
      final catResults = _resultsForCategory(cat);
      final catFound   = catResults
          .where((r) => r.status == _Status.found).length;
      final catIcon    = _catIcons[cat] ?? Icons.category_rounded;

      widgets.add(
        Padding(
          padding: EdgeInsets.only(
              top: globalIdx == 0 ? 0 : 16, bottom: 10),
          child: Row(
            children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color:        c.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(catIcon, size: 14, color: c.primary),
              ),
              const SizedBox(width: 8),
              Text(
                cat,
                style: TextStyle(
                  color:         c.textPrimary,
                  fontSize:      13,
                  fontWeight:    FontWeight.bold,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(width: 8),
              if (catFound > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2ECC71).withOpacity(0.15),
                    borderRadius:
                        BorderRadius.circular(AppRadius.full),
                  ),
                  child: Text(
                    '$catFound found',
                    style: const TextStyle(
                        color:      Color(0xFF2ECC71),
                        fontSize:   11,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.only(left: 10),
                  height: 1,
                  color: c.border,
                ),
              ),
            ],
          ),
        ),
      );

      for (int i = 0; i < catResults.length; i++) {
        widgets.add(_buildTile(catResults[i], c, globalIdx + i));
      }
      globalIdx += catResults.length;
    }
    return widgets;
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

    final isFound      = result.status == _Status.found;
    final url          = result.profileUrl ?? '';
    final variantLabel = result.foundVariant != null &&
            result.foundVariant != _currentUsername
        ? result.foundVariant!
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isFound
            ? const Color(0xFF2ECC71).withOpacity(0.04)
            : c.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: isFound
              ? const Color(0xFF2ECC71).withOpacity(0.30)
              : c.border,
          width: isFound ? 1.2 : 1,
        ),
      ),
      child: Column(
        children: [
          // ── Main row ──────────────────────────────────────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(
                12, 11, 12, isFound ? 0 : 11),
            child: Row(
              children: [
                Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: result.status == _Status.checking
                      ? Padding(
                          padding: const EdgeInsets.all(9),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation(c.primary),
                          ),
                        )
                      : Icon(statusIcon,
                          color: statusColor, size: 16),
                ),
                const SizedBox(width: 10),
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
                      // Show which variant matched (if different from primary)
                      if (variantLabel != null)
                        Text(
                          'as @$variantLabel',
                          style: TextStyle(
                              color:    const Color(0xFF2ECC71)
                                  .withOpacity(0.80),
                              fontSize: 10,
                              fontWeight: FontWeight.w500),
                        )
                      else
                        Text(
                          result.platform.category,
                          style: TextStyle(
                              color: c.textHint, fontSize: 11),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius:
                        BorderRadius.circular(AppRadius.full),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      color:      statusColor,
                      fontSize:   11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── URL row (found only) ───────────────────────────────────────
          if (isFound && url.isNotEmpty) ...[
            Divider(height: 1, color: c.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
              child: Row(
                children: [
                  const Icon(Icons.link_rounded,
                      size: 13, color: Color(0xFF2ECC71)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      url,
                      style: const TextStyle(
                        color:           Color(0xFF2ECC71),
                        fontSize:        11,
                        decoration:      TextDecoration.underline,
                        decorationColor: Color(0x882ECC71),
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Copy button
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: url));
                      HapticFeedback.selectionClick();
                      _snack('${result.platform.name} URL copied!');
                    },
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: c.border.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(Icons.copy_rounded,
                          size: 12, color: c.textSecondary),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Open button
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      _openUrl(url);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2ECC71).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.open_in_new_rounded,
                              size: 11, color: Color(0xFF2ECC71)),
                          SizedBox(width: 4),
                          Text(
                            'Open',
                            style: TextStyle(
                                color:      Color(0xFF2ECC71),
                                fontSize:   11,
                                fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    ).animate(delay: Duration(milliseconds: 15 * index))
        .fadeIn(duration: 180.ms);
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
                shape:  BoxShape.circle,
              ),
              child: Icon(Icons.person_search_rounded,
                  size: 44, color: c.primary.withOpacity(0.70)),
            ),
            const SizedBox(height: 20),
            Text(
              'Username Tracker',
              style: TextStyle(
                  color: c.textPrimary, fontSize: 20,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Find where a username exists across '
              '${_platforms.length} platforms instantly.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: c.textSecondary, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 20),
            _FeatureHint(
                icon: Icons.auto_fix_high_rounded,
                text: 'Spaces → auto-fixed  •  Caps → auto-lowercased',
                c: c),
            const SizedBox(height: 8),
            _FeatureHint(
                icon: Icons.copy_all_rounded,
                text: 'Searches 5 variants per platform automatically',
                c: c),
            const SizedBox(height: 8),
            _FeatureHint(
                icon: Icons.open_in_new_rounded,
                text: 'Tap "Open" to visit found profiles directly',
                c: c),
            const SizedBox(height: 8),
            _FeatureHint(
                icon: Icons.history_rounded,
                text: 'Last 5 searches saved for quick re-run',
                c: c),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 500.ms, delay: 200.ms);
  }
}

// ── Helper widgets ────────────────────────────────────────────────────────────

class _IconBtn extends StatelessWidget {
  final IconData     icon;
  final XissinColors c;
  final VoidCallback onTap;
  const _IconBtn(
      {required this.icon, required this.c, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
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

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   value;
  final Color    color;
  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color:        color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(AppRadius.full),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(value,
            style: TextStyle(
                color: color, fontSize: 13,
                fontWeight: FontWeight.bold)),
        const SizedBox(width: 3),
        Text(label,
            style: TextStyle(
                color: color.withOpacity(0.7), fontSize: 10)),
      ],
    ),
  );
}

class _FeatureHint extends StatelessWidget {
  final IconData     icon;
  final String       text;
  final XissinColors c;
  const _FeatureHint(
      {required this.icon, required this.text, required this.c});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: c.textHint),
      const SizedBox(width: 8),
      Flexible(
        child: Text(text,
            style: TextStyle(color: c.textHint, fontSize: 12)),
      ),
    ],
  );
}