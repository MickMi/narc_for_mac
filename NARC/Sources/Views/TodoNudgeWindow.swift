import Cocoa
import SwiftUI

enum TodoNudgePlacement {
    static func frame(
        adjacentTo widgetFrame: NSRect,
        visibleWidgetSize: CGFloat,
        cardSize: NSSize,
        targetVisibleFrame: NSRect,
        gap: CGFloat = 10,
        margin: CGFloat = 8
    ) -> NSRect {
        let widget = FloatingWidgetPlacement.visibleWidgetRect(
            in: widgetFrame,
            visibleSize: visibleWidgetSize
        )
        let leftX = widget.minX - gap - cardSize.width
        let rightX = widget.maxX + gap

        let originX: CGFloat
        if leftX >= targetVisibleFrame.minX + margin {
            originX = leftX
        } else if rightX + cardSize.width <= targetVisibleFrame.maxX - margin {
            originX = rightX
        } else {
            originX = clamp(
                widget.midX - cardSize.width / 2,
                minimum: targetVisibleFrame.minX + margin,
                maximum: targetVisibleFrame.maxX - cardSize.width - margin,
                fallback: targetVisibleFrame.midX - cardSize.width / 2
            )
        }

        let originY = clamp(
            widget.midY - cardSize.height / 2,
            minimum: targetVisibleFrame.minY + margin,
            maximum: targetVisibleFrame.maxY - cardSize.height - margin,
            fallback: targetVisibleFrame.midY - cardSize.height / 2
        )

        return NSRect(
            origin: NSPoint(x: originX, y: originY),
            size: cardSize
        )
    }

    private static func clamp(
        _ value: CGFloat,
        minimum: CGFloat,
        maximum: CGFloat,
        fallback: CGFloat
    ) -> CGFloat {
        guard minimum <= maximum else { return fallback }
        return max(minimum, min(value, maximum))
    }
}

@MainActor
final class TodoNudgeWindow: NSPanel {
    static let cardSize = NSSize(width: 360, height: 370)

    convenience init<Content: View>(rootView: Content) {
        self.init(
            contentRect: NSRect(origin: .zero, size: Self.cardSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary,
        ]
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        ignoresMouseEvents = false
        isReleasedWhenClosed = false
        contentView = TodoNudgeHostingView(rootView: rootView)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class TodoNudgeHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

struct TodoNudgeCardView: View {
    @ObservedObject var store: AssistantStore
    let onActionStarted: () -> Void
    let onActionFailed: () -> Void
    let onSuccessfulAction: () -> Void
    let onDismiss: () -> Void
    let onSnooze: () -> Void
    let onViewAll: () -> Void
    var isPreview = false
    @State private var error: String?

    var body: some View {
        let summary = TodoReviewSummary(availableTodos: store.availableTodos(),
                                        incompleteCount: store.incompleteTodos.count)
        VStack(alignment: .leading, spacing: NarcSpacing.md) {
            HStack {
                Label(isPreview ? "每日回顾 · 预览" : "每日待办回顾", systemImage: "checklist")
                    .font(.narcCaption).foregroundColor(.narcAccent)
                Spacer()
                Button(action: onDismiss) { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel("收起待办回顾")
            }
            if let todo = summary.featured {
                VStack(alignment: .leading, spacing: NarcSpacing.xs) {
                    Text("先做这一件").font(.narcCaption).foregroundStyle(.secondary)
                    Text(todo.title).font(.narcTitle).lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: NarcSpacing.xs) {
                        Text(todo.isNext ? "你指定的下一件事" : todo.priority.label)
                        if let dueAt = todo.dueAt {
                            Text("· 截止")
                            Text(dueAt, format: .dateTime.month().day().hour().minute())
                        }
                    }
                    .font(.narcCaption).foregroundStyle(.secondary).lineLimit(1)
                }
                Divider()
                VStack(alignment: .leading, spacing: NarcSpacing.sm) {
                    Text(summary.remainingCount == 0 ? "完成它，就清空待办了" : "还有 \(summary.remainingCount) 件待办")
                        .font(.narcCaption).foregroundStyle(.secondary)
                    ForEach(summary.others) { item in
                        HStack(spacing: NarcSpacing.sm) {
                            Image(systemName: "circle").font(.system(size: 8)).foregroundStyle(.secondary)
                            Text(item.title).font(.narcBody).lineLimit(1)
                        }
                    }
                    if summary.deferredCount > 0 {
                        Text("其中 \(summary.deferredCount) 件已延期，暂不推荐")
                            .font(.narcCaption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if let error { Text(error).font(.narcCaption).foregroundStyle(.red).lineLimit(2) }
                HStack {
                    Button("完成这一件") {
                        onActionStarted()
                        if store.setTodoCompleted(id: todo.id, completed: true) {
                            onSuccessfulAction()
                        } else {
                            error = store.lastError?.errorDescription ?? "未能保存，请重试。"
                            onActionFailed()
                        }
                    }.disabled(isPreview)
                    Button("1 小时后", action: onSnooze).disabled(isPreview)
                    Spacer(minLength: 0)
                    Button("查看全部", action: onViewAll)
                }.buttonStyle(.bordered).controlSize(.small)
            } else {
                Spacer()
                Text("当前没有可提醒的 Todo").font(.narcSubtitle)
                Text("已完成或延期中的任务不会主动弹出。")
                    .font(.narcCaption).foregroundStyle(.secondary)
                Button("查看 Todo", action: onViewAll)
                Spacer()
            }
        }
        .padding(NarcSpacing.lg)
        .frame(
            width: TodoNudgeWindow.cardSize.width,
            height: TodoNudgeWindow.cardSize.height
        )
        .background(VisualEffectBackground(material: .hudWindow))
        .clipShape(RoundedRectangle(cornerRadius: NarcRadius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: NarcRadius.lg, style: .continuous)
                .strokeBorder(Color.narcInfo.opacity(0.32), lineWidth: 1)
        }
        .shadow(color: Color.narcInfo.opacity(0.16), radius: 18, y: 8)
    }
}
