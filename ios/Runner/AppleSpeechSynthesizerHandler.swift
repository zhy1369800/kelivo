import Foundation
import AVFoundation
import Flutter

final class AppleSpeechSynthesizerHandler: NSObject, AVSpeechSynthesizerDelegate {
  private let synthesizer = AVSpeechSynthesizer()
  private var activeResult: FlutterResult?

  override init() {
    super.init()
    synthesizer.delegate = self
  }

  func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "speak":
      speak(args: args, result: result)
    case "synthesizeToFile", "writeToFile":
      synthesizeToFile(args: args, result: result)
    case "getVoices", "listVoices":
      getVoices(args: args, result: result)
    case "stop":
      stopSpeech(result: result)
    case "pause":
      pauseSpeech(result: result)
    case "continue", "resume":
      continueSpeech(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - 1. Speak (Real-time Playback)

  private func speak(args: [String: Any], result: @escaping FlutterResult) {
    guard let text = args["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      result(FlutterError(code: "invalid_args", message: "Parameter 'text' is required.", details: nil))
      return
    }

    let language = (args["language"] as? String) ?? "zh-CN"
    let voiceIdentifier = args["voice"] as? String
    let rate = (args["rate"] as? Float) ?? 0.5
    let pitch = (args["pitch"] as? Float) ?? 1.0
    let volume = (args["volume"] as? Float) ?? 1.0

    let utterance = AVSpeechUtterance(string: text)

    // Select Voice
    if let voiceId = voiceIdentifier, !voiceId.isEmpty, let matchedVoice = AVSpeechSynthesisVoice(identifier: voiceId) {
      utterance.voice = matchedVoice
    } else if let langVoice = AVSpeechSynthesisVoice(language: language) {
      utterance.voice = langVoice
    } else {
      utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
    }

    // Set Properties
    utterance.rate = min(max(rate * AVSpeechUtteranceDefaultSpeechRate * 2.0, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
    utterance.pitchMultiplier = min(max(pitch, 0.5), 2.0)
    utterance.volume = min(max(volume, 0.0), 1.0)

    if synthesizer.isSpeaking {
      synthesizer.stopSpeaking(at: .immediate)
    }

    // Configure Audio Session for Speech Output
    do {
      let audioSession = AVAudioSession.sharedInstance()
      try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
      try audioSession.setActive(true)
    } catch {
      // Non-fatal audio session setup
    }

    synthesizer.speak(utterance)

    result([
      "success": true,
      "speaking": true,
      "text_length": text.count,
      "language": utterance.voice?.language ?? language,
      "voice_name": utterance.voice?.name ?? "Default"
    ])
  }

  // MARK: - 2. Synthesize To File

  private func synthesizeToFile(args: [String: Any], result: @escaping FlutterResult) {
    guard let text = args["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      result(FlutterError(code: "invalid_args", message: "Parameter 'text' is required.", details: nil))
      return
    }

    let language = (args["language"] as? String) ?? "zh-CN"
    let voiceIdentifier = args["voice"] as? String
    let rate = (args["rate"] as? Float) ?? 0.5
    let pitch = (args["pitch"] as? Float) ?? 1.0

    let utterance = AVSpeechUtterance(string: text)

    if let voiceId = voiceIdentifier, !voiceId.isEmpty, let matchedVoice = AVSpeechSynthesisVoice(identifier: voiceId) {
      utterance.voice = matchedVoice
    } else if let langVoice = AVSpeechSynthesisVoice(language: language) {
      utterance.voice = langVoice
    }

    utterance.rate = min(max(rate * AVSpeechUtteranceDefaultSpeechRate * 2.0, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
    utterance.pitchMultiplier = min(max(pitch, 0.5), 2.0)

    let fileName = "tts_\(Int(Date().timeIntervalSince1970)).caf"
    let outputPath: String
    if let customPath = args["output_path"] as? String, !customPath.isEmpty {
      outputPath = customPath
    } else {
      let tmpDir = NSTemporaryDirectory()
      outputPath = (tmpDir as NSString).appendingPathComponent(fileName)
    }

    let outputUrl = URL(fileURLWithPath: outputPath)

    if #available(iOS 13.0, *) {
      var outputSettings: [String: Any]?
      var audioFile: AVAudioFile?

      synthesizer.write(utterance) { buffer in
        guard let pcmBuffer = buffer as? AVAudioPCMBuffer else { return }
        if pcmBuffer.frameLength == 0 { return }

        if audioFile == nil {
          outputSettings = pcmBuffer.format.settings
          do {
            audioFile = try AVAudioFile(forWriting: outputUrl, settings: outputSettings!, commonFormat: pcmBuffer.format.commonFormat, interleaved: pcmBuffer.format.isInterleaved)
          } catch {
            return
          }
        }

        do {
          try audioFile?.write(from: pcmBuffer)
        } catch {
          // Ignore writing frame error
        }
      }

      DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: outputPath)[.size] as? Int64) ?? 0
        result([
          "success": true,
          "file_path": outputPath,
          "file_size_bytes": fileSize,
          "text_length": text.count
        ])
      }
    } else {
      result(FlutterError(code: "not_supported", message: "Audio file synthesis requires iOS 13.0 or later.", details: nil))
    }
  }

  // MARK: - 3. Get Voices

  private func getVoices(args: [String: Any], result: @escaping FlutterResult) {
    let filterLang = args["language"] as? String
    let allVoices = AVSpeechSynthesisVoice.speechVoices()

    var voiceList = [[String: Any]]()
    for v in allVoices {
      if let filter = filterLang, !filter.isEmpty {
        if !v.language.lowercased().contains(filter.lowercased()) {
          continue
        }
      }

      var qualityString = "default"
      if #available(iOS 16.0, *) {
        switch v.quality {
        case .premium: qualityString = "premium"
        case .enhanced: qualityString = "enhanced"
        default: qualityString = "default"
        }
      } else if v.quality == .enhanced {
        qualityString = "enhanced"
      }

      voiceList.append([
        "identifier": v.identifier,
        "name": v.name,
        "language": v.language,
        "quality": qualityString
      ])
    }

    result([
      "count": voiceList.count,
      "voices": voiceList
    ])
  }

  // MARK: - 4. Controls (Stop / Pause / Continue)

  private func stopSpeech(result: @escaping FlutterResult) {
    let stopped = synthesizer.stopSpeaking(at: .immediate)
    result(["stopped": stopped])
  }

  private func pauseSpeech(result: @escaping FlutterResult) {
    let paused = synthesizer.pauseSpeaking(at: .immediate)
    result(["paused": paused])
  }

  private func continueSpeech(result: @escaping FlutterResult) {
    let continued = synthesizer.continueSpeaking()
    result(["continued": continued])
  }

  // MARK: - AVSpeechSynthesizerDelegate

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    // Reset Audio Session
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }
}
