import Foundation

enum WidgetSnapshotIDs {
    static let appGroup = "group.com.local.WorkoutApp"
    static let fileName = "widget-snapshot.json"
}

/// Compact payload the main app writes and widgets read. No SwiftData / HealthKit.
struct WidgetSnapshot: Equatable {
    var version: Int
    var updatedAt: Date
    var year: Int
    var dayOfYear: Int
    var liftDayStarts: [Double]
    var runDayStarts: [Double]
    var activityDayCount: Int
    var liftSessionCount: Int
    var recentActivityDays: Int
    var todayStress: Double
    var todayLift: Double
    var todayRun: Double
    var trendTotals: [Double]
    var lastWorkoutTitle: String?
    var lastWorkoutDate: Date?
    var nextDayName: String?
    var nextProgramName: String?
    var accentHex: String
    /// Finished lifting sessions whose startDate falls in the last 7 calendar days.
    var workoutsLast7Days: Int = 0
    /// When false, widgets hide running dots and R / B year-grid legends.
    var showsRunningActivity: Bool = true
    /// When false, stress widgets show a placeholder and year large hides the stress block.
    var showsStressAnalysis: Bool = true
    /// Volume (weight × reps, kg) logged this Monday-start week and the week before.
    var weekVolumeKg: Double = 0
    var lastWeekVolumeKg: Double = 0
    /// Latest complete program cycle and its % volume change vs. the cycle-1 baseline.
    var cycleNumber: Int? = nil
    var cycleVsBaselinePercent: Double? = nil
    /// "kg" or "lb", mirroring the app's weight-unit setting.
    var weightUnit: String = "lb"

    static let empty = WidgetSnapshot(
        version: 1,
        updatedAt: .distantPast,
        year: Calendar.current.component(.year, from: Date()),
        dayOfYear: Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1,
        liftDayStarts: [],
        runDayStarts: [],
        activityDayCount: 0,
        liftSessionCount: 0,
        recentActivityDays: 0,
        todayStress: 0,
        todayLift: 0,
        todayRun: 0,
        trendTotals: Array(repeating: 0, count: 7),
        lastWorkoutTitle: nil,
        lastWorkoutDate: nil,
        nextDayName: nil,
        nextProgramName: nil,
        accentHex: "FA6B2E",
        workoutsLast7Days: 0,
        showsRunningActivity: true,
        showsStressAnalysis: true
    )

    static let preview: WidgetSnapshot = {
        let cal = Calendar.current
        let now = Date()
        let year = cal.component(.year, from: now)
        guard let jan1 = cal.date(from: DateComponents(year: year, month: 1, day: 1)) else {
            return .empty
        }
        var lifts: [Double] = []
        var runs: [Double] = []
        for offset in stride(from: 0, through: 240, by: 3) {
            guard let day = cal.date(byAdding: .day, value: offset, to: jan1) else { continue }
            let start = cal.startOfDay(for: day).timeIntervalSince1970
            if offset % 9 == 0 {
                runs.append(start)
            } else {
                lifts.append(start)
            }
            if offset % 15 == 0 {
                runs.append(start)
            }
        }
        return WidgetSnapshot(
            version: 1,
            updatedAt: now,
            year: year,
            dayOfYear: cal.ordinality(of: .day, in: .year, for: now) ?? 180,
            liftDayStarts: lifts,
            runDayStarts: runs,
            activityDayCount: 84,
            liftSessionCount: 72,
            recentActivityDays: 4,
            todayStress: 44,
            todayLift: 48,
            todayRun: 22,
            trendTotals: [18, 24, 31, 40, 36, 42, 44],
            lastWorkoutTitle: "Push A",
            lastWorkoutDate: cal.date(byAdding: .day, value: -1, to: now),
            nextDayName: "Pull B",
            nextProgramName: "Hypertrophy",
            accentHex: "FA6B2E",
            workoutsLast7Days: 6,
            showsRunningActivity: true,
            showsStressAnalysis: true,
            weekVolumeKg: 18_400,
            lastWeekVolumeKg: 16_500,
            cycleNumber: 4,
            cycleVsBaselinePercent: 9.5,
            weightUnit: "lb"
        )
    }()
}

