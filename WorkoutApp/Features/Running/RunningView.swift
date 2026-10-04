import SwiftUI
import Charts
import MapKit
import CoreLocation

enum CardioSportFilter: String, CaseIterable, Equatable {
    case all = "All"
    case running = "Running"
    case cycling = "Cycling"
}

struct RunningFilters: Equatable {
    var sport: CardioSportFilter = .all
    var useMinDistance = false
    var useMaxDistance = false
    var minDistance: Double = 3
    var maxDistance: Double = 20
    var useMinDuration = false
    var useMaxDuration = false
    var minDurationMinutes: Double = 20
    var maxDurationMinutes: Double = 90
    var useMinPace = false
    var useMaxPace = false
    var minPace: Double = 4
    var maxPace: Double = 8
    var useStartDate = false
    var useEndDate = false
    var startDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    var endDate = Date()

    var isActive: Bool {
        sport != .all || useMinDistance || useMaxDistance || useMinDuration || useMaxDuration
            || useMinPace || useMaxPace || useStartDate || useEndDate
    }

    func matches(_ run: CardioWorkout, unit: DistanceUnit) -> Bool {
        switch sport {
        case .all: break
        case .running: if run.activityType != .running { return false }
        case .cycling: if run.activityType != .cycling { return false }
        }

        let distance = unit.fromMeters(run.distanceMeters)
        if useMinDistance, distance < minDistance { return false }
        if useMaxDistance, distance > maxDistance { return false }

        let minutes = run.duration / 60.0
        if useMinDuration, minutes < minDurationMinutes { return false }
        if useMaxDuration, minutes > maxDurationMinutes { return false }

        if let pace = unit.paceMinutesPerUnit(duration: run.duration, meters: run.distanceMeters) {
            if useMinPace, pace < minPace { return false }
            if useMaxPace, pace > maxPace { return false }
        } else if useMinPace || useMaxPace {
            return false
        }

        if useStartDate, run.start < Calendar.current.startOfDay(for: startDate) { return false }
        if useEndDate {
            let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: endDate)) ?? endDate
            if run.start >= end { return false }
        }
        return true
    }
}

struct RunningView: View {
    @EnvironmentObject private var health: HealthKitService
    @Environment(AppTheme.self) private var theme
    @AppStorage("distanceUnit") private var distanceUnitRaw = DistanceUnit.km.rawValue
    @AppStorage(StressVisibility.showAnalysisKey) private var showStressAnalysis = true
    @State private var filters = RunningFilters()
    @State private var showFilters = false
    @AppStorage(RunningVisibility.olderExpandedKey) private var olderExpanded = false

    private var accent: Color {
        theme.accent
    }

    private var unit: DistanceUnit {
        DistanceUnit(rawValue: distanceUnitRaw) ?? .km
    }

    private var filtered: [CardioWorkout] {
        health.cardioSessions
            .filter { filters.matches($0, unit: unit) }
            .filter { !isSlowRun($0) }
    }

    private func isSlowRun(_ workout: CardioWorkout) -> Bool {
        guard workout.activityType == .running, let pace = workout.paceMinPerKm else { return false }
        return pace > 10
    }

    private var twoWeekCutoff: Date {
        Date().addingTimeInterval(-14 * 86_400)
    }

    private var recentRuns: [CardioWorkout] {
        filtered.filter { $0.start >= twoWeekCutoff }
    }

    private var olderRuns: [CardioWorkout] {
        filtered.filter { $0.start < twoWeekCutoff }
    }

    private var needsOlderForFilters: Bool {
        filters.useStartDate && filters.startDate < twoWeekCutoff
    }

    private var shouldShowOlderFolder: Bool {
        health.olderCardioSessionCount > 0 || !olderRuns.isEmpty || health.isLoadingOlder
    }

    private var olderFolderCount: Int {
        health.olderCardioWorkouts.isEmpty ? health.olderCardioSessionCount : olderRuns.count
    }

    private var weeklyRunStress: Double {
        StressCalculator.averageRunStress(
            health.cardioSessions,
            restingHeartRate: health.restingHeartRate,
            maxHeartRate: health.maxHeartRate
        )
    }

