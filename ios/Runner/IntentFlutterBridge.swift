import Flutter
import Foundation
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Kelivo", category: "IntentFlutterBridge")

struct IntentChatResult {
    let sessionId: String
    let response: String
    let assistantName: String
    let modelName: String
}

@MainActor
final class IntentFlutterBridge {
    static let shared = IntentFlutterBridge()

    private var backgroundEngine: FlutterEngine?
    private var channel: FlutterMethodChannel?

    private init() {}

    /// 后台启动 Headless FlutterEngine 并执行快捷指令任务
    func execute(
        prompt: String,
        assistantId: String?,
        sessionId: String?,
        modelId: String?,
        filePaths: [String]
    ) async throws -> IntentChatResult {
        let engine = FlutterEngine(name: "kelivo_intent_headless_engine", project: nil, allowHeadlessExecution: true)
        
        var didRun = engine.run(withEntrypoint: "backgroundIntentMain", libraryURI: nil)
        if !didRun {
            didRun = engine.run(withEntrypoint: "backgroundIntentMain", libraryURI: "package:Kelivo/main_background_intent.dart")
        }
        guard didRun else {
            logger.error("Failed to run background FlutterEngine with entrypoint backgroundIntentMain")
            throw NSError(domain: "KelivoIntent", code: 500, userInfo: [NSLocalizedDescriptionKey: "无法启动后台处理引擎，请重新编译应用"])
        }

        // ⭐ 必须为 Headless 引擎注册原生插件（如 path_provider），否则 Dart 侧调用插件方法会报 MissingPluginException
        GeneratedPluginRegistrant.register(with: engine)

        let channel = FlutterMethodChannel(name: "app.intent_chat", binaryMessenger: engine.binaryMessenger)
        
        let args: [String: Any?] = [
            "prompt": prompt,
            "assistantId": assistantId,
            "sessionId": sessionId,
            "modelId": modelId,
            "filePaths": filePaths
        ]

        return try await withCheckedThrowingContinuation { continuation in
            channel.invokeMethod("executeIntent", arguments: args) { result in
                // 任务完成，销毁后台引擎释放内存
                engine.destroyContext()

                if let error = result as? FlutterError {
                    logger.error("Intent execution error: \(error.message ?? "")")
                    continuation.resume(throwing: NSError(domain: "KelivoIntent", code: 500, userInfo: [NSLocalizedDescriptionKey: error.message ?? "执行出错"]))
                } else if let dict = result as? [String: Any] {
                    let sessionId = dict["sessionId"] as? String ?? ""
                    let response = dict["response"] as? String ?? ""
                    let assistantName = dict["assistantName"] as? String ?? "Kelivo"
                    let modelName = dict["modelName"] as? String ?? "Default"
                    continuation.resume(returning: IntentChatResult(
                        sessionId: sessionId,
                        response: response,
                        assistantName: assistantName,
                        modelName: modelName
                    ))
                } else {
                    continuation.resume(throwing: NSError(domain: "KelivoIntent", code: 500, userInfo: [NSLocalizedDescriptionKey: "未知返回结果"]))
                }
            }
        }
    }
}
