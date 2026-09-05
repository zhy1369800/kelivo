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

  /// Lists all security-scoped bookmarks granted by the user.
  static Future<List<Map<String, dynamic>>> listBookmarks() async {
    if (!isSupported) return const [];
    try {
      final res =
          await _channel.invokeMapMethod<String, dynamic>('list_bookmarks');
      final list = res?['bookmarks'];
      if (list is List) {
        return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    return const [];
  }

  /// Revokes security-scoped access for a specific granted path.
  static Future<bool> revokeBookmark(String path) async {
    if (!isSupported) return false;
    try {
      final res = await _channel
          .invokeMapMethod<String, dynamic>('revoke', {'path': path});
      return res?['revoked'] == true;
    } catch (_) {}
    return false;
  }
}
