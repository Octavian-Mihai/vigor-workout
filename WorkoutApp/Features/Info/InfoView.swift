import SwiftUI
import SwiftData

enum InfoPageVisibility {
    static let showTodayStressKey = "infoShowTodayStress"
    static let showVolumeChartsKey = "infoShowVolumeCharts"
    static let showEstimated1RMKey = "infoShowEstimated1RM"
    static let showTrainingLoadEvolutionKey = "infoShowTrainingLoadEvolution"
    static let stressExpandedKey = "infoStressExpanded"
    static let analyticsExpandedKey = "infoAnalyticsExpanded"
}

enum RunningVisibility {
    static let showTabKey = "showRunningTab"
    static let showActivityKey = "showRunningActivity"
    static let olderExpandedKey = "runningOlderExpanded"
}

enum StressVisibility {
    static let showAnalysisKey = InfoPageVisibility.showTodayStressKey
    static let colorPresetKey = "stressColorPreset"
}

struct InfoView: View {
    @Query(sort: \WorkoutSession.startDate, order: .reverse) private var sessions: [WorkoutSession]
    @EnvironmentObject private var health: HealthKitService
    @Environment(AppTheme.self) private var theme
    @AppStorage(StressVisibility.showAnalysisKey) private var showStressAnalysis = true
    @AppStorage(InfoPageVisibility.showVolumeChartsKey) private var showVolumeCharts = true
    @AppStorage(InfoPageVisibility.showEstimated1RMKey) private var showEstimated1RM = true
    @AppStorage(InfoPageVisibility.showTrainingLoadEvolutionKey) private var showTrainingLoadEvolution = true
    @AppStorage(RunningVisibility.showActivityKey) private var showRunningActivity = true
    @Environment(AppTourController.self) private var tour
    @AppStorage(InfoPageVisibility.stressExpandedKey) private var stressExpanded = true
    @AppStorage(InfoPageVisibility.analyticsExpandedKey) private var analyticsExpanded = false

    private var accent: Color {
        theme.accent
    }

    private var allSets: [SetLog] {
        sessions.flatMap(\.sets)
    }

    private var stressCardio: [CardioWorkout] {
        showRunningActivity
            ? health.cardioWorkouts
            : health.cardioWorkouts.filter { $0.activityType != .running }
    }

    private var estimate: StressEstimate {
        StressCalculator.todayEstimate(
            sets: allSets,
            cardioWorkouts: stressCardio,
            restingHeartRate: health.restingHeartRate,
            maxHeartRate: health.maxHeartRate
        )
    }

    private var trend: [DailyStress] {
        StressCalculator.dailyTrend(
            sets: allSets,
            cardioWorkouts: stressCardio,
            restingHeartRate: health.restingHeartRate,
            maxHeartRate: health.maxHeartRate
        )
    }

    private var recoveryContext: String? {
        StressCalculator.recoveryContextLabel(
            hrvSDNN: health.hrvSDNN,
            sleepHours: health.lastNightSleepHours
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if showStressAnalysis {
                        DisclosureGroup(isExpanded: $stressExpanded) {
                            VStack(alignment: .leading, spacing: 16) {
                                TodayStressCard(
                                    estimate: estimate,
                                    showSplit: true,
                                    showRunSplit: showRunningActivity,
                                    trend: trend,
                                    accent: accent
                                )

                                if health.cardioWorkouts.contains(where: { $0.activityType != .running }) {
                                    Text("Cardio stress includes walking, hiking, and cycling from Apple Health.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                if let recoveryContext {
                                    Text(recoveryContext)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                compactNavLink("Muscle freshness", destination: MuscleFreshnessView())
                            }
                            .padding(.top, 8)
                        } label: {
                            Text("My stress")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.primary)
                        }
                        .tint(.secondary)
                    }

                    compactNavLink("Daily check-in", destination: CheckInInsightsView())

                    compactNavLink("Personal records", destination: PersonalRecordsView())

                    exerciseHistoryLink

                    measurementsLink

                    DisclosureGroup(isExpanded: $analyticsExpanded) {
                        StrengthAnalyticsView(sets: allSets, accent: accent)
                            .padding(.top, 8)
                    } label: {
                        Text("Analytics")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.primary)
                    }
                    .tint(.secondary)
                }
                .tourTarget(.infoAnalytics)
                .padding(16)
                .onChange(of: tour.step) { _, step in
                    if step == .infoAnalytics {
                        stressExpanded = true
                    }
                }
            }
            .background(theme.groupedBackground.ignoresSafeArea())
            .navigationTitle("Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var exerciseHistoryLink: some View {
        compactNavLink("Exercise history", destination: ExerciseHistoryBrowserView(accent: accent))
    }

    private var measurementsLink: some View {
        compactNavLink("Measurements", destination: MeasurementsView())
    }

    private func compactNavLink<D: View>(_ title: String, destination: D) -> some View {
        NavigationLink {
            destination
        } label: {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .opaqueCard()
        }
        .buttonStyle(.plain)
    }
}

struct LearnLinksView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            learnLink("Exercises list catalog", destination: ExerciseCatalogBrowserView())
            learnLink("Key muscle groups", destination: KeyMuscleGroupsView())
            learnLink("Strength patterns", destination: MoreStrengthPatternsView())
        }
    }

    private func learnLink<D: View>(_ title: String, destination: D) -> some View {
        NavigationLink {
            destination
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(16)
            .opaqueCard()
        }
        .buttonStyle(.plain)
    }
}

