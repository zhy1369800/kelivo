import Foundation
import EventKit
import Flutter

final class CalendarEventHandler: NSObject {
  private let eventStore = EKEventStore()

  func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "requestPermission":
      requestPermission(result: result)
    case "listEvents":
      listEvents(args: args, result: result)
    case "searchEvents":
      searchEvents(args: args, result: result)
    case "createEvent":
      createEvent(args: args, result: result)
    case "deleteEvent":
      deleteEvent(args: args, result: result)
    case "listCalendars":
      listCalendars(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Permission

  private func requestPermission(result: @escaping FlutterResult) {
    if #available(iOS 17.0, *) {
      eventStore.requestFullAccessToEvents { granted, error in
        DispatchQueue.main.async {
          if let error = error {
            result(FlutterError(code: "permission_error", message: error.localizedDescription, details: nil))
          } else {
            result(["authorized": granted])
          }
        }
      }
    } else {
      eventStore.requestAccess(to: .event) { granted, error in
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

  // MARK: - Format Helpers

  private func formatEvent(_ event: EKEvent, isoFormatter: ISO8601DateFormatter) -> [String: Any] {
    return [
      "id": event.eventIdentifier ?? "",
      "title": event.title ?? "",
      "start": isoFormatter.string(from: event.startDate),
      "end": isoFormatter.string(from: event.endDate),
      "is_all_day": event.isAllDay,
      "location": event.location ?? "",
      "notes": event.notes ?? "",
      "calendar": event.calendar?.title ?? ""
    ]
  }

  // MARK: - List Events

  private func listEvents(args: [String: Any], result: @escaping FlutterResult) {
    let days = (args["days"] as? Int) ?? 7
    let now = Date()
    let startDate = Calendar.current.startOfDay(for: now)
    let endDate = Calendar.current.date(byAdding: .day, value: days, to: startDate)!

    let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
    let events = eventStore.events(matching: predicate).sorted { $0.startDate < $1.startDate }

    let isoFormatter = ISO8601DateFormatter()
    let items = events.map { formatEvent($0, isoFormatter: isoFormatter) }

    result([
      "count": items.count,
      "days": days,
      "events": items
    ])
  }

  // MARK: - Search Events

  private func searchEvents(args: [String: Any], result: @escaping FlutterResult) {
    let query = (args["query"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    let days = (args["days"] as? Int) ?? 30
    let now = Date()
    let startDate = Calendar.current.date(byAdding: .day, value: -7, to: now)!
    let endDate = Calendar.current.date(byAdding: .day, value: days, to: now)!

    let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
    let events = eventStore.events(matching: predicate)

    let isoFormatter = ISO8601DateFormatter()
    var matched = [[String: Any]]()

    for event in events {
      let titleMatch = (event.title ?? "").lowercased().contains(query)
      let notesMatch = (event.notes ?? "").lowercased().contains(query)
      let locMatch = (event.location ?? "").lowercased().contains(query)

      if query.isEmpty || titleMatch || notesMatch || locMatch {
        matched.append(formatEvent(event, isoFormatter: isoFormatter))
      }
    }

    result([
      "query": query,
      "count": matched.count,
      "events": matched
    ])
  }

  // MARK: - Create Event

  private func createEvent(args: [String: Any], result: @escaping FlutterResult) {
    guard let title = args["title"] as? String, !title.isEmpty else {
      result(FlutterError(code: "invalid_args", message: "Title is required.", details: nil))
      return
    }

    let isoFormatter = ISO8601DateFormatter()
    var startDate: Date = Date().addingTimeInterval(3600) // Default: 1h later
    var endDate: Date = startDate.addingTimeInterval(3600) // Default: 1h duration

    if let startStr = args["start"] as? String, let parsedStart = isoFormatter.date(from: startStr) {
      startDate = parsedStart
    }
    if let endStr = args["end"] as? String, let parsedEnd = isoFormatter.date(from: endStr) {
      endDate = parsedEnd
    } else {
      endDate = startDate.addingTimeInterval(3600)
    }

    let event = EKEvent(eventStore: eventStore)
    event.title = title
    event.startDate = startDate
    event.endDate = endDate
    event.location = args["location"] as? String
    event.notes = args["notes"] as? String
    event.calendar = eventStore.defaultCalendarForNewEvents

    if let alarmMins = args["alarm_minutes"] as? Int, alarmMins >= 0 {
      let alarm = EKAlarm(relativeOffset: -Double(alarmMins * 60))
      event.addAlarm(alarm)
    }

    do {
      try eventStore.save(event, span: .thisEvent)
      result([
        "success": true,
        "id": event.eventIdentifier ?? "",
        "title": title,
        "start": isoFormatter.string(from: startDate),
        "end": isoFormatter.string(from: endDate),
        "message": "Calendar event created successfully."
      ])
    } catch {
      result(FlutterError(code: "save_failed", message: error.localizedDescription, details: nil))
    }
  }

  // MARK: - Delete Event

  private func deleteEvent(args: [String: Any], result: @escaping FlutterResult) {
    guard let id = args["id"] as? String, !id.isEmpty else {
      result(FlutterError(code: "invalid_args", message: "Event 'id' is required for delete.", details: nil))
      return
    }

    guard let event = eventStore.event(withIdentifier: id) else {
      result(FlutterError(code: "not_found", message: "Event with ID '\(id)' was not found.", details: nil))
      return
    }

    do {
      try eventStore.remove(event, span: .thisEvent)
      result([
        "success": true,
        "id": id,
        "message": "Event '\(event.title ?? "")' deleted successfully."
      ])
    } catch {
      result(FlutterError(code: "delete_failed", message: error.localizedDescription, details: nil))
    }
  }

  // MARK: - List Calendars

  private func listCalendars(result: @escaping FlutterResult) {
    let calendars = eventStore.calendars(for: .event)
    let items = calendars.map { cal in
      return [
        "id": cal.calendarIdentifier,
        "title": cal.title,
        "type": cal.type.rawValue,
        "allows_content_modifications": cal.allowsContentModifications
      ]
    }

    result([
      "count": items.count,
      "calendars": items
    ])
  }
}
