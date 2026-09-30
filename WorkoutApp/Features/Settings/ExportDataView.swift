import SwiftUI

struct ExportDataView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var health: HealthKitService

    let programs: [Program]
    let sessions: [WorkoutSession]
    let weights: [BodyWeightEntry]
    let measurements: [BodyMeasurementEntry]

    enum Timeline: String, CaseIterable, Identifiable {
        case all = "All time"
        case days30 = "Last 30 days"
        case days90 = "Last 90 days"
        case year = "Last year"
        case custom = "Custom range"
        var id: String { rawValue }
    }

    @State private var includeWeight = true
    @State private var includeWorkouts = true
    @State private var includeCardio = true
    @State private var timeline: Timeline = .all
    @State private var customStart = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
    @State private var customEnd = Date()
    @State private var cardioReady = false

    private var nothingSelected: Bool { !includeWeight && !includeWorkouts && !includeCardio }

    private var range: ClosedRange<Date>? {
        let cal = Calendar.current
        let now = Date()
        switch timeline {
        case .all: return nil
        case .days30: return (cal.date(byAdding: .day, value: -30, to: now) ?? now)...now
        case .days90: return (cal.date(byAdding: .day, value: -90, to: now) ?? now)...now
        case .year: return (cal.date(byAdding: .year, value: -1, to: now) ?? now)...now
        case .custom:
            let start = cal.startOfDay(for: min(customStart, customEnd))
            let end = cal.date(bySettingHour: 23, minute: 59, second: 59, of: max(customStart, customEnd)) ?? customEnd
            return start...end
        }
    }

    private func inRange(_ date: Date) -> Bool {
        range?.contains(date) ?? true
    }

    private var backup: WorkoutBackupFile {
        var file = WorkoutBackupService.make(
            programs: includeWorkouts ? programs : [],
            sessions: includeWorkouts ? sessions.filter { inRange($0.startDate) } : [],
            weights: includeWeight ? weights.filter { inRange($0.date) } : [],
            measurements: includeWeight ? measurements.filter { inRange($0.date) } : []
        )
        if includeCardio {
            file.cardio = health.cardioSessions
                .filter { inRange($0.start) }
                .map { WorkoutBackupService.cardioBackup(from: $0) }
        }
        return file
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("What to export") {
                    Toggle("Weight & measurements", isOn: $includeWeight)
                    Toggle("Workouts", isOn: $includeWorkouts)
                    Toggle("Cardio", isOn: $includeCardio)
                }

                Section("Timeline") {
                    Picker("Period", selection: $timeline) {
                        ForEach(Timeline.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if timeline == .custom {
                        DatePicker("From", selection: $customStart, displayedComponents: .date)
                        DatePicker("To", selection: $customEnd, displayedComponents: .date)
                    }
                }

                Section {
                    if includeCardio && !cardioReady {
                        HStack {
                            ProgressView()
                            Text("Loading cardio history…")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ShareLink(item: backup, preview: SharePreview("Workout data")) {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                        .disabled(nothingSelected)
                    }
                }
            }
            .navigationTitle("Export data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: includeCardio) {
                guard includeCardio else { return }
                cardioReady = false
                await health.loadOlderCardioWorkouts()
                cardioReady = true
            }
        }
        .presentationDetents([.medium, .large])
    }
}
