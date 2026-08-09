import Foundation
import UserNotifications
import Flutter

final class AlarmTimerHandler: NSObject {
  private let center = UNUserNotificationCenter.current()

  func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "requestPermission":
      requestPermission(result: result)
    case "setAlarm":
      setAlarm(args: args, result: result)
    case "setTimer":
      setTimer(args: args, result: result)
    case "list":
      listPending(result: result)
    case "cancel":
      cancel(args: args, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Permission

  private func requestPermission(result: @escaping FlutterResult) {
    center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
      DispatchQueue.main.async {
        if let error = error {
          result(FlutterError(code: "permission_error", message: error.localizedDescription, details: nil))
        } else {
          result(["authorized": granted])
        }
      }
    }
  }

  // MARK: - Set Alarm

  private func setAlarm(args: [String: Any], result: @escaping FlutterResult) {
    guard let timeStr = args["time"] as? String, !timeStr.isEmpty else {
      result(FlutterError(code: "invalid_args", message: "Parameter 'time' is required.", details: nil))
      return
    }

    let label = (args["label"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "闹钟"
    let repeatMode = (args["repeat"] as? String)?.lowercased() ?? "none"

    var hour = 7
    var minute = 30
    var isISO = false
    var isoDate: Date?

    // Try HH:MM parse
    let components = timeStr.components(separatedBy: ":")
    if components.count == 2, let h = Int(components[0]), let m = Int(components[1]) {
      hour = h
      minute = m
    } else {
      let isoFormatter = ISO8601DateFormatter()
      if let parsed = isoFormatter.date(from: timeStr) {
        isISO = true
        isoDate = parsed
      }
    }

    let content = UNMutableNotificationContent()
    content.title = label
    content.body = "闹钟响铃了！"
    content.sound = .default

    let trigger: UNNotificationTrigger
    var alarmDateComponents = DateComponents()

    if isISO, let date = isoDate {
      alarmDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
      trigger = UNCalendarNotificationTrigger(dateMatching: alarmDateComponents, repeats: false)
    } else {
      alarmDateComponents.hour = hour
      alarmDateComponents.minute = minute

      var repeats = false
      if repeatMode == "daily" {
        repeats = true
      } else if repeatMode == "weekdays" {
        // Simple daily repeat for weekdays
        repeats = true
      } else {
        // One-time alarm
        let now = Date()
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0

        if let scheduled = cal.date(from: comps), scheduled <= now {
          // If time is past for today, schedule for tomorrow
          if let tomorrow = cal.date(byAdding: .day, value: 1, to: scheduled) {
            alarmDateComponents = cal.dateComponents([.year, .month, .day, .hour, .minute], from: tomorrow)
          }
        }
      }

      trigger = UNCalendarNotificationTrigger(dateMatching: alarmDateComponents, repeats: repeats)
    }

    let id = "alarm_\(UUID().uuidString)"
    let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

    center.add(request) { error in
      DispatchQueue.main.async {
        if let error = error {
          result(FlutterError(code: "add_failed", message: error.localizedDescription, details: nil))
        } else {
          let timeStr: String
          if isISO, let date = isoDate {
            let cal = Calendar.current
            let h = cal.component(.hour, from: date)
            let m = cal.component(.minute, from: date)
            timeStr = String(format: "%02d:%02d", h, m)
          } else {
            timeStr = String(format: "%02d:%02d", hour, minute)
          }
          result([
            "success": true,
            "id": id,
            "label": label,
            "time": timeStr,
            "repeat": repeatMode,
            "message": "Alarm set successfully."
          ])
        }
      }
    }
  }

  // MARK: - Set Timer (Countdown)

  private func setTimer(args: [String: Any], result: @escaping FlutterResult) {
    var seconds: Double = 0

    if let durNum = args["duration_seconds"] as? NSNumber {
      seconds = durNum.doubleValue
    } else if let durStr = args["duration"] as? String {
      seconds = parseDurationString(durStr)
    }

    if seconds <= 0 {
      result(FlutterError(code: "invalid_args", message: "Valid duration in seconds or string (e.g. '5m', '300') is required.", details: nil))
      return
    }

    let label = (args["label"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "倒计时定时器"

    let content = UNMutableNotificationContent()
    content.title = label
    content.body = "倒计时结束！"
    content.sound = .default

    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(0.1, seconds), repeats: false)
    let id = "timer_\(UUID().uuidString)"
    let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

    center.add(request) { error in
      DispatchQueue.main.async {
        if let error = error {
          result(FlutterError(code: "add_failed", message: error.localizedDescription, details: nil))
        } else {
          result([
            "success": true,
            "id": id,
            "label": label,
            "duration_seconds": Int(seconds),
            "message": "Timer started successfully."
          ])
        }
      }
    }
  }

  // MARK: - List Pending

  private func listPending(result: @escaping FlutterResult) {
    center.getPendingNotificationRequests { requests in
      let isoFormatter = ISO8601DateFormatter()
      var items = [[String: Any]]()

      for req in requests {
        if req.identifier.hasPrefix("alarm_") || req.identifier.hasPrefix("timer_") {
          var item: [String: Any] = [
            "id": req.identifier,
            "label": req.content.title,
            "type": req.identifier.hasPrefix("alarm_") ? "alarm" : "timer"
          ]

          if let calTrigger = req.trigger as? UNCalendarNotificationTrigger,
             let nextDate = calTrigger.nextTriggerDate() {
            item["next_trigger_date"] = isoFormatter.string(from: nextDate)
          } else if let timeTrigger = req.trigger as? UNTimeIntervalNotificationTrigger,
                    let nextDate = timeTrigger.nextTriggerDate() {
            item["next_trigger_date"] = isoFormatter.string(from: nextDate)
          }

          items.append(item)
        }
      }

      DispatchQueue.main.async {
        result([
          "count": items.count,
          "items": items
        ])
      }
    }
  }

  // MARK: - Cancel

  private func cancel(args: [String: Any], result: @escaping FlutterResult) {
    let cancelAll = (args["all"] as? Bool) ?? false
    if cancelAll {
      center.removeAllPendingNotificationRequests()
      result(["success": true, "cancelled_all": true, "message": "All alarms and timers cancelled."])
      return
    }

    guard let id = args["id"] as? String, !id.isEmpty else {
      result(FlutterError(code: "invalid_args", message: "ID is required for cancel.", details: nil))
      return
    }

    center.removePendingNotificationRequests(withIdentifiers: [id])
    result(["success": true, "id": id, "message": "Cancelled alarm/timer with ID '\(id)'."])
  }

  // MARK: - Helper

  private func parseDurationString(_ str: String) -> Double {
    let s = str.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if let plainVal = Double(s) {
      return plainVal
    }

    var totalSeconds: Double = 0
    let scanner = Scanner(string: s)
    while !scanner.isAtEnd {
      var val: Double = 0
      if scanner.scanDouble(&val) {
        if scanner.scanString("h", into: nil) || scanner.scanString("小时", into: nil) {
          totalSeconds += val * 3600
        } else if scanner.scanString("m", into: nil) || scanner.scanString("分钟", into: nil) || scanner.scanString("分", into: nil) {
          totalSeconds += val * 60
        } else if scanner.scanString("s", into: nil) || scanner.scanString("秒", into: nil) {
          totalSeconds += val
        } else {
          totalSeconds += val
        }
      } else {
        break
      }
    }
    return totalSeconds
  }
}
