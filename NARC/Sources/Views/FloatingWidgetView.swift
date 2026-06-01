import SwiftUI

// MARK: - 1. State

/// Public state contract per spec §2 / §6.
enum FloatingWidgetState: Equatable {
    case idle
    case hasNotification(count: Int)
    case dragging
}

// MARK: - 2. Drag state

/// Drives the `.dragging` state transition. AppDelegate flips this when the
/// floating panel detects mouse-drag movement.
final class WidgetDragState: ObservableObject {
    @Published var isDragging: Bool = false
}

// MARK: - 3. Container — projects app data sources onto FloatingWidgetState

/// Wraps the spec-compliant `FloatingWidgetView` and computes its state from
/// the project's data sources (IM badge counts + Claude pending events + drag).
struct FloatingWidgetContainer: View {
    @ObservedObject var appMonitor: AppMonitorService
    @ObservedObject var claudeService: ClaudeSessionService
    @ObservedObject var dragState: WidgetDragState

    var body: some View {
        FloatingWidgetView(state: computedState)
    }

    private var computedState: FloatingWidgetState {
        if dragState.isDragging { return .dragging }
        let imCount = appMonitor.totalBadgeCount
        // Only count *external* Claude events (running outside the workspace,
        // typically in iTerm / Terminal.app). Workspace-internal events surface
        // via the Dashboard sidebar's own attention machinery — putting them
        // in the floating-widget badge would double-count and route the user
        // to the wrong place when they tap.
        let externalClaudeCount = claudeService.pendingApprovals.filter { $0.narcSessionId == nil }.count
            + claudeService.notifications.filter { $0.narcSessionId == nil }.count
        let total = imCount + externalClaudeCount
        if total > 0 {
            return .hasNotification(count: total)
        }
        return .idle
    }
}

// MARK: - 4. Public View (spec §6)

/// Total canvas size including transparent shadow padding.
///
/// SwiftUI's `.shadow(radius: 32, y: 12)` is rendered into the host's backing
/// layer. When the host (`NSHostingView`) is sized exactly to the visible
/// widget (48×48), the layer clips the shadow at the frame boundary, leaving
/// a hard rectangular halo right at the edge of the circle — the exact bug
/// the user kept reporting as "圆角方块/方框". Giving the canvas a 40pt
/// transparent margin on each side lets the shadow render fully and the
/// rounded "cushion" effect from the spec actually shows up.
let floatingWidgetCanvasSize: CGFloat = 128
let floatingWidgetVisibleSize: CGFloat = 48

struct FloatingWidgetView: View {
    let state: FloatingWidgetState

    var body: some View {
        widget
            // Outer canvas — only used to give the inner shadow breathing room.
            // The widget itself stays 48pt; the surrounding 40pt is fully
            // transparent and click-through (see FloatingWidgetWindow.hitTest).
            .frame(
                width: floatingWidgetCanvasSize,
                height: floatingWidgetCanvasSize,
                alignment: .center
            )
    }

    private var widget: some View {
        ZStack(alignment: .topTrailing) {
            // Root is a real Circle view filled with .regularMaterial — this
            // guarantees there is no square chrome anywhere. (Spec §6 used
            // `.background(.regularMaterial, in: Circle())` on a generic ZStack
            // which on some macOS versions leaks the material outside the
            // intended Circle bounds, producing a rounded-rect halo around the
            // widget. A real Circle as the root avoids that entirely.)
            Circle()
                .fill(.regularMaterial)
                .frame(width: floatingWidgetVisibleSize, height: floatingWidgetVisibleSize)
                .overlay {
                    HaloInnerView(state: state)
                        .clipShape(Circle())
                }
                .overlay {
                    Circle()
                        .strokeBorder(
                            Color(NSColor.separatorColor).opacity(0.6),
                            lineWidth: 1
                        )
                }
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                .shadow(color: .black.opacity(0.12), radius: 32, y: 12)

            // Badge — sibling of the Circle, NOT inside its overlay, so the
            // capsule overflows the 48pt circle's top-right corner. Per design
            // ref, badge sits mostly OUTSIDE the circle (~70% out).
            if case .hasNotification(let count) = state {
                FloatingBadgeView(count: count)
                    .offset(x: 6, y: -6)
                    .transition(
                        .scale(scale: 0)
                            .animation(.spring(response: 0.4, dampingFraction: 0.6))
                    )
            }
        }
        .frame(width: floatingWidgetVisibleSize, height: floatingWidgetVisibleSize)
        .scaleEffect(state == .dragging ? 1.08 : 1.0)
        .rotationEffect(.degrees(state == .dragging ? -3 : 0))
        .shadow(
            color: .black.opacity(state == .dragging ? 0.18 : 0),
            radius: state == .dragging ? 28 : 0,
            y: state == .dragging ? 12 : 0
        )
        .animation(.easeOut(duration: 0.2), value: state)
    }
}

// MARK: - 5. Halo Inner (bloom + ripple + wordmark)

private struct HaloInnerView: View {
    let state: FloatingWidgetState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            BloomView(reduceMotion: reduceMotion, active: state != .dragging)

            if case .hasNotification = state, !reduceMotion {
                RippleView(delay: 0)
                RippleView(delay: 3.5)
            }

            if state != .dragging {
                WordmarkView(reduceMotion: reduceMotion)
            }
        }
    }
}

// MARK: - 6. Bloom (center radial glow with opacity breathing)

private struct BloomView: View {
    let reduceMotion: Bool
    let active: Bool

    @State private var breathing = false

    var body: some View {
        // 36×36 inset 6pt from 48pt frame
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color.accentColor.opacity(1.0),
                        Color.accentColor.opacity(0.14),
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

// MARK: - 7. Ripple (slow sonar pulse)

private struct RippleView: View {
    let delay: Double
    @State private var animating = false

    var body: some View {
        // Period: 7s. Start at scale 0.7 / opacity 0 → 3.6 / 0.
        // At 20% mark opacity peaks at 0.30, at 60% it's 0.10, then fades to 0.
        // SwiftUI can't easily express keyframe opacity stops pre-iOS 17,
        // so we approximate with a single 7s ease-out arc.
        Circle()
            .strokeBorder(
                Color.accentColor.opacity(animating ? 0 : 0.30),
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

// MARK: - 8. Wordmark (NARC with subtle opacity breathing)

private struct WordmarkView: View {
    let reduceMotion: Bool
    @State private var breathing = false
    @Environment(\.colorScheme) private var scheme

    private var lowOpacity: Double { scheme == .dark ? 0.86 : 0.78 }
    private var highOpacity: Double { 1.0 }

    var body: some View {
        Text("NARC")
            .font(.system(size: 7.5, weight: .semibold, design: .default))
            .tracking(-0.3)                       // letter-spacing -0.04em ≈ -0.3pt at 7.5pt
            .foregroundStyle(.primary)
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

// MARK: - 9. Badge (per spec §6)

private struct FloatingBadgeView: View {
    let count: Int

    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.system(size: 11, weight: .semibold, design: .default))
            .tracking(-0.1)
            .monospacedDigit()
            .foregroundStyle(.white)
            .frame(minWidth: 18, minHeight: 18)
            .padding(.horizontal, 5)
            .background(
                Capsule()
                    .fill(Color(red: 0.86, green: 0.31, blue: 0.27))
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
