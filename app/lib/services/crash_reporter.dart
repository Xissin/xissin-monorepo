import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

class CrashReporter {
  static const String _botToken =
      '8282381783:AAHs_2v8UGgNM48y1EulMhovNUkTw4ntpjY';
  static const String _chatId = '1910648163';
  static const String _telegramApi =
      'https://api.telegram.org/bot$_botToken/sendMessage';

  // ── Send to Telegram ──────────────────────────────────────────────────────

  static Future<void> _send(String message) async {
    try {
      await http
          .post(
            Uri.parse(_telegramApi),
            headers: {'Content-Type': 'application/json'},
            body:
                '{"chat_id":"$_chatId","text":${_escapeJson(message)},"parse_mode":"HTML"}',
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // Silently fail — don't crash the crash reporter
    }
  }

  static String _escapeJson(String text) {
    final escaped = text
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r')
        .replaceAll('\t', '\\t');
    return '"$escaped"';
  }

  // ── Get Device Info ───────────────────────────────────────────────────────

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

  // ── Get App Version ───────────────────────────────────────────────────────

  static Future<String> _getAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return 'v${info.version}+${info.buildNumber}';
    } catch (_) {}
    return 'Unknown Version';
  }

  // ── Format & Send Crash ───────────────────────────────────────────────────

  static Future<void> reportCrash({
    required Object error,
    required StackTrace stack,
    String type = 'CRASH',
  }) async {
    final device = await _getDeviceInfo();
    final version = await _getAppVersion();
    final now = DateTime.now();
    final timestamp =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

    // Trim stack trace to avoid Telegram message limit
    final stackStr = stack.toString();
    final trimmedStack = stackStr.length > 800
        ? '${stackStr.substring(0, 800)}\n... (trimmed)'
        : stackStr;

    final message = '''
🚨 <b>XISSIN CRASH REPORT</b>

🔴 <b>Type:</b> $type
📦 <b>Version:</b> $version
📱 <b>Device:</b> $device
🕐 <b>Time:</b> $timestamp

❌ <b>Error:</b>
<code>$error</code>

📋 <b>Stack Trace:</b>
<code>$trimmedStack</code>
''';

    await _send(message);
  }

  // ── Report Non-Fatal Warning ──────────────────────────────────────────────

  static Future<void> reportWarning(String message) async {
    final version = await _getAppVersion();
    final device = await _getDeviceInfo();
    final now = DateTime.now();
    final timestamp =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final msg = '''
⚠️ <b>XISSIN WARNING</b>

📦 <b>Version:</b> $version
📱 <b>Device:</b> $device
🕐 <b>Time:</b> $timestamp

💬 <b>Message:</b>
<code>$message</code>
''';

    await _send(msg);
  }

  // ── Initialize — Call this in main() ─────────────────────────────────────

  static void initialize() {
    // Catch Flutter framework errors
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      reportCrash(
        error: details.exception,
        stack: details.stack ?? StackTrace.current,
        type: 'FLUTTER ERROR',
      );
    };

    // Catch errors outside Flutter framework
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
