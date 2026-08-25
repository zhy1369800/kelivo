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
        
        // 1. 必须为 Headless 引擎注册原生插件（如 path_provider）
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
            var isFinished = false
            
            // 2. 提前注册 MethodChannel 回调，等待 Dart 引擎就绪后主动拉取参数与上报结果（彻底避免 Native->Dart 时序死锁）
            channel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
                if call.method == "getIntentParams" {
                    // Dart 引擎初始化完成，返回输入参数
                    result(args)
                } else if call.method == "onIntentComplete" {
                    result(true)
                    guard !isFinished else { return }
                    isFinished = true
                    
                    let dict = call.arguments as? [String: Any] ?? [:]
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
                    
                    DispatchQueue.main.async {
                        engine.destroyContext()
                    }
                } else if call.method == "onIntentError" {
                    result(true)
                    guard !isFinished else { return }
                    isFinished = true
                    
                    let errorMsg = (call.arguments as? String) ?? "执行失败"
                    logger.error("Intent execution reported error: \(errorMsg)")
                    continuation.resume(throwing: NSError(
                        domain: "KelivoIntent",
                        code: 500,
                        userInfo: [NSLocalizedDescriptionKey: errorMsg]
                    ))
                    
                    DispatchQueue.main.async {
                        engine.destroyContext()
                    }
                } else {
                    result(FlutterMethodNotImplemented)
                }
            }

            // 3. 启动 Dart 后台引擎
            var didRun = engine.run(withEntrypoint: "backgroundIntentMain", libraryURI: nil)
            if !didRun {
                didRun = engine.run(withEntrypoint: "backgroundIntentMain", libraryURI: "package:Kelivo/main_background_intent.dart")
            }
            guard didRun else {
                guard !isFinished else { return }
                isFinished = true
                logger.error("Failed to run background FlutterEngine with entrypoint backgroundIntentMain")
                continuation.resume(throwing: NSError(domain: "KelivoIntent", code: 500, userInfo: [NSLocalizedDescriptionKey: "无法启动后台处理引擎，请重新编译应用"]))
                engine.destroyContext()
                return
            }
        }
    }
}
