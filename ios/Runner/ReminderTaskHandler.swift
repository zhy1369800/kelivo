import Foundation
import EventKit
import CoreLocation
import Flutter

// MARK: - Location Auth Delegate (semaphore bridge for async CLLocationManager)

private final class ReminderLocAuthDelegate: NSObject, CLLocationManagerDelegate {
  let semaphore = DispatchSemaphore(value: 0)
  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    semaphore.signal()
  }
}

final class ReminderTaskHandler: NSObject {
  private let eventStore = EKEventStore()

  func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "requestPermission":
      requestPermission(result: result)
    case "requestLocationPermission":
      requestLocationPermission(result: result)
    case "listReminders":
      listReminders(args: args, result: result)
    case "createReminder":
      createReminder(args: args, result: result)
    case "updateReminder":
      updateReminder(args: args, result: result)
    case "completeReminder":
      completeReminder(args: args, result: result)
    case "deleteReminder":
      deleteReminder(args: args, result: result)
    case "listLists":
      listLists(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Permission

  private func requestPermission(result: @escaping FlutterResult) {
    if #available(iOS 17.0, *) {
      eventStore.requestFullAccessToReminders { granted, error in
        DispatchQueue.main.async {
          if let error = error {
            result(FlutterError(code: "permission_error", message: error.localizedDescription, details: nil))
          } else {
            result(["authorized": granted])
          }
        }
      }
    } else {
      eventStore.requestAccess(to: .reminder) { granted, error in
        DispatchQueue.main.async {
          if let error = error {
            result(FlutterError(code: "permission_error", message: error.localizedDescription, details: nil))
          } else {
            result(["authorized": granted])
          }
        }
      }
    }
  }

  private func requestLocationPermission(result: @escaping FlutterResult) {
    DispatchQueue.global(qos: .userInitiated).async {
      var errMsg: String? = nil
      let granted = self.reminderLocationAuth(errMsg: &errMsg)
      DispatchQueue.main.async {
        result(["authorized": granted, "message": errMsg ?? ""])
      }
    }
  }

  // MARK: - Location Auth

  /// Check (and if undetermined, request) location authorization for geofence alarms.
  /// Returns true when usable (whenInUse or always). On false, errMsg is set.
  private func reminderLocationAuth(errMsg: inout String?) -> Bool {
    var manager: CLLocationManager!
    let delegate = ReminderLocAuthDelegate()

    DispatchQueue.main.sync {
      manager = CLLocationManager()
    }
    var status = manager.authorizationStatus

    if status == .notDetermined {
      DispatchQueue.main.async {
        manager.delegate = delegate
        manager.requestWhenInUseAuthorization()
      }
      // Wait for initial status callback, then for user answer
      _ = delegate.semaphore.wait(timeout: .now() + 5)
      _ = delegate.semaphore.wait(timeout: .now() + 60)
      status = manager.authorizationStatus
    }

    if status == .authorizedWhenInUse || status == .authorizedAlways {
      return true
    }
    errMsg = "Location access is required for location-based reminders. " +
             "Open Settings > Privacy & Security > Location Services and enable the app. " +
             "Time-based reminders (due_date) work without location access."
    return false
  }

  // MARK: - Location Alarm Helpers

  /// Serialize the geofence alarm (if any) on a reminder for list/create/update output.
  private func reminderLocationDict(_ reminder: EKReminder) -> [String: Any]? {
    for alarm in reminder.alarms ?? [] {
      guard let loc = alarm.structuredLocation,
            alarm.proximity != .none else { continue }
      var d: [String: Any] = [
        "name": loc.title ?? "",
        "radius_m": loc.radius,
        "proximity": alarm.proximity == .leave ? "leave" : "enter"
      ]
      if let geo = loc.geoLocation {
        d["latitude"] = geo.coordinate.latitude
        d["longitude"] = geo.coordinate.longitude
      }
      return d
    }
    return nil
  }

