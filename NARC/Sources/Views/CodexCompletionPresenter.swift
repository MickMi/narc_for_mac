import Cocoa
import SwiftUI

@MainActor
final class CodexCompletionPresenter {
    let service: CodexCompletionService
    private var panel: TodoNudgeWindow?
    private let layout = CodexCompletionCardLayout()
    private var resizeTask: Task<Void, Never>?
    private var presentationID = UUID()
    var anchor: (() -> (NSRect, CGFloat, NSRect)?)?
    var isBlocked: (() -> Bool)?
    var isVisible: Bool { panel?.isVisible == true }

    init(service: CodexCompletionService? = nil) {
        self.service = service ?? CodexCompletionService()
    }

    func start() {
        service.onRefresh = { [weak self] in self?.reconcile() }
        service.start()
    }

    func stop() { service.stop(); service.onRefresh = nil; hide() }

    private func hide() {
        presentationID = UUID()
        resizeTask?.cancel()
        resizeTask = nil
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel?.close()
        panel = nil
    }

    private func requestResize(for id: UUID) {
        guard id == presentationID, resizeTask == nil else { return }
        // NSHostingView can measure synchronously during window construction.
        // Re-entering reconcile there creates a second, unowned visible panel.
        resizeTask = Task { @MainActor [weak self] in
            guard !Task.isCancelled, let self, self.presentationID == id else { return }
            self.resizeTask = nil
            self.reconcile()
        }
    }

    func reconcile() {
        guard !service.pendingEvents.isEmpty, isBlocked?() != true,
              let (widget, visibleSize, screen) = anchor?() else { hide(); return }
        let maximumHeight = max(1, min(360, screen.height - 20))
        if layout.maximumHeight != maximumHeight { layout.maximumHeight = maximumHeight }
        let size = NSSize(width: min(340, max(1, screen.width - 20)), height: layout.cardHeight)
        if panel == nil {
            let id = presentationID
            let card = CodexCompletionCard(service: service, layout: layout,
                onResize: { [weak self] in self?.requestResize(for: id) }, onOpen: { [weak self] event, completion in
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

/// Share measured content height with the AppKit panel; never estimate by row count.
@MainActor
final class CodexCompletionCardLayout: ObservableObject {
    static let chromeHeight: CGFloat = 64 // 16pt padding × 2 + 20pt header + 12pt gap.
    @Published var maximumHeight: CGFloat = 360
    @Published private(set) var contentHeight: CGFloat = 64

    var listHeight: CGFloat { min(contentHeight, max(0, maximumHeight - Self.chromeHeight)) }
    var cardHeight: CGFloat { min(maximumHeight, Self.chromeHeight + listHeight) }

    @discardableResult func measure(_ height: CGFloat) -> Bool {
        guard height.isFinite, height >= 0 else { return false }
        let rounded = ceil(height)
        guard rounded != contentHeight else { return false }
        contentHeight = rounded
        return true
    }
}

private struct CodexCompletionContentHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct CodexCompletionCard: View {
    @ObservedObject var service: CodexCompletionService
    @ObservedObject var layout: CodexCompletionCardLayout
    let onResize: () -> Void
    let onOpen: (CodexCompletionEvent, @escaping (Bool) -> Void) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("\(service.pendingEvents.count) 个对话已回复", systemImage: "bubble.left.and.bubble.right")
                    .font(.narcBody).foregroundStyle(Color.narcAccent)
                Spacer(minLength: 8)
                Text("ChatGPT / Codex").font(.narcCaption).foregroundStyle(.secondary)
            }
            .lineLimit(1).frame(height: 20)
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(service.pendingEvents, id: \.identity) { event in
                        if event.identity != service.pendingEvents.first?.identity { Divider() }
                        CodexCompletionRow(event: event,
                            title: service.displayTitle(threadID: event.threadID, fallback: event.title),
                            onDismiss: { service.acknowledge(identity: event.identity) },
                            onMute: { service.setMuted(true, threadID: event.threadID) },
                            onOpen: { onOpen(event, $0) })
                    }
                }
                .frame(maxWidth: .infinity)
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: CodexCompletionContentHeight.self, value: geometry.size.height)
                })
            }
            .frame(height: layout.listHeight)
            .onPreferenceChange(CodexCompletionContentHeight.self) { height in
                if layout.measure(height) { onResize() }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .topLeading)
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
            HStack(alignment: .top, spacing: 8) {
                Text(event.isPreview ? "测试提示 · \(title)" : title).font(.narcSubtitle).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button(action: onDismiss) { Image(systemName: "xmark") }
                    .frame(width: 20, height: 20)
                    .buttonStyle(.plain).accessibilityLabel("忽略本轮回复提醒")
            }
            HStack {
                Button("不再提醒", action: onMute).buttonStyle(.borderless)
                    .font(.narcCaption).foregroundStyle(.secondary)
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
