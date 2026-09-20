import SwiftUI

struct AccessibilityReadyToastView: View {
    let title: String
    let message: String
    let systemImage: String
    let accentColor: Color
    let size: CGSize

    var body: some View {
        HStack(alignment: .top, spacing: NarcSpacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(accentColor)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: NarcSpacing.xs) {
                Text(title)
                    .font(.narcSubtitle)
                    .foregroundColor(.narcText)
                Text(message)
                    .font(.narcCaption)
                    .foregroundColor(.narcTextMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(NarcSpacing.lg)
        .frame(width: size.width, height: size.height, alignment: .leading)
        .background(Color.narcSurface.opacity(0.98))
        .clipShape(RoundedRectangle(cornerRadius: NarcRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: NarcRadius.lg, style: .continuous)
                .strokeBorder(Color.narcBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        .accessibilityElement(children: .combine)
    }
}
