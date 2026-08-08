import Foundation
import UserNotifications
import Flutter

final class UserNotificationHandler: NSObject {
  private let notificationCenter = UNUserNotificationCenter.current()

  func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "getSettings":
      getSettings(result: result)
    case "requestPermission":
      requestPermission(result: result)
    case "schedule":
      schedule(args: args, result: result)
    case "getPending":
      getPending(result: result)
    case "getDelivered":
      getDelivered(result: result)
    case "cancel":
      cancel(args: args, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Get Settings

  private func getSettings(result: @escaping FlutterResult) {
    notificationCenter.getNotificationSettings { settings in
      let statusString: String
      switch settings.authorizationStatus {
      case .authorized: statusString = "authorized"
      case .denied: statusString = "denied"
      case .notDetermined: statusString = "not_determined"
      case .provisional: statusString = "provisional"
      case .ephemeral: statusString = "ephemeral"
      @unknown default: statusString = "unknown"
      }

      DispatchQueue.main.async {
        result([
          "authorization_status": statusString,
          "sound_enabled": settings.soundSetting == .enabled,
          "badge_enabled": settings.badgeSetting == .enabled,
          "alert_enabled": settings.alertSetting == .enabled,
          "lock_screen_enabled": settings.lockScreenSetting == .enabled,
          "notification_center_enabled": settings.notificationCenterSetting == .enabled,
        ])
      }
    }
  }

  // MARK: - Request Permission

  private func requestPermission(result: @escaping FlutterResult) {
    notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
      DispatchQueue.main.async {
        if let error = error {
          result(FlutterError(code: "permission_error", message: error.localizedDescription, details: nil))
        } else {
          result(["granted": granted])
        }
      }
    }
  }

  // MARK: - Schedule Notification

  private func schedule(args: [String: Any], result: @escaping FlutterResult) {
    let title = (args["title"] as? String) ?? "Kelivo Notification"
    let subtitle = (args["subtitle"] as? String) ?? ""
    let body = (args["body"] as? String) ?? ""
    let sound = (args["sound"] as? Bool) ?? true
    let afterSeconds = (args["after_seconds"] as? Double) ?? 1.0
    let customId = (args["id"] as? String) ?? "notif_\(Int(Date().timeIntervalSince1970 * 1000))"

    let content = UNMutableNotificationContent()
    content.title = title
    content.subtitle = subtitle
    content.body = body
    if sound {
      content.sound = .default
    }

    // Trigger after N seconds (minimum 0.1s for UNTimeIntervalNotificationTrigger)
    let triggerInterval = max(0.1, afterSeconds)
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: triggerInterval, repeats: false)

    let request = UNNotificationRequest(identifier: customId, content: content, trigger: trigger)

    notificationCenter.add(request) { error in
      DispatchQueue.main.async {
        if let error = error {
          result(FlutterError(code: "schedule_failed", message: error.localizedDescription, details: nil))
        } else {
          let formatter = ISO8601DateFormatter()
          let fireDate = Date().addingTimeInterval(triggerInterval)
          result([
            "success": true,
            "id": customId,
            "title": title,
            "body": body,
            "after_seconds": triggerInterval,
            "scheduled_time": formatter.string(from: fireDate)
          ])
        }
      }
    }
  }

  // MARK: - Pending Notifications

  private func getPending(result: @escaping FlutterResult) {
    notificationCenter.getPendingNotificationRequests { requests in
      let items: [[String: Any]] = requests.map { req in
        var dict: [String: Any] = [
          "id": req.identifier,
          "title": req.content.title,
          "subtitle": req.content.subtitle,
          "body": req.content.body
        ]
        if let trigger = req.trigger as? UNTimeIntervalNotificationTrigger {
          dict["trigger_type"] = "time_interval"
          dict["interval_seconds"] = trigger.timeInterval
          if let nextDate = trigger.nextTriggerDate() {
            dict["next_trigger_time"] = ISO8601DateFormatter().string(from: nextDate)
          }
        }
        return dict
      }

      DispatchQueue.main.async {
        result([
          "pending": items,
          "count": items.count
        ])
      }
    }
  }

  // MARK: - Delivered Notifications

  private func getDelivered(result: @escaping FlutterResult) {
    notificationCenter.getDeliveredNotifications { notifications in
      let items: [[String: Any]] = notifications.map { notif in
        let req = notif.request
        return [
          "id": req.identifier,
          "title": req.content.title,
          "subtitle": req.content.subtitle,
          "body": req.content.body,
          "delivered_time": ISO8601DateFormatter().string(from: notif.date)
        ]
      }

      DispatchQueue.main.async {
        result([
          "delivered": items,
          "count": items.count
        ])
      }
    }
  }

  // MARK: - Cancel Notifications

  private func cancel(args: [String: Any], result: @escaping FlutterResult) {
    let cancelAll = (args["all"] as? Bool) ?? false
    let notifId = args["id"] as? String

    if cancelAll {
      notificationCenter.removeAllPendingNotificationRequests()
      result(["success": true, "message": "All pending notifications cancelled."])
    } else if let id = notifId, !id.isEmpty {
      notificationCenter.removePendingNotificationRequests(withIdentifiers: [id])
      result(["success": true, "id": id, "message": "Pending notification '\(id)' cancelled."])
    } else {
      result(FlutterError(code: "invalid_args", message: "Provide either 'id' or set 'all' to true.", details: nil))
    }
  }
}
