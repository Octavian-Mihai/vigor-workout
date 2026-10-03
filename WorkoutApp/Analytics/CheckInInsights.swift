import Foundation
import HealthKit

/// Plain, storage-agnostic view of a `DailyCheckIn`, used by `CheckInInsights`.
struct CheckInSample: Equatable {
    var date: Date
    var sleep: Int?
    var mood: Int?
    var energy: Int?
    /// `CaffeineTiming.rawValue` of the last drink, if any caffeine was logged.
    var lastCaffeine: Int?
    var sleepHours: Double?
    /// Daily averages from Apple Health, merged in by `CheckInInsights.merging`.
    var hrv: Double?
    var restingHR: Double?

    init(
        date: Date,
        sleep: Int? = nil,
        mood: Int? = nil,
        energy: Int? = nil,
        lastCaffeine: Int? = nil,
        sleepHours: Double? = nil,
        hrv: Double? = nil,
        restingHR: Double? = nil
    ) {
        self.date = date
        self.sleep = sleep
        self.mood = mood
        self.energy = energy
        self.lastCaffeine = lastCaffeine
        self.sleepHours = sleepHours
        self.hrv = hrv
        self.restingHR = restingHR
    }

    init(_ entry: DailyCheckIn) {
        self.init(
            date: entry.date,
            sleep: entry.sleepRating,
            mood: entry.moodRating,
            energy: entry.energyRating,
            lastCaffeine: entry.lastCaffeine,
            sleepHours: entry.sleepHours
        )
    }

    var hasAnyRating: Bool { sleep != nil || mood != nil || energy != nil }
}

/// What insights try to explain: how the person felt, and how their body recovered.
enum CheckInOutcome: String, CaseIterable, Identifiable {
    case sleep, mood, energy, hrv, restingHR

    /// The three 1–5 self-ratings.
    static let ratings: [CheckInOutcome] = [.sleep, .mood, .energy]

    var id: String { rawValue }
    var isRating: Bool { Self.ratings.contains(self) }

    var title: String {
        switch self {
        case .sleep: return "Sleep"
        case .mood: return "Mood"
        case .energy: return "Energy"
        case .hrv: return "HRV"
        case .restingHR: return "Resting HR"
        }
    }

    /// Reads naturally at the start of a sentence ("Sleep quality is lower after…").
    var noun: String {
        switch self {
        case .sleep: return "Sleep quality"
        case .restingHR: return "Resting heart rate"
        default: return title
        }
    }

    /// Higher HRV and lower resting heart rate are the better direction.
    var higherIsBetter: Bool { self != .restingHR }

    /// Smallest gap between two groups worth mentioning, in the outcome's own unit.
    var minimumDifference: Double {
        switch self {
        case .hrv: return 5
        case .restingHR: return 2
        default: return 0.4
        }
    }

    /// Floor on the spread used to standardise differences, so tiny samples can't look huge.
    var deviationFloor: Double {
        switch self {
        case .hrv: return 4
        case .restingHR: return 1.5
        default: return 0.5
        }
    }

    func value(in sample: CheckInSample) -> Double? {
        switch self {
        case .sleep: return sample.sleep.map(Double.init)
        case .mood: return sample.mood.map(Double.init)
        case .energy: return sample.energy.map(Double.init)
        case .hrv: return sample.hrv
        case .restingHR: return sample.restingHR
        }
    }

    func format(_ value: Double) -> String {
        switch self {
        case .hrv: return "\(Int(value.rounded())) ms"
        case .restingHR: return "\(Int(value.rounded())) bpm"
        default: return Formatters.trimmedNumber(value, decimals: 1)
        }
    }

    /// What the numbers in a comparison mean, for the line under it.
    var scaleNote: String {
        switch self {
        case .hrv: return "daily average HRV from Apple Health"
        case .restingHR: return "daily resting heart rate from Apple Health"
        default: return "\(noun.lowercased()) averages out of 5"
        }
    }
}

/// Things that might move how the person feels.
enum CheckInDriver: CaseIterable {
    case sleepHours, caffeineTiming, training

    func value(sample: CheckInSample?, isTrainingDay: Bool) -> Double? {
        switch self {
        case .sleepHours: return sample?.sleepHours
        case .caffeineTiming:
            // 0 = no caffeine, then 1...4 from morning to evening, so "later" is simply "higher".
            return sample?.lastCaffeine.map(Double.init)
        case .training: return isTrainingDay ? 1 : 0
        }
    }

    /// Drivers that describe the same thing (how much the person slept), so only the strongest is reported.
    fileprivate var family: String {
        switch self {
        case .sleepHours: return "sleep"
        case .caffeineTiming: return "caffeine"
        case .training: return "training"
        }
    }

