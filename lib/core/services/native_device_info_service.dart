import 'package:flutter/services.dart';

/// Dart-side wrapper for UIKit & NSProcessInfo device operations (`app.device_info` MethodChannel).
class NativeDeviceInfoService {
  static const _channel = MethodChannel('app.device_info');

  /// Gets comprehensive device hardware, OS, CPU, RAM, battery, and storage info.
  static Future<Map<String, dynamic>> getInfo() async {
    final res = await _channel.invokeMapMethod<String, dynamic>('getInfo');
    return Map<String, dynamic>.from(res ?? {});
  }

  /// Gets battery level percentage and charging state.
  static Future<Map<String, dynamic>> getBattery() async {
    final res = await _channel.invokeMapMethod<String, dynamic>('getBattery');
    return Map<String, dynamic>.from(res ?? {});
  }

  /// Gets disk storage space (total, free, used in GB and bytes).
  static Future<Map<String, dynamic>> getStorage() async {
    final res = await _channel.invokeMapMethod<String, dynamic>('getStorage');
    return Map<String, dynamic>.from(res ?? {});
  }
}