    private func runStress(for run: CardioWorkout) -> Double {
        run.stress(restingHeartRate: health.restingHeartRate, maxHeartRate: health.maxHeartRate)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !health.isAvailable {
                        Text("Health data is not available on this device.")
                            .padding(16)
                            .opaqueCard()
                    } else if let error = health.lastError {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(error)
                                .font(.subheadline)
                            Button("Try again") {
                                Task { await health.requestAndLoad() }
                            }
                        }
                        .padding(16)
                        .opaqueCard()
                    }

                    analyticsCard
                        .tourTarget(.running)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Recent cardio sessions")
                                .font(.headline)
                            Spacer()
                            if filters.isActive {
                                Text("Filtered")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(accent)
                            }
                        }
                        if health.isLoading {
                            SkeletonCards()
                        } else if recentRuns.isEmpty && !shouldShowOlderFolder {
                            Text(health.cardioSessions.isEmpty && health.olderCardioSessionCount == 0
                                 ? "No running or cycling workouts found in Apple Health. Record one in the Fitness or Health app, then pull to refresh."
                                 : "No sessions match these filters.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(16)
                                .opaqueCard()
                        } else {
                            ForEach(recentRuns) { run in
                                NavigationLink {
                                    RunDetailView(
                                        run: run,
                                        accent: accent,
                                        unit: unit,
                                        restingHeartRate: health.restingHeartRate,
                                        maxHeartRate: health.maxHeartRate
                                    )
                                    .environmentObject(health)
                                } label: {
                                    RunRow(
                                        run: run,
                                        accent: accent,
                                        unit: unit,
                                        stressScore: runStress(for: run),
                                        showsStressAnalysis: showStressAnalysis
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                            if shouldShowOlderFolder {
                                DisclosureGroup(isExpanded: $olderExpanded) {
                                    VStack(spacing: 8) {
                                        if health.isLoadingOlder {
                                            ProgressView()
                                                .frame(maxWidth: .infinity)
                                                .padding()
                                        } else {
                                            ForEach(olderRuns) { run in
                                                NavigationLink {
                                                    RunDetailView(
                                                        run: run,
                                                        accent: accent,
                                                        unit: unit,
                                                        restingHeartRate: health.restingHeartRate,
                                                        maxHeartRate: health.maxHeartRate
                                                    )
                                                    .environmentObject(health)
                                                } label: {
                                                    RunRow(
                                                        run: run,
                                                        accent: accent,
                                                        unit: unit,
                                                        stressScore: runStress(for: run),
                                                        showsStressAnalysis: showStressAnalysis
                                                    )
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                    }
                                    .padding(.top, 8)
                                } label: {
                                    Text("Older than 2 weeks (\(olderFolderCount))")
                                }
                                .font(.subheadline.weight(.semibold))
                                .padding(14)
                                .opaqueCard()
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(theme.groupedBackground.ignoresSafeArea())
            .navigationTitle("Cardio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showFilters) {
                RunningFilterSheet(filters: $filters, unit: unit)
            }
            .onChange(of: olderExpanded) { _, expanded in
                if expanded {
                    Task { await health.loadOlderCardioWorkouts() }
                }
            }
            .onChange(of: filters) { _, _ in
                if needsOlderForFilters {
                    Task { await health.loadOlderCardioWorkouts() }
                }
            }
            .refreshable {
                await health.requestAndLoad()
            }
            .task {
                guard health.isAvailable else { return }
                if health.isAuthorized {
                    await health.loadDailyStepsIfPossible()
                } else if !health.isLoading {
                    await health.requestAndLoad()
                }
            }
            .onChange(of: health.isAuthorized) { _, authorized in
                guard authorized else { return }
                Task { await health.loadDailyStepsIfPossible() }
            }
        }
    }

    private var analyticsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text("Last 7 days")
                    .font(.headline)
                Spacer()
                Button {
                    showFilters = true
                } label: {
                    Image(systemName: filters.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(accent)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Filters")
                Button {
                    Task {
                        await health.requestAndLoad()
                        await health.loadDailyStepsIfPossible()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(accent)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(health.isLoading)
                .accessibilityLabel("Refresh")
            }
            if showStressAnalysis {
                StressMeter(title: "Cardio stress", score: weeklyRunStress, accent: accent)
            }
            stepsChart
        }
        .padding(16)
        .opaqueCard()
    }

    private var stepsChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Steps")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let today = health.dailySteps.max(by: { $0.date < $1.date }), today.count > 0 {
                    Text("Today: \(today.count.formatted())")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if health.isLoadingSteps, health.dailySteps.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
            } else if let error = health.stepsError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 120)
            } else if health.dailySteps.isEmpty {
                Text("No step data found in Apple Health for the last 7 days.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 120)
            } else {
                let steps = health.dailySteps.sorted { $0.date < $1.date }
                Chart(steps) { point in
                    BarMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Steps", point.count),
                        width: .ratio(0.75)
                    )
                    .foregroundStyle(accent)
                }
                .frame(height: 120)
                .chartXScale(range: .plotDimension(padding: 8))
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartXAxis {
                    AxisMarks(values: steps.map(\.date)) { value in
                        AxisGridLine()
                        if let date = value.as(Date.self) {
                            AxisValueLabel(weekdayLabel(for: date))
                        }
                    }
                }
            }
        }
    }

    private func weekdayLabel(for date: Date) -> String {
        date.formatted(.dateTime.weekday(.narrow))
    }
}

enum RunningFilterField: Hashable {
    case minDistance, maxDistance
    case minDuration, maxDuration
    case maxPace, minPace
    case startDate, endDate
}

struct RunningFilterSheet: View {
    @Binding var filters: RunningFilters
    let unit: DistanceUnit
    @Environment(\.dismiss) private var dismiss
    @Environment(AppTheme.self) private var theme

    @State private var focusedField: RunningFilterField?
    @State private var minDistanceText = ""
    @State private var maxDistanceText = ""
    @State private var minDurationText = ""
    @State private var maxDurationText = ""
    @State private var maxPaceText = ""
    @State private var minPaceText = ""
    @State private var startDateDaysText = ""
    @State private var endDateDaysText = ""

    private var accent: Color { theme.accent }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    filterSection("Activity") {
                        Picker("Activity", selection: $filters.sport) {
                            ForEach(CardioSportFilter.allCases, id: \.self) { sport in
                                Text(sport.rawValue).tag(sport)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    filterSection("Distance (\(unit.title))") {
                        filterField("Minimum", text: minDistanceText, field: .minDistance, placeholder: "Any")
                        filterField("Maximum", text: maxDistanceText, field: .maxDistance, placeholder: "Any")
                    }

                    filterSection("Duration (min)") {
                        filterField("Minimum", text: minDurationText, field: .minDuration, placeholder: "Any")
                        filterField("Maximum", text: maxDurationText, field: .maxDuration, placeholder: "Any")
                    }

                    filterSection("Pace (min / \(unit.title))") {
                        filterField("Faster than", text: maxPaceText, field: .maxPace, placeholder: "Any")
                        filterField("Slower than", text: minPaceText, field: .minPace, placeholder: "Any")
                    }

                    filterSection("Date") {
                        filterField("From", text: startDateDisplay, field: .startDate, placeholder: "Any")
                        filterField("To", text: endDateDisplay, field: .endDate, placeholder: "Any")
                    }

                    Button("Clear filters") {
                        filters = RunningFilters()
                        loadTextsFromFilters()
                        focusedField = nil
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .padding(16)
                .padding(.bottom, focusedField == nil ? 0 : 280)
            }
            .background(theme.groupedBackground.ignoresSafeArea())
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if let field = focusedField {
                            applyField(field)
                            focusedField = nil
                        }
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                filterKeyboard
            }
            .onAppear {
                loadTextsFromFilters()
            }
            .onDisappear {
                focusedField = nil
            }
        }
    }

    @ViewBuilder
    private var filterKeyboard: some View {
        if let field = focusedField {
            FilterInputKeyboard(
                text: activeTextBinding(for: field),
                suggestions: suggestions(for: field),
                allowsDecimal: field != .minDuration && field != .maxDuration && field != .startDate && field != .endDate,
                accent: accent,
                onDismiss: {
                    applyField(field)
                    focusedField = nil
                }
            )
        }
    }

    private func filterSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(spacing: 8) {
                content()
            }
            .padding(14)
            .opaqueCard()
        }
    }

    private func filterField(_ label: String, text: String, field: RunningFilterField, placeholder: String) -> some View {
        Button {
            prepareFieldForEditing(field)
            focusedField = field
        } label: {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer()
                Text(text.isEmpty ? placeholder : text)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(text.isEmpty ? .secondary : (focusedField == field ? accent : .primary))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(focusedField == field ? accent.opacity(0.15) : theme.mutedFill)
            )
        }
        .buttonStyle(.plain)
    }

    private var startDateDisplay: String {
        guard filters.useStartDate else { return "" }
        return Formatters.shortDate.string(from: filters.startDate)
    }

    private var endDateDisplay: String {
        guard filters.useEndDate else { return "" }
        return Formatters.shortDate.string(from: filters.endDate)
    }

    private func activeTextBinding(for field: RunningFilterField) -> Binding<String> {
        switch field {
        case .minDistance: return $minDistanceText
        case .maxDistance: return $maxDistanceText
        case .minDuration: return $minDurationText
        case .maxDuration: return $maxDurationText
        case .maxPace: return $maxPaceText
        case .minPace: return $minPaceText
        case .startDate: return $startDateDaysText
        case .endDate: return $endDateDaysText
        }
    }

    private func suggestions(for field: RunningFilterField) -> [FilterSuggestion] {
        switch field {
        case .minDistance, .maxDistance:
            let values: [(String, String)] = unit == .km
                ? [("5K", "5"), ("10K", "10"), ("Half", "21.1"), ("Marathon", "42.2")]
                : [("5K", "3.1"), ("10K", "6.2"), ("Half", "13.1"), ("Marathon", "26.2")]
            return values.map { FilterSuggestion(label: $0.0, value: $0.1) }
        case .minDuration, .maxDuration:
            return [
                FilterSuggestion(label: "30 min", value: "30"),
                FilterSuggestion(label: "45 min", value: "45"),
                FilterSuggestion(label: "1 h", value: "60"),
                FilterSuggestion(label: "90 min", value: "90")
            ]
        case .maxPace, .minPace:
            return [
                FilterSuggestion(label: "4:00", value: "4"),
                FilterSuggestion(label: "5:00", value: "5"),
                FilterSuggestion(label: "6:00", value: "6"),
                FilterSuggestion(label: "7:00", value: "7"),
                FilterSuggestion(label: "8:00", value: "8")
            ]
        case .startDate:
            return [
                FilterSuggestion(label: "Today", value: "0"),
                FilterSuggestion(label: "Week", value: "7"),
                FilterSuggestion(label: "Month", value: "30"),
                FilterSuggestion(label: "3 months", value: "90")
            ]
        case .endDate:
            return [
                FilterSuggestion(label: "Today", value: "0"),
                FilterSuggestion(label: "Yesterday", value: "1"),
                FilterSuggestion(label: "Week ago", value: "7")
            ]
        }
    }

    private func prepareFieldForEditing(_ field: RunningFilterField) {
        switch field {
        case .startDate where filters.useStartDate:
            startDateDaysText = String(daysAgo(from: filters.startDate))
        case .endDate where filters.useEndDate:
            endDateDaysText = String(daysAgo(from: filters.endDate))
        default:
            break
        }
    }

    private func daysAgo(from date: Date) -> Int {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let today = cal.startOfDay(for: Date())
        return max(cal.dateComponents([.day], from: start, to: today).day ?? 0, 0)
    }

    private func loadTextsFromFilters() {
        minDistanceText = filters.useMinDistance ? Formatters.trimmedNumber(filters.minDistance) : ""
        maxDistanceText = filters.useMaxDistance ? Formatters.trimmedNumber(filters.maxDistance) : ""
        minDurationText = filters.useMinDuration ? String(Int(filters.minDurationMinutes)) : ""
        maxDurationText = filters.useMaxDuration ? String(Int(filters.maxDurationMinutes)) : ""
        maxPaceText = filters.useMaxPace ? Formatters.trimmedNumber(filters.maxPace) : ""
        minPaceText = filters.useMinPace ? Formatters.trimmedNumber(filters.minPace) : ""
        startDateDaysText = ""
        endDateDaysText = ""
    }

    private func applyField(_ field: RunningFilterField) {
        switch field {
        case .minDistance:
            if let value = Double(minDistanceText), value > 0 {
                filters.useMinDistance = true
                filters.minDistance = value
            } else {
                filters.useMinDistance = false
                minDistanceText = ""
            }
        case .maxDistance:
            if let value = Double(maxDistanceText), value > 0 {
                filters.useMaxDistance = true
                filters.maxDistance = value
            } else {
                filters.useMaxDistance = false
                maxDistanceText = ""
            }
        case .minDuration:
            if let value = Double(minDurationText), value > 0 {
                filters.useMinDuration = true
                filters.minDurationMinutes = value
            } else {
                filters.useMinDuration = false
                minDurationText = ""
            }
        case .maxDuration:
            if let value = Double(maxDurationText), value > 0 {
                filters.useMaxDuration = true
                filters.maxDurationMinutes = value
            } else {
                filters.useMaxDuration = false
                maxDurationText = ""
            }
        case .maxPace:
            if let value = Double(maxPaceText), value > 0 {
                filters.useMaxPace = true
                filters.maxPace = value
            } else {
                filters.useMaxPace = false
                maxPaceText = ""
            }
        case .minPace:
            if let value = Double(minPaceText), value > 0 {
                filters.useMinPace = true
                filters.minPace = value
            } else {
                filters.useMinPace = false
                minPaceText = ""
            }
        case .startDate:
            if let days = Int(startDateDaysText), days >= 0 {
                filters.useStartDate = true
                filters.startDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
                startDateDaysText = ""
            } else if startDateDaysText.isEmpty {
                filters.useStartDate = false
            }
        case .endDate:
            if let days = Int(endDateDaysText), days >= 0 {
                filters.useEndDate = true
                filters.endDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
                endDateDaysText = ""
            } else if endDateDaysText.isEmpty {
                filters.useEndDate = false
            }
        }
    }
}

