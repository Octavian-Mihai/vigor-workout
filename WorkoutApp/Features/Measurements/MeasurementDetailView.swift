import SwiftUI

struct MeasurementDetailView: View {
    let entry: BodyMeasurementEntry

    @AppStorage("weightUnit") private var weightUnitRaw = WeightUnit.lb.rawValue
    @AppStorage("lengthUnit") private var lengthUnitRaw = LengthUnit.cm.rawValue

    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .lb }
    private var lengthUnit: LengthUnit { LengthUnit(rawValue: lengthUnitRaw) ?? .cm }

    var body: some View {
        List {
            if entry.photoFilename != nil {
                Section("Progress photo") {
                    ProgressPhotoThumbnail(filename: entry.photoFilename, size: 220)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
            }

            if entry.kilograms != nil || entry.caloriesKcal != nil {
                Section("Weight & intake") {
                    if let kg = entry.kilograms {
                        row("Body weight", weightUnit.format(kg))
                    }
                    if let kcal = entry.caloriesKcal {
                        row("Calorie intake", "\(kcal) kcal")
                    }
                }
            }

            if entry.heightCm != nil {
                Section("Height") {
                    if let cm = entry.heightCm {
                        row("Height", lengthUnit.format(cm))
                    }
                }
            }

            let upper = upperRows
            if !upper.isEmpty {
                Section("Upper body") {
                    ForEach(upper, id: \.0) { label, cm in
                        row(label, lengthUnit.format(cm))
                    }
                }
            }

            let arms = armRows
            if !arms.isEmpty {
                Section("Arms") {
                    ForEach(arms, id: \.0) { label, cm in
                        row(label, lengthUnit.format(cm))
                    }
                }
            }

            let core = coreRows
            if !core.isEmpty {
                Section("Core") {
                    ForEach(core, id: \.0) { label, cm in
                        row(label, lengthUnit.format(cm))
                    }
                }
            }

            let legs = legRows
            if !legs.isEmpty {
                Section("Legs") {
                    ForEach(legs, id: \.0) { label, cm in
                        row(label, lengthUnit.format(cm))
                    }
                }
            }
        }
        .compactNavigationTitle(Formatters.shortDate.string(from: entry.date))
    }

    private var upperRows: [(String, Double)] {
        var rows: [(String, Double)] = []
        if let v = entry.neckCm { rows.append(("Neck", v)) }
        if let v = entry.shouldersCm { rows.append(("Shoulders", v)) }
        if let v = entry.chestCm { rows.append(("Chest", v)) }
        return rows
    }

    private var armRows: [(String, Double)] {
        var rows: [(String, Double)] = []
        if let v = entry.leftBicepsCm { rows.append(("Left biceps", v)) }
        if let v = entry.rightBicepsCm { rows.append(("Right biceps", v)) }
        if let v = entry.leftForearmCm { rows.append(("Left forearm", v)) }
        if let v = entry.rightForearmCm { rows.append(("Right forearm", v)) }
        return rows
    }

    private var coreRows: [(String, Double)] {
        var rows: [(String, Double)] = []
        if let v = entry.waistCm { rows.append(("Waist", v)) }
        if let v = entry.hipsCm { rows.append(("Hips", v)) }
        return rows
    }

    private var legRows: [(String, Double)] {
        var rows: [(String, Double)] = []
        if let v = entry.leftThighCm { rows.append(("Left thigh", v)) }
        if let v = entry.rightThighCm { rows.append(("Right thigh", v)) }
        if let v = entry.leftCalfCm { rows.append(("Left calf", v)) }
        if let v = entry.rightCalfCm { rows.append(("Right calf", v)) }
        return rows
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

struct WeightOnlyDetailView: View {
    let entry: BodyWeightEntry

    @AppStorage("weightUnit") private var weightUnitRaw = WeightUnit.lb.rawValue
    private var unit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .lb }

    var body: some View {
        List {
            Section("Weight") {
                HStack {
                    Text("Body weight")
                    Spacer()
                    Text(unit.format(entry.kilograms))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Text("Logged from the weight log before measurements were unified.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .compactNavigationTitle(Formatters.shortDate.string(from: entry.date))
    }
}
