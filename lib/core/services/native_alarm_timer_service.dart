import 'package:flutter/services.dart';

/// Dart-side wrapper for Alarm & Timer operations (`app.alarm_timer` MethodChannel).
class NativeAlarmTimerService {
  static const _channel = MethodChannel('app.alarm_timer');

  /// Requests Notification permissions for Alarm/Timer.
  static Future<Map<String, dynamic>> requestPermission() async {
    final res = await _channel.invokeMapMethod<String, dynamic>('requestPermission');
    return Map<String, dynamic>.from(res ?? {});
  }

  /// Sets an alarm at a specific time (e.g. "07:30" or ISO string).
  static Future<Map<String, dynamic>> setAlarm({
    required String time,
    String label = '闹钟',
    String repeat = 'none',
  }) async {
    final res = await _channel.invokeMapMethod<String, dynamic>(
      'setAlarm',
      {
        'time': time,
        'label': label,
        'repeat': repeat,
      },
    );
    return Map<String, dynamic>.from(res ?? {});
  }

  /// Sets a countdown timer (e.g. durationSeconds: 300 or duration: "5m").
  static Future<Map<String, dynamic>> setTimer({
    int? durationSeconds,
    String? duration,
    String label = '倒计时定时器',
  }) async {
    final res = await _channel.invokeMapMethod<String, dynamic>(
      'setTimer',
      {
        if (durationSeconds != null) 'duration_seconds': durationSeconds,
        if (duration != null) 'duration': duration,
        'label': label,
      },
    );
    return Map<String, dynamic>.from(res ?? {});
  }

  /// Lists all pending alarms and timers.
  static Future<Map<String, dynamic>> list() async {
    final res = await _channel.invokeMapMethod<String, dynamic>('list');
    return Map<String, dynamic>.from(res ?? {});
  }

  /// Cancels an alarm or timer by [id], or cancels all if [all] is true.
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

  /// Opens Apple's native Clock App to show Alarms or Timers on screen.
  static Future<Map<String, dynamic>> openClockApp({String type = 'alarm'}) async {
    final res = await _channel.invokeMapMethod<String, dynamic>(
      'openClockApp',
      {'type': type},
    );
    return Map<String, dynamic>.from(res ?? {});
  }
}
