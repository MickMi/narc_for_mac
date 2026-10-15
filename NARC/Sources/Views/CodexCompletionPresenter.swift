import Cocoa
import SwiftUI

@MainActor
final class CodexCompletionPresenter {
    let service: CodexCompletionService
    private let automaticDisplayDuration: Duration
    private var panel: TodoNudgeWindow?
    private let layout = CodexCompletionCardLayout()
    private var resizeTask: Task<Void, Never>?
    private var presentationID = UUID()
    private var autoHideTask: Task<Void, Never>?
    private var observedEventIDs: Set<String> = []
    private enum PresentationMode { case hidden, automatic, manual }
    private var mode: PresentationMode = .hidden
    var anchor: (() -> (NSRect, CGFloat, NSRect)?)?
    var isBlocked: (() -> Bool)?
    var isVisible: Bool { panel?.isVisible == true }

    init(service: CodexCompletionService? = nil,
         automaticDisplayDuration: Duration = .seconds(10)) {
        self.service = service ?? CodexCompletionService()
        self.automaticDisplayDuration = automaticDisplayDuration
    }

    func start() {
        service.onRefresh = { [weak self] in self?.reconcile() }
        service.start()
    }

    func stop() {
        service.stop()
        service.onRefresh = nil
        autoHideTask?.cancel()
        autoHideTask = nil
        observedEventIDs.removeAll()
        mode = .hidden
        hide()
    }

    func toggleFromBadge() {
        guard !service.pendingEvents.isEmpty else { return }
        autoHideTask?.cancel()
        autoHideTask = nil
        mode = mode == .manual ? .hidden : .manual
        reconcile()
    }

    private func scheduleAutoHide() {
        autoHideTask?.cancel()
        autoHideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: self?.automaticDisplayDuration ?? .seconds(10))
            guard !Task.isCancelled, let self, self.mode == .automatic else { return }
            self.mode = .hidden
            self.autoHideTask = nil
            self.reconcile()
        }
    }

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
        let identities = Set(service.pendingEvents.map(\.identity))
        guard !identities.isEmpty else {
            observedEventIDs.removeAll()
            autoHideTask?.cancel()
            autoHideTask = nil
            mode = .hidden
            hide()
            return
        }
        guard isBlocked?() != true, let (widget, visibleSize, screen) = anchor?() else {
            // A notification arriving while another panel is open should still
            // receive its brief presentation when the widget becomes available.
            observedEventIDs.removeAll()
            autoHideTask?.cancel()
            autoHideTask = nil
            mode = .hidden
            hide()
            return
        }
        let fresh = identities.subtracting(observedEventIDs)
        observedEventIDs = identities
        if !fresh.isEmpty && mode != .manual {
            mode = .automatic
            scheduleAutoHide()
        }
        guard mode != .hidden else { hide(); return }
        layout.retainEvents(Set(service.pendingEvents.map(\.identity)))
        let maximumHeight = max(1, min(360, screen.height - 20))
        if layout.maximumHeight != maximumHeight { layout.maximumHeight = maximumHeight }
        let size = NSSize(
            width: min(CodexCompletionCardLayout.preferredWidth, max(1, screen.width - 20)),
            height: layout.cardHeight
        )
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

    func open(_ event: CodexCompletionEvent, completion: @escaping (Bool) -> Void) {
        service.resolveForOpening(event) { [weak self] current in
            guard let self, let current else { completion(false); return }
            self.dispatchOpen(current, completion: completion)
        }
    }

    private func dispatchOpen(_ event: CodexCompletionEvent, completion: @escaping (Bool) -> Void) {
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
    static let preferredWidth: CGFloat = 420
    static let chromeHeight: CGFloat = 64 // 16pt padding × 2 + 20pt header + 12pt gap.
    @Published var maximumHeight: CGFloat = 360
    @Published private(set) var contentHeight: CGFloat = 64
    @Published private(set) var expandedEventIDs: Set<String> = []

    var listHeight: CGFloat { min(contentHeight, max(0, maximumHeight - Self.chromeHeight)) }
    var cardHeight: CGFloat { min(maximumHeight, Self.chromeHeight + listHeight) }

    func isExpanded(_ identity: String, eventCount: Int) -> Bool {
        eventCount == 1 || expandedEventIDs.contains(identity)
    }

    func toggleDetails(_ identity: String) {
        if expandedEventIDs.contains(identity) {
            expandedEventIDs.remove(identity)
        } else {
            expandedEventIDs.insert(identity)
        }
    }

    func retainEvents(_ identities: Set<String>) {
        let retained = expandedEventIDs.intersection(identities)
        if retained != expandedEventIDs { expandedEventIDs = retained }
    }

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
    var fillsAvailableHeight = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(service.pendingEvents.count == 1 ? "对话已回复" : "\(service.pendingEvents.count) 个对话已回复", systemImage: "bubble.left.and.bubble.right")
                    .font(.narcCaption).foregroundStyle(Color.narcAccent)
                Spacer(minLength: 8)
                Text("Codex").font(.narcCaption).foregroundStyle(.secondary)
            }
            .lineLimit(1).frame(height: 20)
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(service.pendingEvents, id: \.identity) { event in
                        if event.identity != service.pendingEvents.first?.identity { Divider() }
                        CodexCompletionRow(event: event,
                            title: service.displayTitle(threadID: event.threadID, fallback: event.title),
                            showsDisclosure: event.canExpand(eventCount: service.pendingEvents.count),
                            isExpanded: event.hasRoundDetails && layout.isExpanded(event.identity, eventCount: service.pendingEvents.count),
                            onToggleDetails: { layout.toggleDetails(event.identity) },
                            onDismiss: { service.acknowledge(identity: event.identity) },
                            onMute: { service.setMuted(true, threadID: event.threadID) },
                            onOpen: { onOpen(event, $0) })
                    }
                }
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: CodexCompletionContentHeight.self, value: geometry.size.height)
                })
            }
            .frame(height: fillsAvailableHeight ? nil : layout.listHeight)
            .frame(maxHeight: fillsAvailableHeight ? .infinity : nil)
            .scrollIndicators(.visible)
            .scrollIndicatorsFlash(onAppear: true)
            .onPreferenceChange(CodexCompletionContentHeight.self) { height in
                if layout.measure(height) { onResize() }
            }
            if fillsAvailableHeight && service.pendingEvents.count > 2 {
                Text("可滚动查看全部 \(service.pendingEvents.count) 条回复")
                    .font(.narcCaption).foregroundStyle(Color.narcTextMuted)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(16).frame(maxWidth: .infinity,
                          maxHeight: fillsAvailableHeight ? .infinity : nil, alignment: .topLeading)
        .background(Color.narcFocusSurface)
        .clipShape(RoundedRectangle(cornerRadius: NarcRadius.focus, style: .continuous))
    }
}

