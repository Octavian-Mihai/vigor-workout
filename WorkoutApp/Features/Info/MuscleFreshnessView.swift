import SwiftUI
import SwiftData

struct MuscleFreshnessEntry: Identifiable {
    let muscle: MuscleGroup
    let freshness: Double

    var id: String { muscle.id }
}

struct MuscleFreshnessView: View {
    @Query(sort: \WorkoutSession.startDate, order: .reverse) private var sessions: [WorkoutSession]
    @Environment(AppTheme.self) private var theme

    private var groupedMuscles: [(region: String, entries: [MuscleFreshnessEntry])] {
        let freshness = StressCalculator.allMuscleFreshness(sessions: sessions)
        let regions = ["Upper body", "Arms", "Lower body", "Trunk"]
        return regions.compactMap { region in
            let entries = MuscleGroup.allCases
                .filter { $0.region == region }
                .map { MuscleFreshnessEntry(muscle: $0, freshness: freshness[$0.rawValue] ?? 100) }
                .sorted { $0.freshness < $1.freshness }
            return entries.isEmpty ? nil : (region, entries)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Per-muscle recovery based on recent training load. Higher scores mean the muscle is more ready to train.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ForEach(groupedMuscles, id: \.region) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(group.region)
                            .font(.headline)

                        ForEach(group.entries) { entry in
                            MuscleFreshnessRow(entry: entry)
                        }
                    }
                    .padding(16)
                    .opaqueCard()
                }
            }
            .padding(16)
        }
        .background(theme.groupedBackground.ignoresSafeArea())
        .compactNavigationTitle("Muscle freshness")
    }
}

struct MuscleFreshnessRow: View {
    let entry: MuscleFreshnessEntry
    @Environment(AppTheme.self) private var theme

    private var color: Color {
        let rgb = StressCalculator.freshnessColor(for: entry.freshness)
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.muscle.rawValue)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int(entry.freshness.rounded()))%")
                    .font(.subheadline.monospacedDigit().weight(.bold))
                    .foregroundStyle(color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(theme.mutedFill)
                    Capsule()
                        .fill(color)
                        .frame(width: max(6, geo.size.width * min(max(entry.freshness / 100, 0), 1)))
                }
            }
            .frame(height: 6)
            Text(StressCalculator.freshnessLabel(for: entry.freshness))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

enum HomeMuscleFreshnessSlots {
    static let storageKey = "homeMuscleFreshnessSlots"
    static let defaultJSON = "[\"Chest\",\"Triceps\",\"Lats\",\"Traps\",\"Quadriceps\",\"Hamstrings\"]"

    static var defaultRawValues: [String] {
        [
            MuscleGroup.chest.rawValue,
            MuscleGroup.triceps.rawValue,
            MuscleGroup.lats.rawValue,
            MuscleGroup.traps.rawValue,
            MuscleGroup.quadriceps.rawValue,
            MuscleGroup.hamstrings.rawValue
        ]
    }

    static func decode(_ json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data)
        else { return defaultRawValues }
        return values
    }

    static func encode(_ slots: [String]) -> String {
        guard let data = try? JSONEncoder().encode(slots),
              let json = String(data: data, encoding: .utf8)
        else { return defaultJSON }
        return json
    }

    static func paddedPairs(_ slots: [String]) -> [String] {
        var values = slots
        if values.count % 2 != 0 {
            values.append("")
        }
        return values
    }
}

struct MuscleFreshnessCompactCard: View {
    let sessions: [WorkoutSession]
    @AppStorage(HomeMuscleFreshnessSlots.storageKey) private var slotsJSON = HomeMuscleFreshnessSlots.defaultJSON
    @State private var showEditor = false

    private var displayedEntries: [MuscleFreshnessEntry] {
        let freshness = StressCalculator.allMuscleFreshness(sessions: sessions)
        return HomeMuscleFreshnessSlots.decode(slotsJSON).compactMap { raw in
            guard !raw.isEmpty, let muscle = MuscleGroup.parse(raw) else { return nil }
            return MuscleFreshnessEntry(muscle: muscle, freshness: freshness[muscle.rawValue] ?? 100)
        }
    }

