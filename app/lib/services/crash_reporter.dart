import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CrashReporter — Routes crash reports through YOUR backend, not directly
// to Telegram. This keeps the bot token OFF the device completely.
//
// Backend endpoint: POST /api/crash-report
// The backend forwards to Telegram using its own env var.
// ─────────────────────────────────────────────────────────────────────────────

class CrashReporter {
  static const String _backendBase =
      'https://xissin-app-backend-production.up.railway.app';
  static const String _endpoint = '$_backendBase/api/crash-report';

  // ── Send to backend ───────────────────────────────────────────────────────

  static Future<void> _send({
    required String type,
    required String error,
    required String stack,
    required String device,
    required String version,
    required String timestamp,
  }) async {
    try {
      await http
          .post(
            Uri.parse(_endpoint),
            headers: {'Content-Type': 'application/json'},
            body: _buildJson(
              type: type,
              error: error,
              stack: stack,
              device: device,
              version: version,
              timestamp: timestamp,
            ),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // Silently fail — never crash the crash reporter
    }
  }

  static String _buildJson({
    required String type,
    required String error,
    required String stack,
    required String device,
    required String version,
    required String timestamp,
  }) {
    String esc(String s) => s
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r')
        .replaceAll('\t', '\\t');

    return '{"type":"${esc(type)}","error":"${esc(error)}",'
        '"stack":"${esc(stack)}","device":"${esc(device)}",'
        '"version":"${esc(version)}","timestamp":"${esc(timestamp)}"}';
  }

  // ── Device / version helpers ──────────────────────────────────────────────

  static Future<String> _getDeviceInfo() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final android = await deviceInfo.androidInfo;
        return '${android.brand} ${android.model} (Android ${android.version.release})';
      } else if (Platform.isIOS) {
        final ios = await deviceInfo.iosInfo;
        return '${ios.name} ${ios.systemVersion}';
      }
    } catch (_) {}
    return 'Unknown Device';
  }

  static Future<String> _getAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return 'v${info.version}+${info.buildNumber}';
    } catch (_) {}
    return 'Unknown Version';
  }

  static String _nowTimestamp() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
  }

  // ── Public API ────────────────────────────────────────────────────────────

  static Future<void> reportCrash({
    required Object error,
    required StackTrace stack,
    String type = 'CRASH',
  }) async {
    final device = await _getDeviceInfo();
    final version = await _getAppVersion();

    // Trim stack trace to keep payload small
    final stackStr = stack.toString();
    final trimmedStack = stackStr.length > 800
        ? '${stackStr.substring(0, 800)}\n... (trimmed)'
        : stackStr;

    await _send(
      type: type,
      error: error.toString(),
      stack: trimmedStack,
      device: device,
      version: version,
      timestamp: _nowTimestamp(),
    );
  }

  static Future<void> reportWarning(String message) async {
    final version = await _getAppVersion();
    final device = await _getDeviceInfo();

    await _send(
      type: 'WARNING',
      error: message,
      stack: '',
      device: device,
      version: version,
      timestamp: _nowTimestamp(),
    );
  }

  // ── Initialize — Call this in main() ─────────────────────────────────────

  static void initialize() {
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      reportCrash(
        error: details.exception,
        stack: details.stack ?? StackTrace.current,
        type: 'FLUTTER ERROR',
      );
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      reportCrash(
        error: error,
        stack: stack,
        type: 'PLATFORM ERROR',
      );
      return true;
    };
  }
}
