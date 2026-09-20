import Cocoa
import SwiftUI

@MainActor
final class CodexCompletionPresenter {
    let service = CodexCompletionService()
    private var panel: TodoNudgeWindow?
    var anchor: (() -> (NSRect, CGFloat, NSRect)?)?
    var isBlocked: (() -> Bool)?
    var isVisible: Bool { panel?.isVisible == true }

    func start() {
        service.onRefresh = { [weak self] in self?.reconcile() }
        service.start()
    }

    func stop() { service.stop(); hide() }

    private func hide() { panel?.orderOut(nil); panel = nil }

    private func reconcile() {
        guard !service.pendingEvents.isEmpty, isBlocked?() != true,
              let (widget, visibleSize, screen) = anchor?() else { hide(); return }
        let contentHeight = min(380, 105 + service.pendingEvents.count * 115)
        let size = NSSize(width: 380, height: min(CGFloat(contentHeight), screen.height - 20))
        if panel == nil {
            let card = CodexCompletionCard(service: service, onOpen: { [weak self] event, completion in
                guard let self else { completion(false); return }
                self.open(event, completion: completion)
            })
            let panel = TodoNudgeWindow(rootView: card)
            panel.setContentSize(size)
            self.panel = panel
        }
        panel?.setFrame(TodoNudgePlacement.frame(adjacentTo: widget, visibleWidgetSize: visibleSize,
                                                 cardSize: size, targetVisibleFrame: screen), display: true)
        if panel?.isVisible != true { panel?.orderFrontRegardless() }
    }

    private func open(_ event: CodexCompletionEvent, completion: @escaping (Bool) -> Void) {
        guard let url = event.threadURL,
              let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") else { completion(false); return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        // Explicit target avoids another app taking over the codex URL scheme.
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: config) { [weak self] _, error in
            Task { @MainActor in
                completion(error == nil)
                // Launch success only confirms dispatch, not that the UI selected the right thread.
                if error == nil {
                    self?.service.acknowledge(identity: event.identity)
                }
            }
        }
    }
}

private struct CodexCompletionCard: View {
    @ObservedObject var service: CodexCompletionService
    let onOpen: (CodexCompletionEvent, @escaping (Bool) -> Void) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("\(service.pendingEvents.count) 个对话已回复", systemImage: "bubble.left.and.bubble.right")
                .font(.narcSubtitle).foregroundStyle(Color.narcAccent)
            Text("ChatGPT / Codex · 等待你继续")
                .font(.narcCaption).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(service.pendingEvents, id: \.identity) { event in
                        CodexCompletionRow(event: event,
                            title: service.displayTitle(threadID: event.threadID, fallback: event.title),
                            onDismiss: { service.acknowledge(identity: event.identity) },
                            onMute: { service.setMuted(true, threadID: event.threadID) },
                            onOpen: { onOpen(event, $0) })
                        Divider()
                    }
                }
            }
        }
        .padding(18).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(VisualEffectBackground(material: .hudWindow))
        .clipShape(RoundedRectangle(cornerRadius: NarcRadius.lg))
    }
}

private struct CodexCompletionRow: View {
    let event: CodexCompletionEvent
    let title: String
    let onDismiss: () -> Void
    let onMute: () -> Void
    let onOpen: (@escaping (Bool) -> Void) -> Void
    @State private var openFailed = false
    @State private var opening = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(event.isPreview ? "测试提示 · \(title)" : title).font(.narcSubtitle).lineLimit(2)
                Spacer()
                Button(action: onDismiss) { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel("忽略本轮回复提醒")
            }
            HStack {
                Button("不再提醒", action: onMute).buttonStyle(.borderless)
                    .help("不再提醒此对话；可在设置的 AI 回复中恢复")
                Spacer()
                Button(opening ? "正在打开…" : "继续对话") {
                    opening = true
                    onOpen { success in
                        opening = false
                        openFailed = !success
                    }
                }
                .buttonStyle(.bordered).disabled(opening)
            }
            if openFailed { Text("未能打开客户端，请手动返回").font(.narcCaption).foregroundStyle(.red) }
        }
    }
}
