import 'package:flutter/services.dart';

/// Dart-side wrapper for HealthKit operations (`app.health_kit` MethodChannel).
class NativeHealthKitService {
  static const _channel = MethodChannel('app.health_kit');

  /// Requests HealthKit read & write permissions.
  static Future<Map<String, dynamic>> requestPermission() async {
    final res = await _channel.invokeMapMethod<String, dynamic>('requestPermission');
    return Map<String, dynamic>.from(res ?? {});
  }

  /// Queries daily step count history over the last [days].
  static Future<Map<String, dynamic>> querySteps({int days = 7}) async {
    final res = await _channel.invokeMapMethod<String, dynamic>(
      'querySteps',
      {'days': days},
    );
    return Map<String, dynamic>.from(res ?? {});
  }

  /// Queries heart rate samples with limit [limit].
  static Future<Map<String, dynamic>> queryHeartRate({int limit = 20}) async {
    final res = await _channel.invokeMapMethod<String, dynamic>(
      'queryHeartRate',
      {'limit': limit},
    );
    return Map<String, dynamic>.from(res ?? {});
  }

  /// Queries sleep analysis over the last [days].
  static Future<Map<String, dynamic>> querySleep({int days = 7}) async {
    final res = await _channel.invokeMapMethod<String, dynamic>(
      'querySleep',
      {'days': days},
    );
    return Map<String, dynamic>.from(res ?? {});
  }

  /// Queries active & basal energy burned (kcal) for today.
  static Future<Map<String, dynamic>> queryEnergy() async {
    final res = await _channel.invokeMapMethod<String, dynamic>('queryEnergy');
    return Map<String, dynamic>.from(res ?? {});
  }

  /// Queries latest weight (kg), height (cm), and BMI.
  static Future<Map<String, dynamic>> queryBody() async {
    final res = await _channel.invokeMapMethod<String, dynamic>('queryBody');
    return Map<String, dynamic>.from(res ?? {});
  }

  /// Queries dietary calories (kcal) and water (ml) for today.
  static Future<Map<String, dynamic>> queryNutrition() async {
    final res = await _channel.invokeMapMethod<String, dynamic>('queryNutrition');
    return Map<String, dynamic>.from(res ?? {});
  }

  /// Logs a new health sample into HealthKit.
  /// Supported types: 'steps', 'weight', 'water', 'heart_rate', 'calories'.
  static Future<Map<String, dynamic>> logSample({
    required String type,
    required double value,
  }) async {
    final res = await _channel.invokeMapMethod<String, dynamic>(
      'logSample',
      {
        'type': type,
        'value': value,
      },
    );
    return Map<String, dynamic>.from(res ?? {});
  }

  /// Gets a aggregated health summary for today.
  static Future<Map<String, dynamic>> getSummary() async {
    final res = await _channel.invokeMapMethod<String, dynamic>('getSummary');
    return Map<String, dynamic>.from(res ?? {});
  }
}
