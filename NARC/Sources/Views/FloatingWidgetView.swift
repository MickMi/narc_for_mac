import SwiftUI

// MARK: - 1. State

/// Public state contract per spec §2 / §6.
enum FloatingWidgetState: Equatable {
    case idle
    case hasNotification(count: Int)
    case badgeUnavailable(lastKnownCount: Int)
    case dragging

    static func resolve(
        badgeCount: Int,
        isBadgeStatusUncertain: Bool,
        isDragging: Bool
    ) -> FloatingWidgetState {
        if isDragging { return .dragging }
        if isBadgeStatusUncertain {
            return .badgeUnavailable(lastKnownCount: badgeCount)
        }
        if badgeCount > 0 {
            return .hasNotification(count: badgeCount)
        }
        return .idle
    }

    var badgePresentation: BadgePresentation {
        switch self {
        case .hasNotification(let count):
            return .resolve(count: count, isUncertain: false)
        case .badgeUnavailable(let count):
            return .resolve(count: count, isUncertain: true)
        case .idle, .dragging:
            return .resolve(count: 0, isUncertain: false)
        }
    }

    func showsTodoCue(availableTodoCount: Int) -> Bool {
        availableTodoCount > 0 && self != .dragging
    }
}

struct TodoCuePresentation: Equatable {
    let text: String?

    static func resolve(count: Int) -> TodoCuePresentation {
        guard count > 0 else { return TodoCuePresentation(text: nil) }
        return TodoCuePresentation(text: count > 99 ? "99+" : "\(count)")
    }
}

struct CodexReplyCuePresentation: Equatable {
    let text: String?

    static func resolve(count: Int) -> Self {
        guard count > 0 else { return Self(text: nil) }
        return Self(text: count > 9 ? "9+" : "\(count)")
    }
}

// MARK: - 2. Drag state

/// Drives the `.dragging` state transition. AppDelegate flips this when the
/// floating panel detects mouse-drag movement.
final class WidgetDragState: ObservableObject {
    @Published var isDragging: Bool = false
}

final class WidgetCueHoverState: ObservableObject {
    @Published var target: WidgetPointerInteractionPolicy.TapTarget?
}

// MARK: - 3. Container — projects app data sources onto FloatingWidgetState

/// Wraps the spec-compliant `FloatingWidgetView` and computes its state from
/// the project's data sources (monitored app badge counts, available Todo, and drag).
struct FloatingWidgetContainer: View {
    @ObservedObject var appMonitor: AppMonitorService
    @ObservedObject var assistantStore: AssistantStore
    @ObservedObject var dragState: WidgetDragState
    @ObservedObject var codexCompletionService: CodexCompletionService
    @ObservedObject var cueHoverState: WidgetCueHoverState
    @AppStorage("widgetSize") private var widgetSize = "Medium"

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            FloatingWidgetView(
                state: FloatingWidgetState.resolve(
                    badgeCount: appMonitor.totalBadgeCount,
                    isBadgeStatusUncertain: appMonitor.isBadgeStatusUncertain,
                    isDragging: dragState.isDragging
                ),
                availableTodoCount: assistantStore.availableTodos(now: context.date).count,
                codexReplyCount: codexCompletionService.pendingEvents.count,
                hoveredCue: cueHoverState.target,
                widgetSize: widgetSize
            )
        }
    }
}

// MARK: - 4. Public View (spec §6)

/// Canvas size for a given visible circle size. Includes transparent padding
/// so SwiftUI's drop shadow (radius 32) doesn't clip at the frame edge.
private func widgetCanvasSize(visible: CGFloat) -> CGFloat {
    // Preserve the established canvas and hit geometry even with a quieter shadow.
    visible + 80
}

/// Visible circle diameter for a given widget size preset.
private func widgetVisibleSize(for preset: String) -> CGFloat {
    switch preset {
    case "Small":  return 40
    case "Large":  return 58
    default:       return 48   // Medium (default)
    }
}

struct FloatingWidgetView: View {
    let state: FloatingWidgetState
    var availableTodoCount = 0
    var codexReplyCount = 0
    var hoveredCue: WidgetPointerInteractionPolicy.TapTarget?
    var widgetSize: String = "Medium"

    private var visibleSize: CGFloat { widgetVisibleSize(for: widgetSize) }
    private var canvasSize: CGFloat { widgetCanvasSize(visible: visibleSize) }

