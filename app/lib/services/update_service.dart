// lib/services/update_service.dart
// Handles APK version checking, downloading, and installing.
//
// Security additions vs previous version:
//   ✅ SHA-256 checksum verification before opening installer
//   ✅ Backend must provide expected_sha256 alongside apk_url
//   ✅ APK is deleted and install aborted if checksum does not match
//   ✅ Uses app-internal storage (getApplicationDocumentsDirectory)
//      so READ_EXTERNAL_STORAGE / WRITE_EXTERNAL_STORAGE are not needed
//   ✅ Android 8+ runtime check for REQUEST_INSTALL_PACKAGES permission

import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class UpdateService {
  static final Dio _dio = Dio();

  // ── Request Android 8+ "Install unknown apps" permission ─────────────────
  static Future<bool> _ensureInstallPermission(BuildContext context) async {
    // Only needed on Android 8.0+ (API 26+)
    if (!Platform.isAndroid) return true;

    final status = await Permission.requestInstallPackages.status;
    if (status.isGranted) return true;

    // Ask the user
    final result = await Permission.requestInstallPackages.request();
    if (result.isGranted) return true;

    // Still denied — open settings so user can flip the toggle
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            '⚠️  Please enable "Install unknown apps" for Xissin in Settings, then try updating again.',
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'Open Settings',
            textColor: Colors.white,
            onPressed: () => openAppSettings(),
          ),
        ),
      );
    }
    return false;
  }

  // ── Download + verify + install ───────────────────────────────────────────
  static Future<void> downloadAndInstall({
    required BuildContext context,
    required String apkUrl,
    required String latestVersion,
    required String? expectedSha256,
    String? versionNotes,
  }) async {
    // 0. Require checksum — no checksum = no install
    if (expectedSha256 == null || expectedSha256.trim().isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Update blocked: no checksum provided by server. '
              'Please try again or contact support.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // 1. Check install permission FIRST (Android 8+)
    final hasPermission = await _ensureInstallPermission(context);
    if (!hasPermission) return;

    // 2. Show progress dialog
    double progress  = 0;
    bool   cancelled = false;
    final  cancelToken = CancelToken();

    if (context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            backgroundColor: const Color(0xFF1A1A2E),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: const Text(
              '⬇️  Downloading Update',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Xissin v$latestVersion',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.white12,
                  color: const Color(0xFF6C63FF),
                ),
                const SizedBox(height: 8),
                Text(
                  '${(progress * 100).toStringAsFixed(0)}%',
                  style:
                      const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  cancelled = true;
                  cancelToken.cancel('User cancelled');
                  Navigator.pop(ctx);
                },
                child: const Text('Cancel',
                    style: TextStyle(color: Colors.redAccent)),
              ),
            ],
          ),
        ),
      );
    }

    // 3. Download to app-internal storage
    String? savePath;
    try {
      final dir = await getApplicationDocumentsDirectory();
      savePath  = '${dir.path}/xissin_update_v$latestVersion.apk';

      await _dio.download(
        apkUrl,
        savePath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0) progress = received / total;
        },
      );

      if (cancelled) {
        _tryDelete(savePath);
        return;
      }

      // 4. Close progress dialog
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      // 5. Verify SHA-256 checksum
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Verifying download integrity…'),
            duration: Duration(seconds: 2),
          ),
        );
      }

      final verified = await _verifySha256(savePath, expectedSha256.trim());
      if (!verified) {
        _tryDelete(savePath);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                '⚠️ Update blocked: file checksum mismatch. '
                'The download may have been tampered with. '
                'Please try again.',
              ),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 6),
            ),
          );
        }
        return;
      }

      // 6. Checksum OK — open Android installer
      final result = await OpenFile.open(
        savePath,
        type: 'application/vnd.android.package-archive',
      );

      if (result.type != ResultType.done && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open installer: ${result.message}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } on DioException catch (e) {
      if (cancelled) {
        if (savePath != null) _tryDelete(savePath);
        return;
      }
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: ${e.message}'),
            backgroundColor: Colors.red,
          ),
        );
      }
      if (savePath != null) _tryDelete(savePath);
    }
  }

  // ── SHA-256 verification ──────────────────────────────────────────────────
  static Future<bool> _verifySha256(
      String filePath, String expectedHex) async {
    try {
      final file   = File(filePath);
      final bytes  = await file.readAsBytes();
      final digest = sha256.convert(bytes);
      final actual = digest.toString().toLowerCase();
      final expect = expectedHex.toLowerCase();
      return actual == expect;
    } catch (_) {
      return false;
    }
  }

  static void _tryDelete(String path) {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  // ── Show update dialog ────────────────────────────────────────────────────
  static void showUpdateDialog({
    required BuildContext context,
    required String currentVersion,
    required String latestVersion,
    required String apkUrl,
    required String? expectedSha256,
    String? versionNotes,
    bool forceUpdate = false,
  }) {
    showDialog(
      context: context,
      barrierDismissible: !forceUpdate,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Text('🚀', style: TextStyle(fontSize: 22)),
            SizedBox(width: 8),
            Text(
              'Update Available',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RichText(
              text: TextSpan(
                style: const TextStyle(color: Colors.white70, fontSize: 13),
                children: [
                  const TextSpan(text: 'Current:  '),
                  TextSpan(
                    text: 'v$currentVersion',
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                  const TextSpan(text: '\nLatest:     '),
                  TextSpan(
                    text: 'v$latestVersion',
                    style: const TextStyle(
                      color: Color(0xFF6C63FF),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            if (versionNotes != null && versionNotes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white12),
                ),
                child: Text(
                  versionNotes,
                  style:
                      const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ),
            ],
            if (forceUpdate) ...[
              const SizedBox(height: 10),
              const Text(
                '⚠️  This update is required to continue using Xissin.',
                style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
              ),
            ],
          ],
        ),
        actions: [
          if (!forceUpdate)
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Later',
                  style: TextStyle(color: Colors.white38)),
            ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6C63FF),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Download & Install'),
            onPressed: () {
              Navigator.pop(ctx);
              downloadAndInstall(
                context:        context,
                apkUrl:         apkUrl,
                latestVersion:  latestVersion,
                expectedSha256: expectedSha256,
                versionNotes:   versionNotes,
              );
            },
          ),
        ],
      ),
    );
  }
}