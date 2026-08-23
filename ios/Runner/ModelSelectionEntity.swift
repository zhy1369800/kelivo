import AppIntents
import Foundation

@available(iOS 16.0, *)
struct ModelSelectionEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "模型")
    static var defaultQuery = ModelSelectionEntityQuery()

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
struct ModelSelectionEntityQuery: EntityQuery, EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [ModelSelectionEntity] {
        let all = suggestedEntities()
        return all.filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [ModelSelectionEntity] {
        let all = suggestedEntities()
        if string.isEmpty { return all }
        return all.filter {
            $0.displayName.localizedCaseInsensitiveContains(string) ||
            $0.subtitle.localizedCaseInsensitiveContains(string)
        }
    }

    func suggestedEntities() -> [ModelSelectionEntity] {
        let records = NativeDataStore.shared.fetchConfiguredModels()
        if records.isEmpty {
            return [
                ModelSelectionEntity(id: "default", displayName: "默认模型", subtitle: "使用助手预设模型")
            ]
        }
        return records.map {
            ModelSelectionEntity(id: $0.id, displayName: $0.displayName, subtitle: $0.providerName)
        }
    }
}
