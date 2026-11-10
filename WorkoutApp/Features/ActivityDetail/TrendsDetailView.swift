import SwiftUI
import SwiftData
import Charts

struct TrendsDetailView: View {
    @Query(sort: \WorkoutSession.startDate, order: .reverse) private var sessions: [WorkoutSession]
    @EnvironmentObject private var health: HealthKitService
    @Environment(AppTheme.self) private var theme
    @AppStorage(RunningVisibility.showActivityKey) private var showRunningActivity = true

    private var accent: Color {
        theme.accent
    }

    private var finished: [WorkoutSession] {
        sessions.filter { $0.endDate != nil }
    }

    private var weekdayCounts: [(String, Int)] {
        let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        var counts = Array(repeating: 0, count: 7)
        let cal = Calendar.current
        for session in finished {
            let weekday = cal.component(.weekday, from: session.startDate) - 1
            if weekday >= 0 && weekday < 7 {
                counts[weekday] += 1
            }
        }
        return zip(names, counts).map { ($0, $1) }
    }

    private var averageDuration: Int {
        let timed = finished.filter { $0.durationSeconds > 0 }
        guard !timed.isEmpty else { return 0 }
        return timed.reduce(0) { $0 + $1.durationSeconds } / timed.count
    }

    private var streak: Int {
        let cal = Calendar.current
        let days = Set(finished.map { cal.startOfDay(for: $0.startDate) })
        var cursor = cal.startOfDay(for: Date())
        if !days.contains(cursor) {
            guard let yesterday = cal.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
        }
        var count = 0
        while days.contains(cursor) {
            count += 1
            guard let previous = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    private var weeklyTrend: [WeekCount] {
        let cal = Calendar.current
        guard let interval = cal.date(byAdding: .weekOfYear, value: -11, to: Date()) else { return [] }
        var buckets: [Date: Int] = [:]
        for session in finished {
            let week = cal.dateInterval(of: .weekOfYear, for: session.startDate)?.start ?? session.startDate
            buckets[week, default: 0] += 1
        }
        var result: [WeekCount] = []
        for offset in 0..<12 {
            if let start = cal.date(byAdding: .weekOfYear, value: offset, to: cal.dateInterval(of: .weekOfYear, for: interval)?.start ?? interval) {
                result.append(WeekCount(id: start, start: start, count: buckets[start] ?? 0))
            }
        }
        return result
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    stat(title: "Workouts", value: "\(finished.count)")
                    stat(title: "Avg duration", value: Formatters.duration(averageDuration))
                    stat(title: "Streak", value: "\(streak)d")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Weekday histogram")
                        .font(.headline)
                    Chart(weekdayCounts, id: \.0) { item in
                        BarMark(
                            x: .value("Day", item.0),
                            y: .value("Workouts", item.1)
                        )
                        .foregroundStyle(accent)
                    }
                    .frame(height: 180)
                }
                .padding(16)
                .opaqueCard()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Workouts per week")
                        .font(.headline)
                    Chart(weeklyTrend) { item in
                        LineMark(
                            x: .value("Week", item.start),
                            y: .value("Count", item.count)
                        )
                        .foregroundStyle(accent)
                        PointMark(
                            x: .value("Week", item.start),
                            y: .value("Count", item.count)
                        )
                        .foregroundStyle(accent)
                    }
                    .frame(height: 200)
                }
                .padding(16)
                .opaqueCard()

                YearActivityGrid(
                    sessions: sessions,
                    runDates: showRunningActivity ? health.activityRunDays : [],
                    showsRunningActivity: showRunningActivity
                )
            }
            .padding(16)
        }
        .background(theme.groupedBackground.ignoresSafeArea())
        .compactNavigationTitle("Trends")
    }

    private func stat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .opaqueCard()
    }
}

struct WeekCount: Identifiable {
    let id: Date
    let start: Date
    let count: Int
}