    var body: some View {
        widget
            .frame(
                width: canvasSize,
                height: canvasSize,
                alignment: .center
            )
    }

    private var widget: some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(Color.narcFocusSurface)
                .frame(width: visibleSize, height: visibleSize)
                .overlay {
                    HaloInnerView(state: state, visibleSize: visibleSize)
                        .clipShape(Circle())
                }
                .overlay {
                    Circle()
                        .strokeBorder(
                            Color.narcBorder.opacity(0.25),
                            lineWidth: 0.5
                        )
                }
                .overlay(alignment: .bottomLeading) {
                    if state.showsTodoCue(availableTodoCount: availableTodoCount) {
                        TodoAvailabilityCue(count: availableTodoCount,
                                            isHovered: hoveredCue == .todo)
                            .offset(x: -6, y: 6)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if state != .dragging, codexReplyCount > 0 {
                        CodexReplyCue(count: codexReplyCount,
                                      isHovered: hoveredCue == .codexReply)
                            .offset(x: WidgetPointerInteractionPolicy.codexCueOffsetX,
                                    y: WidgetPointerInteractionPolicy.codexCueOffsetY)
                    }
                }
                .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
                .shadow(color: .black.opacity(0.09), radius: 16, y: 6)

            // Badge — sibling of the Circle, NOT inside its overlay, so the
            // capsule overflows the 48pt circle's top-right corner. Per design
            // ref, badge sits mostly OUTSIDE the circle (~70% out).
            if let text = state.badgePresentation.text {
                FloatingBadgeView(
                    text: text,
                    isUncertain: state.badgePresentation.isUncertain
                )
                    .offset(x: 6, y: -6)
                    .transition(
                        .scale(scale: 0)
                            .animation(.spring(response: 0.4, dampingFraction: 0.6))
                    )
            }
        }
        .frame(width: visibleSize, height: visibleSize)
        .scaleEffect(state == .dragging ? 1.08 : 1.0)
        .rotationEffect(.degrees(state == .dragging ? -3 : 0))
        .animation(.easeOut(duration: 0.2), value: state)
    }
}

// MARK: - 5. Reply and Todo cues

private struct CodexReplyCue: View {
    let count: Int
    let isHovered: Bool

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "bubble.left")
                .font(.system(size: 9, weight: .bold))
            Text(CodexReplyCuePresentation.resolve(count: count).text ?? "")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
            .foregroundStyle(.white)
            .frame(width: WidgetPointerInteractionPolicy.codexCueWidth,
                   height: WidgetPointerInteractionPolicy.codexCueHeight)
            .background(Capsule().fill(Color.narcAccent))
            .overlay {
                Capsule().strokeBorder(Color(NSColor.windowBackgroundColor), lineWidth: 1.5)
            }
            .scaleEffect(isHovered ? 1.14 : 1)
            .shadow(color: Color.narcAccent.opacity(isHovered ? 0.28 : 0),
                    radius: isHovered ? 6 : 0)
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .help("\(count) 个 Codex 回复，点击查看")
            .accessibilityLabel("\(count) 个 Codex 回复，点击查看")
    }
}

/// A blue, count-bearing second status axis for actionable Todo. Application
/// unread keeps exclusive ownership of the red badge in the opposite corner.
private struct TodoAvailabilityCue: View {
    let count: Int
    let isHovered: Bool

    var body: some View {
        let presentation = TodoCuePresentation.resolve(count: count)

        HStack(spacing: 3) {
            Image(systemName: "checklist")
                .font(.system(size: 8, weight: .bold))

            if let text = presentation.text {
                Text(text)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
        }
            .foregroundStyle(.white)
            .frame(width: WidgetPointerInteractionPolicy.todoCueWidth(count: count),
                   height: WidgetPointerInteractionPolicy.todoCueHeight)
            .background(Capsule().fill(Color.narcInfo))
            .overlay {
                Capsule()
                    .strokeBorder(Color(NSColor.windowBackgroundColor), lineWidth: 1.5)
            }
            .scaleEffect(isHovered ? 1.14 : 1)
            .shadow(color: Color.narcInfo.opacity(isHovered ? 0.28 : 0),
                    radius: isHovered ? 6 : 0)
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .help("有 \(count) 项可处理 Todo")
            .accessibilityLabel("有 \(count) 项可处理 Todo")
    }
}

// MARK: - 6. Halo Inner (bloom + ripple + mark)

private struct HaloInnerView: View {
    let state: FloatingWidgetState
    let visibleSize: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // State is communicated by the independent badges, not perpetual motion.
            BloomView(reduceMotion: true, active: false)

