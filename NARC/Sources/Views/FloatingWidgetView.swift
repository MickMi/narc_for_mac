import SwiftUI

/// The circular floating widget that sits on the desktop.
struct FloatingWidgetView: View {
    @ObservedObject var appMonitor: AppMonitorService
    var onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(Color.black.opacity(isHovering ? 1.0 : 0.7))
                .frame(width: 48, height: 48)
                .scaleEffect(isHovering ? 1.08 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: isHovering)

            // "N" logo
            Text("N")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            // Badge (red dot + count)
            if appMonitor.totalBadgeCount > 0 {
                BadgeView(count: appMonitor.totalBadgeCount)
                    .offset(x: 14, y: -14)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 48, height: 48)
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            onTap()
        }
    }
}

/// Red notification badge with count.
struct BadgeView: View {
    let count: Int

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.red)
                .frame(width: 20, height: 20)

            Text(count > 99 ? "99+" : "\(count)")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .minimumScaleFactor(0.5)
        }
    }
}