    /// Where a "lighter vs heavier" split can fall. Continuous values use a half-hour grid so
    /// the cut-off reads as "7h" rather than "6.83h"; everything else splits between observed values.
    fileprivate func candidateThresholds(for values: [Double]) -> [Double] {
        guard let low = values.min(), let high = values.max(), low < high else { return [] }
        switch self {
        case .sleepHours:
            let first = ((low * 2).rounded(.up) / 2)
            return stride(from: first, through: high, by: 0.5).filter { $0 > low }
        default:
            return Array(Set(values)).sorted().dropFirst().map { $0 }
        }
    }

    fileprivate func fragment(high: Bool, threshold: Double, lag: Int, outcome: CheckInOutcome) -> String {
        switch self {
        case .sleepHours:
            let hours = Formatters.trimmedNumber(threshold, decimals: 1)
            return high ? "after \(hours)h+ of sleep" : "after under \(hours)h of sleep"
        case .caffeineTiming:
            let lead = lag == 0 ? "on days" : "after days"
            guard let start = CaffeineTiming(rawValue: Int(threshold))?.startLabel else {
                return high ? "\(lead) with caffeine" : "\(lead) without it"
            }
            return high ? "\(lead) with caffeine after \(start)" : "\(lead) with none or only before \(start)"
        case .training:
            if lag == 0 { return high ? "on training days" : "on rest days" }
            let when = outcome == .sleep ? "the night after" : "the day after"
            return high ? "\(when) training" : "\(when) a rest day"
        }
    }
}

struct CheckInInsight: Identifiable, Equatable {
    enum Confidence: Equatable {
        /// Few days of data — worth watching, not yet worth acting on.
        case early
        /// Enough days that a coincidence is less likely.
        case pattern
    }

    let driver: CheckInDriver
    let outcome: CheckInOutcome
    /// Days between the driver and the feeling it's compared with (0 = same day, 1 = next day).
    let lag: Int
    let threshold: Double
    let highMean: Double
    let lowMean: Double
    let highCount: Int
    let lowCount: Int
    /// Standardised difference between the two groups (Cohen's d).
    let effectSize: Double
    /// Welch's t statistic, used to rank insights.
    let tStatistic: Double

    var id: String { "\(driver)-\(outcome.rawValue)-\(lag)" }
    var difference: Double { highMean - lowMean }
    var dayCount: Int { highCount + lowCount }
    var confidence: Confidence { dayCount >= CheckInInsights.patternDayCount ? .pattern : .early }
    var isPositive: Bool { difference > 0 }
    /// Whether the change is in the better direction for this outcome (lower resting HR is good).
    var isFavourable: Bool { outcome.higherIsBetter ? difference > 0 : difference < 0 }
    var formattedDifference: String {
        let gap = outcome == .hrv || outcome == .restingHR
            ? "\(Int(abs(difference).rounded()))"
            : Formatters.trimmedNumber(abs(difference), decimals: 1)
        return "\(difference > 0 ? "+" : "−")\(gap)"
    }

    var headline: String {
        let direction = difference > 0 ? "higher" : "lower"
        let when = driver.fragment(high: true, threshold: threshold, lag: lag, outcome: outcome)
        return "\(outcome.noun) is \(direction) \(when)"
    }

    /// Short names for the two groups being compared, e.g. "After days with caffeine after 11am".
    var highLabel: String { Self.capitalised(driver.fragment(high: true, threshold: threshold, lag: lag, outcome: outcome)) }
    var lowLabel: String { Self.capitalised(driver.fragment(high: false, threshold: threshold, lag: lag, outcome: outcome)) }

    private static func capitalised(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }

    var detail: String {
        let lowWhen = driver.fragment(high: false, threshold: threshold, lag: lag, outcome: outcome)
        return "\(outcome.format(highMean)) vs \(outcome.format(lowMean)) \(lowWhen) (\(formattedDifference)) · \(dayCount) days"
    }
}

struct CheckInAverage: Equatable {
    let current: Double?
    let previous: Double?

    var delta: Double? {
        guard let current, let previous else { return nil }
        return current - previous
    }
}

enum CheckInInsights {
    /// Logged days before the Insights screen starts looking for patterns.
    static let unlockDayCount = 14
    /// Days at which an insight stops being labelled an early signal.
    static let patternDayCount = 21

    static let minimumPairedDays = 12
    static let minimumGroupSize = 4
    static let minimumEffectSize = 0.5
    static let minimumTStatistic = 2.0

    private struct Pairing {
        let driver: CheckInDriver
        let outcome: CheckInOutcome
        let lag: Int
    }

