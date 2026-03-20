// ============================================================
//  app/lib/screens/ip_tracker_screen.dart
//  🌐 IP Tracker — powered by ip-api.com (free, no key needed)
//  Accepts: raw IP · domain · full URL
//  Calls ip-api.com directly from Flutter (no backend hop needed)
// ============================================================
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/ad_service.dart';
import '../theme/app_theme.dart';

class IpTrackerScreen extends StatefulWidget {
  const IpTrackerScreen({super.key});

  @override
  State<IpTrackerScreen> createState() => _IpTrackerScreenState();
}

class _IpTrackerScreenState extends State<IpTrackerScreen> {

  // ── Ad state ─────────────────────────────────────────────────────────────────
  BannerAd? _bannerAd;
  bool      _bannerReady = false;

  // ── Screen state ─────────────────────────────────────────────────────────────
  final _queryCtrl = TextEditingController();
  bool                    _loading = false;
  Map<String, dynamic>?   _result;
  String?                 _error;

  // ── Constants ─────────────────────────────────────────────────────────────────
  static const _accent  = Color(0xFF00B4D8);
  static const _accent2 = Color(0xFF0077B6);
  static const _fields  =
      'status,message,country,countryCode,regionName,city,zip,'
      'lat,lon,timezone,isp,org,as,query,mobile,proxy,hosting';

