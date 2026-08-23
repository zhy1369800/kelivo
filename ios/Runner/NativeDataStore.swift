import Foundation
import SQLite3
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Kelivo", category: "NativeDataStore")

struct NativeAssistantRecord {
    let id: String
    let name: String
    let description: String
}

struct NativeSessionRecord {
    let id: String
    let title: String
    let assistantId: String?
    let updatedAt: Date
}

struct NativeModelRecord {
    let id: String
    let displayName: String
    let providerKey: String
    let providerName: String
}

final class NativeDataStore {
    static let shared = NativeDataStore()

    private init() {}

    /// 获取 Documents 目录下的 kelivo.db 数据库路径
    private var databasePath: String? {
        guard let documentsUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dbUrl = documentsUrl.appendingPathComponent("kelivo.db")
        if FileManager.default.fileExists(atPath: dbUrl.path) {
            return dbUrl.path
        }
        return nil
    }

    /// 读取所有助手列表
    /// 表：assistant_rows，列：id (TEXT PK)、sort_order、payload (TEXT JSON)、updated_at
    func fetchAssistants() -> [NativeAssistantRecord] {
        guard let dbPath = databasePath else { return [] }
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_close(db) }

        var results: [NativeAssistantRecord] = []
        let query = "SELECT id, payload FROM assistant_rows ORDER BY sort_order;"
        var stmt: OpaquePointer?

        if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let idChars = sqlite3_column_text(stmt, 0),
                   let jsonChars = sqlite3_column_text(stmt, 1) {
                    let id = String(cString: idChars)
                    let jsonString = String(cString: jsonChars)
                    if let data = jsonString.data(using: .utf8),
                       let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let name = dict["name"] as? String ?? id
                        let desc = dict["description"] as? String ?? dict["systemPrompt"] as? String ?? ""
                        results.append(NativeAssistantRecord(id: id, name: name, description: desc))
                    }
                }
            }
        }
        sqlite3_finalize(stmt)
        return results
    }

    /// 读取最近活跃的会话列表
    /// 表：conversation_rows，列：id、title、assistant_id、updated_at（微秒 epoch）
    func fetchRecentSessions(limit: Int = 30) -> [NativeSessionRecord] {
        guard let dbPath = databasePath else { return [] }
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_close(db) }

        var results: [NativeSessionRecord] = []
        let query = "SELECT id, title, assistant_id, updated_at FROM conversation_rows ORDER BY updated_at DESC LIMIT ?;"
        var stmt: OpaquePointer?

        if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int(stmt, 1, Int32(limit))
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let idChars = sqlite3_column_text(stmt, 0),
                   let titleChars = sqlite3_column_text(stmt, 1) {
                    let id = String(cString: idChars)
                    let title = String(cString: titleChars)
                    var assistantId: String? = nil
                    if let aIdChars = sqlite3_column_text(stmt, 2) {
                        assistantId = String(cString: aIdChars)
                    }
                    let microEpoch = sqlite3_column_int64(stmt, 3)
                    let date = Date(timeIntervalSince1970: Double(microEpoch) / 1_000_000.0)
                    results.append(NativeSessionRecord(id: id, title: title, assistantId: assistantId, updatedAt: date))
                }
            }
        }
        sqlite3_finalize(stmt)
        return results
    }

    /// 读取已配置的模型列表
    /// 表：provider_rows，主键列：provider_key，payload 中包含 models 数组
    /// 每个 model 对象包含 id、name/displayName 字段
    func fetchConfiguredModels() -> [NativeModelRecord] {
        guard let dbPath = databasePath else { return [] }
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_close(db) }

        var results: [NativeModelRecord] = []
        // provider_rows 的主键列名是 provider_key（不是 id）
        let query = "SELECT provider_key, payload FROM provider_rows ORDER BY sort_order;"
        var stmt: OpaquePointer?

        if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let pkChars = sqlite3_column_text(stmt, 0),
                   let jsonChars = sqlite3_column_text(stmt, 1) {
                    let providerKey = String(cString: pkChars)
                    let jsonString = String(cString: jsonChars)
                    if let data = jsonString.data(using: .utf8),
                       let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let providerName = dict["name"] as? String ?? providerKey
                        // payload 中的 models 数组（每项包含 id、name/displayName）
                        if let models = dict["models"] as? [[String: Any]] {
                            for model in models {
                                let modelId = model["id"] as? String ?? ""
                                let modelName = model["name"] as? String
                                    ?? model["displayName"] as? String
                                    ?? modelId
                                if !modelId.isEmpty {
                                    results.append(NativeModelRecord(
                                        id: modelId,
                                        displayName: modelName,
                                        providerKey: providerKey,
                                        providerName: providerName
                                    ))
                                }
                            }
                        }
                    }
                }
            }
        }
        sqlite3_finalize(stmt)
        return results
    }
}
