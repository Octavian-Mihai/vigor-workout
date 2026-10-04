import SwiftUI

/// One "you just beat your best" moment, shown while a session is running.
struct PRCelebration: Identifiable, Equatable {
    let id = UUID()
    let exerciseName: String
    let estimateKg: Double
    let previousKg: Double

    var gainKg: Double { estimateKg - previousKg }
}

/// A banner with a short burst of confetti. It never blocks touches.
struct PRCelebrationBanner: View {
    let celebration: PRCelebration
    let unit: WeightUnit
    let accent: Color

    @Environment(AppTheme.self) private var theme

    var body: some View {
        ZStack(alignment: .top) {
            ConfettiBurst(colors: [accent, .yellow, .orange, .pink, .green, .blue])
                .allowsHitTesting(false)

            HStack(spacing: 12) {
                Image(systemName: "trophy.fill")
                    .font(.title2)
                    .foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 2) {
                    Text("New PR!")
                        .font(.headline)
                    Text(celebration.exerciseName)
                        .font(.subheadline)
                        .lineLimit(1)
                    Text("Est. 1RM \(unit.format(celebration.estimateKg, decimals: 1)) · +\(unit.format(celebration.gainKg, decimals: 1))")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(accent)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                    .strokeBorder(accent.opacity(0.6), lineWidth: 1.5)
            )
            .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
            .padding(.horizontal, 16)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("New personal record, \(celebration.exerciseName), estimated one rep max \(unit.format(celebration.estimateKg, decimals: 1))")
    }
}

/// Confetti pieces that fall once and fade. Positions are random per burst.
private struct ConfettiBurst: View {
    let colors: [Color]

    private struct Piece: Identifiable {
        let id: Int
        let x: CGFloat
        let delay: Double
        let duration: Double
        let size: CGFloat
        let spin: Double
        let color: Color
        let drift: CGFloat
    }

    @State private var fallen = false
    @State private var pieces: [Piece] = []

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(pieces) { piece in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(piece.color)
                        .frame(width: piece.size, height: piece.size * 1.8)
                        .rotationEffect(.degrees(fallen ? piece.spin : 0))
                        .offset(
                            x: piece.x * geo.size.width + (fallen ? piece.drift : 0),
                            y: fallen ? 360 : -20
                        )
                        .opacity(fallen ? 0 : 1)
                        .animation(.easeIn(duration: piece.duration).delay(piece.delay), value: fallen)
                }
            }
        }
        .frame(height: 360)
        .onAppear {
            pieces = (0..<36).map { index in
                Piece(
                    id: index,
                    x: CGFloat.random(in: 0.02...0.96),
                    delay: Double.random(in: 0...0.35),
                    duration: Double.random(in: 1.3...2.0),
                    size: CGFloat.random(in: 5...9),
                    spin: Double.random(in: 180...720),
                    color: colors.randomElement() ?? .yellow,
                    drift: CGFloat.random(in: -40...40)
                )
            }
            DispatchQueue.main.async { fallen = true }
        }
    }
}