    private var rows: [(MuscleFreshnessEntry, MuscleFreshnessEntry?)] {
        let entries = displayedEntries
        return stride(from: 0, to: entries.count, by: 2).map { index in
            let left = entries[index]
            let right = index + 1 < entries.count ? entries[index + 1] : nil
            return (left, right)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                NavigationLink {
                    MuscleFreshnessView()
                } label: {
                    Text("Muscle freshness")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Button {
                    showEditor = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit muscles")

                NavigationLink {
                    MuscleFreshnessView()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Muscle freshness details")
            }

            NavigationLink {
                MuscleFreshnessView()
            } label: {
                freshnessGrid
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .opaqueCard()
        .sheet(isPresented: $showEditor) {
            MuscleFreshnessLayoutEditor(slotsJSON: $slotsJSON)
        }
    }

    @ViewBuilder
    private var freshnessGrid: some View {
        if rows.isEmpty {
            Text("Edit to choose muscles")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(spacing: 6) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, pair in
                    HStack(spacing: 12) {
                        muscleCell(pair.0)
                        if let right = pair.1 {
                            muscleCell(right)
                        } else {
                            Color.clear
                        }
                    }
                }
            }
        }
    }

    private func muscleCell(_ entry: MuscleFreshnessEntry) -> some View {
        HStack(spacing: 4) {
            Text(entry.muscle.compactName)
                .font(.caption)
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 2)
            Text("\(Int(entry.freshness.rounded()))%")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(freshnessColor(for: entry.freshness))
        }
        .frame(maxWidth: .infinity)
    }

    private func freshnessColor(for score: Double) -> Color {
        let rgb = StressCalculator.freshnessColor(for: score)
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

private struct MuscleFreshnessEditorRow: Identifiable, Equatable {
    let id: UUID
    var left: String
    var right: String

    init(left: String, right: String, id: UUID = UUID()) {
        self.id = id
        self.left = left
        self.right = right
    }
}

struct MuscleFreshnessLayoutEditor: View {
    @Binding var slotsJSON: String
    @Environment(\.dismiss) private var dismiss
    @Environment(AppTheme.self) private var theme
    @State private var rows: [MuscleFreshnessEditorRow]

    init(slotsJSON: Binding<String>) {
        _slotsJSON = slotsJSON
        let slots = HomeMuscleFreshnessSlots.paddedPairs(HomeMuscleFreshnessSlots.decode(slotsJSON.wrappedValue))
        let parsed = stride(from: 0, to: slots.count, by: 2).map { index in
            MuscleFreshnessEditorRow(
                left: slots[index],
                right: index + 1 < slots.count ? slots[index + 1] : ""
            )
        }
        _rows = State(initialValue: parsed)
    }

    private var usedMuscles: Set<String> {
        Set(rows.flatMap { [$0.left, $0.right] }.filter { !$0.isEmpty })
    }

    private var remainingMuscles: [String] {
        MuscleGroup.allCases.map(\.rawValue).filter { !usedMuscles.contains($0) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach($rows) { $row in
                    HStack(spacing: 10) {
                        slotMenu(value: $row.left)
                        slotMenu(value: $row.right)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                }
                .onMove { source, destination in
                    rows.move(fromOffsets: source, toOffset: destination)
                }
                .onDelete { offsets in
                    rows.remove(atOffsets: offsets)
                }

                Button {
                    addRow()
                } label: {
                    Label("Add row", systemImage: "plus.circle.fill")
                }
                .disabled(remainingMuscles.isEmpty)
                .listRowBackground(Color.clear)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(theme.groupedBackground)
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Edit muscles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        slotsJSON = HomeMuscleFreshnessSlots.encode(rows.flatMap { [$0.left, $0.right] })
                        dismiss()
                    }
                }
            }
        }
    }

    private func slotMenu(value: Binding<String>) -> some View {
        let current = value.wrappedValue
        return Menu {
            Button("Empty") { value.wrappedValue = "" }
            Divider()
            ForEach(MuscleGroup.allCases) { muscle in
                Button(muscle.rawValue) { value.wrappedValue = muscle.rawValue }
                    .disabled(usedMuscles.contains(muscle.rawValue) && muscle.rawValue != current)
            }
        } label: {
            HStack(spacing: 4) {
                Text(current.isEmpty ? "Empty" : current)
                    .font(.subheadline)
                    .foregroundStyle(current.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(theme.mutedFill)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .frame(maxWidth: .infinity)
    }

    private func addRow() {
        let remaining = remainingMuscles
        rows.append(
            MuscleFreshnessEditorRow(
                left: remaining.first ?? "",
                right: remaining.dropFirst().first ?? ""
            )
        )
    }
}
