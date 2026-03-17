// lib/services/update_service.dart
// Handles APK version checking, downloading, and installing.

import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class UpdateService {
  static final Dio _dio = Dio();

  // ── Download + install ─────────────────────────────────────────────────────
  static Future<void> downloadAndInstall({
    required BuildContext context,
    required String apkUrl,
    required String latestVersion,
    String? versionNotes,
  }) async {
    // 1. Ask for storage permission (Android ≤ 12)
    if (Platform.isAndroid) {
      final status = await Permission.storage.request();
      if (!status.isGranted) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Storage permission is required to download the update.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
    }

    // 2. Show progress dialog
    double progress = 0;
    bool cancelled = false;
    CancelToken cancelToken = CancelToken();

    if (context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            backgroundColor: const Color(0xFF1A1A2E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
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
                child: const Text('Cancel', style: TextStyle(color: Colors.redAccent)),
              ),
            ],
          ),
        ),
      );
    }

    // 3. Download APK
    try {
      final dir = await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
      final savePath = '${dir.path}/xissin_v$latestVersion.apk';

      await _dio.download(
        apkUrl,
        savePath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            progress = received / total;
          }
        },
      );

      if (cancelled) return;

      // 4. Close progress dialog
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();

      // 5. Launch Android installer
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
      if (cancelled) return;
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: ${e.message}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ── Show update dialog ─────────────────────────────────────────────────────
  static void showUpdateDialog({
    required BuildContext context,
    required String currentVersion,
    required String latestVersion,
    required String apkUrl,
    String? versionNotes,
    bool forceUpdate = false,
  }) {
    showDialog(
      context: context,
      barrierDismissible: !forceUpdate,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
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
              child: const Text('Later', style: TextStyle(color: Colors.white38)),
            ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6C63FF),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Download & Install'),
            onPressed: () {
              Navigator.pop(ctx);
              downloadAndInstall(
                context: context,
                apkUrl: apkUrl,
                latestVersion: latestVersion,
                versionNotes: versionNotes,
              );
            },
          ),
        ],
      ),
    );
  }
}