    private static let pairings: [Pairing] = [
        Pairing(driver: .sleepHours, outcome: .mood, lag: 0),
        Pairing(driver: .sleepHours, outcome: .energy, lag: 0),
        Pairing(driver: .caffeineTiming, outcome: .sleep, lag: 1),
        Pairing(driver: .training, outcome: .energy, lag: 0),
        Pairing(driver: .training, outcome: .energy, lag: 1),
        Pairing(driver: .training, outcome: .mood, lag: 0),
        Pairing(driver: .training, outcome: .sleep, lag: 1),
        // Recovery measures from Apple Health: the morning reading reflects the day before.
        Pairing(driver: .sleepHours, outcome: .hrv, lag: 0),
        Pairing(driver: .sleepHours, outcome: .restingHR, lag: 0),
        Pairing(driver: .caffeineTiming, outcome: .hrv, lag: 1),
        Pairing(driver: .caffeineTiming, outcome: .restingHR, lag: 1),
        Pairing(driver: .training, outcome: .hrv, lag: 1),
        Pairing(driver: .training, outcome: .restingHR, lag: 1)
    ]

    // MARK: - Insights

    /// Compares how the person felt on days that differ in one thing (sleep, caffeine, screen time,
    /// training), and returns the comparisons that are big and consistent enough to mention —
    /// strongest first. These are correlations in the person's own log, not proof of cause.
    static func analyze(
        samples: [CheckInSample],
        trainedDays: Set<Date>,
        calendar: Calendar = .current
    ) -> [CheckInInsight] {
        let byDay = samplesByDay(samples, calendar: calendar)
        let trained = Set(trainedDays.map { calendar.startOfDay(for: $0) })

        let ranked = pairings
            .compactMap { insight(for: $0, byDay: byDay, trainedDays: trained, calendar: calendar) }
            .sorted { abs($0.tStatistic) > abs($1.tStatistic) }

        // "Energy is higher after good sleep" and "…after 7h+ of sleep" are one finding; keep the stronger.
        var seen = Set<String>()
        return ranked.filter { seen.insert("\($0.driver.family)-\($0.outcome.rawValue)-\($0.lag)").inserted }
    }

    private static func insight(
        for pairing: Pairing,
        byDay: [Date: CheckInSample],
        trainedDays: Set<Date>,
        calendar: Calendar
    ) -> CheckInInsight? {
        var pairs: [(driver: Double, outcome: Double)] = []
        for (day, sample) in byDay {
            guard let outcome = pairing.outcome.value(in: sample),
                  let driverDay = calendar.date(byAdding: .day, value: -pairing.lag, to: day) else { continue }
            guard let driver = pairing.driver.value(
                sample: byDay[driverDay],
                isTrainingDay: trainedDays.contains(driverDay)
            ) else { continue }
            pairs.append((driver, outcome))
        }
        guard pairs.count >= minimumPairedDays else { return nil }

        guard let threshold = balancedThreshold(
            for: pairing.driver,
            values: pairs.map(\.driver)
        ) else { return nil }

        let high = pairs.filter { $0.driver >= threshold }.map(\.outcome)
        let low = pairs.filter { $0.driver < threshold }.map(\.outcome)
        let highStats = GroupStats(high)
        let lowStats = GroupStats(low)

        let difference = highStats.mean - lowStats.mean
        let pooledVariance = (Double(high.count - 1) * highStats.variance + Double(low.count - 1) * lowStats.variance)
            / Double(high.count + low.count - 2)
        // Floors keep two near-identical groups from producing absurd scores on a short log.
        let floor = pairing.outcome.deviationFloor
        let effectSize = difference / max(pooledVariance.squareRoot(), floor)
        let standardError = max((highStats.variance / Double(high.count) + lowStats.variance / Double(low.count)).squareRoot(), floor * 0.3)
        let tStatistic = difference / standardError

        guard abs(effectSize) >= minimumEffectSize,
              abs(difference) >= pairing.outcome.minimumDifference,
              abs(tStatistic) >= minimumTStatistic else { return nil }

        return CheckInInsight(
            driver: pairing.driver,
            outcome: pairing.outcome,
            lag: pairing.lag,
            threshold: threshold,
            highMean: highStats.mean,
            lowMean: lowStats.mean,
            highCount: high.count,
            lowCount: low.count,
            effectSize: effectSize,
            tStatistic: tStatistic
        )
    }

