import SwiftUI

struct RIRSelector: View {
    @Binding var rir: Int
    var accent: Color
    var compact: Bool = false
    @Environment(AppTheme.self) private var theme

    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            ForEach(0...5, id: \.self) { value in
                Button {
                    rir = value
                } label: {
                    Text(RIRPalette.display(value))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, compact ? 6 : 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(rir == value ? RIRPalette.color(for: value, accent: accent) : theme.mutedFill)
                        )
                        .foregroundStyle(rir == value ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct RIRDot: View {
    let rir: Int
    var size: CGFloat = 14

    var body: some View {
        ZStack {
            Circle()
                .fill(RIRPalette.color(for: rir, accent: .clear))
                .frame(width: size, height: size)
            Text(RIRPalette.display(rir))
                .font(.system(size: size * 0.45, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
        }
    }
}