extension WidgetSnapshot: Codable {
    enum CodingKeys: String, CodingKey {
        case version, updatedAt, year, dayOfYear
        case liftDayStarts, runDayStarts, activityDayCount
        case liftSessionCount, recentActivityDays
        case todayStress, todayLift, todayRun, trendTotals
        case lastWorkoutTitle, lastWorkoutDate
        case nextDayName, nextProgramName, accentHex
        case workoutsLast7Days
        case showsRunningActivity
        case showsStressAnalysis
        case weekVolumeKg, lastWeekVolumeKg, cycleNumber, cycleVsBaselinePercent, weightUnit
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            version: try c.decode(Int.self, forKey: .version),
            updatedAt: try c.decode(Date.self, forKey: .updatedAt),
            year: try c.decode(Int.self, forKey: .year),
            dayOfYear: try c.decode(Int.self, forKey: .dayOfYear),
            liftDayStarts: try c.decode([Double].self, forKey: .liftDayStarts),
            runDayStarts: try c.decode([Double].self, forKey: .runDayStarts),
            activityDayCount: try c.decode(Int.self, forKey: .activityDayCount),
            liftSessionCount: try c.decode(Int.self, forKey: .liftSessionCount),
            recentActivityDays: try c.decode(Int.self, forKey: .recentActivityDays),
            todayStress: try c.decode(Double.self, forKey: .todayStress),
            todayLift: try c.decode(Double.self, forKey: .todayLift),
            todayRun: try c.decode(Double.self, forKey: .todayRun),
            trendTotals: try c.decode([Double].self, forKey: .trendTotals),
            lastWorkoutTitle: try c.decodeIfPresent(String.self, forKey: .lastWorkoutTitle),
            lastWorkoutDate: try c.decodeIfPresent(Date.self, forKey: .lastWorkoutDate),
            nextDayName: try c.decodeIfPresent(String.self, forKey: .nextDayName),
            nextProgramName: try c.decodeIfPresent(String.self, forKey: .nextProgramName),
            accentHex: try c.decode(String.self, forKey: .accentHex),
            workoutsLast7Days: try c.decodeIfPresent(Int.self, forKey: .workoutsLast7Days) ?? 0,
            showsRunningActivity: try c.decodeIfPresent(Bool.self, forKey: .showsRunningActivity) ?? true,
            showsStressAnalysis: try c.decodeIfPresent(Bool.self, forKey: .showsStressAnalysis) ?? true,
            weekVolumeKg: try c.decodeIfPresent(Double.self, forKey: .weekVolumeKg) ?? 0,
            lastWeekVolumeKg: try c.decodeIfPresent(Double.self, forKey: .lastWeekVolumeKg) ?? 0,
            cycleNumber: try c.decodeIfPresent(Int.self, forKey: .cycleNumber),
            cycleVsBaselinePercent: try c.decodeIfPresent(Double.self, forKey: .cycleVsBaselinePercent),
            weightUnit: try c.decodeIfPresent(String.self, forKey: .weightUnit) ?? "lb"
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(year, forKey: .year)
        try c.encode(dayOfYear, forKey: .dayOfYear)
        try c.encode(liftDayStarts, forKey: .liftDayStarts)
        try c.encode(runDayStarts, forKey: .runDayStarts)
        try c.encode(activityDayCount, forKey: .activityDayCount)
        try c.encode(liftSessionCount, forKey: .liftSessionCount)
        try c.encode(recentActivityDays, forKey: .recentActivityDays)
        try c.encode(todayStress, forKey: .todayStress)
        try c.encode(todayLift, forKey: .todayLift)
        try c.encode(todayRun, forKey: .todayRun)
        try c.encode(trendTotals, forKey: .trendTotals)
        try c.encodeIfPresent(lastWorkoutTitle, forKey: .lastWorkoutTitle)
        try c.encodeIfPresent(lastWorkoutDate, forKey: .lastWorkoutDate)
        try c.encodeIfPresent(nextDayName, forKey: .nextDayName)
        try c.encodeIfPresent(nextProgramName, forKey: .nextProgramName)
        try c.encode(accentHex, forKey: .accentHex)
        try c.encode(workoutsLast7Days, forKey: .workoutsLast7Days)
        try c.encode(showsRunningActivity, forKey: .showsRunningActivity)
        try c.encode(showsStressAnalysis, forKey: .showsStressAnalysis)
        try c.encode(weekVolumeKg, forKey: .weekVolumeKg)
        try c.encode(lastWeekVolumeKg, forKey: .lastWeekVolumeKg)
        try c.encodeIfPresent(cycleNumber, forKey: .cycleNumber)
        try c.encodeIfPresent(cycleVsBaselinePercent, forKey: .cycleVsBaselinePercent)
        try c.encode(weightUnit, forKey: .weightUnit)
    }
}

