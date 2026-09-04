import ActivityKit
import AVFoundation
import Flutter
import Foundation
import UIKit

@available(iOS 16.1, *)
public class VoiceChatLiveActivityHandler: NSObject {
  public static let shared = VoiceChatLiveActivityHandler()

  private var currentActivity: Activity<VoiceChatActivityAttributes>?
  private var channel: FlutterMethodChannel?
  private var isObservingDarwinNotification = false
  private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
  private var audioPlayer: AVAudioPlayer?

  private func beginBackgroundTask() {
    endBackgroundTask()
    backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "KelivoVoiceChatKeepAlive") { [weak self] in
      self?.endBackgroundTask()
    }
  }

  private func endBackgroundTask() {
    if backgroundTask != .invalid {
      UIApplication.shared.endBackgroundTask(backgroundTask)
      backgroundTask = .invalid
    }
  }

  private func startAudioKeepAlive() {
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(
        .playAndRecord,
        mode: .voiceChat,
        options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP, .mixWithOthers]
      )
      try session.setActive(true)
      try session.overrideOutputAudioPort(.speaker)

      if audioPlayer == nil {
        audioPlayer = createSilentAudioPlayer()
      }
      audioPlayer?.numberOfLoops = -1
      audioPlayer?.volume = 0.001
      audioPlayer?.play()
    } catch {
      NSLog("VoiceChat startAudioKeepAlive failed: \(error)")
    }
  }

  private func stopAudioKeepAlive() {
    audioPlayer?.stop()
    audioPlayer = nil
  }

  private func createSilentAudioPlayer() -> AVAudioPlayer? {
    let sampleRate: Double = 44100.0
    let duration: Double = 1.0
    let numSamples = Int(sampleRate * duration)
    let numChannels: Int = 1
    let bitsPerSample: Int = 16
    let byteRate = Int(sampleRate * Double(numChannels * bitsPerSample / 8))
    let blockAlign = numChannels * bitsPerSample / 8
    let subchunk2Size = numSamples * blockAlign
    let chunkSize = 36 + subchunk2Size

    var data = Data()
    data.append(contentsOf: "RIFF".utf8)
    var chunkSizeBytes = UInt32(chunkSize).littleEndian
    data.append(Data(bytes: &chunkSizeBytes, count: 4))
    data.append(contentsOf: "WAVE".utf8)
    data.append(contentsOf: "fmt ".utf8)
    var subchunk1Size = UInt32(16).littleEndian
    data.append(Data(bytes: &subchunk1Size, count: 4))
    var audioFormat = UInt16(1).littleEndian
    data.append(Data(bytes: &audioFormat, count: 2))
    var channels = UInt16(numChannels).littleEndian
    data.append(Data(bytes: &channels, count: 2))
    var sampleRateVal = UInt32(sampleRate).littleEndian
    data.append(Data(bytes: &sampleRateVal, count: 4))
    var byteRateVal = UInt32(byteRate).littleEndian
    data.append(Data(bytes: &byteRateVal, count: 4))
    var blockAlignVal = UInt16(blockAlign).littleEndian
    data.append(Data(bytes: &blockAlignVal, count: 2))
    var bitsPerSampleVal = UInt16(bitsPerSample).littleEndian
    data.append(Data(bytes: &bitsPerSampleVal, count: 2))
    data.append(contentsOf: "data".utf8)
    var subchunk2SizeBytes = UInt32(subchunk2Size).littleEndian
    data.append(Data(bytes: &subchunk2SizeBytes, count: 4))
    data.append(Data(repeating: 0, count: subchunk2Size))

    do {
      let p = try AVAudioPlayer(data: data)
      p.prepareToPlay()
      return p
    } catch {
      NSLog("Error creating silent audio player: \(error)")
      return nil
    }
  }

  public func setup(binaryMessenger: FlutterBinaryMessenger) {
    let methodChannel = FlutterMethodChannel(
      name: "app.voice_chat_live_activity",
      binaryMessenger: binaryMessenger
    )
    self.channel = methodChannel

    methodChannel.setMethodCallHandler { [weak self] (call, result) in
      self?.handle(call, result: result)
    }

    setupDarwinNotificationObserver()
  }

  private func setupDarwinNotificationObserver() {
    guard !isObservingDarwinNotification else { return }
    isObservingDarwinNotification = true

    let notificationName = "psyche.kelivo.voice_chat.stop" as CFString
    let observer = Unmanaged.passUnretained(self).toOpaque()

    CFNotificationCenterAddObserver(
      CFNotificationCenterGetDarwinNotifyCenter(),
      observer,
      { _, observer, _, _, _ in
        guard let observer = observer else { return }
        let handler = Unmanaged<VoiceChatLiveActivityHandler>.fromOpaque(observer).takeUnretainedValue()
        DispatchQueue.main.async {
          handler.handleStopFromWidget()
        }
      },
      notificationName,
      nil,
      .deliverImmediately
    )
  }

  public func handleStopFromWidget() {
    // 通知 Flutter 停止语音对话
    channel?.invokeMethod("onStopFromLiveActivity", arguments: nil)
    stopActivity()
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "start":
      guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "INVALID_ARGS", message: "Arguments missing", details: nil))
        return
      }
      let sessionId = args["sessionId"] as? String ?? UUID().uuidString
      let assistantName = args["assistantName"] as? String ?? "AI 助手"
      let avatarPath = args["avatarPath"] as? String

      startActivity(sessionId: sessionId, assistantName: assistantName, avatarPath: avatarPath)
      result(true)

    case "update":
      guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "INVALID_ARGS", message: "Arguments missing", details: nil))
        return
      }
      let state = args["state"] as? String ?? "listening"
      let stateLabel = args["stateLabel"] as? String ?? "在听呢..."
      let transcript = args["transcript"] as? String ?? ""
      let assistantName = args["assistantName"] as? String ?? "AI 助手"
      let waveLevel = (args["waveLevel"] as? NSNumber)?.doubleValue ?? 0.1
      let isFinished = args["isFinished"] as? Bool ?? false

      updateActivity(
        state: state,
        stateLabel: stateLabel,
        transcript: transcript,
        assistantName: assistantName,
        waveLevel: waveLevel,
        isFinished: isFinished
      )
      result(true)

    case "stop":
      stopActivity()
      result(true)

    case "isSupported":
      result(ActivityAuthorizationInfo().areActivitiesEnabled)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func startActivity(sessionId: String, assistantName: String, avatarPath: String?) {
    beginBackgroundTask()
    startAudioKeepAlive()

    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

    // 先清理已有活动
    if currentActivity != nil {
      stopActivity()
      beginBackgroundTask()
      startAudioKeepAlive()
    }

    let attributes = VoiceChatActivityAttributes(
      sessionId: sessionId,
      assistantName: assistantName,
      avatarPath: avatarPath
    )

    let initialState = VoiceChatActivityAttributes.ContentState(
      state: "listening",
      stateLabel: "在听呢...",
      transcript: "",
      assistantName: assistantName,
      waveLevel: 0.1,
      isFinished: false
    )

    do {
      if #available(iOS 16.2, *) {
        currentActivity = try Activity<VoiceChatActivityAttributes>.request(
          attributes: attributes,
          content: ActivityContent(state: initialState, staleDate: nil),
          pushType: nil
        )
      } else {
        currentActivity = try Activity<VoiceChatActivityAttributes>.request(
          attributes: attributes,
          contentState: initialState,
          pushType: nil
        )
      }
    } catch {
      NSLog("Kelivo VoiceChat Live Activity start failed: \(error)")
      currentActivity = nil
    }
  }

  public func updateActivity(
    state: String,
    stateLabel: String,
    transcript: String,
    assistantName: String,
    waveLevel: Double,
    isFinished: Bool
  ) {
    // 确保后台任务持续有效
    if backgroundTask == .invalid && !isFinished {
      beginBackgroundTask()
    }

    guard let activity = currentActivity else { return }

    let contentState = VoiceChatActivityAttributes.ContentState(
      state: state,
      stateLabel: stateLabel,
      transcript: transcript,
      assistantName: assistantName,
      waveLevel: waveLevel,
      isFinished: isFinished
    )

    Task {
      if #available(iOS 16.2, *) {
        await activity.update(ActivityContent(state: contentState, staleDate: nil))
      } else {
        await activity.update(using: contentState)
      }
    }
  }

  public func stopActivity() {
    endBackgroundTask()
    stopAudioKeepAlive()

    guard let activity = currentActivity else { return }

    Task {
      if #available(iOS 16.2, *) {
        await activity.end(nil, dismissalPolicy: .immediate)
      } else {
        let finalState = VoiceChatActivityAttributes.ContentState(
          state: "idle",
          stateLabel: "已结束",
          transcript: "",
          assistantName: "",
          waveLevel: 0,
          isFinished: true
        )
        await activity.end(using: finalState, dismissalPolicy: .immediate)
      }
    }

    currentActivity = nil
  }
}
