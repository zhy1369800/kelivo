import 'package:flutter/services.dart';

/// Dart-side wrapper for CoreBluetooth BLE operations (`app.ble_bridge` MethodChannel).
class NativeBleBridgeService {
  static const _channel = MethodChannel('app.ble_bridge');

  /// Gets current Bluetooth adapter status.
  static Future<Map<String, dynamic>> getStatus() async {
    final res = await _channel.invokeMapMethod<String, dynamic>('getStatus');
    return Map<String, dynamic>.from(res ?? {});
  }

  /// Scans for nearby BLE peripherals for [durationSeconds].
  static Future<Map<String, dynamic>> scan({
    double durationSeconds = 5.0,
  }) async {
    final res = await _channel.invokeMapMethod<String, dynamic>(
      'scan',
      {'duration_seconds': durationSeconds},
    );
    return Map<String, dynamic>.from(res ?? {});
  }

  /// Connects to a peripheral by its [uuid].
  static Future<Map<String, dynamic>> connect({
    required String uuid,
  }) async {
    final res = await _channel.invokeMapMethod<String, dynamic>(
      'connect',
      {'uuid': uuid},
    );
    return Map<String, dynamic>.from(res ?? {});
  }

  /// Disconnects from a peripheral by its [uuid].
  static Future<Map<String, dynamic>> disconnect({
    required String uuid,
  }) async {
    final res = await _channel.invokeMapMethod<String, dynamic>(
      'disconnect',
      {'uuid': uuid},
    );
    return Map<String, dynamic>.from(res ?? {});
  }

  /// Discovers GATT services and characteristics for a connected peripheral [uuid].
  static Future<Map<String, dynamic>> discoverServices({
    required String uuid,
  }) async {
    final res = await _channel.invokeMapMethod<String, dynamic>(
      'discoverServices',
      {'uuid': uuid},
    );
    return Map<String, dynamic>.from(res ?? {});
  }

  /// Reads a characteristic value for peripheral [uuid], [serviceUuid], and [characteristicUuid].
  static Future<Map<String, dynamic>> readCharacteristic({
    required String uuid,
    required String serviceUuid,
    required String characteristicUuid,
  }) async {
    final res = await _channel.invokeMapMethod<String, dynamic>(
      'read',
      {
        'uuid': uuid,
        'service_uuid': serviceUuid,
        'characteristic_uuid': characteristicUuid,
      },
    );
    return Map<String, dynamic>.from(res ?? {});
  }

  /// Writes a hex string or text string to a characteristic.
  static Future<Map<String, dynamic>> writeCharacteristic({
    required String uuid,
    required String serviceUuid,
    required String characteristicUuid,
    String? valueHex,
    String? valueString,
  }) async {
    final res = await _channel.invokeMapMethod<String, dynamic>(
      'write',
      {
        'uuid': uuid,
        'service_uuid': serviceUuid,
        'characteristic_uuid': characteristicUuid,
        if (valueHex != null) 'value_hex': valueHex,
        if (valueString != null) 'value_string': valueString,
      },
    );
    return Map<String, dynamic>.from(res ?? {});
  }
}
