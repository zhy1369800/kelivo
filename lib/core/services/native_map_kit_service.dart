import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Dart-side wrapper for the `app.map_kit` Flutter MethodChannel.
///
/// Provides:
/// - [searchPlaces]   → MKLocalSearch  (place / POI search)
/// - [getRoute]       → MKDirections.calculate  (full route with steps)
/// - [getEta]         → MKDirections.calculateETA  (lightweight ETA)
/// - [openNavigation] → Apple Maps URL scheme (url_launcher, no native needed)
class NativeMapKitService {
  static const _channel = MethodChannel('app.map_kit');

  // ---------------------------------------------------------------------------
  // Search places via MKLocalSearch
  // ---------------------------------------------------------------------------

  static Future<Map<String, dynamic>> searchPlaces({
    required String query,
    double? latitude,
    double? longitude,
    double radiusMeters = 1000,
    int limit = 10,
  }) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'searchPlaces',
      {
        'query': query,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        'radius_meters': radiusMeters,
        'limit': limit,
      },
    );
    return Map<String, dynamic>.from(result ?? {});
  }

  // ---------------------------------------------------------------------------
  // Full route (steps + distance + duration) via MKDirections.calculate
  // ---------------------------------------------------------------------------

  static Future<Map<String, dynamic>> getRoute({
    String? fromAddress,
    double? fromLatitude,
    double? fromLongitude,
    String? toAddress,
    double? toLatitude,
    double? toLongitude,
    String mode = 'driving',
  }) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'getRoute',
      {
        if (fromAddress != null) 'from_address': fromAddress,
        if (fromLatitude != null) 'from_latitude': fromLatitude,
        if (fromLongitude != null) 'from_longitude': fromLongitude,
        if (toAddress != null) 'to_address': toAddress,
        if (toLatitude != null) 'to_latitude': toLatitude,
        if (toLongitude != null) 'to_longitude': toLongitude,
        'mode': mode,
      },
    );
    return Map<String, dynamic>.from(result ?? {});
  }

  // ---------------------------------------------------------------------------
  // Lightweight ETA via MKDirections.calculateETA
  // ---------------------------------------------------------------------------

  static Future<Map<String, dynamic>> getEta({
    String? fromAddress,
    double? fromLatitude,
    double? fromLongitude,
    String? toAddress,
    double? toLatitude,
    double? toLongitude,
    String mode = 'driving',
  }) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'getEta',
      {
        if (fromAddress != null) 'from_address': fromAddress,
        if (fromLatitude != null) 'from_latitude': fromLatitude,
        if (fromLongitude != null) 'from_longitude': fromLongitude,
        if (toAddress != null) 'to_address': toAddress,
        if (toLatitude != null) 'to_latitude': toLatitude,
        if (toLongitude != null) 'to_longitude': toLongitude,
        'mode': mode,
      },
    );
    return Map<String, dynamic>.from(result ?? {});
  }

  // ---------------------------------------------------------------------------
  // Open Apple Maps for navigation (URL scheme, no native channel needed)
  // ---------------------------------------------------------------------------

  /// Builds and launches an Apple Maps URL.
  /// Returns true if Maps app was opened successfully.
  static Future<bool> openNavigation({
    String? fromAddress,
    double? fromLatitude,
    double? fromLongitude,
    String? toAddress,
    double? toLatitude,
    double? toLongitude,
    String mode = 'driving',
  }) async {
    final dirflg = switch (mode.toLowerCase()) {
      'walking' => 'w',
      'transit' => 'r',
      _ => 'd',
    };

    String saddr = '';
    if (fromLatitude != null && fromLongitude != null) {
      saddr = '$fromLatitude,$fromLongitude';
    } else if (fromAddress != null && fromAddress.isNotEmpty) {
      saddr = Uri.encodeComponent(fromAddress);
    }

    String daddr = '';
    if (toLatitude != null && toLongitude != null) {
      daddr = '$toLatitude,$toLongitude';
    } else if (toAddress != null && toAddress.isNotEmpty) {
      daddr = Uri.encodeComponent(toAddress);
    }

    final params = <String>[];
    if (saddr.isNotEmpty) params.add('saddr=$saddr');
    if (daddr.isNotEmpty) params.add('daddr=$daddr');
    params.add('dirflg=$dirflg');

    final uri = Uri.parse('maps://?${params.join('&')}');
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
