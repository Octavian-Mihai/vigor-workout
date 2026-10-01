import SwiftUI
import SwiftData
import Charts

struct WorkoutTabView: View {
    @Query(sort: \WorkoutSession.startDate, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \Program.createdAt) private var programs: [Program]
    @EnvironmentObject private var sessionStore: ActiveSessionStore
    @Environment(AppTheme.self) private var theme
    @Environment(AppTourController.self) private var tour
    @AppStorage("weightUnit") private var weightUnitRaw = WeightUnit.kg.rawValue
    @State private var selectedDayID: UUID?
    @AppStorage(WorkoutPageVisibility.learnExpandedKey) private var learnExpanded = false
    @AppStorage(WorkoutPageVisibility.customExercisesExpandedKey) private var customExercisesExpanded = false
    @AppStorage(WorkoutPageVisibility.historyExpandedKey) private var historyExpanded = false

    private var accent: Color { theme.accent }
    private var unit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .kg }

    private var activeProgram: Program? {
        programs.first(where: \.isActive)
    }

    private var nextDay: ProgramDay? {
        NextWorkoutResolver.nextDay(activeProgram: activeProgram, sessions: sessions)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ProgramListView()
                            .tourTarget(.workoutPrograms)
                            .id(AppTourTargetID.workoutPrograms)

                        if let program = activeProgram, let day = selectedProgramDay(in: program) {
                            VStack(spacing: 8) {
                                programDayChooser(program: program, day: day)
                                startProgramButton(program: program, day: day)
                            }
                        }

                        Button {
                            sessionStore.start(program: nil, programDay: nil)
                        } label: {
                            Label("Start empty workout", systemImage: "plus")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered)

                        DisclosureGroup(isExpanded: $learnExpanded) {
                            LearnLinksView()
                                .padding(.top, 8)
                        } label: {
                            Text("Learn")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.primary)
                        }
                        .tint(.secondary)
                        .tourTarget(.workoutLearn)
                        .id(AppTourTargetID.workoutLearn)

                        VStack(alignment: .leading, spacing: 16) {
                            CustomExercisesSection()
                            WorkoutHistoryView(sessions: sessions, accent: accent, unit: unit)
                        }
                        .tourTarget(.workoutLibrary)
                        .id(AppTourTargetID.workoutLibrary)
                    }
                    .padding(16)
                }
                .onChange(of: tour.step) { _, step in
                    if step == .workoutLearn {
                        learnExpanded = true
                    }
                    if step == .workoutLibrary {
                        customExercisesExpanded = true
                        historyExpanded = true
                    }
                    scrollWorkoutTour(step, proxy: proxy)
                }
            }
            .background(theme.groupedBackground.ignoresSafeArea())
            .navigationTitle("Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear(perform: syncSelectedDayToResolvedNext)
            .onChange(of: activeProgram?.uuid) { _, _ in
                syncSelectedDayToResolvedNext()
            }
            .onChange(of: nextDay?.uuid) { _, _ in
                syncSelectedDayToResolvedNext()
            }
        }
    }

    private func selectedProgramDay(in program: Program) -> ProgramDay? {
        let days = program.orderedDays
        guard !days.isEmpty else { return nil }
        if let selectedDayID, let match = days.first(where: { $0.uuid == selectedDayID }) {
            return match
        }
        return nextDay ?? days[0]
    }

    private func syncSelectedDayToResolvedNext() {
        selectedDayID = nextDay?.uuid
    }

    private func stepSelectedDay(in program: Program, by delta: Int) {
        let days = program.orderedDays
        guard !days.isEmpty else { return }
        let currentID = selectedDayID ?? nextDay?.uuid
        let currentIndex = days.firstIndex(where: { $0.uuid == currentID }) ?? 0
        let newIndex = (currentIndex + delta + days.count) % days.count
        selectedDayID = days[newIndex].uuid
    }

    private func programDayChooser(program: Program, day: ProgramDay) -> some View {
        let days = program.orderedDays
        let index = days.firstIndex(where: { $0.uuid == day.uuid }) ?? 0
        return HStack(spacing: 12) {
            Button {
                stepSelectedDay(in: program, by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(minWidth: 36, minHeight: 32)
            }
            .buttonStyle(.bordered)
            .disabled(days.count < 2)
            .accessibilityLabel("Previous day")

            VStack(spacing: 2) {
                Text(dayChooserTitle(day))
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity)
                Text("\(index + 1) of \(days.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)

            Button {
                stepSelectedDay(in: program, by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .frame(minWidth: 36, minHeight: 32)
            }
            .buttonStyle(.bordered)
            .disabled(days.count < 2)
            .accessibilityLabel("Next day")
        }
        .accessibilityElement(children: .contain)
    }

    private func startProgramButton(program: Program, day: ProgramDay) -> some View {
        Button {
            sessionStore.start(program: program, programDay: day)
        } label: {
            Label("Start \(day.name)", systemImage: "play.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityHint(startHint(program: program, day: day))
    }

    private func dayChooserTitle(_ day: ProgramDay) -> String {
        let exercises = day.orderedExercises
        if let minutes = WorkoutDurationEstimate.minutes(
            exerciseCount: exercises.count,
            totalSets: exercises.reduce(0) { $0 + max($1.targetSets, 0) }
        ) {
            return "\(day.name), \(minutes) min"
        }
        return day.name
    }

    private func dayDurationLabel(_ day: ProgramDay) -> String? {
        let exercises = day.orderedExercises
        return WorkoutDurationEstimate.label(
            exerciseCount: exercises.count,
            totalSets: exercises.reduce(0) { $0 + max($1.targetSets, 0) }
        )
    }

    private func startHint(program: Program, day: ProgramDay) -> String {
        if let estimate = dayDurationLabel(day) {
            return "Starts \(program.name), \(estimate)"
        }
        return "Starts \(program.name)"
    }

    private func scrollWorkoutTour(_ step: AppTourStep, proxy: ScrollViewProxy) {
        let id: AppTourTargetID?
        switch step {
        case .workoutPrograms: id = .workoutPrograms
        case .workoutLearn: id = .workoutLearn
        case .workoutLibrary: id = .workoutLibrary
        default: id = nil
        }
        guard let id else { return }
        DispatchQueue.main.async {
            withAnimation {
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }
}

struct StrengthAnalyticsView: View {
    let sets: [SetLog]
    let accent: Color

    @Environment(AppTheme.self) private var theme
    @AppStorage("weightUnit") private var weightUnitRaw = WeightUnit.kg.rawValue
    @AppStorage(InfoPageVisibility.showVolumeChartsKey) private var showVolumeCharts = true
    @AppStorage(InfoPageVisibility.showEstimated1RMKey) private var showEstimated1RM = true
    @AppStorage(InfoPageVisibility.showTrainingLoadEvolutionKey) private var showTrainingLoadEvolution = true

    private var unit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .kg }
    private var recent: [SetEntry] { VolumeAnalytics.sets(inLastDays: 7, from: sets.map(SetEntry.init)) }
    private var muscleVolume: [(String, Double)] {
        let recorded = VolumeAnalytics.muscleVolume(from: recent)
            .map { ($0.key, $0.value) }
            .sorted { $0.1 > $1.1 }
        if recorded.isEmpty {
            return MuscleGroup.allCases.map { ($0.rawValue, 0) }
        }
        return recorded
    }
    private var muscleLoads: [(name: String, tonnageKg: Double, reps: Double)] {
        let reps = VolumeAnalytics.muscleReps(from: recent)
        return muscleVolume.map { ($0.0, $0.1, reps[$0.0] ?? 0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showTrainingLoadEvolution {
                TrainingLoadEvolutionChart(sets: sets, accent: accent)
            }
            if showVolumeCharts {
                WeeklyVolumeTrendChart(sets: sets, accent: accent)
                engagementChart
            }
            BodyWeightTrendChart(accent: accent)
            if showEstimated1RM {
                oneRMChart
            }
        }
    }

    private var oneRMChart: some View {
        let series = oneRMSeries()
        return VStack(alignment: .leading, spacing: 8) {
            Text("Estimated 1RM")
                .font(.headline)
            Text("weight × (1 + (reps + RIR) / 30)")
                .font(.caption)
                .foregroundStyle(.secondary)
            oneRMPlot(series)
        }
        .padding(16)
        .opaqueCard()
    }

    private var engagementChart: some View {
        let data = muscleVolume
        return VStack(alignment: .leading, spacing: 8) {
            Text("Volume per muscle (7d)")
                .font(.headline)
            Chart(data, id: \.0) { item in
                BarMark(
                    x: .value("Muscle", item.0),
                    y: .value("Volume", unit.fromKg(item.1))
                )
                .foregroundStyle(accent.opacity(0.85))
            }
            .chartYScale(domain: recent.isEmpty ? 0...1 : 0...max(1, unit.fromKg(data.map(\.1).max() ?? 0)))
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel(orientation: .vertical)
                }
            }
            .frame(height: 200)
        }
        .padding(16)
        .opaqueCard()
    }

    @ViewBuilder
    private func oneRMPlot(_ series: [LiftPoint]) -> some View {
        let chart = Chart(series) { point in
            LineMark(
                x: .value("Date", point.date),
                y: .value("1RM", unit.fromKg(point.value))
            )
            .foregroundStyle(by: .value("Lift", point.lift))
            PointMark(
                x: .value("Date", point.date),
                y: .value("1RM", unit.fromKg(point.value))
            )
            .foregroundStyle(by: .value("Lift", point.lift))
        }
        .frame(height: 220)

        if series.isEmpty {
            chart.chartYScale(domain: 0...1)
        } else {
            chart
        }
    }

    private func oneRMSeries() -> [LiftPoint] {
        var points: [LiftPoint] = []
        for lift in BigLift.allCases {
            let matching = sets
                .filter { lift.matches($0.exerciseName) && $0.weight > 0 && $0.reps > 0 }
                .sorted { $0.timestamp < $1.timestamp }
            var bestByDay: [Date: Double] = [:]
            let cal = Calendar.current
            for set in matching {
                let day = cal.startOfDay(for: set.timestamp)
                let est = OneRM.estimate(weight: set.weight, reps: set.reps, rir: set.rir)
                bestByDay[day] = max(bestByDay[day] ?? 0, est)
            }
            for (day, value) in bestByDay.sorted(by: { $0.key < $1.key }) {
                points.append(LiftPoint(id: "\(lift.rawValue)-\(day.timeIntervalSince1970)", lift: lift.rawValue, date: day, value: value))
            }
        }
        return points
    }
}

struct LiftPoint: Identifiable {
    let id: String
    let lift: String
    let date: Date
    let value: Double
}
