import AppIntents

@available(iOS 17.0, *)
struct KelivoShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskAIIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "向 \(.applicationName) 提问",
                "问问 \(.applicationName)",
                "使用 \(.applicationName) 对话"
            ],
            shortTitle: "询问 Kelivo",
            systemImageName: "sparkles"
        )
    }
}
