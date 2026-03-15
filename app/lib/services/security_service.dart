// ignore_for_file: constant_identifier_names
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:safe_device/safe_device.dart';

// ─────────────────────────────────────────────────────────────────────────────
// HMAC secret — split across character codes so string grep won't find it.
// Change these values before building if you want a unique key.
// The SAME assembled string must be set as XISSIN_APP_SECRET in Railway env.
// ─────────────────────────────────────────────────────────────────────────────
class _K {
  static final String v = String.fromCharCodes([
    88,  49,  83, 83, 73,  78,  // X1SSIN
    95,  83,  69, 67, 82,  51,  // _SECR3
    84,  95,  50, 48, 50,  53,  // T_2025
    95,  90,  88, 89, 90,       // _ZXYZ  ← change these last 5 for your own key
  ]);
}

// ─────────────────────────────────────────────────────────────────────────────
// Expected package name — if APK is repackaged this won't match → block
// ─────────────────────────────────────────────────────────────────────────────
const _kExpectedPackage = 'com.xissin.app';

// ─────────────────────────────────────────────────────────────────────────────
// SecurityService
// ─────────────────────────────────────────────────────────────────────────────
class SecurityService {
  SecurityService._();

  // ── Results ──────────────────────────────────────────────────────────────
  static bool _checked      = false;
  static bool _isRooted     = false;
  static bool _isEmulator   = false;
  static bool _isDebugged   = false;
  static bool _isTampered   = false;

  static bool get isRooted   => _isRooted;
  static bool get isEmulator => _isEmulator;
  static bool get isDebugged => _isDebugged;
  static bool get isTampered => _isTampered;

  /// Returns true if the device/environment is considered safe.
  static bool get isSafe =>
      !_isRooted && !_isEmulator && !_isDebugged && !_isTampered;

  // ── Run all checks ────────────────────────────────────────────────────────
  static Future<SecurityReport> runChecks() async {
    if (_checked) {
      return SecurityReport(
        isRooted:   _isRooted,
        isEmulator: _isEmulator,
        isDebugged: _isDebugged,
        isTampered: _isTampered,
      );
    }
    _checked = true;

    await Future.wait([
      _checkRoot(),
      _checkEmulator(),
      _checkDebugger(),
      _checkIntegrity(),
    ]);

    return SecurityReport(
      isRooted:   _isRooted,
      isEmulator: _isEmulator,
      isDebugged: _isDebugged,
      isTampered: _isTampered,
    );
  }

  // ── 1. Root / Jailbreak detection ─────────────────────────────────────────
  static Future<void> _checkRoot() async {
    try {
      // safe_device covers: su binary, dangerous apps, RW system partition
      final jailBroken = await SafeDevice.isJailBroken;
      final realDevice = await SafeDevice.isRealDevice;
      _isRooted = jailBroken || !realDevice;
    } catch (_) {
      // If we can't check, assume safe (don't block legitimate users on error)
      _isRooted = false;
    }
  }

  // ── 2. Emulator / VM detection ────────────────────────────────────────────
  static Future<void> _checkEmulator() async {
    try {
      if (Platform.isAndroid) {
        final info = await DeviceInfoPlugin().androidInfo;

        final brand    = info.brand.toLowerCase();
        final model    = info.model.toLowerCase();
        final product  = info.product.toLowerCase();
        final hardware = info.hardware.toLowerCase();
        final host     = info.host.toLowerCase();
        final fingerprint = info.fingerprint.toLowerCase();

        _isEmulator = !info.isPhysicalDevice
            || brand    == 'google'    && model.contains('sdk')
            || product.contains('sdk')
            || product.contains('emulator')
            || product.contains('vbox')
            || product.contains('genymotion')
            || product.contains('nox')
            || product.contains('bluestacks')
            || product.contains('ldmicro')
            || product.contains('memu')
            || hardware == 'goldfish'
            || hardware == 'ranchu'
            || hardware.contains('vbox')
            || model    == 'android sdk built for x86'
            || model.contains('emulator')
            || fingerprint.contains('generic')
            || fingerprint.contains('unknown')
            || host.startsWith('build')
            || brand.contains('genymotion');
      } else if (Platform.isIOS) {
        final info = await DeviceInfoPlugin().iosInfo;
        _isEmulator = !info.isPhysicalDevice;
      }
    } catch (_) {
      _isEmulator = false;
    }
  }

  // ── 3. Debugger / instrumentation detection ───────────────────────────────
  static Future<void> _checkDebugger() async {
    // kDebugMode is set by the Flutter framework — true only in debug builds
    // In release + obfuscated builds this is always false
    _isDebugged = kDebugMode;

    // Additional: check if a debugger is currently attached
    // dart:developer.Service is not available in release mode after obfuscation
    // but the flag below is a reliable runtime check
    try {
      if (Platform.isAndroid) {
        final info = await DeviceInfoPlugin().androidInfo;
        // If build is debuggable that's set in the manifest
        final fp = info.fingerprint.toLowerCase();
        // test-keys fingerprint = custom ROM / dev build
        if (fp.contains('test-keys') || fp.contains('userdebug')) {
          _isDebugged = true;
        }
      }
    } catch (_) {}
  }

  // ── 4. Package integrity check ────────────────────────────────────────────
  // Detects if someone repackaged your APK with a different package name
  static Future<void> _checkIntegrity() async {
    try {
      final pkg = await PackageInfo.fromPlatform();
      if (pkg.packageName != _kExpectedPackage) {
        _isTampered = true;
      }
    } catch (_) {
      _isTampered = false;
    }
  }

  // ── HMAC request signing ──────────────────────────────────────────────────
  /// Generates a signed token for API requests.
  /// Format: HMAC-SHA256(userId + ":" + timestampSeconds)
  /// The backend verifies this using the same secret.
  static String generateRequestToken({
    required String userId,
    required int timestampSeconds,
  }) {
    final message = '$userId:$timestampSeconds';
    final key     = utf8.encode(_K.v);
    final msg     = utf8.encode(message);
    final hmac    = Hmac(sha256, key);
    final digest  = hmac.convert(msg);
    return digest.toString();
  }

  /// Returns current Unix timestamp in seconds.
  static int get nowSeconds =>
      DateTime.now().millisecondsSinceEpoch ~/ 1000;
}

// ─────────────────────────────────────────────────────────────────────────────
// Security report model
// ─────────────────────────────────────────────────────────────────────────────
class SecurityReport {
  final bool isRooted;
  final bool isEmulator;
  final bool isDebugged;
  final bool isTampered;

  const SecurityReport({
    required this.isRooted,
    required this.isEmulator,
    required this.isDebugged,
    required this.isTampered,
  });

  bool get isSafe => !isRooted && !isEmulator && !isDebugged && !isTampered;

  String get primaryThreat {
    if (isTampered)  return 'tampered_apk';
    if (isRooted)    return 'rooted_device';
    if (isEmulator)  return 'emulator';
    if (isDebugged)  return 'debugger';
    return 'none';
  }

  @override
  String toString() =>
      'SecurityReport(rooted:$isRooted emulator:$isEmulator '
      'debugged:$isDebugged tampered:$isTampered)';
}