enum WidgetYearActivityKind: Int {
    case none = 0
    case weights = 1
    case running = 2
    case both = 3
}

struct WidgetYearCell: Identifiable {
    var id: Date { date }
    var date: Date
    var inYear: Bool
    var kind: WidgetYearActivityKind
}

/// Week layout shared by Home `YearActivityGrid` and the year widget grid.
enum YearGridWeekdays {
    /// Sunday. Both year grids pin `Calendar.firstWeekday` to this value.
    static let firstWeekday = 1

    /// Single-letter weekday names in grid-row order (Sunday → Saturday).
    static func letters(calendar: Calendar = .current) -> [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let fallback = ["S", "M", "T", "W", "T", "F", "S"]
        guard symbols.count == 7 else { return fallback }
        let start = (firstWeekday - 1 + 7) % 7
        return (0..<7).map { symbols[(start + $0) % 7] }
    }
}

enum WidgetYearGridBuilder {
    static func cells(
        year: Int,
        liftDayStarts: [Double],
        runDayStarts: [Double],
        calendar: Calendar = .current
    ) -> [WidgetYearCell] {
        var cal = calendar
        cal.firstWeekday = YearGridWeekdays.firstWeekday

        let liftDays = Set(liftDayStarts.map { cal.startOfDay(for: Date(timeIntervalSince1970: $0)).timeIntervalSince1970 })
        let runDays = Set(runDayStarts.map { cal.startOfDay(for: Date(timeIntervalSince1970: $0)).timeIntervalSince1970 })

        guard let jan1 = cal.date(from: DateComponents(year: year, month: 1, day: 1)) else { return [] }
        let weekday = cal.component(.weekday, from: jan1)
        let offset = weekday - cal.firstWeekday
        guard let start = cal.date(byAdding: .day, value: -offset, to: jan1) else { return [] }

        var result: [WidgetYearCell] = []
        result.reserveCapacity(53 * 7)
        for i in 0..<(53 * 7) {
            guard let date = cal.date(byAdding: .day, value: i, to: start) else { continue }
            let day = cal.startOfDay(for: date)
            let inYear = cal.component(.year, from: date) == year
            let stamp = day.timeIntervalSince1970
            let hasLift = inYear && liftDays.contains(stamp)
            let hasRun = inYear && runDays.contains(stamp)
            let kind: WidgetYearActivityKind
            switch (hasLift, hasRun) {
            case (true, true): kind = .both
            case (true, false): kind = .weights
            case (false, true): kind = .running
            case (false, false): kind = .none
            }
            result.append(WidgetYearCell(date: date, inYear: inYear, kind: kind))
        }
        return result
    }
}

enum WidgetSnapshotStore {
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshotIDs.appGroup)
    }

    static func load() -> WidgetSnapshot? {
        guard let url = containerURL?.appendingPathComponent(WidgetSnapshotIDs.fileName),
              let data = try? Data(contentsOf: url)
        else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    static func save(_ snapshot: WidgetSnapshot) {
        guard let url = containerURL?.appendingPathComponent(WidgetSnapshotIDs.fileName) else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
