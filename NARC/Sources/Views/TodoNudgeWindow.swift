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
        hasShadow = true
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
    var onHeightChange: (CGFloat) -> Void = { _ in }
    @State private var error: String?

    var body: some View {
        let summary = TodoReviewSummary(availableTodos: store.availableTodos(),
                                        incompleteCount: store.incompleteTodos.count)
        VStack(alignment: .leading, spacing: NarcSpacing.md) {
            HStack {
                Label(isPreview ? "每日回顾 · 预览" : "每日待办回顾", systemImage: "checklist")
                    .font(.narcCaption).foregroundColor(.narcAccent)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark").foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                }
                    .buttonStyle(.plain).accessibilityLabel("收起待办回顾")
            }
            if let todo = summary.featured {
                VStack(alignment: .leading, spacing: NarcSpacing.xs) {
                    Text(todo.title).font(.system(size: 20, weight: .semibold)).lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Button {
                        onActionStarted()
                        if store.setTodoCompleted(id: todo.id, completed: true) {
                            onSuccessfulAction()
                        } else {
                            error = store.lastError?.errorDescription ?? "未能保存，请重试。"
                            onActionFailed()
                        }
                    } label: {
                        Label("完成", systemImage: "checkmark")
                    }
                    .buttonStyle(NarcFocusPrimaryButtonStyle()).disabled(isPreview)
                    Button("稍后提醒", action: onSnooze)
                        .buttonStyle(.borderless).foregroundStyle(.secondary).disabled(isPreview)
                    Spacer(minLength: 0)
                }
                .controlSize(.regular)
                .padding(.vertical, NarcSpacing.xs)
                if let error { Text(error).font(.narcCaption).foregroundStyle(.red).lineLimit(2) }
                Divider().opacity(0.5)
                VStack(alignment: .leading, spacing: NarcSpacing.sm) {
                    Text(summary.remainingCount == 0 ? "完成它，就清空待办了" : "还有 \(summary.remainingCount) 件待办")
                        .font(.narcCaption).foregroundStyle(.secondary)
                    ForEach(summary.others) { item in
                        HStack(spacing: NarcSpacing.sm) {
                            Image(systemName: "circle").font(.system(size: 8)).foregroundStyle(.secondary)
                            Text(item.title).font(.narcBody).lineLimit(1)
                        }
                    }
                }
                HStack {
                    Spacer(minLength: 0)
                    Button(action: onViewAll) {
                        Label("查看全部", systemImage: "chevron.right")
                    }
                }.buttonStyle(.borderless).font(.narcCaption)
            } else {
                Text("当前没有待完成 Todo").font(.narcSubtitle)
                Text("记下一件事后，会在这里提醒你。")
                    .font(.narcCaption).foregroundStyle(.secondary)
                Button("查看 Todo", action: onViewAll)
            }
        }
        .padding(NarcSpacing.xl)
        .frame(width: TodoNudgeWindow.cardSize.width)
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { geometry in
            Color.clear.preference(key: TodoReviewHeight.self, value: geometry.size.height)
        })
        .onPreferenceChange(TodoReviewHeight.self, perform: onHeightChange)
        .background(Color.narcFocusSurface)
        .clipShape(RoundedRectangle(cornerRadius: NarcRadius.focus, style: .continuous))
    }
}

private struct TodoReviewHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
