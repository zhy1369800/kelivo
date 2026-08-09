import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Dart-side wrapper for Apple Vision Framework operations (`app.apple_vision` MethodChannel).
class NativeAppleVisionService {
  static const _channel = MethodChannel('app.apple_vision');

  static bool get isSupported => defaultTargetPlatform == TargetPlatform.iOS;

  /// Performs offline OCR text recognition on an image file.
  static Future<Map<String, dynamic>> recognizeText({
    required String imagePath,
    List<String>? languages,
    bool accurate = true,
  }) async {
    if (!isSupported) {
      return {
        'error': 'platform_not_supported',
        'message': 'Apple Vision text recognition requires iOS platform.',
      };
    }
    final res = await _channel.invokeMapMethod<String, dynamic>(
      'ocr',
      {
        'image_path': imagePath,
        if (languages != null) 'languages': languages,
        'accurate': accurate,
      },
    );
    return Map<String, dynamic>.from(res ?? {});
  }

  /// Detects QR codes and barcodes in an image file.
  static Future<Map<String, dynamic>> detectBarcodes({
    required String imagePath,
  }) async {
    if (!isSupported) {
      return {
        'error': 'platform_not_supported',
        'message': 'Apple Vision barcode detection requires iOS platform.',
      };
    }
    final res = await _channel.invokeMapMethod<String, dynamic>(
      'detectBarcodes',
      {'image_path': imagePath},
    );
    return Map<String, dynamic>.from(res ?? {});
  }

  /// Detects faces and facial landmarks in an image file.
  static Future<Map<String, dynamic>> detectFaces({
    required String imagePath,
    bool includeLandmarks = false,
  }) async {
    if (!isSupported) {
      return {
        'error': 'platform_not_supported',
        'message': 'Apple Vision face detection requires iOS platform.',
      };
    }
    final res = await _channel.invokeMapMethod<String, dynamic>(
      'detectFaces',
      {
        'image_path': imagePath,
        'include_landmarks': includeLandmarks,
      },
    );
    return Map<String, dynamic>.from(res ?? {});
  }

  /// Classifies image content using Apple Vision built-in taxonomy.
  static Future<Map<String, dynamic>> classifyImage({
    required String imagePath,
    int maxResults = 10,
    double minConfidence = 0.05,
  }) async {
    if (!isSupported) {
      return {
        'error': 'platform_not_supported',
        'message': 'Apple Vision image classification requires iOS platform.',
      };
    }
    final res = await _channel.invokeMapMethod<String, dynamic>(
      'classifyImage',
      {
        'image_path': imagePath,
        'max_results': maxResults,
        'min_confidence': minConfidence,
      },
    );
    return Map<String, dynamic>.from(res ?? {});
  }

  /// Runs all Vision inspection requests (OCR, barcodes, faces, classification) in a single pass.
  static Future<Map<String, dynamic>> analyzeAll({
    required String imagePath,
  }) async {
    if (!isSupported) {
      return {
        'error': 'platform_not_supported',
        'message': 'Apple Vision analysis requires iOS platform.',
      };
    }
    final res = await _channel.invokeMapMethod<String, dynamic>(
      'analyzeAll',
      {'image_path': imagePath},
    );
    return Map<String, dynamic>.from(res ?? {});
  }
}
