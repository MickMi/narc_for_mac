import SwiftUI
import AppKit

// MARK: - Color Tokens (semantic, auto light/dark)

extension Color {
    /// App base background, corresponds to --bg
    static let narcBackground = Color(NSColor.windowBackgroundColor)
    /// Card / panel surface, corresponds to --surface
    static let narcSurface = Color(NSColor.controlBackgroundColor)
    /// Secondary surface (hover / selected background), corresponds to --surface-2
    static let narcSurfaceMuted = Color(NSColor.unemphasizedSelectedContentBackgroundColor)
    /// Primary text
    static let narcText = Color(NSColor.labelColor)
    /// Secondary text (meta, descriptions)
    static let narcTextMuted = Color(NSColor.secondaryLabelColor)
    /// Tertiary text (timestamps, hints)
    static let narcTextFaint = Color(NSColor.tertiaryLabelColor)
    /// Borders (hairline)
    static let narcBorder = Color(NSColor.separatorColor)
    /// Main accent — always follows system preference
    static let narcAccent = Color.accentColor
    /// Status colors
    static let narcSuccess = Color(NSColor.systemGreen)
    static let narcWarn = Color(NSColor.systemOrange)
    static let narcDanger = Color(NSColor.systemRed)
    static let narcInfo = Color(NSColor.systemBlue)
}

// MARK: - Typography

extension Font {
    /// 28pt — splash, empty states
    static let narcDisplayXL = Font.system(size: 28, weight: .semibold)
    /// 22pt — widget logo, large icons
    static let narcDisplay = Font.system(size: 22, weight: .semibold)
    /// 17pt — panel titles
    static let narcTitle = Font.system(size: 17, weight: .semibold)
    /// 14pt — section headers, app names
    static let narcSubtitle = Font.system(size: 14, weight: .medium)
    /// 13pt — body text
    static let narcBody = Font.system(size: 13, weight: .regular)
    /// 11pt — captions, secondary info
    static let narcCaption = Font.system(size: 11, weight: .regular)
    /// 12pt monospaced — code, commands
    static let narcMono = Font.system(size: 12, weight: .regular, design: .monospaced)
    /// 11pt monospaced — keyboard shortcuts, timestamps
    static let narcMonoSmall = Font.system(size: 11, weight: .medium, design: .monospaced)
    /// 9pt monospaced — tiny keyboard hints
    static let narcMonoTiny = Font.system(size: 9, weight: .medium, design: .monospaced)
}

// MARK: - Spacing (multiples of 4)

enum NarcSpacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32
    static let xxxxl: CGFloat = 40   // v5.5 — major visual grouping
    static let xxxxxl: CGFloat = 48  // v5.5 — empty-state breathing room
}

// MARK: - Corner Radius
// v5.5 softening: bumped all radii for continuous-curvature feel.
// SwiftUI: use RoundedRectangle(cornerRadius:style: .continuous)

enum NarcRadius {
    static let xs: CGFloat = 6       // was 4  → small buttons, icons, status dots
    static let sm: CGFloat = 10      // was 8  → tab rows (core), input fields, small cards
    static let md: CGFloat = 14      // was 10 → panels, inline cards, popovers
    static let lg: CGFloat = 20      // was 14 → toasts, approval views
    static let xl: CGFloat = 24      // was 18 → main floating panel
    static let pill: CGFloat = 999
}

// MARK: - Sizes (common dimensions)

enum NarcSize {
    static let widgetDiameter: CGFloat = 48
    static let panelWidth: CGFloat = 320
    static let panelHeight: CGFloat = 420
    static let toastWidth: CGFloat = 380
    static let toastHeight: CGFloat = 56
    static let prefsWidth: CGFloat = 520
    static let prefsHeight: CGFloat = 420

    static let appIconSize: CGFloat = 32
    static let windowIconSize: CGFloat = 28
    static let badgeSize: CGFloat = 20
    static let keyBadgeSize: CGFloat = 16
    static let statusDotSmall: CGFloat = 8
    static let statusDotLarge: CGFloat = 10
}

// MARK: - Animation

extension Animation {
    /// Default snap (buttons, tab switches)
    static let narcSnap = Animation.spring(response: 0.32, dampingFraction: 0.86)
    /// Large movements (window enter/exit, panel expand)
    static let narcSoft = Animation.spring(response: 0.45, dampingFraction: 0.78)
    /// Micro-interactions (hover, focus)
    static let narcEase = Animation.easeOut(duration: 0.18)
    /// Breathing rhythm (halo pulsation)
    static let narcBreath = Animation.easeInOut(duration: 2.4).repeatForever(autoreverses: true)
}

