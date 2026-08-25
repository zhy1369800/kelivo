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

    private init() {}

    /// 执行快捷指令任务（自动检测并复用已有主引擎，或安全启动独立 Headless 引擎）
    func execute(
        prompt: String,
        assistantId: String?,
        sessionId: String?,
        modelId: String?,
        filePaths: [String]
    ) async throws -> IntentChatResult {
        let args: [String: Any?] = [
            "prompt": prompt,
            "assistantId": assistantId,
            "sessionId": sessionId,
            "modelId": modelId,
            "filePaths": filePaths
        ]

        // 1. 优先检测主 App 是否已在运行（前台或后台唤醒中）
        // 若主引擎已存活，直接复用其 binaryMessenger 进行通信，避免在同进程中创建第二个 FlutterEngine 导致内存暴涨被系统 Jetsam 杀死
        if let appDelegate = UIApplication.shared.delegate as? FlutterAppDelegate,
           let flutterVC = appDelegate.window?.rootViewController as? FlutterViewController,
           let activeEngine = flutterVC.engine {
            logger.info("Reusing active main FlutterEngine for Intent execution")
            let channel = FlutterMethodChannel(name: "app.intent_chat", binaryMessenger: activeEngine.binaryMessenger)
            return try await withCheckedThrowingContinuation { continuation in
                channel.invokeMethod("executeIntent", arguments: args) { result in
                    if let error = result as? FlutterError {
                        continuation.resume(throwing: NSError(
                            domain: "KelivoIntent",
                            code: 500,
                            userInfo: [NSLocalizedDescriptionKey: error.message ?? "执行出错"]
                        ))
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
                        continuation.resume(throwing: NSError(
                            domain: "KelivoIntent",
                            code: 500,
                            userInfo: [NSLocalizedDescriptionKey: "未知返回结果"]
                        ))
                    }
                }
            }
        }

        // 2. 冷启动状态：创建并启动 Headless FlutterEngine
        logger.info("Starting new Headless FlutterEngine for Intent execution")
        let headlessEngine = FlutterEngine(name: "kelivo_intent_headless_engine", project: nil, allowHeadlessExecution: true)

        // ⭐ 关键顺序：必须先 run() 启动引擎与 Isolate，然后再调用 GeneratedPluginRegistrant 注册插件
        // 在 engine 运行前注册插件会因 Isolate 尚未分配而触发 EXC_BAD_ACCESS 内存段错误直接导致 App 意外退出
        var didRun = headlessEngine.run(withEntrypoint: "backgroundIntentMain", libraryURI: nil)
        if !didRun {
            didRun = headlessEngine.run(withEntrypoint: "backgroundIntentMain", libraryURI: "package:Kelivo/main.dart")
        }
        if !didRun {
            didRun = headlessEngine.run(withEntrypoint: "backgroundIntentMain", libraryURI: "package:Kelivo/main_background_intent.dart")
        }

        guard didRun else {
            logger.error("Failed to run background FlutterEngine with entrypoint backgroundIntentMain")
            headlessEngine.destroyContext()
            throw NSError(domain: "KelivoIntent", code: 500, userInfo: [NSLocalizedDescriptionKey: "无法启动后台处理引擎，请重新编译应用"])
        }

        // 引擎成功启动后，注册原生插件（如 path_provider）
        GeneratedPluginRegistrant.register(with: headlessEngine)

        let channel = FlutterMethodChannel(name: "app.intent_chat", binaryMessenger: headlessEngine.binaryMessenger)

        return try await withCheckedThrowingContinuation { continuation in
            var isFinished = false

            // 监听 Dart 侧的回调结果
            channel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
                if call.method == "getIntentParams" {
                    // Dart 引擎初始化就绪，返回任务参数
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
                        headlessEngine.destroyContext()
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
                        headlessEngine.destroyContext()
                    }
                } else {
                    result(FlutterMethodNotImplemented)
                }
            }
        }
    }
}
