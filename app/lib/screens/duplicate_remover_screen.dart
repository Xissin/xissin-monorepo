// ============================================================
//  app/lib/screens/duplicate_remover_screen.dart
//  🗂️ Duplicate Remover — 100% local, no backend, offline-safe ads
//
//  Part 3: Line limits
//   • Free    : 1,000 lines max (excess lines silently truncated)
//   • Premium : Unlimited
// ============================================================
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/ad_service.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

// ── Part 3 constants ──────────────────────────────────────────────────────────
const _kFreeLineCap = 1000; // Free tier: max lines to process

class DuplicateRemoverScreen extends StatefulWidget {
  final String userId;
  const DuplicateRemoverScreen({super.key, required this.userId});

  @override
  State<DuplicateRemoverScreen> createState() => _DuplicateRemoverScreenState();
}

class _DuplicateRemoverScreenState extends State<DuplicateRemoverScreen>
    with TickerProviderStateMixin {

  _Phase  _phase         = _Phase.idle;
  String? _pickedFileName;
  String? _rawContent;
  List<String> _result  = [];
  int    _originalCount = 0;   // total non-empty lines in file
  int    _processedCount = 0;  // lines actually processed (capped for free)
  double _progress      = 0.0;
  String? _errorMsg;
  File?  _outputFile;

  bool _isOnline = true;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  StreamSubscription<int>? _ticker;

  // ── Watch-ad gate (free users) ────────────────────────────────────────────
  bool _adGranted = false; // true after watching ad → one process allowed

  BannerAd? _bannerAd;
  bool      _bannerReady = false;

  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;

  static List<String> _deduplicateLines(List<String> rawLines) {
    final out  = <String>[];
    final seen = <String>{};
    for (final line in rawLines) {
      if (line.trim().isEmpty) continue;
      final cleanLine = line.replaceAll('|', ':');
      final sepIdx    = cleanLine.indexOf(':');
      String dedupKey;
      if (sepIdx > 0) {
        dedupKey = cleanLine.substring(0, sepIdx).trim().toLowerCase();
      } else if (sepIdx == 0) {
        out.add(cleanLine);
        continue;
      } else {
        dedupKey = cleanLine.toLowerCase();
      }
      if (!seen.contains(dedupKey)) {
        seen.add(dedupKey);
        out.add(cleanLine);
      }
    }
    return out;
  }

  static Future<List<String>> _runInIsolate(List<String> lines) =>
      Isolate.run(() => _deduplicateLines(lines));

  // ── Helpers ───────────────────────────────────────────────────────────────

  bool get _isPremium => AdService.instance.adsRemoved;

  int get _totalLines =>
      _rawContent?.split('\n').where((l) => l.trim().isNotEmpty).length ?? 0;

  bool get _isCapped => !_isPremium && _totalLines > _kFreeLineCap;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    AdService.instance.init(userId: widget.userId);
    _checkConnectivity();

    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      if (!mounted) return;
      final online = !results.every((r) => r == ConnectivityResult.none);
      if (online != _isOnline) {
        setState(() => _isOnline = online);
        if (online && !_bannerReady && !AdService.instance.adsRemoved) {
          _initBanner();
        }
      }
    });

    AdService.instance.addListener(_onAdChanged);
    _initBanner();
  }

  Future<void> _checkConnectivity() async {
    final results = await Connectivity().checkConnectivity();
    if (!mounted) return;
    setState(() => _isOnline = !results.every((r) => r == ConnectivityResult.none));
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _ticker?.cancel();
    AdService.instance.removeListener(_onAdChanged);
    _bannerAd?.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ── Banner Ad ─────────────────────────────────────────────────────────────

  void _onAdChanged() {
    if (!mounted) return;
    if (AdService.instance.adsRemoved && _bannerAd != null) {
      _bannerAd?.dispose();
      setState(() { _bannerAd = null; _bannerReady = false; });
    }
  }

  void _initBanner() {
    if (!_isOnline || AdService.instance.adsRemoved) return;
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
          if (mounted && _isOnline && !AdService.instance.adsRemoved) _initBanner();
        });
      },
    );
    if (ad == null) return;
    _bannerAd = ad;
    _bannerAd!.load();
  }

  Widget _buildBannerAd() {
    if (!_isOnline || AdService.instance.adsRemoved || !_bannerReady || _bannerAd == null) {
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

  void _tryShowInterstitial() {
    if (_isOnline && !AdService.instance.adsRemoved) {
      AdService.instance.showInterstitial();
    }
  }

  // ── Watch-ad gate ─────────────────────────────────────────────────────

  void _watchAdToProcess() {
    HapticFeedback.selectionClick();
    AdService.instance.showGatedInterstitial(
      onGranted: () {
        if (mounted) {
          setState(() => _adGranted = true);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('🔓 Unlocked! Tap Remove Duplicates to process.',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            backgroundColor: const Color(0xFFFFA94D),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
            margin: const EdgeInsets.all(12),
            duration: const Duration(seconds: 2),
          ));
        }
      },
    );
  }

  // ── Actions ───────────────────────────────────────────────────────────────

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
      if (bytes == null) {
        setState(() => _errorMsg = 'Could not read file.');
        return;
      }
      setState(() {
        _pickedFileName = file.name;
        _rawContent     = utf8.decode(bytes, allowMalformed: true);
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

    final allLines = _rawContent!.split('\n');

    // ── Part 3: Apply line cap for free users ──────────────────────────────
    final isPremium      = _isPremium;
    final nonEmpty       = allLines.where((l) => l.trim().isNotEmpty).toList();
    final linesToProcess = isPremium
        ? nonEmpty
        : nonEmpty.take(_kFreeLineCap).toList();

    setState(() {
      _originalCount  = nonEmpty.length;
      _processedCount = linesToProcess.length;
      _phase          = _Phase.processing;
      _progress       = 0.0;
      _errorMsg       = null;
    });

    _ticker?.cancel();
    _ticker = Stream.periodic(const Duration(milliseconds: 150), (i) => i)
        .listen((_) {
      if (!mounted) return;
      if (_phase == _Phase.processing && _progress < 0.90) {
        setState(() => _progress = (_progress + 0.012).clamp(0.0, 0.90));
      }
    });

    try {
      final result = await _runInIsolate(linesToProcess);
      _ticker?.cancel();
      _ticker = null;

      if (result.isEmpty) {
        setState(() {
          _phase    = _Phase.ready;
          _progress = 0.0;
          _errorMsg = 'No unique lines found. '
              'The file may already be fully deduped or have no valid entries.';
        });
        return;
      }

      final dir      = await getTemporaryDirectory();
      final baseName = (_pickedFileName ?? 'output').replaceAll(RegExp(r'\.[^.]+$'), '');
      final outFile  = File('${dir.path}/${baseName}_deduped.txt');
      await outFile.writeAsString(result.join('\n'));

      if (!mounted) return;
      setState(() {
        _result     = result;
        _phase      = _Phase.done;
        _progress   = 1.0;
        _outputFile = outFile;
        _adGranted  = false; // reset gate after each process
      });

      if (_isOnline) {
        ApiService.logToolUsage(
          tool:         'dup_remover',
          inputCount:   _processedCount,
          outputCount:  result.length,
          removedCount: _processedCount - result.length,
        ).catchError((_) {});
      }

      Future.delayed(const Duration(milliseconds: 600), _tryShowInterstitial);

    } catch (e) {
      _ticker?.cancel();
      _ticker = null;
      if (mounted) {
        setState(() { _phase = _Phase.ready; _errorMsg = 'Processing failed: $e'; });
      }
    }
  }

  Future<void> _shareFile() async {
    if (_outputFile == null) return;
    HapticFeedback.mediumImpact();
    await Share.shareXFiles(
      [XFile(_outputFile!.path)],
      subject: 'Deduped — ${_outputFile!.path.split('/').last}',
    );
    Future.delayed(const Duration(milliseconds: 300), _tryShowInterstitial);
  }

  void _copyAll() {
    if (_result.isEmpty) return;
    HapticFeedback.mediumImpact();
    Clipboard.setData(ClipboardData(text: _result.join('\n')));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior:        SnackBarBehavior.floating,
        backgroundColor: context.c.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md)),
        margin:   const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: const Duration(seconds: 2),
        content: Row(children: [
          const Icon(Icons.check_circle_rounded,
              color: Color(0xFFFFA94D), size: 16),
          const SizedBox(width: 8),
          Text('${_result.length} lines copied to clipboard!',
              style: TextStyle(
                  color: context.c.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
        ]),
      ),
    );
    Future.delayed(const Duration(milliseconds: 300), _tryShowInterstitial);
  }

  void _reset() {
    _tryShowInterstitial();
    setState(() {
      _phase          = _Phase.idle;
      _pickedFileName = null;
      _rawContent     = null;
      _result         = [];
      _outputFile     = null;
      _progress       = 0;
      _errorMsg       = null;
      _originalCount  = 0;
      _processedCount = 0;
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

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
              color: Color(0xFFFFA94D), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFFFFA94D).withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.filter_list_off_rounded,
                color: Color(0xFFFFA94D), size: 18),
          ),
          const SizedBox(width: 10),
          Text('Dup Remover',
              style: TextStyle(
                  color: c.textPrimary, fontSize: 17,
                  fontWeight: FontWeight.w700, letterSpacing: 0.4)),
        ]),
        centerTitle: true,
        actions: [
          if (!_isOnline)
            Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color:  const Color(0xFFFF6B6B).withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFFF6B6B).withOpacity(0.4)),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.wifi_off_rounded, color: Color(0xFFFF6B6B), size: 11),
                SizedBox(width: 4),
                Text('Offline',
                    style: TextStyle(color: Color(0xFFFF6B6B),
                        fontSize: 10, fontWeight: FontWeight.w600)),
              ]),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildInfoCard(c),
            const SizedBox(height: 16),
            if (_errorMsg != null) _buildErrorCard(),
            _buildMainCard(c),
            const SizedBox(height: 16),
            if (_phase == _Phase.done) _buildResultCard(c),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // ── Info Card ─────────────────────────────────────────────────────────────

  Widget _buildInfoCard(XissinColors c) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color:        const Color(0xFFFFA94D).withOpacity(0.08),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFFFA94D).withOpacity(0.2)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Row(children: [
        Icon(Icons.info_outline_rounded, color: Color(0xFFFFA94D), size: 16),
        SizedBox(width: 8),
        Text('What does this do?',
            style: TextStyle(color: Color(0xFFFFA94D),
                fontWeight: FontWeight.w700, fontSize: 13)),
      ]),
      const SizedBox(height: 8),
      Text(
        'Removes duplicate entries from combo/credential lists.\n'
        'Keeps the FIRST occurrence of each username/email.\n\n'
        '✦  Dedup key = everything before the first  :\n'
        '✦  Handles both  :  and  |  separators\n'
        '✦  Runs entirely on your device — no internet needed\n'
        '✦  💡 Tip: Run URL Remover first for best results',
        style: TextStyle(color: c.textSecondary, fontSize: 12, height: 1.6),
      ),
      const SizedBox(height: 10),
      // ── Part 3: Line limit badge ──────────────────────────────────────────
      _buildLineLimitBadge(c),
    ]),
  );

  Widget _buildLineLimitBadge(XissinColors c) {
    final isPremium = _isPremium;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isPremium
            ? const Color(0xFFFFD700).withOpacity(0.08)
            : const Color(0xFFFFA94D).withOpacity(0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isPremium
              ? const Color(0xFFFFD700).withOpacity(0.35)
              : const Color(0xFFFFA94D).withOpacity(0.35),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isPremium ? Icons.workspace_premium_rounded : Icons.lock_outline_rounded,
            size:  14,
            color: isPremium ? const Color(0xFFFFD700) : const Color(0xFFFFA94D),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isPremium
                  ? '⭐ Premium — Unlimited lines'
                  : '🔒 Free — Up to $_kFreeLineCap lines  ·  Get Premium for unlimited',
              style: TextStyle(
                color:    isPremium ? const Color(0xFFFFD700) : c.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Error Card ────────────────────────────────────────────────────────────

  Widget _buildErrorCard() => Container(
    margin:  const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color:        const Color(0xFFFF6B6B).withOpacity(0.1),
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

  // ── Main Card ─────────────────────────────────────────────────────────────

  Widget _buildMainCard(XissinColors c) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: c.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: c.border),
      boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 8))],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_phase == _Phase.idle || _phase == _Phase.ready)
        _buildPickButton(c),
      if (_pickedFileName != null) ...[
        const SizedBox(height: 14),
        _buildFileChip(c),
      ],
      // ── Part 3: Cap warning ───────────────────────────────────────────────
      if (_phase == _Phase.ready && _isCapped) ...[
        const SizedBox(height: 10),
        _buildCapWarning(c),
      ],
      if (_phase == _Phase.processing) ...[
        const SizedBox(height: 20),
        _buildProgressSection(c),
      ],
      if (_phase == _Phase.ready) ...[
        const SizedBox(height: 16),
        _buildRunButton(),
      ],
      if (_phase == _Phase.done) ...[
        const SizedBox(height: 14),
        _buildActionRow(c),
      ],
    ]),
  );

  Widget _buildCapWarning(XissinColors c) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:        const Color(0xFFFF9A44).withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFF9A44).withOpacity(0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFFF9A44), size: 15),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(color: c.textSecondary, fontSize: 11, height: 1.4),
                children: [
                  TextSpan(
                    text: 'File has $_totalLines lines. ',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const TextSpan(
                    text: 'Free tier processes only the first '
                        '$_kFreeLineCap lines. '
                        'Get Premium to process all lines.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPickButton(XissinColors c) => GestureDetector(
    onTap: _pickFile,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 22),
      decoration: BoxDecoration(
        color: const Color(0xFFFFA94D).withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFA94D).withOpacity(0.3), width: 1.5),
      ),
      child: Column(children: [
        Icon(Icons.upload_file_rounded,
            color: const Color(0xFFFFA94D).withOpacity(0.8), size: 36),
        const SizedBox(height: 10),
        const Text('Tap to select file',
            style: TextStyle(color: Color(0xFFFFA94D),
                fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 4),
        Text('.txt  ·  .csv  ·  .list  ·  .combo',
            style: TextStyle(color: c.textHint, fontSize: 11)),
      ]),
    ),
  );

  Widget _buildFileChip(XissinColors c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
        color: c.background, borderRadius: BorderRadius.circular(10)),
    child: Row(children: [
      const Icon(Icons.insert_drive_file_rounded, color: Color(0xFFFFA94D), size: 16),
      const SizedBox(width: 8),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_pickedFileName ?? '',
                style: TextStyle(color: c.textSecondary, fontSize: 12),
                overflow: TextOverflow.ellipsis),
            if (_rawContent != null)
              Text(
                '$_totalLines lines${_isCapped ? ' · processing first $_kFreeLineCap' : ''}',
                style: TextStyle(
                  color: _isCapped ? const Color(0xFFFF9A44) : c.textHint,
                  fontSize: 10,
                ),
              ),
          ],
        ),
      ),
      if (_phase == _Phase.ready)
        GestureDetector(
          onTap: _reset,
          child: Icon(Icons.close_rounded, color: c.textHint, size: 16),
        ),
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
              Icon(Icons.filter_list_off_rounded, color: Color(0xFFFFA94D), size: 14),
              SizedBox(width: 6),
              Text('Removing duplicates…',
                  style: TextStyle(color: Color(0xFFFFA94D),
                      fontSize: 13, fontWeight: FontWeight.w600)),
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
          valueColor: const AlwaysStoppedAnimation(Color(0xFFFFA94D)),
        ),
      ),
      const SizedBox(height: 10),
      Text(
        'Scanning $_processedCount lines on your device…'
        '${_isCapped ? ' (capped at $_kFreeLineCap for free tier)' : ''}',
        style: TextStyle(color: c.textHint, fontSize: 11),
      ),
    ],
  );

  Widget _buildRunButton() {
    final isPremium = _isPremium;

    // Premium: direct run button
    if (isPremium) {
      return _directRunButton();
    }

    // Free + ad already watched: show the run button
    if (_adGranted) {
      return Column(
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFFA94D).withOpacity(0.10),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: const Color(0xFFFFA94D).withOpacity(0.30)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_outline_rounded, color: Color(0xFFFFA94D), size: 14),
                SizedBox(width: 6),
                Text('🔓 Ad watched — ready to process!',
                    style: TextStyle(color: Color(0xFFFFA94D), fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          _directRunButton(),
        ],
      );
    }

    // Free + no ad yet: show watch-ad button
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFA94D).withOpacity(0.06),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: const Color(0xFFFFA94D).withOpacity(0.2)),
          ),
          child: const Row(
            children: [
              Icon(Icons.lock_outline_rounded, color: AppColors.textSecondary, size: 15),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Free: Watch a short ad to process • Premium: instant access',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 11, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: _watchAdToProcess,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFA94D),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
              elevation: 0,
            ),
            icon:  const Icon(Icons.play_circle_rounded, size: 20),
            label: const Text('Watch Ad to Process',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  Widget _directRunButton() => GestureDetector(
    onTap: () { HapticFeedback.mediumImpact(); _runProcess(); },
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 15),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFFFFA94D), Color(0xFFE67E22)]),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(
            color: const Color(0xFFFFA94D).withOpacity(0.4),
            blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
          SizedBox(width: 8),
          Text('Remove Duplicates',
              style: TextStyle(color: Colors.white,
                  fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
        ],
      ),
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
            Text('New File', style: TextStyle(color: c.textSecondary, fontSize: 13)),
          ]),
        ),
      ),
    ),
    const SizedBox(width: 8),
    Expanded(
      child: GestureDetector(
        onTap: _copyAll,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFFFFA94D), Color(0xFFE67E22)]),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(
                color: const Color(0xFFFFA94D).withOpacity(0.3),
                blurRadius: 10, offset: const Offset(0, 3))],
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.copy_rounded, color: Colors.white, size: 16),
              SizedBox(width: 6),
              Text('Copy All',
                  style: TextStyle(color: Colors.white,
                      fontSize: 13, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    ),
    const SizedBox(width: 8),
    Expanded(
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
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.share_rounded, color: Colors.white, size: 16),
              SizedBox(width: 6),
              Text('Share',
                  style: TextStyle(color: Colors.white,
                      fontSize: 13, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    ),
  ]);

  // ── Result Card ───────────────────────────────────────────────────────────

  Widget _buildResultCard(XissinColors c) {
    final kept  = _result.length;
    final dupes = _processedCount - kept;
    final pct   = _processedCount > 0
        ? (dupes / _processedCount * 100).toStringAsFixed(1)
        : '0.0';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color:        const Color(0xFFFFA94D).withOpacity(0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFFA94D).withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.check_circle_rounded, color: Color(0xFFFFA94D), size: 18),
          SizedBox(width: 8),
          Text('Done!', style: TextStyle(color: Color(0xFFFFA94D),
              fontWeight: FontWeight.w800, fontSize: 15)),
        ]),
        const SizedBox(height: 14),
        if (_isCapped) ...[
          _statRow('Total lines in file', '$_originalCount', c.textSecondary),
          const SizedBox(height: 8),
          _statRow('Lines processed (free cap)', '$_processedCount / $_kFreeLineCap',
              const Color(0xFFFF9A44)),
          const SizedBox(height: 8),
        ] else ...[
          _statRow('Original lines', '$_originalCount', c.textSecondary),
          const SizedBox(height: 8),
        ],
        _statRow('Unique lines kept',   '$kept',          const Color(0xFF2ECC71)),
        const SizedBox(height: 8),
        _statRow('Duplicates removed',  '$dupes ($pct%)', const Color(0xFFFF6B6B)),

        if (_isCapped) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color:        const Color(0xFFFFD700).withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.30)),
            ),
            child: Row(children: [
              const Icon(Icons.workspace_premium_rounded,
                  color: Color(0xFFFFD700), size: 14),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${_originalCount - _processedCount} lines skipped. '
                  'Get Premium to process all $_originalCount lines.',
                  style: TextStyle(color: c.textSecondary, fontSize: 11, height: 1.4),
                ),
              ),
            ]),
          ),
        ],

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
          const SizedBox(height: 10),
          Row(children: [
            Icon(Icons.info_outline_rounded, color: c.textHint, size: 12),
            const SizedBox(width: 6),
            Text('Use "Copy All" for clipboard or "Share" to save as file',
                style: TextStyle(color: c.textHint, fontSize: 10)),
          ]),
        ],
      ]),
    );
  }

  Widget _statRow(String label, String value, Color valueColor) =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
        Text(value, style: TextStyle(color: valueColor,
            fontSize: 13, fontWeight: FontWeight.w700)),
      ]);
}

enum _Phase { idle, ready, processing, done }