struct RunRow: View {
    let run: CardioWorkout
    let accent: Color
    let unit: DistanceUnit
    let stressScore: Double
    var showsStressAnalysis: Bool = true

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(run.sportLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                Text(Formatters.shortDate.string(from: run.start))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("\(Formatters.distance(run.distanceMeters, unit: unit))  ·  \(Formatters.duration(run.duration))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if let pace = unit.paceMinutesPerUnit(duration: run.duration, meters: run.distanceMeters) {
                    Text(Formatters.pace(pace, unit: unit))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.primary)
                }
                if showsStressAnalysis {
                    Text("Stress \(Int(stressScore.rounded()))")
                        .font(.caption)
                        .foregroundStyle(RIRPalette.color(for: stressScore > 75 ? 0 : (stressScore > 55 ? 2 : 4), accent: accent))
                }
            }
        }
        .padding(14)
        .opaqueCard()
    }
}

struct RunDetailView: View {
    let run: CardioWorkout
    let accent: Color
    let unit: DistanceUnit
    let restingHeartRate: Double?
    let maxHeartRate: Double

    @EnvironmentObject private var health: HealthKitService
    @Environment(AppTheme.self) private var theme
    @AppStorage(StressVisibility.showAnalysisKey) private var showStressAnalysis = true
    @State private var details: RunDetailData?
    @State private var loading = true