    /// The cut-off that splits the days most evenly while leaving enough days on each side.
    /// Choosing by balance rather than by biggest difference avoids fishing for a flattering split.
    private static func balancedThreshold(for driver: CheckInDriver, values: [Double]) -> Double? {
        var best: (threshold: Double, imbalance: Int)?
        for candidate in driver.candidateThresholds(for: values) {
            let highCount = values.filter { $0 >= candidate }.count
            let lowCount = values.count - highCount
            guard highCount >= minimumGroupSize, lowCount >= minimumGroupSize else { continue }
            let imbalance = abs(highCount - lowCount)
            if best == nil || imbalance < best!.imbalance {
                best = (candidate, imbalance)
            }
        }
        return best?.threshold
    }

    private struct GroupStats {
        let mean: Double
        /// Sample variance (n − 1); zero for a single value.
        let variance: Double

        init(_ values: [Double]) {
            let count = Double(values.count)
            let average = values.reduce(0, +) / max(count, 1)
            mean = average
            variance = values.count > 1
                ? values.reduce(0) { $0 + ($1 - average) * ($1 - average) } / (count - 1)
                : 0
        }
    }

    // MARK: - Progress and trends

    static func loggedDayCount(_ samples: [CheckInSample], calendar: Calendar = .current) -> Int {
        samplesByDay(samples, calendar: calendar).values.filter(\.hasAnyRating).count
    }

    /// Consecutive logged days ending today. A day that hasn't been logged *yet* doesn't break the streak.
    static func currentStreak(_ samples: [CheckInSample], today: Date, calendar: Calendar = .current) -> Int {
        let logged = Set(
            samplesByDay(samples, calendar: calendar).values.filter(\.hasAnyRating).map(\.date)
        )
        var day = calendar.startOfDay(for: today)
        if !logged.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var streak = 0
        while logged.contains(day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    /// Mean of an outcome over the `days` ending on `today`, and over the `days` before that.
    static func average(
        _ outcome: CheckInOutcome,
        in samples: [CheckInSample],
        endingOn today: Date,
        days: Int,
        calendar: Calendar = .current
    ) -> CheckInAverage {
        let byDay = samplesByDay(samples, calendar: calendar)
        let end = calendar.startOfDay(for: today)

        func mean(offset: Int) -> Double? {
            var values: [Double] = []
            for back in offset..<(offset + days) {
                guard let day = calendar.date(byAdding: .day, value: -back, to: end),
                      let sample = byDay[day],
                      let value = outcome.value(in: sample) else { continue }
                values.append(value)
            }
            return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }

        return CheckInAverage(current: mean(offset: 0), previous: mean(offset: days))
    }

    // MARK: - Apple Health

    /// Adds Apple Health's daily HRV, resting heart rate and sleep hours to the check-in samples.
    /// Days with Health data but no check-in still get a sample, so they can serve as comparison days.
    /// Hours logged on the check-in itself win over Health's.
    static func merging(
        _ samples: [CheckInSample],
        hrv: [Date: Double],
        restingHR: [Date: Double],
        sleepHours: [Date: Double],
        calendar: Calendar = .current
    ) -> [CheckInSample] {
        var byDay = samplesByDay(samples, calendar: calendar)
        func attach(_ values: [Date: Double], _ apply: (inout CheckInSample, Double) -> Void) {
            for (date, value) in values {
                let day = calendar.startOfDay(for: date)
                var sample = byDay[day] ?? CheckInSample(date: day)
                apply(&sample, value)
                byDay[day] = sample
            }
        }
        attach(hrv) { $0.hrv = $1 }
        attach(restingHR) { $0.restingHR = $1 }
        attach(sleepHours) { if $0.sleepHours == nil { $0.sleepHours = $1 } }
        return Array(byDay.values)
    }

    // MARK: - Training days

    /// Days that count as training: any logged strength session, plus cardio that wasn't just a short walk.
    static func trainedDays(
        sessions: [WorkoutSession],
        cardio: [CardioWorkout],
        calendar: Calendar = .current
    ) -> Set<Date> {
        var days = Set<Date>()
        for session in sessions where !session.sets.isEmpty {
            days.insert(calendar.startOfDay(for: session.startDate))
        }
        for workout in cardio where isTraining(workout) {
            days.insert(calendar.startOfDay(for: workout.start))
        }
        return days
    }

    private static func isTraining(_ workout: CardioWorkout) -> Bool {
        switch workout.activityType {
        case .running, .cycling: return true
        default: return workout.duration >= 30 * 60
        }
    }

    // MARK: - Helpers

    /// One sample per calendar day (the last one wins if a day was somehow logged twice).
    private static func samplesByDay(_ samples: [CheckInSample], calendar: Calendar) -> [Date: CheckInSample] {
        var byDay: [Date: CheckInSample] = [:]
        for sample in samples {
            var normalised = sample
            normalised.date = calendar.startOfDay(for: sample.date)
            byDay[normalised.date] = normalised
        }
        return byDay
    }
}
