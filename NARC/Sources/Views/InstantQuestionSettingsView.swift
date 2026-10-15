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
                Text("即时回答使用 deepseek-flash，支持文字和图片理解。密钥只保存在 macOS 钥匙串。")
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
                Text("点击后尝试读取钥匙串；需要授权时由 macOS 提示。已获授权则直接就绪，不会强制弹密码窗口。此操作不发送 AI 请求，不计费。")
                    .font(.narcCaption).foregroundStyle(Color.narcTextMuted)
            }

            Section("搜索模式") {
                Text("DeepSeek 问答与 Bing / Google 网页搜索彼此独立：NARC 不会把网页结果转交给 DeepSeek，也不需要额外的搜索 API Key。")
                    .font(.narcCaption)
                    .foregroundStyle(Color.narcTextMuted)
                Text("DeepSeek 当前不提供可执行的内建网页搜索，所以 AI 回答不会显示为“已联网”。")
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
                Text("验证会发送一次真实 DeepSeek 请求，可能计入服务额度。Bing / Google 网页搜索不使用 API。")
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
