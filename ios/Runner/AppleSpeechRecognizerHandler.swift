import Foundation
import Speech
import AVFoundation
import Flutter

final class AppleSpeechRecognizerHandler: NSObject {
  func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "transcribeFile", "recognizeFile":
      transcribeFile(args: args, result: result)
    case "getLocales", "supportedLocales":
      getSupportedLocales(result: result)
    case "requestPermission":
      requestPermission(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - 1. Transcribe Audio File

  private func transcribeFile(args: [String: Any], result: @escaping FlutterResult) {
    guard let path = args["audio_path"] as? String, !path.isEmpty else {
      result(FlutterError(code: "invalid_args", message: "Parameter 'audio_path' is required.", details: nil))
      return
    }

    let cleanPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
    let fileUrl = URL(fileURLWithPath: cleanPath)

    guard FileManager.default.fileExists(atPath: cleanPath) else {
      result(FlutterError(code: "file_not_found", message: "Audio file at path '\(cleanPath)' does not exist.", details: nil))
      return
    }

    let localeStr = (args["locale"] as? String) ?? "zh-CN"
    let forceOffline = (args["force_offline"] as? Bool) ?? true
    let locale = Locale(identifier: localeStr)

    guard let recognizer = SFSpeechRecognizer(locale: locale) else {
      result(FlutterError(code: "locale_not_supported", message: "Speech recognizer does not support locale '\(localeStr)'.", details: nil))
      return
    }

    if !recognizer.isAvailable {
      result(FlutterError(code: "recognizer_unavailable", message: "Speech recognizer for locale '\(localeStr)' is currently unavailable.", details: nil))
      return
    }

    // Check Authorization
    let authStatus = SFSpeechRecognizer.authorizationStatus()
    if authStatus != .authorized {
      SFSpeechRecognizer.requestAuthorization { status in
        if status == .authorized {
          self.executeFileTranscription(recognizer: recognizer, fileUrl: fileUrl, localeStr: localeStr, forceOffline: forceOffline, result: result)
        } else {
          DispatchQueue.main.async {
            result(FlutterError(code: "permission_denied", message: "Speech recognition permission was not granted (status: \(status.rawValue)).", details: nil))
          }
        }
      }
    } else {
      executeFileTranscription(recognizer: recognizer, fileUrl: fileUrl, localeStr: localeStr, forceOffline: forceOffline, result: result)
    }
  }

  private func executeFileTranscription(
    recognizer: SFSpeechRecognizer,
    fileUrl: URL,
    localeStr: String,
    forceOffline: Bool,
    result: @escaping FlutterResult
  ) {
    let request = SFSpeechURLRecognitionRequest(url: fileUrl)
    if #available(iOS 13.0, *) {
      request.requiresOnDeviceRecognition = forceOffline
    }
    request.shouldReportPartialResults = false

    recognizer.recognitionTask(with: request) { taskResult, error in
      if let error = error {
        DispatchQueue.main.async {
          result(FlutterError(code: "transcription_failed", message: error.localizedDescription, details: nil))
        }
        return
      }

      guard let taskResult = taskResult else { return }

      if taskResult.isFinal {
        let bestTranscription = taskResult.bestTranscription
        var segments = [[String: Any]]()

        for segment in bestTranscription.segments {
          segments.append([
            "text": segment.substring,
            "timestamp": (segment.timestamp * 100).rounded() / 100,
            "duration": (segment.duration * 100).rounded() / 100,
            "confidence": (segment.confidence * 100).rounded() / 100
          ])
        }

        let isOnDevice: Bool
        if #available(iOS 13.0, *) {
          isOnDevice = recognizer.supportsOnDeviceRecognition
        } else {
          isOnDevice = false
        }

        DispatchQueue.main.async {
          result([
            "text": bestTranscription.formattedString,
            "locale": localeStr,
            "is_final": true,
            "is_on_device": isOnDevice,
            "segment_count": segments.count,
            "segments": segments
          ])
        }
      }
    }
  }

  // MARK: - 2. Supported Locales

  private func getSupportedLocales(result: @escaping FlutterResult) {
    let supported = SFSpeechRecognizer.supportedLocales()
    var localeList = [[String: Any]]()

    for loc in supported {
      var info: [String: Any] = [
        "identifier": loc.identifier,
        "display_name": Locale.current.localizedString(forIdentifier: loc.identifier) ?? loc.identifier
      ]
      if #available(iOS 13.0, *), let rec = SFSpeechRecognizer(locale: loc) {
        info["supports_on_device"] = rec.supportsOnDeviceRecognition
      } else {
        info["supports_on_device"] = false
      }
      localeList.append(info)
    }

    // Sort by identifier
    localeList.sort { ($0["identifier"] as? String ?? "") < ($1["identifier"] as? String ?? "") }

    result([
      "count": localeList.count,
      "locales": localeList
    ])
  }

  // MARK: - 3. Permission Request

  private func requestPermission(result: @escaping FlutterResult) {
    SFSpeechRecognizer.requestAuthorization { status in
      let statusString: String
      switch status {
      case .authorized: statusString = "authorized"
      case .denied: statusString = "denied"
      case .restricted: statusString = "restricted"
      case .notDetermined: statusString = "notDetermined"
      @unknown default: statusString = "unknown"
      }

      DispatchQueue.main.async {
        result([
          "status": statusString,
          "is_authorized": status == .authorized
        ])
      }
    }
  }
}
