import Foundation
import EventKit
import Flutter

final class ReminderTaskHandler: NSObject {
  private let eventStore = EKEventStore()

  func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "requestPermission":
      requestPermission(result: result)
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
    var dueDateStr: Any = NSNull()
    if let date = reminder.dueDateComponents?.date {
      dueDateStr = isoFormatter.string(from: date)
    }

    return [
      "id": reminder.calendarItemIdentifier,
      "title": reminder.title ?? "",
      "is_completed": reminder.isCompleted,
      "due_date": dueDateStr,
      "priority": reminder.priority,
      "notes": reminder.notes ?? "",
      "list_name": reminder.calendar?.title ?? ""
    ]
  }

  // MARK: - List Reminders

  private func listReminders(args: [String: Any], result: @escaping FlutterResult) {
    let includeCompleted = (args["include_completed"] as? Bool) ?? false
    let listName = (args["list_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

    var targetCalendars: [EKCalendar]? = nil
    if let name = listName, !name.isEmpty {
      let calendars = eventStore.calendars(for: .reminder)
      if let matched = calendars.first(where: { $0.title.lowercased() == name.lowercased() || $0.title.lowercased().contains(name.lowercased()) }) {
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
      let isoFormatter = ISO8601DateFormatter()
      let items = (reminders ?? []).map { self.formatReminder($0, isoFormatter: isoFormatter) }

      DispatchQueue.main.async {
        result([
          "count": items.count,
          "include_completed": includeCompleted,
          "reminders": items
        ])
      }
    }
  }

  // MARK: - Create Reminder

  private func createReminder(args: [String: Any], result: @escaping FlutterResult) {
    guard let title = args["title"] as? String, !title.isEmpty else {
      result(FlutterError(code: "invalid_args", message: "Title is required for createReminder.", details: nil))
      return
    }

    let reminder = EKReminder(eventStore: eventStore)
    reminder.title = title
    reminder.notes = args["notes"] as? String
    reminder.priority = (args["priority"] as? NSNumber)?.intValue ?? 0

    if let listName = (args["list_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !listName.isEmpty {
      let calendars = eventStore.calendars(for: .reminder)
      if let matched = calendars.first(where: { $0.title.lowercased() == listName.lowercased() || $0.title.lowercased().contains(listName.lowercased()) }) {
        reminder.calendar = matched
      } else {
        reminder.calendar = eventStore.defaultCalendarForNewReminders()
      }
    } else {
      reminder.calendar = eventStore.defaultCalendarForNewReminders()
    }

    let isoFormatter = ISO8601DateFormatter()
    if let dueStr = args["due_date"] as? String, let parsedDate = isoFormatter.date(from: dueStr) {
      let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: parsedDate)
      reminder.dueDateComponents = components

      // Automatically attach an EKAlarm at the due date for system notification ringing
      if let alarms = reminder.alarms {
        for alarm in alarms {
          reminder.removeAlarm(alarm)
        }
      }
      reminder.addAlarm(EKAlarm(absoluteDate: parsedDate))
    }

    do {
      try eventStore.save(reminder, commit: true)
      result([
        "success": true,
        "id": reminder.calendarItemIdentifier,
        "title": title,
        "list_name": reminder.calendar?.title ?? "",
        "message": "Reminder created successfully with alarm."
      ])
    } catch {
      result(FlutterError(code: "save_failed", message: error.localizedDescription, details: nil))
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

      if let title = args["title"] as? String, !title.isEmpty {
        reminder.title = title
      }

      if let notes = args["notes"] as? String {
        reminder.notes = notes
      }

      if let prio = args["priority"] as? NSNumber {
        reminder.priority = prio.intValue
      }

      if let completed = args["completed"] as? Bool {
        reminder.isCompleted = completed
        reminder.completionDate = completed ? Date() : nil
      }

      if let listName = (args["list_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !listName.isEmpty {
        let calendars = self.eventStore.calendars(for: .reminder)
        if let matched = calendars.first(where: { $0.title.lowercased() == listName.lowercased() || $0.title.lowercased().contains(listName.lowercased()) }) {
          reminder.calendar = matched
        }
      }

      let isoFormatter = ISO8601DateFormatter()
      if let dueStr = args["due_date"] as? String, let parsedDate = isoFormatter.date(from: dueStr) {
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: parsedDate)
        reminder.dueDateComponents = components

        // Automatically attach/update EKAlarm at due date
        if let alarms = reminder.alarms {
          for alarm in alarms {
            reminder.removeAlarm(alarm)
          }
        }
        reminder.addAlarm(EKAlarm(absoluteDate: parsedDate))
      }

      do {
        try self.eventStore.save(reminder, commit: true)
        DispatchQueue.main.async {
          result([
            "success": true,
            "id": id,
            "title": reminder.title ?? "",
            "list_name": reminder.calendar?.title ?? "",
            "message": "Reminder updated successfully."
          ])
        }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "update_failed", message: error.localizedDescription, details: nil))
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
          result([
            "success": true,
            "id": id,
            "completed": completed,
            "message": "Reminder updated successfully."
          ])
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

      do {
        try self.eventStore.remove(item, commit: true)
        DispatchQueue.main.async {
          result([
            "success": true,
            "id": id,
            "message": "Reminder '\(item.title ?? "")' deleted successfully."
          ])
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
    let items = calendars.map { cal in
      return [
        "id": cal.calendarIdentifier,
        "title": cal.title,
        "allows_content_modifications": cal.allowsContentModifications
      ]
    }

    result([
      "count": items.count,
      "lists": items
    ])
  }
}
