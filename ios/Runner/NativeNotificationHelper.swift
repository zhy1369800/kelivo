import Foundation
import UserNotifications
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Kelivo", category: "NativeNotificationHelper")

final class NativeNotificationHelper {
    static let shared = NativeNotificationHelper()

    private init() {}

    /// 发送本地通知
    func sendNotification(id: String = UUID().uuidString, title: String, body: String, userInfo: [String: Any] = [:]) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                logger.warning("Notification permission not granted, requesting...")
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    if granted {
                        self.schedule(id: id, title: title, body: body, userInfo: userInfo)
                    }
                }
                return
            }
            self.schedule(id: id, title: title, body: body, userInfo: userInfo)
        }
    }

    private func schedule(id: String, title: String, body: String, userInfo: [String: Any]) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = userInfo

        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil) // 立即触发
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                logger.error("Failed to post notification: \(error.localizedDescription)")
            } else {
                logger.info("Notification posted successfully: \(title)")
            }
        }
    }
}
