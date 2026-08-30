import AppIntents
import Foundation

@available(iOS 17.0, *)
public struct StopVoiceChatIntent: LiveActivityIntent {
  public static var title: LocalizedStringResource = "停止语音对话"
  public static var description = IntentDescription("结束当前正在进行的实时语音通话")

  public init() {}

  public func perform() async throws -> some IntentResult {
    // 发送 Darwin Notification 通知主 App 进程
    let notificationName = CFNotificationName("psyche.kelivo.voice_chat.stop" as CFString)
    CFNotificationCenterPostNotification(
      CFNotificationCenterGetDarwinNotifyCenter(),
      notificationName,
      nil,
      nil,
      true
    )

    // 写入共享 App Group 标记
    if let sharedDefaults = UserDefaults(suiteName: "group.psyche.kelivo") {
      sharedDefaults.set(true, forKey: "voice_chat_stop_requested")
      sharedDefaults.synchronize()
    }

    return .result()
  }
}
