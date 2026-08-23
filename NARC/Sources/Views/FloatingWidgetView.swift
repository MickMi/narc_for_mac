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
/// the project's data sources (monitored app badge counts + drag).
struct FloatingWidgetContainer: View {
    @ObservedObject var appMonitor: AppMonitorService
    @ObservedObject var dragState: WidgetDragState
    @AppStorage("widgetSize") private var widgetSize = "Medium"

    var body: some View {
        FloatingWidgetView(
            state: computedState,
            widgetSize: widgetSize
        )
    }

    private var computedState: FloatingWidgetState {
        if dragState.isDragging { return .dragging }
        let badgeCount = appMonitor.totalBadgeCount
        if badgeCount > 0 {
            return .hasNotification(count: badgeCount)
        }
        return .idle
    }
}

// MARK: - 4. Public View (spec §6)

/// Canvas size for a given visible circle size. Includes transparent padding
/// so SwiftUI's drop shadow (radius 32) doesn't clip at the frame edge.
private func widgetCanvasSize(visible: CGFloat) -> CGFloat {
    // 80pt padding (40pt each side) gives radius-32 shadow room to breathe.
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
                .fill(Color(NSColor.windowBackgroundColor))
                .frame(width: visibleSize, height: visibleSize)
                .overlay {
                    HaloInnerView(state: state, visibleSize: visibleSize)
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
        .frame(width: visibleSize, height: visibleSize)
        .scaleEffect(state == .dragging ? 1.08 : 1.0)
        .rotationEffect(.degrees(state == .dragging ? -3 : 0))
        .animation(.easeOut(duration: 0.2), value: state)
    }
}

// MARK: - 5. Halo Inner (bloom + ripple + mark)

private struct HaloInnerView: View {
    let state: FloatingWidgetState
    let visibleSize: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            BloomView(reduceMotion: reduceMotion, active: state != .dragging)

            if case .hasNotification = state, !reduceMotion {
                RippleView(delay: 0)
                RippleView(delay: 3.5)
            }

            if state != .dragging {
                FloatingMarkView(
                    reduceMotion: reduceMotion,
                    visibleSize: visibleSize
                )
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
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color.narcAccent.opacity(1.0),
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

// MARK: - 7. Ripple (slow sonar pulse)

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

// MARK: - 8. Brand mark (N with subtle opacity breathing)

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
