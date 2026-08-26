import AppIntents
import Foundation
import UniformTypeIdentifiers

@available(iOS 16.0, *)
struct AskAIIntent: AppIntent {
    static var title: LocalizedStringResource = "询问 Kelivo"
    static var description = IntentDescription("在后台向 Kelivo AI 助手发送提示词，支持选择助手、会话及模型。")

    // ⭐ 关键：不唤起 App 界面，纯后台执行
    static var openAppWhenRun = false

    @Parameter(
        title: "提示词",
        requestValueDialog: "想向 Kelivo 询问什么？",
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var prompt: String

    @Parameter(
        title: "助手",
        description: "选择提问的助手，不选则使用默认助手"
    )
    var assistant: AssistantEntity?

    @Parameter(
        title: "会话",
        description: "选择已有会话继续对话；留空则自动创建新会话"
    )
    var session: SessionEntity?

    @Parameter(
        title: "模型",
        description: "指定使用的模型；留空则使用助手预设模型"
    )
    var model: ModelSelectionEntity?

    @Parameter(
        title: "附件",
        description: "可选图片或文件附件，可留空",
        supportedTypeIdentifiers: ["public.image", "public.movie", "public.data"],
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var files: [IntentFile]?

    @Parameter(
        title: "等待回复结果",
        description: "开启后等待完整回复返回，可用于快捷指令后续动作；关闭则后台生成并通过通知提醒",
        default: true  // 默认同步等待，避免异步模式下系统挂起 Intent 进程
    )
    var waitForResult: Bool

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        // 1. 开启后台音频保活
        BackgroundAudioKeepAlive.shared.start()

        // 2. 导出附件到临时文件以便 Dart 读取
        var tempFilePaths: [String] = []
        if let files = files {
            for (idx, file) in files.enumerated() {
                let tmpDir = FileManager.default.temporaryDirectory
                let ext = file.filename.components(separatedBy: ".").last ?? "dat"
                let targetUrl = tmpDir.appendingPathComponent("intent_upload_\(idx)_\(UUID().uuidString).\(ext)")
                do {
                    try file.data.write(to: targetUrl)
                    tempFilePaths.append(targetUrl.path)
                } catch {
                    // ignore single file error
                }
            }
        }

        let assistantId = assistant?.id
        let sessionId = session?.id
        let modelId = model?.id
        let inputPrompt = prompt

        // 3. 同步模式（推荐）：等待生成完毕后返回，结果可直接用于快捷指令后续动作
        if waitForResult {
            defer {
                BackgroundAudioKeepAlive.shared.stop()
                for path in tempFilePaths {
                    try? FileManager.default.removeItem(atPath: path)
                }
            }

            NativeNotificationHelper.shared.sendNotification(
                title: "Kelivo 正在思考...",
                body: inputPrompt
            )

            do {
                let result = try await IntentFlutterBridge.shared.execute(
                    prompt: inputPrompt,
                    assistantId: assistantId,
                    sessionId: sessionId,
                    modelId: modelId,
                    filePaths: tempFilePaths
                )

                NativeNotificationHelper.shared.sendNotification(
                    title: "\(result.assistantName) 已回复",
                    body: result.response
                )

                let jsonDict: [String: Any] = [
                    "success": true,
                    "session_id": result.sessionId,
                    "response": result.response,
                    "assistant_name": result.assistantName,
                    "model_name": result.modelName
                ]
                if let jsonData = try? JSONSerialization.data(withJSONObject: jsonDict, options: [.prettyPrinted, .sortedKeys]),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    return .result(value: jsonString, dialog: "\(result.response)")
                }

                return .result(value: result.response, dialog: "\(result.response)")
            } catch {
                let errorMsg = error.localizedDescription
                NativeNotificationHelper.shared.sendNotification(
                    title: "Kelivo 任务失败",
                    body: errorMsg
                )
                let errorDict: [String: Any] = [
                    "success": false,
                    "error": errorMsg,
                    "session_id": sessionId ?? "",
                    "response": "执行失败: \(errorMsg)"
                ]
                if let jsonData = try? JSONSerialization.data(withJSONObject: errorDict, options: [.prettyPrinted, .sortedKeys]),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    return .result(value: jsonString, dialog: "执行失败: \(errorMsg)")
                }
                return .result(value: "执行失败: \(errorMsg)", dialog: "执行失败: \(errorMsg)")
            }
        }

        // 4. 异步模式（实验性）：立即返回，后台协程继续跑
        // ⚠️ 注意：AppIntents 的 perform() 返回后系统随时可能挂起进程，
        // 后台任务能否完成取决于系统调度，不可保证。建议优先使用同步模式。
        NativeNotificationHelper.shared.sendNotification(
            title: "Kelivo 任务已开始",
            body: inputPrompt
        )

        Task { @MainActor in
            defer {
                BackgroundAudioKeepAlive.shared.stop()
                for path in tempFilePaths {
                    try? FileManager.default.removeItem(atPath: path)
                }
            }

            do {
                let result = try await IntentFlutterBridge.shared.execute(
                    prompt: inputPrompt,
                    assistantId: assistantId,
                    sessionId: sessionId,
                    modelId: modelId,
                    filePaths: tempFilePaths
                )

                NativeNotificationHelper.shared.sendNotification(
                    title: "\(result.assistantName) 已回复",
                    body: result.response
                )
            } catch {
                NativeNotificationHelper.shared.sendNotification(
                    title: "Kelivo 任务失败",
                    body: error.localizedDescription
                )
            }
        }

        return .result(value: "任务已在后台启动，完成后将推送通知", dialog: "任务已在后台启动")
    }
}