            if state != .dragging {
                FloatingMarkView(
                    reduceMotion: true,
                    visibleSize: visibleSize
                )
            }
        }
    }
}

// MARK: - 7. Bloom (center radial glow with opacity breathing)

private struct BloomView: View {
    let reduceMotion: Bool
    let active: Bool

    @State private var breathing = false

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color.narcAccent.opacity(0.45),
                        Color.narcAccent.opacity(0.14),
                        .clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: 18
                )
            )
            .blur(radius: 6)
            .frame(width: 36, height: 36)
            .opacity(reduceMotion ? 0.75 : (breathing ? 0.95 : 0.55))
            .animation(
                reduceMotion || !active
                    ? nil
                    : .easeInOut(duration: 4).repeatForever(autoreverses: true),
                value: breathing
            )
            .onAppear { if !reduceMotion { breathing.toggle() } }
    }
}

// MARK: - 8. Ripple (slow sonar pulse)

private struct RippleView: View {
    let delay: Double
    @State private var animating = false

    var body: some View {
        Circle()
            .strokeBorder(
                Color.narcAccent.opacity(animating ? 0 : 0.30),
                lineWidth: animating ? 0.4 : 1
            )
            .frame(width: 8, height: 8)
            .scaleEffect(animating ? 3.6 : 0.7)
            .animation(
                .easeOut(duration: 7)
                    .repeatForever(autoreverses: false),
                value: animating
            )
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    animating = true
                }
            }
    }
}

// MARK: - 9. Brand mark (N with subtle opacity breathing)

private struct FloatingMarkView: View {
    let reduceMotion: Bool
    let visibleSize: CGFloat
    @State private var breathing = false
    @Environment(\.colorScheme) private var scheme

    private var lowOpacity: Double { scheme == .dark ? 0.86 : 0.78 }
    private var highOpacity: Double { 1.0 }
    private var fontSize: CGFloat { visibleSize * 0.34 }

    var body: some View {
        Text("N")
            .font(.system(size: fontSize, weight: .heavy, design: .default))
            .foregroundStyle(.primary)
            // System text metrics include descender space that the capital N
            // never occupies. Lift the visible glyph by half a point so its
            // optical center matches the circle and the generated Dock mark.
            .offset(y: -0.5)
            .opacity(reduceMotion ? lowOpacity : (breathing ? highOpacity : lowOpacity))
            .animation(
                reduceMotion
                    ? nil
                    : .easeInOut(duration: 4).repeatForever(autoreverses: true),
                value: breathing
            )
            .onAppear { if !reduceMotion { breathing.toggle() } }
    }
}

// MARK: - 10. Badge (per spec §6)

private struct FloatingBadgeView: View {
    let text: String
    let isUncertain: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .default))
            .tracking(-0.1)
            .monospacedDigit()
            .foregroundStyle(.white)
            .frame(minWidth: 18, minHeight: 18)
            .padding(.horizontal, 5)
            .background(
                Capsule()
                    .fill(isUncertain ? Color.narcWarn : Color(red: 0.86, green: 0.31, blue: 0.27))
            )
            .help(isUncertain ? "未读暂不可确认，已保留上次可信结果" : "应用级未读")
            .accessibilityLabel(
                isUncertain
                    ? "未读暂不可确认，最后可信结果 \(text)"
                    : "应用级未读 \(text)"
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        Color(NSColor.windowBackgroundColor),
                        lineWidth: 2
                    )
            )
    }
}

// MARK: - Preview
//
// Note: SwiftUI's `#Preview` macro is unavailable in plain Swift Package builds
// (it requires the Xcode-bundled PreviewsMacros plugin). Re-enable when this
// file is opened from an Xcode project.
//
// #Preview("Three states") {
//     VStack(spacing: 32) {
//         FloatingWidgetView(state: .idle)
//         FloatingWidgetView(state: .hasNotification(count: 3))
//         FloatingWidgetView(state: .dragging)
//     }
//     .padding(40)
//     .background(Color.gray.opacity(0.1))
// }