  // ── Lifecycle ─────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    AdService.instance.init();
    AdService.instance.addListener(_onAdChanged);
    _initBanner();
  }

  @override
  void dispose() {
    AdService.instance.removeListener(_onAdChanged);
    _bannerAd?.dispose();
    _queryCtrl.dispose();
    super.dispose();
  }

  // ── Banner ────────────────────────────────────────────────────────────────────

  void _onAdChanged() {
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

  // ── Input cleaning ────────────────────────────────────────────────────────────

  String _cleanInput(String raw) {
    var q = raw.trim();
    // Strip protocol
    q = q.replaceAll(RegExp(r'^https?://', caseSensitive: false), '');
    // Strip path / query string / fragment
    q = q.split('/').first;
    q = q.split('?').first;
    q = q.split('#').first;
    // Strip port — but only for domains, not raw IPv4
    final isIpv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(q);
    if (!isIpv4) q = q.split(':').first;
    return q.trim();
  }

  // ── Lookup ────────────────────────────────────────────────────────────────────

  Future<void> _lookup() async {
    final raw = _queryCtrl.text.trim();
    if (raw.isEmpty) return;

    final query = _cleanInput(raw);
    if (query.isEmpty) {
      setState(() => _error = 'Invalid input. Enter an IP, domain, or URL.');
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() { _loading = true; _error = null; _result = null; });

    try {
      final uri = Uri.parse(
          'https://ip-api.com/json/$query?fields=$_fields');
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));

      if (resp.statusCode != 200) {
        throw Exception('Service unavailable (${resp.statusCode})');
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;

      if (data['status'] == 'fail') {
        setState(() {
          _loading = false;
          _error   = data['message'] as String? ?? 'Invalid IP or domain.';
        });
        return;
      }

      setState(() { _loading = false; _result = data; });

      // ── Interstitial AFTER successful result ──────────────────────────────
      Future.delayed(const Duration(milliseconds: 600), () {
        if (!AdService.instance.adsRemoved) AdService.instance.showInterstitial();
      });

    } on Exception catch (e) {
      setState(() {
        _loading = false;
        _error   = e.toString().contains('TimeoutException')
            ? 'Request timed out. Check your internet connection.'
            : 'Lookup failed. Check your internet connection.';
      });
    }
  }

  // ── Url launcher helper ───────────────────────────────────────────────────────

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ── Copy helper ───────────────────────────────────────────────────────────────

  void _copy(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied!'),
        duration: const Duration(seconds: 1),
        backgroundColor: _accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      backgroundColor: c.background,
      bottomNavigationBar: _buildBannerAd(),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: _accent, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _accent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.location_on_rounded,
                color: _accent, size: 18),
          ),
          const SizedBox(width: 10),
          Text('IP Tracker',
              style: TextStyle(
                  color: c.textPrimary, fontSize: 17,
                  fontWeight: FontWeight.w700, letterSpacing: 0.4)),
        ]),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSearchCard(c),
            const SizedBox(height: 16),
            if (_error != null) _buildErrorCard(),
            if (_loading)       _buildLoadingCard(c),
            if (_result != null) ..._buildResultSection(c),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // ── Search Card ───────────────────────────────────────────────────────────────

  Widget _buildSearchCard(XissinColors c) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: c.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: c.border),
      boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(0.1),
          blurRadius: 20, offset: const Offset(0, 8))],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── Input row ──────────────────────────────────────────────────────────
      Row(children: [
        Expanded(
          child: TextField(
            controller: _queryCtrl,
            style: TextStyle(color: c.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'IP, domain, or URL…',
              hintStyle: TextStyle(color: c.textHint, fontSize: 13),
              filled:    true,
              fillColor: c.background,
              border:    OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
              prefixIcon: Icon(Icons.travel_explore_rounded,
                  color: c.textHint, size: 18),
              suffixIcon: _queryCtrl.text.isNotEmpty
                  ? GestureDetector(
                      onTap: () {
                        _queryCtrl.clear();
                        setState(() { _result = null; _error = null; });
                      },
                      child: Icon(Icons.close_rounded,
                          color: c.textHint, size: 16))
                  : null,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 14),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _lookup(),
            textInputAction: TextInputAction.search,
            keyboardType: TextInputType.url,
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: _lookup,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [_accent, _accent2]),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(
                  color: _accent.withOpacity(0.4),
                  blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: const Icon(Icons.my_location_rounded,
                color: Colors.white, size: 20),
          ),
        ),
      ]),
      const SizedBox(height: 14),
      // ── Quick examples ─────────────────────────────────────────────────────
      Text('Examples',
          style: TextStyle(color: c.textHint, fontSize: 10,
              fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 6, children: [
        for (final ex in [
          '8.8.8.8',
          '112.198.0.1',
          'facebook.com',
          'shopee.ph',
          'https://lazada.com.ph',
        ])
          GestureDetector(
            onTap: () {
              _queryCtrl.text = ex;
              setState(() {});
            },
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _accent.withOpacity(0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: _accent.withOpacity(0.25)),
              ),
              child: Text(ex,
                  style: const TextStyle(
                      color: _accent, fontSize: 11)),
            ),
          ),
      ]),
    ]),
  );

  // ── Error Card ────────────────────────────────────────────────────────────────

  Widget _buildErrorCard() => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFFF6B6B).withOpacity(0.1),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
          color: const Color(0xFFFF6B6B).withOpacity(0.3)),
    ),
    child: Row(children: [
      const Icon(Icons.error_outline_rounded,
          color: Color(0xFFFF6B6B), size: 16),
      const SizedBox(width: 8),
      Expanded(child: Text(_error!,
          style: const TextStyle(
              color: Color(0xFFFF6B6B), fontSize: 12))),
    ]),
  );

  // ── Loading Card ──────────────────────────────────────────────────────────────

  Widget _buildLoadingCard(XissinColors c) => Container(
    padding: const EdgeInsets.symmetric(vertical: 32),
    decoration: BoxDecoration(
        color: c.surface, borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.border)),
    child: Column(children: [
      const SizedBox(
        width: 28, height: 28,
        child: CircularProgressIndicator(
            color: _accent, strokeWidth: 2.5),
      ),
      const SizedBox(height: 14),
      Text('Locating…',
          style: TextStyle(color: c.textSecondary, fontSize: 13)),
    ]),
  );

  // ── Result Section ────────────────────────────────────────────────────────────

  List<Widget> _buildResultSection(XissinColors c) {
    final d           = _result!;
    final resolvedIp  = d['query']      as String? ?? '';
    final country     = d['country']    as String? ?? '';
    final countryCode = d['countryCode'] as String? ?? '';
    final regionName  = d['regionName'] as String? ?? '';
    final city        = d['city']       as String? ?? '';
    final zip         = d['zip']        as String? ?? '';
    final lat         = (d['lat']  as num?)?.toDouble() ?? 0.0;
    final lon         = (d['lon']  as num?)?.toDouble() ?? 0.0;
    final timezone    = d['timezone']   as String? ?? '';
    final isp         = d['isp']        as String? ?? '';
    final org         = d['org']        as String? ?? '';
    final asInfo      = d['as']         as String? ?? '';
    final mobile      = d['mobile']     as bool?   ?? false;
    final proxy       = d['proxy']      as bool?   ?? false;
    final hosting     = d['hosting']    as bool?   ?? false;

    final mapsUrl = (lat != 0 || lon != 0)
        ? 'https://www.google.com/maps?q=$lat,$lon'
        : null;

    return [
      // ── Resolved IP chip ───────────────────────────────────────────────────
      Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _accent.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _accent.withOpacity(0.3)),
        ),
        child: Row(children: [
          const Icon(Icons.dns_rounded, color: _accent, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text('Resolved IP',
                  style: TextStyle(
                      color: _accent.withOpacity(0.7),
                      fontSize: 10)),
              Text(resolvedIp,
                  style: const TextStyle(
                      color: _accent, fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8)),
            ]),
          ),
          GestureDetector(
            onTap: () => _copy(resolvedIp, 'IP'),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: _accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.copy_rounded,
                  color: _accent, size: 14),
            ),
          ),
        ]),
      ),

      // ── Location ───────────────────────────────────────────────────────────
      _card(
        c: c, icon: Icons.place_rounded,
        title: 'Location', color: const Color(0xFF2ECC71),
        children: [
          _infoRow(c, '🌍', 'Country',
              countryCode.isNotEmpty
                  ? '$countryCode  $country'
                  : country),
          _infoRow(c, '🗺️', 'Region',
              regionName.isNotEmpty ? regionName : '—'),
          _infoRow(c, '🏙️', 'City',
              city.isNotEmpty ? city : '—'),
          _infoRow(c, '📮', 'ZIP Code',
              zip.isNotEmpty ? zip : '—'),
          _infoRow(c, '🧭', 'Coordinates',
              lat != 0 ? '${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)}' : '—'),
          if (mapsUrl != null) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => _launch(mapsUrl),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    vertical: 11),
                decoration: BoxDecoration(
                  color: const Color(0xFF2ECC71).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: const Color(0xFF2ECC71)
                          .withOpacity(0.3)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.map_rounded,
                        color: Color(0xFF2ECC71), size: 15),
                    SizedBox(width: 6),
                    Text('Open in Google Maps',
                        style: TextStyle(
                            color: Color(0xFF2ECC71),
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),

      // ── Network ────────────────────────────────────────────────────────────
      _card(
        c: c, icon: Icons.cell_tower_rounded,
        title: 'Network', color: _accent,
        children: [
          _infoRow(c, '📡', 'ISP',
              isp.isNotEmpty ? isp : '—'),
          _infoRow(c, '🏢', 'Organization',
              org.isNotEmpty ? org : '—'),
          _infoRow(c, '🔢', 'AS Info',
              asInfo.isNotEmpty ? asInfo : '—'),
          if (isp.isNotEmpty) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _copy(isp, 'ISP'),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _accent.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: _accent.withOpacity(0.2)),
                  ),
                  child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                    Icon(Icons.copy_rounded,
                        color: _accent, size: 11),
                    SizedBox(width: 4),
                    Text('Copy ISP',
                        style: TextStyle(
                            color: _accent, fontSize: 11)),
                  ]),
                ),
              ),
            ),
          ],
        ],
      ),

      // ── Details ────────────────────────────────────────────────────────────
      _card(
        c: c, icon: Icons.manage_search_rounded,
        title: 'Details', color: const Color(0xFFFFA94D),
        children: [
          _infoRow(c, '🕐', 'Timezone',
              timezone.isNotEmpty ? timezone : '—'),
          _flagRow(c, '📱', 'Mobile Connection', mobile),
          _flagRow(c, '🛡️', 'Proxy / VPN',       proxy),
          _flagRow(c, '🖥️', 'Hosting / Datacenter', hosting),
        ],
      ),

      const SizedBox(height: 4),
    ];
  }

  // ── Card builder ──────────────────────────────────────────────────────────────

  Widget _card({
    required XissinColors    c,
    required IconData        icon,
    required String          title,
    required Color           color,
    required List<Widget>    children,
  }) =>
      Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 14),
            ),
            const SizedBox(width: 8),
            Text(title,
                style: TextStyle(
                    color: color, fontSize: 13,
                    fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 12),
          ...children,
        ]),
      );

  // ── Row builders ──────────────────────────────────────────────────────────────

  Widget _infoRow(
      XissinColors c, String emoji, String label, String value) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Text(emoji, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(label,
                  style: TextStyle(
                      color: c.textHint, fontSize: 10)),
              const SizedBox(height: 1),
              Text(value,
                  style: TextStyle(
                      color: c.textPrimary, fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
      );

  Widget _flagRow(XissinColors c, String emoji, String label,
      bool value) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 8),
          Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: c.textSecondary, fontSize: 13))),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: (value
                      ? const Color(0xFFFF6B6B)
                      : const Color(0xFF2ECC71))
                  .withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              value ? 'YES' : 'NO',
              style: TextStyle(
                color: value
                    ? const Color(0xFFFF6B6B)
                    : const Color(0xFF2ECC71),
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ]),
      );
}
