import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Dart-side wrapper for iOS Files/iCloud document access (`app.file_system`).
class NativeFileSystemService {
  static const _channel = MethodChannel('app.file_system');

  static bool get isSupported => defaultTargetPlatform == TargetPlatform.iOS;

  static Future<Map<String, dynamic>> invoke(Map<String, dynamic> args) async {
    if (!isSupported) {
      return {
        'error': 'platform_not_supported',
        'message': 'File system tool currently requires iOS.',
      };
    }
    final action = (args['action'] ?? '').toString();
    final res = await _channel.invokeMapMethod<String, dynamic>(action, args);
    return Map<String, dynamic>.from(res ?? {});
  }
}
