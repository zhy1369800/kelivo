import 'package:flutter/services.dart';

/// Dart-side service wrapper for Apple WeatherKit (`app.weather_kit` channel).
class NativeWeatherKitService {
  static const _channel = MethodChannel('app.weather_kit');

  /// Fetches weather data (current, hourly forecast, daily forecast, weather alerts)
  /// for the specified GPS coordinates [latitude] and [longitude].
  static Future<Map<String, dynamic>> getWeather({
    required double latitude,
    required double longitude,
  }) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'getWeather',
      {
        'latitude': latitude,
        'longitude': longitude,
      },
    );
    return Map<String, dynamic>.from(result ?? {});
  }
}