private struct CodexCompletionRow: View {
    let event: CodexCompletionEvent
    let title: String
    let showsDisclosure: Bool
    let isExpanded: Bool
    let onToggleDetails: () -> Void
    let onDismiss: () -> Void
    let onMute: () -> Void
    let onOpen: (@escaping (Bool) -> Void) -> Void
    @State private var openFailed = false
    @State private var opening = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Text(event.isPreview ? "测试提示 · \(title)" : title)
                    .font(.narcSubtitle)
                    .foregroundStyle(.primary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                Spacer(minLength: 0)
                if showsDisclosure {
                    Button(action: onToggleDetails) {
                        Label(isExpanded ? "收起详情" : "展开详情",
                              systemImage: isExpanded ? "chevron.up" : "chevron.down")
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .font(.narcCaption)
                    .foregroundStyle(Color.narcAccent)
                    .buttonStyle(.plain)
                    .accessibilityLabel(isExpanded ? "收起\(title)的详情" : "展开\(title)的详情")
                }
                Button(action: onDismiss) { Image(systemName: "xmark") }
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .buttonStyle(.plain).accessibilityLabel("忽略本轮回复提醒")
            }
            if isExpanded {
                if let summary = event.roundSummary {
                    CodexCompletionDetailRow(
                        text: "本回合：\(summary)",
                        symbol: "checkmark.circle.fill",
                        color: .primary,
                        font: .narcBody
                    )
                }
                if let action = roundAction {
                    CodexCompletionDetailRow(
                        text: action.text,
                        symbol: action.symbol,
                        color: action.isBlocker ? Color.orange : Color.narcTextMuted,
                        font: .narcCaption
                    )
                }
            }
            HStack {
                Button("不再提醒此对话", action: onMute).buttonStyle(.borderless)
                    .font(.narcCaption).foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .help("不再提醒此对话；可在设置的 AI 回复中恢复")
                Spacer()
                Button {
                    opening = true
                    onOpen { success in
                        opening = false
                        openFailed = !success
                    }
                } label: {
                    Label(opening ? "正在打开…" : "继续对话", systemImage: "arrow.up.right")
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(NarcFocusPrimaryButtonStyle()).disabled(opening)
            }
            if openFailed { Text("未能打开客户端，请手动返回").font(.narcCaption).foregroundStyle(.red) }
        }
    }

    private var roundAction: (text: String, symbol: String, isBlocker: Bool)? {
        if let blocker = event.blocker {
            return ("阻塞：\(blocker)", "exclamationmark.triangle.fill", true)
        }
        if let nextStep = event.nextStep {
            return ("下一步：\(nextStep)", "arrow.right", false)
        }
        return nil
    }
}

private struct CodexCompletionDetailRow: View {
    let text: String
    let symbol: String
    let color: Color
    let font: Font

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 16, height: 18)
            Text(text)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
        }
        .font(font)
        .foregroundStyle(color)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
