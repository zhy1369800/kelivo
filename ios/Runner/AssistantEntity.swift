import AppIntents
import Foundation

@available(iOS 16.0, *)
struct AssistantEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "助手")
    static var defaultQuery = AssistantEntityQuery()

    var id: String
    var displayName: String
    var subtitle: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(displayName)", subtitle: "\(subtitle)")
    }

    init(id: String, displayName: String, subtitle: String = "") {
        self.id = id
        self.displayName = displayName
        self.subtitle = subtitle
    }
}

@available(iOS 16.0, *)
struct AssistantEntityQuery: EntityQuery, EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [AssistantEntity] {
        let all = suggestedEntities()
        return all.filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [AssistantEntity] {
        let all = suggestedEntities()
        if string.isEmpty { return all }
        return all.filter {
            $0.displayName.localizedCaseInsensitiveContains(string) ||
            $0.subtitle.localizedCaseInsensitiveContains(string)
        }
    }

    func suggestedEntities() -> [AssistantEntity] {
        let records = NativeDataStore.shared.fetchAssistants()
        if records.isEmpty {
            return [
                AssistantEntity(id: "default", displayName: "默认助手", subtitle: "Kelivo 内置通用助手")
            ]
        }
        return records.map {
            AssistantEntity(id: $0.id, displayName: $0.name, subtitle: $0.description)
        }
    }
}
