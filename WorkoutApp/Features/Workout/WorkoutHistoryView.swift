import SwiftUI
import SwiftData

struct WorkoutHistoryView: View {
    let sessions: [WorkoutSession]
    let accent: Color
    let unit: WeightUnit

    @Environment(AppTheme.self) private var theme
    @Environment(\.modelContext) private var modelContext
    @AppStorage(WorkoutPageVisibility.historyExpandedKey) private var isExpanded = false
    @AppStorage(WorkoutPageVisibility.historyOlderExpandedKey) private var olderExpanded = false
    @State private var pendingDeleteSession: WorkoutSession?

    private var finished: [WorkoutSession] {
        sessions.filter { $0.endDate != nil }
    }

    private var twoWeekCutoff: Date {
        Date().addingTimeInterval(-14 * 86_400)
    }

    private var recentSessions: [WorkoutSession] {
        finished.filter { $0.startDate >= twoWeekCutoff }
    }

    private var olderSessions: [WorkoutSession] {
        finished.filter { $0.startDate < twoWeekCutoff }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                if finished.isEmpty {
                    Text("No completed workouts yet. Finish a session to see it here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(16)
                        .opaqueCard()
                } else {
                    sessionList(recentSessions)

                    if !olderSessions.isEmpty {
                        DisclosureGroup(isExpanded: $olderExpanded) {
                            sessionList(olderSessions)
                                .padding(.top, 8)
                        } label: {
                            Text("Older than 2 weeks (\(olderSessions.count))")
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(14)
                        .opaqueCard()
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            Text("History")
                .font(.headline)
                .foregroundStyle(.primary)
        }
        .tint(.secondary)
        .onAppear {
            if finished.isEmpty,
               UserDefaults.standard.object(forKey: WorkoutPageVisibility.historyExpandedKey) == nil {
                isExpanded = true
            }
        }
        .alert("Delete workout?", isPresented: Binding(
            get: { pendingDeleteSession != nil },
            set: { if !$0 { pendingDeleteSession = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let session = pendingDeleteSession {
                    deleteSession(session)
                    pendingDeleteSession = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteSession = nil
            }
        } message: {
            Text("This workout and all logged sets will be permanently removed.")
        }
    }

    @ViewBuilder
    private func sessionList(_ sessions: [WorkoutSession]) -> some View {
        List {
            ForEach(sessions) { session in
                NavigationLink {
                    WorkoutSessionDetailView(session: session, accent: accent, unit: unit)
                } label: {
                    WorkoutSessionRow(session: session, accent: accent, unit: unit)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        pendingDeleteSession = session
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDisabled(true)
        .frame(height: CGFloat(sessions.count) * 72)
    }

    private func deleteSession(_ session: WorkoutSession) {
        modelContext.delete(session)
        try? modelContext.save()
    }
}

struct WorkoutSessionRow: View {
    let session: WorkoutSession
    let accent: Color
    let unit: WeightUnit

    private var setCount: Int { session.orderedSets.count }

    private var totalVolumeKg: Double {
        StressCalculator.totalVolume(from: session.orderedSets)
    }

    private var dayName: String {
        session.programDayName ?? "Workout"
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(dayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(Formatters.shortDate.string(from: session.startDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(Formatters.workoutDuration(session.durationSeconds))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.primary)
                Text("\(setCount) sets · \(Formatters.compactNumber(unit.fromKg(totalVolumeKg))) \(unit.rawValue)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .opaqueCard()
    }
}

struct WorkoutSessionDetailView: View {
    let session: WorkoutSession
    let accent: Color
    let unit: WeightUnit

    @Environment(AppTheme.self) private var theme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sessionStore: ActiveSessionStore
    @State private var showDeleteConfirm = false

    private var model: WorkoutSummaryModel {
        WorkoutSummaryModel(session: session)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    row("Day", model.dayName)
                    row("Date", Formatters.shortDate.string(from: model.date))
                    row("Duration", Formatters.workoutDuration(model.durationSeconds))
                    row("Sets", "\(model.totalSets)")
                    row(
                        "Volume",
                        "\(Formatters.compactNumber(unit.fromKg(model.totalVolumeKg))) \(unit.rawValue)·reps"
                    )
                    row("Exercises", "\(model.exerciseCount)")
                }
                .padding(16)
                .opaqueCard()

                if !model.displayedExercises.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Exercises")
                            .font(.headline)
                        ForEach(model.displayedExercises) { exercise in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(exercise.name)
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text("\(exercise.setCount) sets")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text("Top \(unit.format(exercise.topSetWeightKg)) × \(exercise.topSetReps)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(accent)
                                ForEach(exercise.sets) { set in
                                    HStack(spacing: 8) {
                                        Text("\(set.id + 1)")
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                            .frame(width: 16, alignment: .trailing)
                                        Text("\(unit.format(set.weightKg)) × \(set.reps)")
                                            .font(.caption.monospacedDigit())
                                        Text("RIR \(RIRPalette.display(set.rir))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                            if exercise.id != model.displayedExercises.last?.id {
                                Divider()
                            }
                        }
                        if model.hiddenExerciseCount > 0 {
                            Text("+ \(model.hiddenExerciseCount) more exercise\(model.hiddenExerciseCount == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(16)
                    .opaqueCard()
                }
            }
            .padding(16)
        }
        .background(theme.groupedBackground.ignoresSafeArea())
        .navigationTitle("Session")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Repeat workout") {
                    sessionStore.start(from: session)
                }
            }
            ToolbarItem(placement: .destructiveAction) {
                Button("Delete", role: .destructive) {
                    showDeleteConfirm = true
                }
            }
        }
        .alert("Delete workout?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                modelContext.delete(session)
                try? modelContext.save()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This workout and all logged sets will be permanently removed.")
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
        .font(.subheadline)
    }
}
