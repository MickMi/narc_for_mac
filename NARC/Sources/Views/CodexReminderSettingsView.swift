import SwiftUI
import AppKit

struct CodexReminderSettingsView: View {
    @ObservedObject var service: CodexCompletionService
    @State private var showSetupConfirmation = false
    @State private var filter = ""
    @State private var launchFailed = false
    private let connectionRefresh = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("回复提醒连接") {
                Label(service.installing ? "正在连接…" : service.connectionInfo?.status.title ?? "正在检查连接…",
                      systemImage: service.connectionInfo?.status == .connected ? "checkmark.circle" : "link")
                    .font(.headline)
                Text(service.installing ? "请稍候，不需要重复点击。" : service.connectionInfo?.status.guidance ?? "请稍候。")
                    .foregroundStyle(.secondary)
                if let state = service.connectionInfo?.status, let title = state.actionTitle {
                    Button(title) {
                        switch state {
                        case .notConfigured: showSetupConfirmation = true
                        case .waiting: openChatGPT()
                        case .error: service.checkConnection()
                        case .connected: break
                        }
                    }
                    .buttonStyle(.borderedProminent)
                        .disabled(service.installing || service.checkingConnection)
                }
                if launchFailed {
                    Text("未能打开 ChatGPT，请从应用程序中手动打开。")
                        .font(.narcCaption).foregroundStyle(.secondary)
                }
                if service.connectionInfo?.status == .waiting {
                    DisclosureGroup("回复结束后没有提醒？") {
                        Text("如果刚完成首次连接：保存工作，完全退出并重开 ChatGPT，再发一条消息。已经重开过仍无提醒，请联系维护者；不用反复连接或授权。")
                            .font(.narcCaption).foregroundStyle(.secondary)
                    }
                }
                DisclosureGroup("连接详情") {
                    Text("仅支持 Codex 任务，暂不支持普通 GPT 聊天。状态以最近收到的通知为准，不保证每一轮均成功。关闭或静音只停止显示提示，仍可能接收会话的基本信息。")
                    if let seconds = service.connectionInfo?.receivedAt {
                        Text("最近收到：" + Date(timeIntervalSince1970: seconds).formatted(date: .abbreviated, time: .standard))
                    }
                    if let message = service.setupMessage { Text(message).textSelection(.enabled) }
                    Button(service.checkingConnection ? "检查中…" : "检查连接") { service.checkConnection() }
                        .disabled(service.installing || service.checkingConnection)
                }
                .font(.narcCaption).foregroundStyle(.secondary)
            }
            Section("AI 回复提醒") {
                Toggle("显示回复提醒", isOn: Binding(get: { service.preferences.enabled }, set: { service.setEnabled($0) }))
                Text(service.preferences.enabled ? "回复结束后，在悬浮球旁显示提示。" : "提醒已暂停；打开上方开关即可恢复。")
                    .font(.narcCaption).foregroundStyle(.secondary)
            }
            Section("对话管理") {
                TextField("搜索对话名称或 ID", text: $filter)
                Text("新对话默认提醒。关掉单条开关即静音；重新打开只提醒之后的新结果。可起本地别名，不改变客户端里的标题。")
                    .font(.narcCaption).foregroundStyle(.secondary)
                if service.conversations.isEmpty {
                    Text("收到回复后，对话会自动出现在这里，无需逐条添加。")
                        .font(.narcCaption).foregroundStyle(.secondary)
                }
                ForEach(service.conversations.filter {
                    filter.isEmpty || service.displayTitle(threadID: $0.id, fallback: $0.title).localizedCaseInsensitiveContains(filter)
                        || $0.id.localizedCaseInsensitiveContains(filter)
                }) { conversation in
                    VStack(alignment: .leading, spacing: 5) {
                        Toggle(isOn: Binding(
                            get: { !service.preferences.muted.contains(conversation.id) },
                            set: { service.setMuted(!$0, threadID: conversation.id) }
                        )) {
                            Text(service.displayTitle(threadID: conversation.id, fallback: conversation.title)).lineLimit(2)
                        }
                        HStack {
                            Text(String(conversation.id.suffix(8))).font(.narcCaption).foregroundStyle(.secondary)
                            TextField("本地别名（可选）", text: Binding(
                                get: { service.preferences.names[conversation.id] ?? "" },
                                set: { service.setName($0, threadID: conversation.id) }
                            )).textFieldStyle(.roundedBorder)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped).padding()
        .onAppear { service.checkConnection() }
        .onReceive(connectionRefresh) { _ in
            if !showSetupConfirmation { service.checkConnection() }
        }
        .confirmationDialog("允许 NARC 连接回复提醒？", isPresented: $showSetupConfirmation) {
            Button("允许并连接") { service.connectNotifications() }
            Button("取消", role: .cancel) { }
        } message: {
            Text("连接后，Codex 任务回复结束时会提醒你。\n\nNARC 会调整本机通知设置，保留已有通知。原通知程序仍会收到原始事件（可能含对话正文）；NARC 自己只保存标题和完成状态等基本信息，不保存或上传正文。\n\n不会修改已有授权，也不会替你退出 ChatGPT。")
        }
    }

    private func openChatGPT() {
        launchFailed = false
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") else {
            launchFailed = true
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
            DispatchQueue.main.async { launchFailed = error != nil }
        }
    }
}