    private var stressScore: Double {
        run.stress(restingHeartRate: restingHeartRate, maxHeartRate: maxHeartRate)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    row("Date", Formatters.shortDate.string(from: run.start))
                    row("Distance", Formatters.distance(run.distanceMeters, unit: unit))
                    row("Time", Formatters.duration(run.duration))
                    row("Pace", unit.paceMinutesPerUnit(duration: run.duration, meters: run.distanceMeters).map { Formatters.pace($0, unit: unit) } ?? "—")
                    row("Avg HR", run.averageHeartRate.map { String(format: "%.0f bpm", $0) } ?? "Not recorded")
                    if let elevation = run.elevationGainMeters {
                        row("Elevation", String(format: "%.0f m gain", elevation))
                    }
                }
                .padding(16)
                .opaqueCard()

                routeCard
                heartRateCard
                paceCard

                if showStressAnalysis {
                    StressMeter(title: "\(run.sportLabel) stress", score: stressScore, accent: accent)
                        .padding(16)
                        .opaqueCard()

                    VStack(alignment: .leading, spacing: 8) {
                        Text(stressExplanation)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let context = StressCalculator.recoveryContextLabel(
                            hrvSDNN: health.hrvSDNN,
                            sleepHours: health.lastNightSleepHours
                        ) {
                            Text("Recovery context: \(context)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        StressLegendView(compact: true)
                    }
                    .padding(16)
                    .opaqueCard()
                }
            }
            .padding(16)
        }
        .background(theme.groupedBackground.ignoresSafeArea())
        .compactNavigationTitle(run.sportLabel)
        .task {
            loading = true
            details = await health.loadDetails(for: run)
            loading = false
        }
    }

    private var stressExplanation: String {
        if run.averageHeartRate == nil {
            return "Stress used pace versus an easy 8:00/km baseline because no heart rate was stored for this run."
        }
        var text = "Stress used personalized TRIMP (resting HR"
        if let resting = restingHeartRate {
            text += String(format: " %.0f bpm", resting)
        } else {
            text += " estimated"
        }
        text += ", max HR \(Int(maxHeartRate)) bpm)."
        if run.elevationGainMeters != nil {
            text += " Elevation gain increased the score."
        }
        return text
    }

    @ViewBuilder
    private var routeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Route")
                .font(.headline)
            if loading && details == nil {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if let coords = details?.route, coords.count >= 2 {
                RunRouteMap(locations: coords, accent: accent)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Text("No route recorded.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .opaqueCard()
    }

    @ViewBuilder
    private var heartRateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Heart rate")
                .font(.headline)
            if let series = details?.heartRate, series.count >= 2 {
                Chart(series) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("bpm", point.bpm)
                    )
                    .foregroundStyle(accent)
                }
                .frame(height: 160)
            } else if !loading {
                Text("No heart-rate samples for this run.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .opaqueCard()
    }

    @ViewBuilder
    private var paceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pace")
                .font(.headline)
            if let series = details?.pace, series.count >= 2 {
                let points: [PaceSample] = series.map { point in
                    let display = unit == .km ? point.minutesPerKm : point.minutesPerKm * 1.609344
                    return PaceSample(date: point.date, minutesPerKm: display)
                }
                Chart(points) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Pace", point.minutesPerKm)
                    )
                    .foregroundStyle(accent)
                }
                .frame(height: 160)
                .chartYScale(domain: .automatic(includesZero: false))
            } else if !loading {
                Text("No pace series for this run.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .opaqueCard()
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

struct RunRouteMap: View {
    let locations: [CLLocation]
    let accent: Color
    @State private var position: MapCameraPosition

    init(locations: [CLLocation], accent: Color) {
        self.locations = locations
        self.accent = accent
        if let region = Self.region(for: locations) {
            _position = State(initialValue: .region(region))
        } else {
            _position = State(initialValue: .automatic)
        }
    }

    private var coordinates: [CLLocationCoordinate2D] {
        locations.map(\.coordinate)
    }

    var body: some View {
        Map(position: $position) {
            MapPolyline(coordinates: coordinates)
                .stroke(accent, lineWidth: 3)
            if let start = coordinates.first {
                Marker("Start", coordinate: start)
            }
            if let end = coordinates.last {
                Marker("End", coordinate: end)
            }
        }
        .mapStyle(.standard)
    }

    private static func region(for locations: [CLLocation]) -> MKCoordinateRegion? {
        guard !locations.isEmpty else { return nil }
        let coords = locations.map(\.coordinate)
        let lats = coords.map(\.latitude)
        let lons = coords.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return nil }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.5, 0.005),
            longitudeDelta: max((maxLon - minLon) * 1.5, 0.005)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}
