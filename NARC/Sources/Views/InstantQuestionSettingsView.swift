import SwiftUI

struct InstantQuestionSettingsView: View {
    @ObservedObject var controller: InstantQuestionController
    @ObservedObject private var credentials: InstantQuestionCredentialManager

    @State private var deepSeekKey = ""
    @State private var statusMessage: String?

    init(controller: InstantQuestionController) {
        self.controller = controller
        _credentials = ObservedObject(wrappedValue: controller.credentials)
    }

    var body: some View {
        Form {
            Section("DeepSeek") {
                SecureField("DeepSeek API Key", text: $deepSeekKey)
                credentialActions(
                    isConfigured: credentials.hasDeepSeekKey,
                    save: {
                        if credentials.saveDeepSeekKey(deepSeekKey) {
                            deepSeekKey = ""
                            statusMessage = "DeepSeek API Key 已保存到钥匙串。"
                        } else {
                            statusMessage = credentials.lastError
                        }
                    },
                    remove: {
                        if credentials.removeDeepSeekKey() { statusMessage = "DeepSeek API Key 已移除。" }
                    }
                )
                .disabled(credentials.isAuthorizing || controller.isBusy || controller.isCheckingConnection)
                Text("联网问答使用 Pro 原生搜索；关闭联网时使用 Flash，支持文字和图片理解。两种模式共用此 Key，密钥只保存在 macOS 钥匙串。")
                    .font(.narcCaption)
                    .foregroundStyle(Color.narcTextMuted)
            }

            Section("密钥读取授权") {
                HStack(spacing: NarcSpacing.md) {
                    statusLabel(credentials.isReady ? "密钥已就绪（本次运行）" : "尚未授权读取", ready: credentials.isReady)
                    Spacer()
                    Button {
                        Task { await credentials.authorizeRead() }
                    } label: {
                        Label(credentials.isAuthorizing ? "等待授权…" : "授权读取密钥", systemImage: "key.horizontal")
                            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    }
                    .disabled(credentials.isReady || credentials.isAuthorizing || controller.isBusy || controller.isCheckingConnection)
                    .accessibilityLabel("授权读取密钥")
                }
                if let message = credentials.lastError {
                    Text(message).font(.narcCaption).foregroundStyle(Color.narcDanger)
                }
                Text("保存或授权后，后续打开 AI 会尝试无弹窗读取；系统需要重新确认时才在这里主动授权。密钥只保存在钥匙串，并在本次运行缓存；这一步不发送 AI 请求，不计费。")
                    .font(.narcCaption).foregroundStyle(Color.narcTextMuted)
            }

            Section("搜索模式") {
                Toggle("联网搜索", isOn: $controller.webSearchEnabled)
                    .disabled(controller.isBusy)
                Text("首次默认开启，并记住你的选择。开启时使用 deepseek-v4-pro 和原生网页搜索，模型与搜索费用由 DeepSeek 计费；无需额外搜索 Key。Pro 暂不支持图片，图片提问需要明确关闭联网。")
                    .font(.narcCaption)
                    .foregroundStyle(Color.narcTextMuted)
                Text("Bing / Google 仍是独立网页搜索，结果不会自动发送给 DeepSeek；它们不使用搜索 API。")
                    .font(.narcCaption)
                    .foregroundStyle(Color.narcTextFaint)
            }

            Section("连接状态") {
                HStack(spacing: NarcSpacing.md) {
                    Text("DeepSeek 连接测试").font(.narcBody)
                    Spacer()
                    Button(action: controller.validateConnection) {
                        Label(controller.isCheckingConnection ? "验证中" : "验证连接", systemImage: "network")
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .disabled(!credentials.isReady || controller.isCheckingConnection)
                }
                if let message = controller.connectionCheckMessage ?? statusMessage {
                    Text(message)
                        .font(.narcCaption)
                        .foregroundStyle(Color.narcTextMuted)
                }
                Text("验证只发送一次 Flash 基础问答请求，可能计入服务额度；联网效果请在问答窗口测试。")
                    .font(.narcCaption)
                    .foregroundStyle(Color.narcTextFaint)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            // The shared controller can be created while this LSUIElement app
            // is still activating. Retry when the settings UI is actually
            // visible so a transient Keychain interaction failure is not
            // cached for the rest of the process lifetime.
            credentials.refreshStatus()
        }
    }

    private func credentialActions(
        isConfigured: Bool,
        save: @escaping () -> Void,
        remove: @escaping () -> Void
    ) -> some View {
        HStack(spacing: NarcSpacing.sm) {
            Label(isConfigured ? "已保存在钥匙串" : "尚未配置", systemImage: isConfigured ? "checkmark.circle.fill" : "circle")
                .font(.narcCaption)
                .foregroundStyle(isConfigured ? Color.narcSuccess : Color.narcTextMuted)
                .lineLimit(1)
            Spacer()
            Button("保存", action: save)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            if isConfigured {
                Button("移除", action: remove)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private func statusLabel(_ title: String, ready: Bool) -> some View {
        Label(title, systemImage: ready ? "checkmark.circle.fill" : "exclamationmark.circle")
            .font(.narcCaption)
            .foregroundStyle(ready ? Color.narcSuccess : Color.narcWarn)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
}
