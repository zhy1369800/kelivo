import 'package:flutter/services.dart';

/// Dart-side wrapper for UserNotifications operations (`app.user_notification` MethodChannel).
class NativeUserNotificationService {
  static const _channel = MethodChannel('app.user_notification');

  /// Gets current local notification settings and authorization status.
  static Future<Map<String, dynamic>> getSettings() async {
    final res = await _channel.invokeMapMethod<String, dynamic>('getSettings');
    return Map<String, dynamic>.from(res ?? {});
  }

  /// Requests local notification permission (alert, sound, badge).
  static Future<Map<String, dynamic>> requestPermission() async {
    final res = await _channel.invokeMapMethod<String, dynamic>('requestPermission');
    return Map<String, dynamic>.from(res ?? {});
  }

  /// Schedules an immediate or delayed local notification.
  static Future<Map<String, dynamic>> schedule({
    required String title,
    String? subtitle,
    required String body,
    double afterSeconds = 1.0,
    bool sound = true,
    String? id,
  }) async {
    final res = await _channel.invokeMapMethod<String, dynamic>(
      'schedule',
      {
        'title': title,
        if (subtitle != null) 'subtitle': subtitle,
        'body': body,
        'after_seconds': afterSeconds,
        'sound': sound,
        if (id != null) 'id': id,
      },
    );
    return Map<String, dynamic>.from(res ?? {});
  }

  /// Gets all pending (scheduled) notification requests.
  static Future<Map<String, dynamic>> getPending() async {
    final res = await _channel.invokeMapMethod<String, dynamic>('getPending');
    return Map<String, dynamic>.from(res ?? {});
  }

  /// Gets all delivered notifications currently in Notification Center.
  static Future<Map<String, dynamic>> getDelivered() async {
    final res = await _channel.invokeMapMethod<String, dynamic>('getDelivered');
    return Map<String, dynamic>.from(res ?? {});
  }

  /// Cancels a pending notification by [id] or cancels [all] pending notifications.
  static Future<Map<String, dynamic>> cancel({
    String? id,
    bool all = false,
  }) async {
    final res = await _channel.invokeMapMethod<String, dynamic>(
      'cancel',
      {
        if (id != null) 'id': id,
        'all': all,
      },
    );
    return Map<String, dynamic>.from(res ?? {});
  }
}
