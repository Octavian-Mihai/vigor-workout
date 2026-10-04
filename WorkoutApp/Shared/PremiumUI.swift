import SwiftUI

/// Press feedback for custom-styled buttons: a small spring scale and dim while held.
/// Drop-in replacement for `.buttonStyle(.plain)` on keys, chips and cards.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    var pressedOpacity: Double = 0.85

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .opacity(configuration.isPressed ? pressedOpacity : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
}

/// Haptic that respects the "Rest-timer haptics" setting in Settings.
private struct GatedHaptic: ViewModifier {
    @AppStorage("restTimerHaptics") private var enabled = true
    let feedback: SensoryFeedback
    let trigger: Int

    func body(content: Content) -> some View {
        content.sensoryFeedback(trigger: trigger) { _, _ in
            enabled ? feedback : nil
        }
    }
}

extension View {
    /// Plays `feedback` whenever `trigger` changes, unless haptics are turned off in Settings.
    func gatedHaptic(_ feedback: SensoryFeedback, trigger: Int) -> some View {
        modifier(GatedHaptic(feedback: feedback, trigger: trigger))
    }
}

/// Standard full-screen empty state: icon, title, message and an optional action.
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
            }
        }
    }
}

/// Placeholder card rows shown while a list loads, in place of a bare spinner.
struct SkeletonCards: View {
    var count = 3
    var height: CGFloat = 72

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    var body: some View {
        VStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    Text("Placeholder workout title")
                        .font(.subheadline.weight(.semibold))
                    Text("Placeholder details line")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, minHeight: height, alignment: .leading)
                .padding(.horizontal, 14)
                .redacted(reason: .placeholder)
                .opaqueCard()
            }
        }
        .opacity(dimmed ? 0.55 : 1)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: dimmed)
        .onAppear { dimmed = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}
