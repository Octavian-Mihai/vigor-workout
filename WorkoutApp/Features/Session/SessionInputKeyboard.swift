import SwiftUI

struct SessionInputKeyboard: View {
    enum Mode {
        case weight
        case reps
    }

    let mode: Mode
    let focusIdentity: SessionField
    let accent: Color
    let unit: WeightUnit
    let equipment: ExerciseEquipment
    @Binding var weightText: String
    @Binding var repsText: String
    @Binding var rir: Int
    var completeTitle: String = "Complete Set"
    var barWeight: Double = 0
    var onAdjustBarWeight: ((Double) -> Void)?
    var onDismiss: () -> Void
    var onNext: () -> Void
    var onCompleteSet: () -> Void

    @Environment(AppTheme.self) private var theme
    @State private var replacePending = true
    @State private var showRIRGuide = false
    @State private var keyTick = 0

    @AppStorage(EquipmentSettings.barbellBarKgKey) private var barbellBarKg = EquipmentSettings.defaultBarKg
    @AppStorage(EquipmentSettings.barbellBarLbKey) private var barbellBarLb = EquipmentSettings.defaultBarLb

    private let rowHeight: CGFloat = 50
    private let gap: CGFloat = 6
    private let numberKeys: [[String?]] = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        [".", "0", "⌫"]
    ]

    private var showsPlates: Bool {
        mode == .weight && equipment.showsPlateCalculator
    }

    private var baseWeight: Double {
        if equipment == .barbell, onAdjustBarWeight != nil {
            return barWeight
        }
        return EquipmentSettings.plateBaseWeight(
            for: equipment,
            unit: unit,
            barKg: barbellBarKg,
            barLb: barbellBarLb
        )
    }

    private var barStep: Double {
        EquipmentSettings.barStep(for: unit)
    }

    private var breakdown: PlateBreakdown? {
        guard showsPlates else { return nil }
        let total = Double(weightText) ?? 0
        return PlateCalculator.calculate(
            total: total,
            base: baseWeight,
            unit: unit,
            equipment: equipment
        )
    }

    var body: some View {
        VStack(spacing: 8) {
            if showsPlates, let breakdown {
                plateStrip(breakdown)
            }
            if mode == .reps {
                HStack(alignment: .center, spacing: 6) {
                    Button {
                        showRIRGuide = true
                    } label: {
                        Text("RIR")
                            .font(.caption.weight(.semibold))
                            .frame(width: 36)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(theme.mutedFill)
                            )
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("About RIR")

                    RIRSelector(rir: $rir, accent: accent, compact: true)
                }
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
        .onChange(of: focusIdentity) { _, _ in
            replacePending = true
        }
        .onAppear {
            replacePending = true
        }
        .sheet(isPresented: $showRIRGuide) {
            NavigationStack {
                RIRGuideView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showRIRGuide = false }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
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
                    title: "Dismiss Keyboard",
                    fill: theme.mutedFill,
                    foreground: .primary,
                    action: onDismiss
                )
                .frame(height: rowHeight * 2 + gap)

                if mode == .weight {
                    actionKey(
                        title: "Next",
                        fill: accent,
                        foreground: .white,
                        action: onNext
                    )
                    .frame(height: rowHeight * 2 + gap)
                } else {
                    actionKey(
                        title: completeTitle,
                        fill: accent,
                        foreground: .white,
                        ticks: false,
                        action: onCompleteSet
                    )
                    .frame(height: rowHeight * 2 + gap)
                }
            }
            .containerRelativeFrame(.horizontal, count: 4, span: 1, spacing: gap)
        }
    }

    @ViewBuilder
    private func padCell(row: Int, column: Int) -> some View {
        let token = numberKeys[row][column] ?? ""
        if row == 3 && column == 0 && mode == .reps {
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

    private func actionKey(title: String, fill: Color, foreground: Color, ticks: Bool = true, action: @escaping () -> Void) -> some View {
        Button {
            if ticks { keyTick += 1 }
            action()
        } label: {
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

    private func plateStrip(_ breakdown: PlateBreakdown) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(plateHeadline(breakdown))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if breakdown.remainder > 0.001, !breakdown.isBelowBase {
                    Text("rem \(Formatters.trimmedNumber(breakdown.remainder)) \(unit.rawValue)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if equipment == .barbell, let onAdjustBarWeight {
                HStack(spacing: 6) {
                    Button {
                        keyTick += 1
                        onAdjustBarWeight(-barStep)
                    } label: {
                        Image(systemName: "minus")
                            .font(.caption.weight(.bold))
                            .frame(width: 24, height: 24)
                            .background(theme.mutedFill)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.pressable)
                    Text("Bar \(Formatters.trimmedNumber(baseWeight))")
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                    Button {
                        keyTick += 1
                        onAdjustBarWeight(barStep)
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption.weight(.bold))
                            .frame(width: 24, height: 24)
                            .background(theme.mutedFill)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.pressable)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    private func plateHeadline(_ breakdown: PlateBreakdown) -> String {
        if breakdown.isBelowBase {
            return "Below bar"
        }
        if breakdown.perSide < 0.001 {
            if breakdown.base > 0.001 {
                return "Bar only"
            }
            return breakdown.total < 0.001 ? "Enter weight" : "—"
        }
        let plates = breakdown.compactPlates
        if plates.isEmpty || plates == "—" {
            return "Per side rem \(Formatters.trimmedNumber(breakdown.remainder))"
        }
        return "Per side \(plates)"
    }

    private func appendDigit(_ digit: String) {
        keyTick += 1
        if consumeReplacePending() {
            if mode == .weight {
                weightText = digit
            } else {
                repsText = digit
            }
            return
        }
        if mode == .weight {
            var text = weightText
            if text == "0" { text = digit }
            else if text.count < 7 { text += digit }
            weightText = text
        } else {
            var text = repsText
            if text == "0" { text = digit }
            else if text.count < 3 { text += digit }
            repsText = text
        }
    }

    private func appendDecimal() {
        guard mode == .weight else { return }
        keyTick += 1
        if consumeReplacePending() {
            weightText = "0."
            return
        }
        var text = weightText
        if text.isEmpty { text = "0." }
        else if !text.contains(".") { text += "." }
        weightText = text
    }

    private func backspace() {
        keyTick += 1
        replacePending = false
        if mode == .weight {
            if !weightText.isEmpty {
                weightText.removeLast()
            }
        } else if !repsText.isEmpty {
            repsText.removeLast()
        }
    }

    private func consumeReplacePending() -> Bool {
        guard replacePending else { return false }
        replacePending = false
        return true
    }
}
