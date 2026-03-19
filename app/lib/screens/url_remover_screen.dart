// ============================================================
//  app/lib/screens/url_remover_screen.dart
//  🔗 URL Remover — 100% local, runs on device, no backend
// ============================================================
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/ad_service.dart';
import '../theme/app_theme.dart';

class UrlRemoverScreen extends StatefulWidget {
  const UrlRemoverScreen({super.key});

  @override
  State<UrlRemoverScreen> createState() => _UrlRemoverScreenState();
}

class _UrlRemoverScreenState extends State<UrlRemoverScreen>
    with TickerProviderStateMixin {

  // ── State ───────────────────────────────────────────────────────────────────
  _Phase  _phase         = _Phase.idle;
  String? _pickedFileName;
  String? _rawContent;
  List<String> _result  = [];
  int    _originalCount = 0;
  double _progress      = 0.0;
  String? _errorMsg;
  File?  _outputFile;

  // ── Local Banner Ad ──────────────────────────────────────────────────────────
  BannerAd? _bannerAd;
  bool      _bannerReady = false;

  // ── Animations ───────────────────────────────────────────────────────────────
  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;

  // ── Protocol keywords (mirrors Python) ──────────────────────────────────────
  static const _protoKeywords = {
    'http', 'https', 'ftp', 'ftps', 'sftp', 'ssh', 'rtmp', 'rtsp',
  };

  static bool _isUrlPart(String fragment) {
    final low = fragment.toLowerCase();
    if (_protoKeywords.contains(low)) return true;
    if (low.contains('//')) return true;
    if (low.startsWith('www.')) return true;
    if (!fragment.contains('@')) {
      final domainRe = RegExp(
        r'^[a-zA-Z0-9][a-zA-Z0-9.\-]*\.[a-zA-Z]{2,12}(?:[:/][^\s]*)?$',
      );
      if (domainRe.hasMatch(fragment)) return true;
    }
    return false;
  }

  // ── Core logic (exact port of your Python bot) ───────────────────────────────
  static List<String> _processLines(List<String> rawLines) {
    final out = <String>[];
    for (final line in rawLines) {
      if (line.trim().isEmpty) continue;
      var normalized = line.replaceAll(RegExp(r'\s*\|\s*'), ':');
      normalized     = normalized.replaceAll(RegExp(r'\t+'), ':');
      final parts    = normalized
          .split(':')
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .toList();
      final cleanParts = <String>[];
      for (final part in parts) {
        if (part.contains('@')) {
          cleanParts.add(part);
        } else if (_isUrlPart(part)) {
          continue;
        } else {
          cleanParts.add(part);
        }
      }
      if (cleanParts.length >= 2) out.add(cleanParts.join(':'));
    }
    return out;
  }

  static Future<List<String>> _runInIsolate(List<String> lines) =>
      Isolate.run(() => _processLines(lines));

  // ── Lifecycle ────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _initBanner();
    AdService.instance.addListener(_onAdChanged);
  }

  @override
  void dispose() {
    AdService.instance.removeListener(_onAdChanged);
    _bannerAd?.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

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

  // ── Actions ──────────────────────────────────────────────────────────────────

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt', 'csv', 'list', 'combo'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file  = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) { setState(() => _errorMsg = 'Could not read file.'); return; }
      setState(() {
        _pickedFileName = file.name;
        _rawContent     = String.fromCharCodes(bytes);
        _phase          = _Phase.ready;
        _errorMsg       = null;
        _result         = [];
        _outputFile     = null;
        _progress       = 0;
      });
    } catch (e) {
      setState(() => _errorMsg = 'Error picking file: $e');
    }
  }

  Future<void> _runProcess() async {
    if (_rawContent == null) return;
    AdService.instance.showInterstitial();
    final lines = _rawContent!.split('\n');
    _originalCount = lines.where((l) => l.trim().isNotEmpty).length;
    setState(() { _phase = _Phase.processing; _progress = 0.0; _errorMsg = null; });

    final ticker = Stream.periodic(const Duration(milliseconds: 120)).listen((_) {
      if (_phase == _Phase.processing && _progress < 0.92) {
        setState(() => _progress = (_progress + 0.015).clamp(0.0, 0.92));
      }
    });

    try {
      final result  = await _runInIsolate(lines);
      ticker.cancel();
      final dir     = await getTemporaryDirectory();
      final outName = '${(_pickedFileName ?? 'output').replaceAll(RegExp(r'\.[^.]+$'), '')}_url_removed.txt';
      final outFile = File('${dir.path}/$outName');
      await outFile.writeAsString(result.join('\n'));
      setState(() { _result = result; _phase = _Phase.done; _progress = 1.0; _outputFile = outFile; });
    } catch (e) {
      ticker.cancel();
      setState(() { _phase = _Phase.ready; _errorMsg = 'Processing failed: $e'; });
    }
  }

  Future<void> _shareFile() async {
    if (_outputFile == null) return;
    HapticFeedback.mediumImpact();
    await Share.shareXFiles([XFile(_outputFile!.path)],
        subject: 'URL Removed — ${_outputFile!.path.split('/').last}');
  }

  void _reset() => setState(() {
    _phase = _Phase.idle; _pickedFileName = null; _rawContent = null;
    _result = []; _outputFile = null; _progress = 0; _errorMsg = null;
  });

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
              color: Color(0xFF7B8CDE), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFF7B8CDE).withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.link_off_rounded,
                color: Color(0xFF7B8CDE), size: 18),
          ),
          const SizedBox(width: 10),
          Text('URL Remover',
              style: TextStyle(color: c.textPrimary,
                  fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
        ]),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _buildInfoCard(c),
          const SizedBox(height: 16),
          if (_errorMsg != null) _buildErrorCard(),
          _buildMainCard(c),
          const SizedBox(height: 16),
          if (_phase == _Phase.done) _buildResultCard(c),
          const SizedBox(height: 40),
        ]),
      ),
    );
  }

  Widget _buildInfoCard(XissinColors c) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFF7B8CDE).withOpacity(0.08),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFF7B8CDE).withOpacity(0.2)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Row(children: [
        Icon(Icons.info_outline_rounded, color: Color(0xFF7B8CDE), size: 16),
        SizedBox(width: 8),
        Text('What does this do?', style: TextStyle(
            color: Color(0xFF7B8CDE), fontWeight: FontWeight.w700, fontSize: 13)),
      ]),
      const SizedBox(height: 8),
      Text(
        'Strips URLs, domains & protocol fragments from combo lists.\n'
        'Keeps only valid username:password pairs (2+ parts).\n\n'
        '✦  Runs entirely on your device — no internet needed\n'
        '✦  Supports .txt, .csv, .list, .combo\n'
        '✦  Handles  |  and  \\t  separators automatically',
        style: TextStyle(color: c.textSecondary, fontSize: 12, height: 1.6),
      ),
    ]),
  );

  Widget _buildErrorCard() => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFFF6B6B).withOpacity(0.1),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFFF6B6B).withOpacity(0.3)),
    ),
    child: Row(children: [
      const Icon(Icons.error_outline_rounded, color: Color(0xFFFF6B6B), size: 16),
      const SizedBox(width: 8),
      Expanded(child: Text(_errorMsg!,
          style: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 12))),
    ]),
  );

  Widget _buildMainCard(XissinColors c) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: c.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: c.border),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1),
          blurRadius: 20, offset: const Offset(0, 8))],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_phase == _Phase.idle || _phase == _Phase.ready) _buildPickButton(c),
      if (_pickedFileName != null) ...[
        const SizedBox(height: 14), _buildFileChip(c),
      ],
      if (_phase == _Phase.processing) ...[
        const SizedBox(height: 20), _buildProgressSection(c),
      ],
      if (_phase == _Phase.ready) ...[
        const SizedBox(height: 16), _buildRunButton(),
      ],
      if (_phase == _Phase.done) ...[
        const SizedBox(height: 14), _buildActionRow(c),
      ],
    ]),
  );

  Widget _buildPickButton(XissinColors c) => GestureDetector(
    onTap: _pickFile,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 22),
      decoration: BoxDecoration(
        color: const Color(0xFF7B8CDE).withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: const Color(0xFF7B8CDE).withOpacity(0.3), width: 1.5),
      ),
      child: Column(children: [
        Icon(Icons.upload_file_rounded,
            color: const Color(0xFF7B8CDE).withOpacity(0.8), size: 36),
        const SizedBox(height: 10),
        const Text('Tap to select file', style: TextStyle(
            color: Color(0xFF7B8CDE), fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 4),
        Text('.txt  •  .csv  •  .list  •  .combo',
            style: TextStyle(color: c.textHint, fontSize: 11)),
      ]),
    ),
  );

  Widget _buildFileChip(XissinColors c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
        color: c.background, borderRadius: BorderRadius.circular(10)),
    child: Row(children: [
      const Icon(Icons.insert_drive_file_rounded,
          color: Color(0xFF7B8CDE), size: 16),
      const SizedBox(width: 8),
      Expanded(child: Text(_pickedFileName ?? '',
          style: TextStyle(color: c.textSecondary, fontSize: 12),
          overflow: TextOverflow.ellipsis)),
      if (_phase == _Phase.ready)
        GestureDetector(onTap: _reset,
            child: Icon(Icons.close_rounded, color: c.textHint, size: 16)),
    ]),
  );

  Widget _buildProgressSection(XissinColors c) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        AnimatedBuilder(
          animation: _pulseAnim,
          builder: (_, __) => Opacity(
            opacity: _pulseAnim.value,
            child: const Row(children: [
              Icon(Icons.link_off_rounded, color: Color(0xFF7B8CDE), size: 14),
              SizedBox(width: 6),
              Text('Removing URLs…', style: TextStyle(
                  color: Color(0xFF7B8CDE), fontSize: 13,
                  fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
        Text('${(_progress * 100).toStringAsFixed(0)}%',
            style: TextStyle(color: c.textHint, fontSize: 11)),
      ]),
      const SizedBox(height: 12),
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: LinearProgressIndicator(
          value: _progress, minHeight: 6,
          backgroundColor: c.background,
          valueColor: const AlwaysStoppedAnimation(Color(0xFF7B8CDE)),
        ),
      ),
      const SizedBox(height: 10),
      Text('Processing $_originalCount lines on your device…',
          style: TextStyle(color: c.textHint, fontSize: 11)),
    ],
  );

  Widget _buildRunButton() => GestureDetector(
    onTap: () { HapticFeedback.mediumImpact(); _runProcess(); },
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 15),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF7B8CDE), Color(0xFF5B6CBE)]),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: const Color(0xFF7B8CDE).withOpacity(0.4),
            blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
        SizedBox(width: 8),
        Text('Remove URLs', style: TextStyle(color: Colors.white,
            fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
      ]),
    ),
  );

  Widget _buildActionRow(XissinColors c) => Row(children: [
    Expanded(
      child: GestureDetector(
        onTap: _reset,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
              color: c.background, borderRadius: BorderRadius.circular(12)),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.refresh_rounded, color: c.textSecondary, size: 16),
            const SizedBox(width: 6),
            Text('New File',
                style: TextStyle(color: c.textSecondary, fontSize: 13)),
          ]),
        ),
      ),
    ),
    const SizedBox(width: 10),
    Expanded(
      flex: 2,
      child: GestureDetector(
        onTap: _shareFile,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF56CCF2), Color(0xFF2F80ED)]),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(
                color: const Color(0xFF56CCF2).withOpacity(0.3),
                blurRadius: 10, offset: const Offset(0, 3))],
          ),
          child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.share_rounded, color: Colors.white, size: 16),
            SizedBox(width: 6),
            Text('Share Result', style: TextStyle(
                color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    ),
  ]);

  Widget _buildResultCard(XissinColors c) {
    final kept    = _result.length;
    final removed = _originalCount - kept;
    final pct     = _originalCount > 0
        ? (removed / _originalCount * 100).toStringAsFixed(1) : '0.0';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF2ECC71).withOpacity(0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF2ECC71).withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.check_circle_rounded, color: Color(0xFF2ECC71), size: 18),
          SizedBox(width: 8),
          Text('Done!', style: TextStyle(color: Color(0xFF2ECC71),
              fontWeight: FontWeight.w800, fontSize: 15)),
        ]),
        const SizedBox(height: 14),
        _statRow('Original lines',  '$_originalCount', c.textSecondary),
        const SizedBox(height: 8),
        _statRow('Clean lines kept', '$kept',           const Color(0xFF2ECC71)),
        const SizedBox(height: 8),
        _statRow('URLs removed',    '$removed ($pct%)', const Color(0xFFFF6B6B)),
        if (_result.isNotEmpty) ...[
          const SizedBox(height: 14),
          Divider(color: c.border),
          const SizedBox(height: 10),
          Text('Preview (first 5 lines)',
              style: TextStyle(color: c.textHint, fontSize: 11)),
          const SizedBox(height: 6),
          ..._result.take(5).map((line) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(line, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.textSecondary, fontSize: 11)),
          )),
        ],
      ]),
    );
  }

  Widget _statRow(String label, String value, Color valueColor) =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label,
            style: const TextStyle(color: Colors.white54, fontSize: 13)),
        Text(value, style: TextStyle(color: valueColor,
            fontSize: 13, fontWeight: FontWeight.w700)),
      ]);
}

enum _Phase { idle, ready, processing, done }
