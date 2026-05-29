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
}

// MARK: - Corner Radius

enum NarcRadius {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 10
    static let lg: CGFloat = 14
    static let xl: CGFloat = 18
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
