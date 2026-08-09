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
    case "updateEvent":
      updateEvent(args: args, result: result)
    case "deleteEvent":
      deleteEvent(args: args, result: result)
    case "listCalendars":
      listCalendars(result: result)
    case "freebusy":
      freebusy(args: args, result: result)
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

  private func findCalendar(named name: String) -> EKCalendar? {
    let calendars = eventStore.calendars(for: .event)
    let n = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return calendars.first(where: { $0.title.lowercased() == n || $0.title.lowercased().contains(n) })
  }

  // MARK: - List Events

  private func listEvents(args: [String: Any], result: @escaping FlutterResult) {
    let days = (args["days"] as? Int) ?? 7
    let now = Date()
    let startDate = Calendar.current.startOfDay(for: now)
    let endDate = Calendar.current.date(byAdding: .day, value: days, to: startDate)!

    var targetCalendars: [EKCalendar]? = nil
    if let calName = args["calendar_name"] as? String, !calName.isEmpty {
      if let cal = findCalendar(named: calName) {
        targetCalendars = [cal]
      }
    }

    let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: targetCalendars)
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
    var startDate: Date = Date().addingTimeInterval(3600)
    var endDate: Date = startDate.addingTimeInterval(3600)

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

    if let calName = args["calendar_name"] as? String, !calName.isEmpty, let cal = findCalendar(named: calName) {
      event.calendar = cal
    } else {
      event.calendar = eventStore.defaultCalendarForNewEvents
    }

    if let alarmMins = (args["alarm_minutes"] as? NSNumber)?.intValue, alarmMins >= 0 {
      let alarm = EKAlarm(relativeOffset: -Double(alarmMins * 60))
      event.addAlarm(alarm)
    }

    do {
      try eventStore.save(event, span: .thisEvent)
      result([
        "success": true,
        "id": event.eventIdentifier ?? "",
        "title": title,
        "calendar": event.calendar?.title ?? "",
        "start": isoFormatter.string(from: startDate),
        "end": isoFormatter.string(from: endDate),
        "message": "Calendar event created successfully."
      ])
    } catch {
      result(FlutterError(code: "save_failed", message: error.localizedDescription, details: nil))
    }
  }

  // MARK: - Update Event

  private func updateEvent(args: [String: Any], result: @escaping FlutterResult) {
    guard let id = args["id"] as? String, !id.isEmpty else {
      result(FlutterError(code: "invalid_args", message: "Event 'id' is required for update.", details: nil))
      return
    }

    guard let event = eventStore.event(withIdentifier: id) else {
      result(FlutterError(code: "not_found", message: "Event with ID '\(id)' was not found.", details: nil))
      return
    }

    let isoFormatter = ISO8601DateFormatter()

    if let title = args["title"] as? String, !title.isEmpty {
      event.title = title
    }
    if let startStr = args["start"] as? String, let parsedStart = isoFormatter.date(from: startStr) {
      event.startDate = parsedStart
    }
    if let endStr = args["end"] as? String, let parsedEnd = isoFormatter.date(from: endStr) {
      event.endDate = parsedEnd
    }
    if let location = args["location"] as? String {
      event.location = location
    }
    if let notes = args["notes"] as? String {
      event.notes = notes
    }
    if let calName = args["calendar_name"] as? String, !calName.isEmpty, let cal = findCalendar(named: calName) {
      event.calendar = cal
    }
    if let alarmMins = (args["alarm_minutes"] as? NSNumber)?.intValue {
      if let alarms = event.alarms {
        for a in alarms {
          event.removeAlarm(a)
        }
      }
      if alarmMins >= 0 {
        event.addAlarm(EKAlarm(relativeOffset: -Double(alarmMins * 60)))
      }
    }

    let spanStr = (args["span"] as? String)?.lowercased() ?? "this"
    let span: EKSpan = (spanStr == "future" || spanStr == "all") ? .futureEvents : .thisEvent

    do {
      try eventStore.save(event, span: span)
      result([
        "success": true,
        "id": id,
        "title": event.title ?? "",
        "calendar": event.calendar?.title ?? "",
        "start": isoFormatter.string(from: event.startDate),
        "end": isoFormatter.string(from: event.endDate),
        "message": "Calendar event updated successfully."
      ])
    } catch {
      result(FlutterError(code: "update_failed", message: error.localizedDescription, details: nil))
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

    let spanStr = (args["span"] as? String)?.lowercased() ?? "this"
    let span: EKSpan = (spanStr == "future" || spanStr == "all") ? .futureEvents : .thisEvent

    do {
      try eventStore.remove(event, span: span)
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

  // MARK: - FreeBusy Analysis

  private func freebusy(args: [String: Any], result: @escaping FlutterResult) {
    let days = (args["days"] as? Int) ?? 1
    let isoFormatter = ISO8601DateFormatter()

    let now = Date()
    var startDate = Calendar.current.startOfDay(for: now)
    var endDate = Calendar.current.date(byAdding: .day, value: days, to: startDate)!

    if let startStr = args["start"] as? String, let parsed = isoFormatter.date(from: startStr) {
      startDate = parsed
    }
    if let endStr = args["end"] as? String, let parsed = isoFormatter.date(from: endStr) {
      endDate = parsed
    }

    let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
    let events = eventStore.events(matching: predicate).sorted { $0.startDate < $1.startDate }

    var busySlots = [[String: String]]()
    var freeSlots = [[String: String]]()

    var lastEnd = startDate

    for e in events {
      if e.isAllDay { continue }
      let s = e.startDate > startDate ? e.startDate : startDate
      let end = e.endDate < endDate ? e.endDate : endDate

      if s > lastEnd {
        freeSlots.append([
          "start": isoFormatter.string(from: lastEnd),
          "end": isoFormatter.string(from: s)
        ])
      }

      busySlots.append([
        "title": e.title ?? "",
        "start": isoFormatter.string(from: e.startDate),
        "end": isoFormatter.string(from: e.endDate)
      ])

      if end > lastEnd {
        lastEnd = end
      }
    }

    if lastEnd < endDate {
      freeSlots.append([
        "start": isoFormatter.string(from: lastEnd),
        "end": isoFormatter.string(from: endDate)
      ])
    }

    result([
      "start": isoFormatter.string(from: startDate),
      "end": isoFormatter.string(from: endDate),
      "busy_count": busySlots.count,
      "free_count": freeSlots.count,
      "busy_slots": busySlots,
      "free_slots": freeSlots
    ])
  }
}
