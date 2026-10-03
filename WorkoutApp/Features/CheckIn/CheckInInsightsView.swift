import SwiftUI
import SwiftData
import Charts

private struct CheckInEditorRequest: Identifiable {
    let day: Date
    let allowsDatePicking: Bool

    var id: String { "\(day.timeIntervalSince1970)-\(allowsDatePicking)" }
}

private struct CheckInTrendPoint: Identifiable {
    let date: Date
    let outcome: CheckInOutcome
    let value: Double

    var id: String { "\(outcome.rawValue)-\(date.timeIntervalSince1970)" }
}

/// Trends from the daily check-in, and — after a couple of weeks — what seems to move them.
struct CheckInInsightsView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppTheme.self) private var theme
    @EnvironmentObject private var health: HealthKitService
    @Query(sort: \DailyCheckIn.date, order: .reverse) private var checkIns: [DailyCheckIn]
    @Query(sort: \WorkoutSession.startDate, order: .reverse) private var sessions: [WorkoutSession]
    @State private var editor: CheckInEditorRequest?

    private var today: Date { Calendar.current.startOfDay(for: Date()) }
    private var loggedEntries: [DailyCheckIn] { checkIns.filter { !$0.isEmpty } }
    private var samples: [CheckInSample] { checkIns.map(CheckInSample.init) }
    private var loggedDays: Int { CheckInInsights.loggedDayCount(samples) }
    private var todayEntry: DailyCheckIn? {
        checkIns.first { Calendar.current.isDate($0.date, inSameDayAs: today) }
    }

    private var insights: [CheckInInsight] {
        guard loggedDays >= CheckInInsights.unlockDayCount else { return [] }
        let trained = CheckInInsights.trainedDays(sessions: sessions, cardio: health.cardioWorkouts)
        let withHealth = CheckInInsights.merging(
            samples,
            hrv: health.dailyHRV,
            restingHR: health.dailyRestingHR,
            sleepHours: health.dailySleepHours
        )
        return CheckInInsights.analyze(samples: withHealth, trainedDays: trained)
    }

    private var trendPoints: [CheckInTrendPoint] {
        guard let start = Calendar.current.date(byAdding: .day, value: -29, to: today) else { return [] }
        return checkIns.filter { $0.date >= start }.flatMap { entry in
            let sample = CheckInSample(entry)
            return CheckInOutcome.ratings.compactMap { outcome in
                outcome.value(in: sample).map { CheckInTrendPoint(date: entry.date, outcome: outcome, value: $0) }
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !(todayEntry?.isComplete ?? false) {
                    logTodayButton
                }
                overviewCard
                if loggedDays >= 2 {
                    trendCard
                }
                insightsCard
                historyCard
            }
            .padding(16)
        }
        .background(theme.groupedBackground.ignoresSafeArea())
        .compactNavigationTitle("Daily check-in")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editor = CheckInEditorRequest(day: addDefaultDay, allowsDatePicking: true)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add a check-in for another day")
            }
        }
        .sheet(item: $editor) { request in
            CheckInEditorSheet(day: request.day, allowsDatePicking: request.allowsDatePicking)
                .environment(theme)
                .environmentObject(health)
                .environment(\.modelContext, context)
        }
    }

    /// Opens on the most recent day that still needs logging.
    private var addDefaultDay: Date {
        if !(todayEntry?.isComplete ?? false) { return today }
        return Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today
    }

    // MARK: - Cards

    private var logTodayButton: some View {
        Button {
            editor = CheckInEditorRequest(day: today, allowsDatePicking: false)
        } label: {
            Label("Log today's check-in", systemImage: "plus.circle.fill")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
    }

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Last 7 days")
                .font(.headline)

            HStack(alignment: .top, spacing: 12) {
                ForEach(CheckInOutcome.ratings) { outcome in
                    averageTile(outcome)
                }
            }

            let streak = CheckInInsights.currentStreak(samples, today: today)
            Text(streak >= 2
                 ? "\(loggedDays) days logged · \(streak)-day streak"
                 : "\(loggedDays) \(loggedDays == 1 ? "day" : "days") logged")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .opaqueCard()
    }

    private func averageTile(_ outcome: CheckInOutcome) -> some View {
        let average = CheckInInsights.average(outcome, in: samples, endingOn: today, days: 7)
        return VStack(alignment: .leading, spacing: 2) {
            Text(outcome.title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(average.current.map { Formatters.trimmedNumber($0, decimals: 1) } ?? "–")
                .font(.title2.weight(.bold).monospacedDigit())
            if let delta = average.delta, abs(delta) >= 0.1 {
                Label(Formatters.trimmedNumber(abs(delta), decimals: 1), systemImage: delta > 0 ? "arrow.up" : "arrow.down")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(delta > 0 ? Color.green : Color.red)
            } else {
                Text(average.previous == nil ? " " : "steady")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Last 30 days")
                .font(.headline)

            Chart(trendPoints) { point in
                LineMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Rating", point.value)
                )
                .foregroundStyle(by: .value("Metric", point.outcome.title))
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)

                PointMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Rating", point.value)
                )
                .foregroundStyle(by: .value("Metric", point.outcome.title))
                .symbolSize(16)
            }
            .chartForegroundStyleScale([
                CheckInOutcome.sleep.title: Color.indigo,
                CheckInOutcome.mood.title: Color.teal,
                CheckInOutcome.energy.title: Color.orange
            ])
            .chartYScale(domain: 1...5)
            .chartYAxis {
                AxisMarks(values: [1, 3, 5])
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .frame(height: 180)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .opaqueCard()
    }

    private var insightsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What affects how you feel")
                .font(.headline)

            if loggedDays < CheckInInsights.unlockDayCount {
                lockedContent
            } else if insights.isEmpty {
                Text("Nothing clearly stands out yet. Patterns show up when sleep, caffeine timing or training change enough from day to day — keep logging.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(insights.prefix(5)) { insight in
                    insightRow(insight)
                }
            }

            Text("These are patterns in your own log, not proof of cause.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .opaqueCard()
    }

    private var lockedContent: some View {
        let remaining = CheckInInsights.unlockDayCount - loggedDays
        return VStack(alignment: .leading, spacing: 10) {
            ProgressView(value: Double(loggedDays), total: Double(CheckInInsights.unlockDayCount))
                .tint(theme.accent)
            Text("Log \(remaining) more \(remaining == 1 ? "day" : "days") to unlock. Then your sleep, caffeine timing and workouts are compared with how you felt and with your HRV and resting heart rate from Apple Health.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func insightRow(_ insight: CheckInInsight) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(insight.headline)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(insight.formattedDifference)
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(insight.isFavourable ? Color.green : Color.red)
            }
            let barMax = insight.outcome.isRating ? 5 : max(insight.highMean, insight.lowMean) * 1.15
            comparisonBar(label: insight.highLabel, value: insight.highMean, text: insight.outcome.format(insight.highMean), max: barMax, emphasised: true)
            comparisonBar(label: insight.lowLabel, value: insight.lowMean, text: insight.outcome.format(insight.lowMean), max: barMax, emphasised: false)
            Text("\(insight.confidence == .pattern ? "Pattern" : "Early signal") · \(insight.dayCount) days · \(insight.outcome.scaleNote)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.mutedFill.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func comparisonBar(label: String, value: Double, text: String, max barMax: Double, emphasised: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(text)
                    .font(.caption.weight(.semibold).monospacedDigit())
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.mutedFill)
                    Capsule()
                        .fill(emphasised ? theme.accent : theme.accent.opacity(0.35))
                        .frame(width: max(geo.size.width * CGFloat(value / barMax), 6))
                }
            }
            .frame(height: 8)
        }
    }

    private var historyCard: some View {
        let rows = Array(loggedEntries.prefix(60))
        return VStack(alignment: .leading, spacing: 4) {
            Text("History")
                .font(.headline)
                .padding(.bottom, 6)

            if rows.isEmpty {
                Text("No check-ins yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(rows.indices, id: \.self) { index in
                    let entry = rows[index]
                    Button {
                        editor = CheckInEditorRequest(day: entry.date, allowsDatePicking: false)
                    } label: {
                        historyRow(entry)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            context.delete(entry)
                            try? context.save()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    if index < rows.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .opaqueCard()
    }

    private func historyRow(_ entry: DailyCheckIn) -> some View {
        HStack(spacing: 8) {
            Text(Formatters.shortDate.string(from: entry.date))
                .font(.subheadline)
            Spacer(minLength: 8)
            Text("S \(rating(entry.sleepRating)) · M \(rating(entry.moodRating)) · E \(rating(entry.energyRating))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func rating(_ value: Int?) -> String {
        value.map(String.init) ?? "–"
    }
}

/// Log or fix one day. With `allowsDatePicking` it can also reach back to a day that was missed.
struct CheckInEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppTheme.self) private var theme
    @EnvironmentObject private var health: HealthKitService
    @Query private var allEntries: [DailyCheckIn]

    @State private var day: Date
    let allowsDatePicking: Bool

    init(day: Date, allowsDatePicking: Bool) {
        _day = State(initialValue: Calendar.current.startOfDay(for: day))
        self.allowsDatePicking = allowsDatePicking
    }

    private var normalisedDay: Date { Calendar.current.startOfDay(for: day) }

    private var existing: DailyCheckIn? {
        allEntries.first { Calendar.current.isDate($0.date, inSameDayAs: normalisedDay) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if allowsDatePicking {
                        DatePicker("Day", selection: $day, in: ...Date(), displayedComponents: .date)
                            .datePickerStyle(.compact)
                    }

                    CheckInInputView(
                        day: normalisedDay,
                        healthSleepHours: health.lastNightSleepHours,
                        showsExtras: true
                    )
                    .id(normalisedDay)

                    if existing != nil {
                        Button(role: .destructive) {
                            if let entry = existing {
                                context.delete(entry)
                                try? context.save()
                            }
                            dismiss()
                        } label: {
                            Text("Delete this day")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(16)
            }
            .background(theme.groupedBackground.ignoresSafeArea())
            .navigationTitle(Calendar.current.isDateInToday(normalisedDay) ? "Today" : Formatters.shortDate.string(from: normalisedDay))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}
