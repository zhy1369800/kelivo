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

  // MARK: - Permission Helper

  private func ensurePermission(completion: @escaping (Bool) -> Void) {
    notificationCenter.getNotificationSettings { settings in
      if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
        completion(true)
      } else if settings.authorizationStatus == .notDetermined {
        self.notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
          completion(granted)
        }
      } else {
        completion(false)
      }
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
    let customId = (args["id"] as? String) ?? "notif_\(Int(Date().timeIntervalSince1970 * 1000))"
    let atTimeStr = args["at_time"] as? String

    // Safely cast NSNumber to double for seconds offset
    let afterSeconds: Double?
    if let num = args["after_seconds"] as? NSNumber {
      afterSeconds = num.doubleValue
    } else {
      afterSeconds = nil
    }

    ensurePermission { [weak self] granted in
      guard let self = self else { return }
      guard granted else {
        DispatchQueue.main.async {
          result(FlutterError(code: "permission_denied", message: "Notification permission is not granted. Please enable notifications in System Settings.", details: nil))
        }
        return
      }

      let content = UNMutableNotificationContent()
      content.title = title
      content.subtitle = subtitle
      content.body = body
      if sound {
        content.sound = .default
      }

      let trigger: UNNotificationTrigger
      let isoFormatter = ISO8601DateFormatter()
      let fireDate: Date

      if let atTimeStr = atTimeStr, let parsedDate = isoFormatter.date(from: atTimeStr) {
        fireDate = parsedDate
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: parsedDate)
        trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
      } else {
        let sec = max(0.1, afterSeconds ?? 1.0)
        fireDate = Date().addingTimeInterval(sec)
        trigger = UNTimeIntervalNotificationTrigger(timeInterval: sec, repeats: false)
      }

      let request = UNNotificationRequest(identifier: customId, content: content, trigger: trigger)

      self.notificationCenter.add(request) { error in
        DispatchQueue.main.async {
          if let error = error {
            result(FlutterError(code: "schedule_failed", message: error.localizedDescription, details: nil))
          } else {
            result([
              "success": true,
              "id": customId,
              "title": title,
              "body": body,
              "scheduled_time": isoFormatter.string(from: fireDate)
            ])
          }
        }
      }
    }
  }

  // MARK: - Pending Notifications

  private func getPending(result: @escaping FlutterResult) {
    notificationCenter.getPendingNotificationRequests { requests in
      let isoFormatter = ISO8601DateFormatter()
      let items: [[String: Any]] = requests.map { req in
        var dict: [String: Any] = [
          "id": req.identifier,
          "title": req.content.title,
          "subtitle": req.content.subtitle,
          "body": req.content.body
        ]
        if let timeTrigger = req.trigger as? UNTimeIntervalNotificationTrigger {
          dict["trigger_type"] = "time_interval"
          dict["interval_seconds"] = timeTrigger.timeInterval
          if let nextDate = timeTrigger.nextTriggerDate() {
            dict["next_trigger_time"] = isoFormatter.string(from: nextDate)
          }
        } else if let calTrigger = req.trigger as? UNCalendarNotificationTrigger {
          dict["trigger_type"] = "calendar"
          if let nextDate = calTrigger.nextTriggerDate() {
            dict["next_trigger_time"] = isoFormatter.string(from: nextDate)
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
      let isoFormatter = ISO8601DateFormatter()
      let items: [[String: Any]] = notifications.map { notif in
        let req = notif.request
        return [
          "id": req.identifier,
          "title": req.content.title,
          "subtitle": req.content.subtitle,
          "body": req.content.body,
          "delivered_time": isoFormatter.string(from: notif.date)
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
