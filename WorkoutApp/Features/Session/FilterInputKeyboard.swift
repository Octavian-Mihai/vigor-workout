import SwiftUI

struct FilterSuggestion: Identifiable {
    let id = UUID()
    let label: String
    let value: String
}

struct FilterInputKeyboard: View {
    @Binding var text: String
    let suggestions: [FilterSuggestion]
    let allowsDecimal: Bool
    let accent: Color
    var onDismiss: () -> Void

    @Environment(AppTheme.self) private var theme
    @State private var keyTick = 0

    private let rowHeight: CGFloat = 50
    private let gap: CGFloat = 6
    private let numberKeys: [[String?]] = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        [".", "0", "⌫"]
    ]

    var body: some View {
        VStack(spacing: 8) {
            if !suggestions.isEmpty {
                suggestionStrip
            }
            padGrid
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(theme.cardFill.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Divider()
        }
        .gatedHaptic(.impact(weight: .light), trigger: keyTick)
    }

    private var suggestionStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestions) { suggestion in
                    Button {
                        text = suggestion.value
                    } label: {
                        Text(suggestion.label)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(theme.mutedFill)
                            .clipShape(Capsule())
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.pressable)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var padGrid: some View {
        HStack(alignment: .top, spacing: gap) {
            VStack(spacing: gap) {
                ForEach(0..<4, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(0..<3, id: \.self) { column in
                            padCell(row: row, column: column)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: gap) {
                actionKey(
                    title: "Dismiss",
                    fill: theme.mutedFill,
                    foreground: .primary,
                    action: onDismiss
                )
                .frame(height: rowHeight * 4 + gap * 3)
            }
            .containerRelativeFrame(.horizontal, count: 4, span: 1, spacing: gap)
        }
    }

    @ViewBuilder
    private func padCell(row: Int, column: Int) -> some View {
        let token = numberKeys[row][column] ?? ""
        if row == 3 && column == 0 && !allowsDecimal {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: rowHeight)
        } else if token == "⌫" {
            Button(action: backspace) {
                Image(systemName: "delete.backward")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 34, height: 26)
                    .background(theme.mutedFill)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.pressable)
            .frame(maxWidth: .infinity)
            .frame(height: rowHeight)
        } else if token == "." {
            numberKey(".", action: appendDecimal)
        } else {
            numberKey(token) { appendDigit(token) }
        }
    }

    private func numberKey(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.title2.monospacedDigit().weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: rowHeight)
                .background(theme.mutedFill)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .foregroundStyle(.primary)
        }
        .buttonStyle(.pressable)
    }

    private func actionKey(title: String, fill: Color, foreground: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(fill)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .foregroundStyle(foreground)
        }
        .buttonStyle(.pressable)
    }

    private func appendDigit(_ digit: String) {
        keyTick += 1
        var current = text
        if current == "0" { current = digit }
        else if current.count < 8 { current += digit }
        text = current
    }

    private func appendDecimal() {
        guard allowsDecimal else { return }
        keyTick += 1
        var current = text
        if current.isEmpty { current = "0." }
        else if !current.contains(".") { current += "." }
        text = current
    }

    private func backspace() {
        keyTick += 1
        if !text.isEmpty {
            text.removeLast()
        }
    }
}
