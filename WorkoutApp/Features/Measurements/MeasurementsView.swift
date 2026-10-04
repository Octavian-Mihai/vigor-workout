import SwiftUI
import SwiftData

enum MeasurementTimelineItem: Identifiable {
    case measurement(BodyMeasurementEntry)
    case weightOnly(BodyWeightEntry)

    var id: String {
        switch self {
        case .measurement(let entry): return "m-\(entry.persistentModelID.hashValue)"
        case .weightOnly(let entry): return "w-\(entry.persistentModelID.hashValue)"
        }
    }

    var date: Date {
        switch self {
        case .measurement(let entry): return entry.date
        case .weightOnly(let entry): return entry.date
        }
    }
}

struct MeasurementsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var health: HealthKitService
    @Query(sort: \BodyMeasurementEntry.date, order: .reverse) private var measurements: [BodyMeasurementEntry]
    @Query(sort: \BodyWeightEntry.date, order: .reverse) private var weightEntries: [BodyWeightEntry]
    @AppStorage("weightUnit") private var weightUnitRaw = WeightUnit.lb.rawValue
    @State private var showAdd = false

    private var unit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .lb }

    private var timeline: [MeasurementTimelineItem] {
        let calendar = Calendar.current
        let measurementDaysWithWeight = Set(
            measurements.compactMap { entry -> Date? in
                guard entry.kilograms != nil else { return nil }
                return calendar.startOfDay(for: entry.date)
            }
        )
        var items: [MeasurementTimelineItem] = measurements.map { .measurement($0) }
        for weight in weightEntries {
            let day = calendar.startOfDay(for: weight.date)
            let covered = measurementDaysWithWeight.contains(day)
                || measurements.contains { entry in
                    calendar.isDate(entry.date, inSameDayAs: weight.date)
                        && entry.kilograms != nil
                        && abs((entry.kilograms ?? 0) - weight.kilograms) < 0.05
                }
            if !covered {
                items.append(.weightOnly(weight))
            }
        }
        return items.sorted { $0.date > $1.date }
    }

    private var latest: MeasurementTimelineItem? {
        timeline.first
    }

    var body: some View {
        List {
            if let latest {
                Section("Latest") {
                    latestCard(latest)
                }
            }

            Section("History") {
                if timeline.isEmpty {
                    EmptyStateView(
                        systemImage: "figure.arms.open",
                        title: "No Entries Yet",
                        message: "Log progress photos, body weight, calories, or circumferences.",
                        actionTitle: "Add Measurement",
                        action: { showAdd = true }
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(timeline) { item in
                        NavigationLink {
                            destination(for: item)
                        } label: {
                            historyRow(item)
                        }
                    }
                    .onDelete(perform: deleteItems)
                }
            }
        }
        .navigationTitle("Measurements")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAdd = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            NavigationStack {
                AddMeasurementView { entry in
                    saveMeasurement(entry)
                }
            }
        }
        .task {
            await mergeHealthKitWeights()
        }
    }

    @ViewBuilder
    private func destination(for item: MeasurementTimelineItem) -> some View {
        switch item {
        case .measurement(let entry):
            MeasurementDetailView(entry: entry)
        case .weightOnly(let entry):
            WeightOnlyDetailView(entry: entry)
        }
    }

    @ViewBuilder
    private func latestCard(_ item: MeasurementTimelineItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                switch item {
                case .measurement(let entry):
                    ProgressPhotoThumbnail(filename: entry.photoFilename, size: 72)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Formatters.shortDate.string(from: entry.date))
                            .font(.headline)
                        Text(summary(for: entry))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                case .weightOnly(let entry):
                    ProgressPhotoThumbnail(filename: nil, size: 72)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Formatters.shortDate.string(from: entry.date))
                            .font(.headline)
                        Text(unit.format(entry.kilograms))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 4)
    }

    private func historyRow(_ item: MeasurementTimelineItem) -> some View {
        HStack(spacing: 12) {
            switch item {
            case .measurement(let entry):
                ProgressPhotoThumbnail(filename: entry.photoFilename, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Formatters.shortDate.string(from: entry.date))
                    Text(summary(for: entry))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            case .weightOnly(let entry):
                ProgressPhotoThumbnail(filename: nil, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Formatters.shortDate.string(from: entry.date))
                    Text(unit.format(entry.kilograms))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func summary(for entry: BodyMeasurementEntry) -> String {
        var parts: [String] = []
        if let kg = entry.kilograms {
            parts.append(unit.format(kg))
        }
        if entry.photoFilename != nil {
            parts.append("Photo")
        }
        if entry.caloriesKcal != nil {
            parts.append("Calories")
        }
        let circumferenceCount = [
            entry.heightCm, entry.neckCm, entry.shouldersCm, entry.chestCm,
            entry.leftBicepsCm, entry.rightBicepsCm, entry.leftForearmCm, entry.rightForearmCm,
            entry.waistCm, entry.hipsCm, entry.leftThighCm, entry.rightThighCm,
            entry.leftCalfCm, entry.rightCalfCm
        ].compactMap { $0 }.count
        if circumferenceCount > 0 {
            parts.append("\(circumferenceCount) measures")
        }
        return parts.isEmpty ? "Measurement" : parts.joined(separator: " · ")
    }

    private func saveMeasurement(_ entry: BodyMeasurementEntry) {
        let isNew = !measurements.contains { $0.persistentModelID == entry.persistentModelID }
        if isNew {
            modelContext.insert(entry)
        }
        try? modelContext.save()

        if let kg = entry.kilograms {
            syncBodyWeight(kilograms: kg, date: entry.date)
            Task { await health.saveBodyMass(kilograms: kg, date: entry.date) }
        }
    }

    private func syncBodyWeight(kilograms: Double, date: Date) {
        let calendar = Calendar.current
        if let existing = weightEntries.first(where: { calendar.isDate($0.date, inSameDayAs: date) }) {
            existing.kilograms = kilograms
            existing.date = date
        } else {
            modelContext.insert(BodyWeightEntry(date: date, kilograms: kilograms))
        }
        try? modelContext.save()
    }

    private func deleteItems(at offsets: IndexSet) {
        for index in offsets {
            let item = timeline[index]
            switch item {
            case .measurement(let entry):
                ProgressPhotoStorage.delete(filename: entry.photoFilename)
                modelContext.delete(entry)
            case .weightOnly(let entry):
                modelContext.delete(entry)
            }
        }
        try? modelContext.save()
    }

    private func mergeHealthKitWeights() async {
        do {
            let samples = try await health.fetchBodyMass()
            let calendar = Calendar.current
            var added = false
            for sample in samples {
                let exists = weightEntries.contains { entry in
                    calendar.isDate(entry.date, inSameDayAs: sample.date)
                        && abs(entry.kilograms - sample.kilograms) < 0.05
                }
                if !exists {
                    modelContext.insert(BodyWeightEntry(date: sample.date, kilograms: sample.kilograms))
                    added = true
                }
            }
            if added {
                try modelContext.save()
            }
        } catch {
            health.lastError = error.localizedDescription
        }
    }
}
