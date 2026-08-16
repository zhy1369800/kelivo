import Foundation
import UserNotifications
import Flutter

#if canImport(AlarmKit)
import AlarmKit

@available(iOS 26.0, *)
private struct KelivoAlarmMetadata: AlarmMetadata {}
#endif

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
    case "openClockApp":
      openClockApp(args: args, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Permission

  private func ensurePermission(completion: @escaping (Bool) -> Void) {
    #if canImport(AlarmKit)
    if #available(iOS 26.0, *) {
      Task {
        let manager = AlarmManager.shared
        switch manager.authorizationState {
        case .authorized:
          completion(true)
        case .notDetermined:
          do {
            let state = try await manager.requestAuthorization()
            if state == .authorized {
              completion(true)
            } else {
              self.fallbackEnsureUNPermission(completion: completion)
            }
          } catch {
            self.fallbackEnsureUNPermission(completion: completion)
          }
        case .denied:
          self.fallbackEnsureUNPermission(completion: completion)
        @unknown default:
          self.fallbackEnsureUNPermission(completion: completion)
        }
      }
      return
    }
    #endif
    fallbackEnsureUNPermission(completion: completion)
  }

  private func fallbackEnsureUNPermission(completion: @escaping (Bool) -> Void) {
    center.getNotificationSettings { settings in
      if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
        completion(true)
      } else if settings.authorizationStatus == .notDetermined {
        self.center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
          completion(granted)
        }
      } else {
        completion(false)
      }
    }
  }

  private func requestPermission(result: @escaping FlutterResult) {
    #if canImport(AlarmKit)
    if #available(iOS 26.0, *) {
      Task {
        do {
          let state = try await AlarmManager.shared.requestAuthorization()
          let granted = (state == .authorized)
          DispatchQueue.main.async {
            result(["authorized": granted])
          }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "permission_error", message: error.localizedDescription, details: nil))
          }
        }
      }
      return
    }
    #endif

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

    let components = timeStr.components(separatedBy: ":")
    if components.count >= 2, let h = Int(components[0]), let m = Int(components[1]) {
      hour = h
      minute = m
    } else {
      let isoFormatter = ISO8601DateFormatter()
      if let parsed = isoFormatter.date(from: timeStr) {
        isISO = true
        isoDate = parsed
      }
    }

    ensurePermission { [weak self] granted in
      guard let self = self else { return }
      guard granted else {
        DispatchQueue.main.async {
          result(FlutterError(code: "permission_denied", message: "Notification / Alarm permission is not granted.", details: nil))
        }
        return
      }

      let now = Date()
      let cal = Calendar.current
      var targetDate: Date

      if isISO, let date = isoDate {
        targetDate = date
      } else {
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        if let scheduled = cal.date(from: comps) {
          if scheduled <= now {
            targetDate = cal.date(byAdding: .day, value: 1, to: scheduled) ?? scheduled
          } else {
            targetDate = scheduled
          }
        } else {
          targetDate = now.addingTimeInterval(60)
        }
      }

      var alarmId = "alarm_\(UUID().uuidString)"

      #if canImport(AlarmKit)
      if #available(iOS 26.0, *) {
        Task {
          do {
            let manager = AlarmManager.shared
            let stopBtn = AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.circle")
            let alert = AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: label), stopButton: stopBtn)
            let attributes = AlarmAttributes<KelivoAlarmMetadata>(presentation: AlarmPresentation(alert: alert), tintColor: .blue)

            let schedule: Alarm.Schedule
            if repeatMode == "daily" {
              let comps = cal.dateComponents([.hour, .minute], from: targetDate)
              schedule = .relative(Alarm.Schedule.Relative(
                time: Alarm.Schedule.Relative.Time(hour: comps.hour ?? hour, minute: comps.minute ?? minute),
                repeats: .weekly([.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday])
              ))
            } else if repeatMode == "weekdays" {
              let comps = cal.dateComponents([.hour, .minute], from: targetDate)
              schedule = .relative(Alarm.Schedule.Relative(
                time: Alarm.Schedule.Relative.Time(hour: comps.hour ?? hour, minute: comps.minute ?? minute),
                repeats: .weekly([.monday, .tuesday, .wednesday, .thursday, .friday])
              ))
            } else {
              schedule = .fixed(targetDate)
            }

            let config = AlarmManager.AlarmConfiguration(schedule: schedule, attributes: attributes)
            let uuid = UUID()
            alarmId = "alarm_\(uuid.uuidString)"
            _ = try await manager.schedule(id: uuid, configuration: config)
          } catch {
            // AlarmKit failed, proceed with UserNotifications fallback below
          }

          // Always add UserNotifications request as well for double reliability
      self.scheduleUNAlarm(id: alarmId, label: label, repeatMode: repeatMode, hour: hour, minute: minute, targetDate: targetDate, isISO: isISO, isoDate: isoDate, result: result)
    }
        return
  }
      #endif

      self.scheduleUNAlarm(id: alarmId, label: label, repeatMode: repeatMode, hour: hour, minute: minute, targetDate: targetDate, isISO: isISO, isoDate: isoDate, result: result)
    }
  }

  private func scheduleUNAlarm(
    id: String,
    label: String,
    repeatMode: String,
    hour: Int,
    minute: Int,
    targetDate: Date,
    isISO: Bool,
    isoDate: Date?,
    result: @escaping FlutterResult
  ) {
    let content = UNMutableNotificationContent()
    content.title = label
    content.body = "闹钟响铃了！"
    content.sound = .default

    let trigger: UNNotificationTrigger
    var alarmDateComponents = DateComponents()

    if isISO, let date = isoDate {
      alarmDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
      trigger = UNCalendarNotificationTrigger(dateMatching: alarmDateComponents, repeats: false)
    } else if repeatMode == "daily" || repeatMode == "weekdays" {
      alarmDateComponents.hour = hour
      alarmDateComponents.minute = minute
      trigger = UNCalendarNotificationTrigger(dateMatching: alarmDateComponents, repeats: true)
    } else {
      alarmDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: targetDate)
      trigger = UNCalendarNotificationTrigger(dateMatching: alarmDateComponents, repeats: false)
    }

    let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

    center.add(request) { error in
      DispatchQueue.main.async {
        if let error = error {
          result(FlutterError(code: "add_failed", message: error.localizedDescription, details: nil))
        } else {
          let formattedTime: String
          if isISO, let date = isoDate {
            let cal = Calendar.current
            let h = cal.component(.hour, from: date)
            let m = cal.component(.minute, from: date)
            formattedTime = String(format: "%02d:%02d", h, m)
          } else {
            formattedTime = String(format: "%02d:%02d", hour, minute)
          }
          result([
            "success": true,
            "id": id,
            "label": label,
            "time": formattedTime,
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

    ensurePermission { [weak self] granted in
      guard let self = self else { return }
      guard granted else {
        DispatchQueue.main.async {
          result(FlutterError(code: "permission_denied", message: "Notification / Alarm permission is not granted.", details: nil))
        }
        return
      }

      var timerId = "timer_\(UUID().uuidString)"

      #if canImport(AlarmKit)
      if #available(iOS 26.0, *) {
        Task {
          do {
            let manager = AlarmManager.shared
            let stopBtn = AlarmButton(text: "Done", textColor: .green, systemImageName: "checkmark")
            let alert = AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: label), stopButton: stopBtn)
            let attributes = AlarmAttributes<KelivoAlarmMetadata>(presentation: AlarmPresentation(alert: alert), tintColor: .orange)

            let countdown = Alarm.CountdownDuration(preAlert: max(0.1, seconds), postAlert: nil)
            let config = AlarmManager.AlarmConfiguration(countdownDuration: countdown, attributes: attributes)
            let uuid = UUID()
            timerId = "timer_\(uuid.uuidString)"
            _ = try await manager.schedule(id: uuid, configuration: config)
          } catch {
            // Fallback to UNTimeIntervalNotificationTrigger
          }

      self.scheduleUNTimer(id: timerId, label: label, seconds: seconds, result: result)
    }
        return
  }
      #endif

      self.scheduleUNTimer(id: timerId, label: label, seconds: seconds, result: result)
    }
  }

  private func scheduleUNTimer(
    id: String,
    label: String,
    seconds: Double,
    result: @escaping FlutterResult
  ) {
    let content = UNMutableNotificationContent()
    content.title = label
    content.body = "倒计时结束！"
    content.sound = .default

    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(0.1, seconds), repeats: false)
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

      #if canImport(AlarmKit)
      if #available(iOS 26.0, *) {
        Task {
          do {
            let manager = AlarmManager.shared
            for await alarms in manager.alarmUpdates {
              for alarm in alarms {
                let rawUuid = alarm.id.uuidString
                if let index = items.firstIndex(where: {
                  let existingId = ($0["id"] as? String) ?? ""
                  return existingId.contains(rawUuid)
                }) {
                  items[index]["state"] = "\(alarm.state)"
                } else {
                  var item: [String: Any] = [
                    "id": "alarm_\(rawUuid)",
                    "type": alarm.countdownDuration != nil ? "timer" : "alarm",
                    "state": "\(alarm.state)"
                  ]
                  if let sched = alarm.schedule {
                    if case .fixed(let date) = sched {
                      item["next_trigger_date"] = isoFormatter.string(from: date)
                    }
                  }
                  items.append(item)
                }
              }
              break
            }
          } catch {
            // Ignore AlarmKit query error
          }

          DispatchQueue.main.async {
            result([
              "count": items.count,
              "items": items
            ])
          }
        }
        return
      }
      #endif

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

      #if canImport(AlarmKit)
      if #available(iOS 26.0, *) {
        Task {
          let manager = AlarmManager.shared
          for await alarms in manager.alarmUpdates {
            for alarm in alarms {
              try? manager.cancel(id: alarm.id)
            }
            break
          }
          DispatchQueue.main.async {
            result(["success": true, "cancelled_all": true, "message": "All alarms and timers cancelled."])
          }
        }
        return
      }
      #endif

      result(["success": true, "cancelled_all": true, "message": "All alarms and timers cancelled."])
      return
    }

    guard let rawId = args["id"] as? String, !rawId.isEmpty else {
      result(FlutterError(code: "invalid_args", message: "ID is required for cancel.", details: nil))
      return
    }

    let cleanUuidStr = rawId.replacingOccurrences(of: "alarm_", with: "").replacingOccurrences(of: "timer_", with: "")
    center.removePendingNotificationRequests(withIdentifiers: [rawId, "timer_\(cleanUuidStr)", "alarm_\(cleanUuidStr)"])

    #if canImport(AlarmKit)
    if #available(iOS 26.0, *) {
      if let uuid = UUID(uuidString: cleanUuidStr) {
        try? AlarmManager.shared.cancel(id: uuid)
      }
    }
    #endif

    result(["success": true, "id": rawId, "message": "Cancelled alarm/timer with ID '\(rawId)'."])
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

  // MARK: - Open Clock App

  private func openClockApp(args: [String: Any], result: @escaping FlutterResult) {
    let type = (args["type"] as? String)?.lowercased() ?? "alarm"
    let urlString = type == "timer" ? "clock-timer://" : "clock-alarm://"

    DispatchQueue.main.async {
      if let url = URL(string: urlString), UIApplication.shared.canOpenURL(url) {
        UIApplication.shared.open(url, options: [:]) { success in
          result(["success": success, "message": "Opened Apple Clock App (\(type))."])
        }
      } else if let fallbackUrl = URL(string: "clock://"), UIApplication.shared.canOpenURL(fallbackUrl) {
        UIApplication.shared.open(fallbackUrl, options: [:]) { success in
          result(["success": success, "message": "Opened Apple Clock App."])
        }
      } else {
        result(FlutterError(code: "open_failed", message: "Unable to open Apple Clock App on this device.", details: nil))
      }
    }
  }
}