  /// Parse lat/lng/radius/proximity args and attach a geofence alarm to the reminder.
  /// Returns nil on success, or a FlutterError on failure.
  private func applyLocationAlarm(args: [String: Any], reminder: EKReminder) -> FlutterError? {
    guard let latAny = args["lat"], let lngAny = args["lng"] else {
      // No location args → no-op
      return nil
    }
    guard let lat = (latAny as? NSNumber)?.doubleValue,
          let lng = (lngAny as? NSNumber)?.doubleValue else {
      return FlutterError(code: "invalid_args",
                          message: "lat and lng must be numeric (WGS-84 decimal degrees).",
                          details: nil)
    }
    guard lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180 else {
      return FlutterError(code: "invalid_args",
                          message: "lat must be in [-90,90], lng in [-180,180].",
                          details: nil)
    }

    let radius = (args["radius"] as? NSNumber)?.doubleValue ?? 0
    let locationName = (args["location_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                     ?? String(format: "%.4f,%.4f", lat, lng)

    var proximity: EKAlarmProximity = .enter
    if let proxStr = args["proximity"] as? String {
      let p = proxStr.lowercased()
      if p == "leave" || p == "exit" {
        proximity = .leave
      } else if p == "enter" || p == "arrive" {
        proximity = .enter
      } else {
        return FlutterError(code: "invalid_args",
                            message: "Invalid proximity '\(proxStr)'. Use 'enter' or 'leave'.",
                            details: nil)
      }
    }

    // Check location authorization
    var authErr: String? = nil
    guard reminderLocationAuth(errMsg: &authErr) else {
      return FlutterError(code: "location_permission_denied", message: authErr, details: nil)
    }

    // Remove existing location alarms (idempotent update)
    for alarm in (reminder.alarms ?? []) {
      if alarm.structuredLocation != nil && alarm.proximity != .none {
        reminder.removeAlarm(alarm)
      }
    }

    let loc = EKStructuredLocation(title: locationName)
    loc.geoLocation = CLLocation(latitude: lat, longitude: lng)
    loc.radius = radius
    let alarm = EKAlarm()
    alarm.structuredLocation = loc
    alarm.proximity = proximity
    reminder.addAlarm(alarm)
    return nil
  }

  // MARK: - Recurrence Helpers

  /// Parse recur/recur_interval/recur_days/recur_count/recur_until from args.
  /// Returns nil when no --recur given (one-off). On error, sets errMsg and returns nil.
  private func buildRecurrenceRule(args: [String: Any], anchor: Date?) -> (EKRecurrenceRule?, FlutterError?) {
    guard let freqStr = args["recur"] as? String else { return (nil, nil) }

    let freq: EKRecurrenceFrequency
    switch freqStr.lowercased() {
    case "daily", "day":    freq = .daily
    case "weekly", "week":  freq = .weekly
    case "monthly", "month": freq = .monthly
    case "yearly", "year", "annually": freq = .yearly
    default:
      return (nil, FlutterError(code: "invalid_args",
                                message: "Invalid recur '\(freqStr)'. Use: daily, weekly, monthly, yearly.",
                                details: nil))
    }

    var interval = 1
    if let iv = args["recur_interval"] as? NSNumber {
      interval = iv.intValue
      if interval < 1 {
        return (nil, FlutterError(code: "invalid_args",
                                  message: "recur_interval must be a positive integer.",
                                  details: nil))
      }
    }

    var days: [EKRecurrenceDayOfWeek]? = nil
    if let daysStr = args["recur_days"] as? String {
      if freq == .daily {
        return (nil, FlutterError(code: "invalid_args",
                                  message: "recur_days cannot be combined with recur=daily.",
                                  details: nil))
      }
      var parsed: [EKRecurrenceDayOfWeek] = []
      for tok in daysStr.components(separatedBy: ",") {
        let t = tok.trimmingCharacters(in: .whitespaces).lowercased()
        if t.hasPrefix("su") { parsed.append(EKRecurrenceDayOfWeek(.sunday)) }
        else if t.hasPrefix("mo") { parsed.append(EKRecurrenceDayOfWeek(.monday)) }
        else if t.hasPrefix("tu") { parsed.append(EKRecurrenceDayOfWeek(.tuesday)) }
        else if t.hasPrefix("we") { parsed.append(EKRecurrenceDayOfWeek(.wednesday)) }
        else if t.hasPrefix("th") { parsed.append(EKRecurrenceDayOfWeek(.thursday)) }
        else if t.hasPrefix("fr") { parsed.append(EKRecurrenceDayOfWeek(.friday)) }
        else if t.hasPrefix("sa") { parsed.append(EKRecurrenceDayOfWeek(.saturday)) }
        else {
          return (nil, FlutterError(code: "invalid_args",
                                    message: "Invalid recur_days token '\(tok)'. Use: mon, tue, wed, thu, fri, sat, sun.",
                                    details: nil))
        }
      }
      if !parsed.isEmpty { days = parsed }
    }

    // End condition
    let hasCount = args["recur_count"] != nil
    let hasUntil = args["recur_until"] != nil
    if hasCount && hasUntil {
      return (nil, FlutterError(code: "invalid_args",
                                message: "recur_count and recur_until are mutually exclusive.",
                                details: nil))
    }

    var end: EKRecurrenceEnd? = nil
    if hasUntil, let untilStr = args["recur_until"] as? String {
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      var until = formatter.date(from: untilStr)
      if until == nil {
        formatter.formatOptions = [.withInternetDateTime]
        until = formatter.date(from: untilStr)
      }
      if until == nil {
        return (nil, FlutterError(code: "invalid_args",
                                  message: "Invalid recur_until '\(untilStr)'. Use ISO 8601.",
                                  details: nil))
      }
      if let anchorDate = anchor, until! <= anchorDate {
        return (nil, FlutterError(code: "invalid_args",
                                  message: "recur_until must be later than the reminder's due_date.",
                                  details: nil))
      }
      end = EKRecurrenceEnd(end: until!)
    } else if hasCount, let countNum = args["recur_count"] as? NSNumber {
      let count = countNum.intValue
      if count < 1 {
        return (nil, FlutterError(code: "invalid_args",
                                  message: "recur_count must be a positive integer.",
                                  details: nil))
      }
      end = EKRecurrenceEnd(occurrenceCount: count)
    }

    let rule = EKRecurrenceRule(
      recurrenceWith: freq,
      interval: interval,
      daysOfTheWeek: days,
      daysOfTheMonth: nil,
      monthsOfTheYear: nil,
      weeksOfTheYear: nil,
      daysOfTheYear: nil,
      setPositions: nil,
      end: end
    )
    return (rule, nil)
  }

  /// Serialize a recurrence rule to a dict for list/create/update output.
  private func recurrenceToDict(_ rule: EKRecurrenceRule) -> [String: Any] {
    let freqStr: String
    switch rule.frequency {
    case .daily:   freqStr = "daily"
    case .weekly:  freqStr = "weekly"
    case .monthly: freqStr = "monthly"
    case .yearly:  freqStr = "yearly"
    @unknown default: freqStr = "unknown"
    }
    var d: [String: Any] = ["frequency": freqStr, "interval": rule.interval]
    if let dows = rule.daysOfTheWeek, !dows.isEmpty {
      let names = ["", "sun", "mon", "tue", "wed", "thu", "fri", "sat"]
      d["days_of_week"] = dows.compactMap { dw -> String? in
        let idx = dw.dayOfTheWeek.rawValue
        return (idx >= 1 && idx <= 7) ? names[Int(idx)] : nil
      }
    }
    if let endDate = rule.recurrenceEnd?.endDate {
      let fmt = ISO8601DateFormatter()
      fmt.timeZone = TimeZone.current
      fmt.formatOptions = [.withInternetDateTime, .withTimeZone]
      d["until"] = fmt.string(from: endDate)
    } else if let count = rule.recurrenceEnd?.occurrenceCount, count > 0 {
      d["count"] = count
    } else {
      d["never_ends"] = true
    }
    return d
  }

  // MARK: - ISO8601 Formatter

  private func makeISOFormatter() -> ISO8601DateFormatter {
    let fmt = ISO8601DateFormatter()
    fmt.timeZone = TimeZone.current
    fmt.formatOptions = [.withInternetDateTime, .withTimeZone]
    return fmt
  }

  // MARK: - Helper

  private func fetchReminder(withId id: String, completion: @escaping (EKReminder?) -> Void) {
    if let item = eventStore.calendarItem(withIdentifier: id) as? EKReminder {
      completion(item)
      return
    }
    let pred = eventStore.predicateForReminders(in: nil)
    eventStore.fetchReminders(matching: pred) { reminders in
      let found = reminders?.first(where: { $0.calendarItemIdentifier == id })
      completion(found)
    }
  }

  private func formatReminder(_ reminder: EKReminder, isoFormatter: ISO8601DateFormatter) -> [String: Any] {
    var d: [String: Any] = [
      "id": reminder.calendarItemIdentifier,
      "title": reminder.title ?? "",
      "is_completed": reminder.isCompleted,
      "due_date": NSNull(),
      "priority": reminder.priority,
      "notes": reminder.notes ?? "",
      "list_name": reminder.calendar?.title ?? ""
    ]
    if let date = reminder.dueDateComponents?.date {
      d["due_date"] = isoFormatter.string(from: date)
    }
    if let locDict = reminderLocationDict(reminder) {
      d["location"] = locDict
    }
    if reminder.hasRecurrenceRules, let rule = reminder.recurrenceRules?.first {
      d["recurrence"] = recurrenceToDict(rule)
    }
    return d
  }

  // MARK: - List Reminders  private func listReminders(args: [String: Any], result: @escaping FlutterResult) {
    let includeCompleted = (args["include_completed"] as? Bool) ?? false
    let listName = (args["list_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    let limit = (args["limit"] as? NSNumber)?.intValue ?? 100

    var targetCalendars: [EKCalendar]? = nil
    if let name = listName, !name.isEmpty {
      let calendars = eventStore.calendars(for: .reminder)
      if let matched = calendars.first(where: {
        $0.title.lowercased() == name.lowercased() || $0.title.lowercased().contains(name.lowercased())
      }) {
        targetCalendars = [matched]
      }
    }

    let predicate: NSPredicate
    if includeCompleted {
      predicate = eventStore.predicateForReminders(in: targetCalendars)
    } else {
      predicate = eventStore.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: targetCalendars)
    }

    eventStore.fetchReminders(matching: predicate) { [weak self] reminders in
      guard let self = self else { return }
      let isoFormatter = self.makeISOFormatter()
      let totalReminders = reminders ?? []
      let totalAvailable = totalReminders.count
      let sliced = limit > 0 && totalAvailable > limit ? Array(totalReminders.prefix(limit)) : totalReminders
      let items = sliced.map { self.formatReminder($0, isoFormatter: isoFormatter) }

      DispatchQueue.main.async {
        var resp: [String: Any] = [
          "count": items.count,
          "include_completed": includeCompleted,
          "reminders": items
        ]
        if totalAvailable > items.count {
          resp["_warning"] = "Results truncated by limit. Returned \(items.count) of \(totalAvailable) total records."
          resp["total_available"] = totalAvailable
        }
        result(resp)
      }
    }
  }

  // MARK: - Create Reminder

  private func createReminder(args: [String: Any], result: @escaping FlutterResult) {
    guard let title = args["title"] as? String, !title.isEmpty else {
      result(FlutterError(code: "invalid_args", message: "Title is required for createReminder.", details: nil))
      return
    }

    if let parentId = args["parent_id"] as? String, !parentId.isEmpty {
      result(FlutterError(
        code: "not_supported",
        message: "Reminder subtasks are not supported: iOS EventKit provides no public API to set a parent/child relationship, so parent_id cannot be honored.",
        details: nil
      ))
      return
    } }

    let reminder = EKReminder(eventStore: eventStore)
    reminder.title = title
    reminder.notes = args["notes"] as? String
    reminder.priority = (args["priority"] as? NSNumber)?.intValue ?? 0

    // Assign to list
    let listName = (args["list_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !listName.isEmpty {
      let calendars = eventStore.calendars(for: .reminder)
      reminder.calendar = calendars.first(where: {
        $0.title.lowercased() == listName.lowercased() || $0.title.lowercased().contains(listName.lowercased())
      }) ?? eventStore.defaultCalendarForNewReminders()
    } else {
      reminder.calendar = eventStore.defaultCalendarForNewReminders()
    }

    // Due date + time alarm
    let isoFormatter = makeISOFormatter()
    var dueDate: Date? = nil
    if let dueStr = args["due_date"] as? String {
      let parsers = [
        ISO8601DateFormatter(),
        { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f }()
      ]
      for parser in parsers {
        if let d = parser.date(from: dueStr) { dueDate = d; break }
      }
      if let d = dueDate {
        reminder.dueDateComponents = Calendar.current.dateComponents(
          [.year, .month, .day, .hour, .minute, .second], from: d)
        // Clear old time alarms; keep location alarms untouched
        for alarm in (reminder.alarms ?? []) {
          if alarm.structuredLocation == nil { reminder.removeAlarm(alarm) }
        }
        reminder.addAlarm(EKAlarm(absoluteDate: d))
      }
    }

    // Recurrence (must parse before save so a bad rule fails before creating)
    let (rule, recurErr) = buildRecurrenceRule(args: args, anchor: dueDate)
    if let recurErr = recurErr { result(recurErr); return }
    if let rule = rule {
      if dueDate == nil {
        result(FlutterError(code: "invalid_args",
                            message: "recur requires due_date: a repeating reminder needs a due date to repeat from.",
                            details: nil))
        return
      }
      reminder.recurrenceRules = [rule]
    }

    // Geofence alarm (runs on background thread due to location auth semaphore)
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self = self else { return }
      if let locErr = self.applyLocationAlarm(args: args, reminder: reminder) {
        DispatchQueue.main.async { result(locErr) }
        return
      }
      do {
        try self.eventStore.save(reminder, commit: true)
        var resp: [String: Any] = [
          "success": true,
          "id": reminder.calendarItemIdentifier,
          "title": title,
          "list_name": reminder.calendar?.title ?? "",
          "message": "Reminder created successfully."
        ]
        if let loc = self.reminderLocationDict(reminder) { resp["location"] = loc }
        if reminder.hasRecurrenceRules, let r = reminder.recurrenceRules?.first {
          resp["recurrence"] = self.recurrenceToDict(r)
        }
        if let d = dueDate { resp["due_date"] = isoFormatter.string(from: d) }
        DispatchQueue.main.async { result(resp) }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "save_failed", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  // MARK: - Update Reminder

  private func updateReminder(args: [String: Any], result: @escaping FlutterResult) {
    guard let id = args["id"] as? String, !id.isEmpty else {
      result(FlutterError(code: "invalid_args", message: "Reminder 'id' is required for update.", details: nil))
      return
    }

    fetchReminder(withId: id) { [weak self] reminder in
      guard let self = self, let reminder = reminder else {
        DispatchQueue.main.async {
          result(FlutterError(code: "not_found", message: "Reminder with ID '\(id)' not found.", details: nil))
        }
        return
      }

      if let title = args["title"] as? String, !title.isEmpty { reminder.title = title }
      if let notes = args["notes"] as? String { reminder.notes = notes }
      if let prio = args["priority"] as? NSNumber { reminder.priority = prio.intValue }
      if let completed = args["completed"] as? Bool {
        reminder.isCompleted = completed
        reminder.completionDate = completed ? Date() : nil
      }

      if let listName = (args["list_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !listName.isEmpty {
        let calendars = self.eventStore.calendars(for: .reminder)
        if let matched = calendars.first(where: {
          $0.title.lowercased() == listName.lowercased() || $0.title.lowercased().contains(listName.lowercased())
        }) { reminder.calendar = matched }
      }

      // Due date update
      let isoFormatter = self.makeISOFormatter()
      var dueDate: Date? = reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
      if let dueStr = args["due_date"] as? String {
        let parsers = [
          ISO8601DateFormatter(),
          { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f }()
        ]
        for parser in parsers {
          if let d = parser.date(from: dueStr) { dueDate = d; break }
        }
        if let d = dueDate {
          reminder.dueDateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: d)
          for alarm in (reminder.alarms ?? []) {
            if alarm.structuredLocation == nil { reminder.removeAlarm(alarm) }
          }
          reminder.addAlarm(EKAlarm(absoluteDate: d))
        }
      }

      // Clear recurrence
      if let clearRecur = args["clear_recur"] as? Bool, clearRecur {
        reminder.recurrenceRules = nil
      }

      // Recurrence update
      let (rule, recurErr) = self.buildRecurrenceRule(args: args, anchor: dueDate)
      if let recurErr = recurErr { DispatchQueue.main.async { result(recurErr) }; return }
      if let rule = rule {
        if dueDate == nil {
          DispatchQueue.main.async {
            result(FlutterError(code: "invalid_args",
                                message: "recur requires the reminder to have a due_date.",
                                details: nil))
          }
          return
        }
        reminder.recurrenceRules = [rule]
      }

      // Clear location
      if let clearLoc = args["clear_location"] as? Bool, clearLoc {
        for alarm in (reminder.alarms ?? []) {
          if alarm.structuredLocation != nil && alarm.proximity != .none { reminder.removeAlarm(alarm) }
        }
      }

      // Geofence update (needs background thread for location auth)
      DispatchQueue.global(qos: .userInitiated).async {
        if let locErr = self.applyLocationAlarm(args: args, reminder: reminder) {
          DispatchQueue.main.async { result(locErr) }
          return
        }
        do {
          try self.eventStore.save(reminder, commit: true)
          var resp: [String: Any] = [
            "success": true,
            "id": id,
            "title": reminder.title ?? "",
            "list_name": reminder.calendar?.title ?? "",
            "message": "Reminder updated successfully."
          ]
          if let d = dueDate { resp["due_date"] = isoFormatter.string(from: d) }
          if let loc = self.reminderLocationDict(reminder) { resp["location"] = loc }
          if reminder.hasRecurrenceRules, let r = reminder.recurrenceRules?.first {
            resp["recurrence"] = self.recurrenceToDict(r)
          }
          DispatchQueue.main.async { result(resp) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "update_failed", message: error.localizedDescription, details: nil))
          }
        }
      }
    }
  }

  // MARK: - Complete Reminder

  private func completeReminder(args: [String: Any], result: @escaping FlutterResult) {
    guard let id = args["id"] as? String, !id.isEmpty else {
      result(FlutterError(code: "invalid_args", message: "Reminder 'id' is required.", details: nil))
      return
    }
    let completed = (args["completed"] as? Bool) ?? true

    fetchReminder(withId: id) { [weak self] item in
      guard let self = self, let item = item else {
        DispatchQueue.main.async {
          result(FlutterError(code: "not_found", message: "Reminder with ID '\(id)' not found.", details: nil))
        }
        return
      }
      item.isCompleted = completed
      item.completionDate = completed ? Date() : nil
      do {
        try self.eventStore.save(item, commit: true)
        DispatchQueue.main.async {
          result(["success": true, "id": id, "completed": completed, "message": "Reminder updated successfully."])
        }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "update_failed", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  // MARK: - Delete Reminder

  private func deleteReminder(args: [String: Any], result: @escaping FlutterResult) {
    guard let id = args["id"] as? String, !id.isEmpty else {
      result(FlutterError(code: "invalid_args", message: "Reminder 'id' is required.", details: nil))
      return
    }
    fetchReminder(withId: id) { [weak self] item in
      guard let self = self, let item = item else {
        DispatchQueue.main.async {
          result(FlutterError(code: "not_found", message: "Reminder with ID '\(id)' not found.", details: nil))
        }
        return
      }
      let titleCopy = item.title ?? ""
      do {
        try self.eventStore.remove(item, commit: true)
        DispatchQueue.main.async {
          result(["success": true, "id": id, "message": "Reminder '\(titleCopy)' deleted successfully."])
        }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "delete_failed", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  // MARK: - List Lists

  private func listLists(result: @escaping FlutterResult) {
    let calendars = eventStore.calendars(for: .reminder)
    let items = calendars.map { cal -> [String: Any] in
      return [
        "id": cal.calendarIdentifier,
        "title": cal.title,
        "allows_content_modifications": cal.allowsContentModifications
      ]
    }
    result(["count": items.count, "lists": items])
  }
}