// MARK: - NSVisualEffectView Bridge (frosted glass)

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = state
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blendingMode
        v.state = state
    }
}

// MARK: - Breathing Halo Modifier

struct BreathingHalo: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0
    let active: Bool

    func body(content: Content) -> some View {
        content
            .shadow(
                color: Color.narcAccent.opacity(active ? (0.20 + phase * 0.18) : 0),
                radius: active ? 14 : 0,
                y: 0
            )
            .onAppear {
                guard !reduceMotion, active else { return }
                withAnimation(.narcBreath) { phase = 1 }
            }
            .onChange(of: active) { _, newValue in
                phase = 0
                guard !reduceMotion, newValue else { return }
                withAnimation(.narcBreath) { phase = 1 }
            }
    }
}

extension View {
    func breathingHalo(active: Bool) -> some View {
        modifier(BreathingHalo(active: active))
    }
}

// MARK: - Soft Row Background (v5.5 softening)

/// Rounded, bordered row background for tab lists — replaces flat-colour
/// rectangles with continuous-curvature surfaces and hairline strokes that
/// only appear on hover/selection/attention states.
struct SoftRowBackground: ViewModifier {
    let isSelected: Bool
    let needsAttention: Bool
    let isHovering: Bool

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: NarcRadius.sm, style: .continuous)
                    .fill(rowFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: NarcRadius.sm, style: .continuous)
                    .strokeBorder(rowStroke, lineWidth: 0.5)
            )
    }

    private var rowFill: Color {
        if needsAttention {
            return Color.narcDanger.opacity(0.10)
        } else if isSelected {
            return Color.narcAccent.opacity(0.10)
        } else if isHovering {
            return Color.narcText.opacity(0.05)
        }
        return .clear
    }

    private var rowStroke: Color {
        if needsAttention {
            return Color.narcDanger.opacity(0.20)
        } else if isSelected {
            return Color.narcAccent.opacity(0.25)
        }
        return .clear
    }
}

extension View {
    func softRowBackground(isSelected: Bool, needsAttention: Bool, isHovering: Bool) -> some View {
        modifier(SoftRowBackground(isSelected: isSelected, needsAttention: needsAttention, isHovering: isHovering))
    }
}

// MARK: - Layered Shadow (v5.5 softening)

/// Approximates CSS multi-layer shadows via overlay + shadow.
/// SwiftUI single-shadow limit means we stack two modifiers.
struct SoftShadow: ViewModifier {
    /// xs / sm / md / lg
    let level: String

    func body(content: Content) -> some View {
        switch level {
        case "xs":
            content.shadow(color: .black.opacity(0.04), radius: 0.5, y: 0.5)
        case "sm":
            content.shadow(color: .black.opacity(0.05), radius: 1.5, y: 0.5)
                  .shadow(color: .black.opacity(0.03), radius: 2, y: 1)
        case "md":
            content.shadow(color: .black.opacity(0.05), radius: 3, y: 1)
                  .shadow(color: .black.opacity(0.04), radius: 6, y: 3)
        case "lg":
            content.shadow(color: .black.opacity(0.05), radius: 8, y: 2)
                  .shadow(color: .black.opacity(0.04), radius: 16, y: 6)
        default:
            content
        }
    }
}

extension View {
    func softShadow(_ level: String) -> some View {
        modifier(SoftShadow(level: level))
    }
}

// MARK: - Signal Logo (concentric arcs)

struct NarcSignalLogo: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var animated: Bool = true
    @State private var phase: CGFloat = 0

    var body: some View {
        Canvas { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            // Core dot
            let core = Path(ellipseIn: CGRect(
                x: center.x - 3, y: center.y - 3, width: 6, height: 6
            ))
            ctx.fill(core, with: .color(.narcAccent))
            // Three fading arcs
            for (i, radius) in [8.0, 14.0, 20.0].enumerated() {
                let opacity = (1.0 - Double(i) * 0.28) * (0.5 + Double(phase) * 0.5)
                let arcPath = Path(ellipseIn: CGRect(
                    x: center.x - radius, y: center.y - radius,
                    width: radius * 2, height: radius * 2
                ))
                ctx.stroke(
                    arcPath,
                    with: .color(.narcAccent.opacity(opacity)),
                    lineWidth: 1.2
                )
            }
        }
        .frame(width: NarcSize.widgetDiameter, height: NarcSize.widgetDiameter)
        .onAppear {
            guard !reduceMotion, animated else { return }
            withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }
}
