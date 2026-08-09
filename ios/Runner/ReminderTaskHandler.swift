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

  // MARK: - Format Helper

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
      if let matched = calendars.first(where: { $0.title.lowercased() == name.lowercased() }) {
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
      if let matched = calendars.first(where: { $0.title.lowercased() == listName.lowercased() }) {
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
    }

    do {
      try eventStore.save(reminder, commit: true)
      result([
        "success": true,
        "id": reminder.calendarItemIdentifier,
        "title": title,
        "list_name": reminder.calendar?.title ?? "",
        "message": "Reminder created successfully."
      ])
    } catch {
      result(FlutterError(code: "save_failed", message: error.localizedDescription, details: nil))
    }
  }

  // MARK: - Complete Reminder

  private func completeReminder(args: [String: Any], result: @escaping FlutterResult) {
    guard let id = args["id"] as? String, !id.isEmpty else {
      result(FlutterError(code: "invalid_args", message: "Reminder 'id' is required.", details: nil))
      return
    }

    let completed = (args["completed"] as? Bool) ?? true

    guard let item = eventStore.calendarItem(withIdentifier: id) as? EKReminder else {
      result(FlutterError(code: "not_found", message: "Reminder with ID '\(id)' not found.", details: nil))
      return
    }

    item.isCompleted = completed
    if completed {
      item.completionDate = Date()
    } else {
      item.completionDate = nil
    }

    do {
      try eventStore.save(item, commit: true)
      result([
        "success": true,
        "id": id,
        "completed": completed,
        "message": "Reminder updated successfully."
      ])
    } catch {
      result(FlutterError(code: "update_failed", message: error.localizedDescription, details: nil))
    }
  }

  // MARK: - Delete Reminder

  private func deleteReminder(args: [String: Any], result: @escaping FlutterResult) {
    guard let id = args["id"] as? String, !id.isEmpty else {
      result(FlutterError(code: "invalid_args", message: "Reminder 'id' is required.", details: nil))
      return
    }

    guard let item = eventStore.calendarItem(withIdentifier: id) as? EKReminder else {
      result(FlutterError(code: "not_found", message: "Reminder with ID '\(id)' not found.", details: nil))
      return
    }

    do {
      try eventStore.remove(item, commit: true)
      result([
        "success": true,
        "id": id,
        "message": "Reminder '\(item.title ?? "")' deleted successfully."
      ])
    } catch {
      result(FlutterError(code: "delete_failed", message: error.localizedDescription, details: nil))
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