struct ExerciseCatalogBrowserView: View {
    @Environment(AppTheme.self) private var theme
    @State private var query = ""
    @State private var categoryFilter: ExerciseCategory?
    @State private var equipmentFilter: ExerciseEquipment?
    @State private var muscleFilter: MuscleGroup?
    @State private var previewExercise: CatalogExercise?

    private var filtered: [CatalogExercise] {
        ExerciseCatalog.displaySorted(
            ExerciseCatalog.all.filter { item in
                let matchesQuery = query.isEmpty
                    || item.name.localizedCaseInsensitiveContains(query)
                    || item.primaryNames.contains { $0.localizedCaseInsensitiveContains(query) }
                let matchesCategory = categoryFilter == nil || item.category == categoryFilter
                let matchesEquipment = equipmentFilter == nil || item.equipment == equipmentFilter
                let matchesMuscle = muscleFilter == nil
                    || item.primary.contains(muscleFilter!)
                    || item.secondary.contains(muscleFilter!)
                return matchesQuery && matchesCategory && matchesEquipment && matchesMuscle
            }
        )
    }

    private var grouped: [(ExerciseCategory, [CatalogExercise])] {
        ExerciseCategory.allCases.compactMap { category in
            let items = filtered.filter { $0.category == category }
            return items.isEmpty ? nil : (category, items)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            List {
                if filtered.isEmpty {
                    EmptyStateView(
                        systemImage: "magnifyingglass",
                        title: "No Results",
                        message: "No exercises match your search or filters."
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(grouped, id: \.0) { category, items in
                        Section(category.rawValue) {
                            ForEach(items) { item in
                                Button {
                                    previewExercise = item
                                } label: {
                                    catalogRow(item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .background(theme.groupedBackground)
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search exercises or muscles"
        )
        .compactNavigationTitle("Exercise catalog")
        .sheet(item: $previewExercise) { exercise in
            ExercisePreviewSheet(exercise: exercise)
        }
    }

    private func catalogRow(_ exercise: CatalogExercise) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(exercise.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                HStack(spacing: 8) {
                    Text(exercise.primaryNames.joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Text(exercise.equipment.shortBadge)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(theme.mutedFill)
                        .clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)

            Image(systemName: "info.circle")
                .font(.title3)
                .foregroundStyle(theme.accent)
        }
        .contentShape(Rectangle())
        .accessibilityLabel("\(exercise.name) details")
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "All", selected: categoryFilter == nil && equipmentFilter == nil && muscleFilter == nil) {
                    categoryFilter = nil
                    equipmentFilter = nil
                    muscleFilter = nil
                }

                Menu {
                    Button("All categories") { categoryFilter = nil }
                    Divider()
                    ForEach(ExerciseCategory.allCases) { cat in
                        Button(cat.rawValue) { categoryFilter = cat }
                    }
                } label: {
                    FilterChipLabel(
                        title: categoryFilter?.rawValue ?? "Category",
                        selected: categoryFilter != nil
                    )
                }

                Menu {
                    Button("All equipment") { equipmentFilter = nil }
                    Divider()
                    ForEach(ExerciseEquipment.allCases) { eq in
                        Button(eq.displayTitle) { equipmentFilter = eq }
                    }
                } label: {
                    FilterChipLabel(
                        title: equipmentFilter?.displayTitle ?? "Equipment",
                        selected: equipmentFilter != nil
                    )
                }

                Menu {
                    Button("All muscles") { muscleFilter = nil }
                    Divider()
                    ForEach(MuscleGroup.allCases.sorted { $0.rawValue < $1.rawValue }) { muscle in
                        Button(muscle.rawValue) { muscleFilter = muscle }
                    }
                } label: {
                    FilterChipLabel(
                        title: muscleFilter?.rawValue ?? "Muscle",
                        selected: muscleFilter != nil
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(theme.cardFill)
        .overlay(alignment: .bottom) { Divider() }
    }
}

struct ArticleScreen<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @Environment(AppTheme.self) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding(16)
        }
        .background(theme.groupedBackground.ignoresSafeArea())
        .compactNavigationTitle(title)
    }
}

struct ArticleCard: View {
    let title: String
    let bodyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(bodyText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .opaqueCard()
    }
}

struct RIRGuideView: View {
    var body: some View {
        ArticleScreen(title: "RIR") {
            ArticleCard(
                title: "What RIR is",
                bodyText: "RIR means reps in reserve — how many more clean reps you could have done. A set of 8 at RIR 2 means you had about two reps left. Log the set you actually did, then mark RIR honestly."
            )
            ArticleCard(
                title: "0–1 grind",
                bodyText: "Near failure. Useful for testing a top set, but these cost a lot of fatigue. Keep them scarce if you train often."
            )
            ArticleCard(
                title: "2–3 productive",
                bodyText: "Hard, useful work. Most working sets belong here: challenging enough to drive progress, with a little room left so form stays solid."
            )
            ArticleCard(
                title: "4 easy",
                bodyText: "Comfortable sets. Good for warm-ups, back-off work, or days you are managing fatigue instead of pushing."
            )
            ArticleCard(
                title: "5+ technique",
                bodyText: "Easy leftover reps. Use these for skill work, first warm-up plates, or when the load is just there to groove the pattern."
            )
            ArticleCard(
                title: "Why honest RIR matters",
                bodyText: "RIR is how the app reads how hard a set really was — not just the weight and reps. Low RIR raises fatigue and stress estimates. If you sandbag the number, trends look easier than the work you did. If you always log 0, everything looks like a grind. Match the color to how the set felt so volume, stress, and estimated 1RM stay trustworthy."
            )
        }
    }
}
