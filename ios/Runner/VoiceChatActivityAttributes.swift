import ActivityKit
import Foundation

@available(iOS 16.1, *)
public struct VoiceChatActivityAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    public var state: String // "listening", "processing", "aiSpeaking", "idle"
    public var stateLabel: String // "在听呢...", "AI 思考中...", "AI 回复中..."
    public var transcript: String // 实时字幕 / 用户输入或 AI 回复
    public var assistantName: String
    public var waveLevel: Double // 0.0 ~ 1.0
    public var isFinished: Bool
    public var timestamp: Date

    public init(
      state: String,
      stateLabel: String,
      transcript: String,
      assistantName: String,
      waveLevel: Double,
      isFinished: Bool,
      timestamp: Date = Date()
    ) {
      self.state = state
      self.stateLabel = stateLabel
      self.transcript = transcript
      self.assistantName = assistantName
      self.waveLevel = waveLevel
      self.isFinished = isFinished
      self.timestamp = timestamp
    }
  }

  public var sessionId: String
  public var assistantName: String
  public var avatarPath: String?

  public init(sessionId: String, assistantName: String, avatarPath: String? = nil) {
    self.sessionId = sessionId
    self.assistantName = assistantName
    self.avatarPath = avatarPath
  }
}
