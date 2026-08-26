import AppIntents
import Foundation

@available(iOS 16.0, *)
struct SessionEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "会话")
    static var defaultQuery = SessionEntityQuery()

    var id: String
    var title: String
    var subtitle: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(subtitle)")
    }

    init(id: String, title: String, subtitle: String = "") {
        self.id = id
        self.title = title
        self.subtitle = subtitle
    }
}

@available(iOS 16.0, *)
struct SessionEntityQuery: EntityQuery, EntityStringQuery {
    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        return df
    }()

    func entities(for identifiers: [String]) async throws -> [SessionEntity] {
        let all = try await suggestedEntities()
        return identifiers.map { id in
            if let matched = all.first(where: { $0.id == id }) {
                return matched
            }
            return SessionEntity(id: id, title: "会话 (\(id.prefix(8)))")
        }
    }

    func entities(matching string: String) async throws -> [SessionEntity] {
        let all = try await suggestedEntities()
        if string.isEmpty { return all }
        let filtered = all.filter {
            $0.title.localizedCaseInsensitiveContains(string) || $0.id.lowercased() == string.lowercased()
        }
        if !filtered.isEmpty { return filtered }
        return [SessionEntity(id: string, title: "会话 (\(string.prefix(8)))")]
    }

    func suggestedEntities() async throws -> [SessionEntity] {
        let records = NativeDataStore.shared.fetchRecentSessions()
        return records.map {
            let timeStr = dateFormatter.string(from: $0.updatedAt)
            return SessionEntity(id: $0.id, title: $0.title, subtitle: timeStr)
        }
    }
}
