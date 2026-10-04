import Foundation

/// Everything the deload check looks at, already boiled down to plain numbers.
struct DeloadInputs {
    /// Finished sessions with at least one set, by date.
    var sessionDates: [Date] = []
    /// Tonnage for the last full weeks, oldest first. The current, unfinished week must be left out.
    var completedWeeklyTonnage: [Double] = []
    /// Total leftover fatigue (0–100) for the most recent days, oldest first.
    var recentStress: [Double] = []
    /// Best estimated 1RM per session for each main lift, oldest first (only lifts with history).
    var liftSessionBests: [String: [Double]] = [:]
    var hrvRecent: Double?
    var hrvBaseline: Double?
    var restingHRRecent: Double?
    var restingHRBaseline: Double?
    var energyRecent: Double?
    var energyPrevious: Double?
    var now: Date = Date()
}

struct DeloadAssessment: Equatable {
    let reasons: [String]
    let points: Int
}

/// Suggests a lighter week when several independent signals agree. It is deliberately conservative:
/// no single number triggers it, and it stays quiet for anyone who hasn't been training consistently.
enum DeloadAdvisor {
    static let pointsNeeded = 4
    static let signalsNeeded = 2
    static let highFatigueStress = 56.0

    static let recommendation = "Keep your usual exercises for one week, but do about half the sets, use weights roughly 10% lighter and stop with 3+ reps in reserve. Then return to normal."

    static func assess(_ inputs: DeloadInputs, calendar: Calendar = .current) -> DeloadAssessment? {
        guard trainedConsistently(inputs, calendar: calendar) else { return nil }

        var reasons: [String] = []
        var points = 0

        if inputs.recentStress.count >= 5 {
            let recent = inputs.recentStress.suffix(5)
            let mean = recent.reduce(0, +) / Double(recent.count)
            if mean >= highFatigueStress {
                reasons.append("Training fatigue has stayed high for the last 5 days.")
                points += 2
            }
        }

        let slipping = inputs.liftSessionBests.filter { isSlipping($0.value) }.keys.sorted()
        if !slipping.isEmpty {
            reasons.append("Estimated strength has slipped on \(joined(slipping)).")
            points += slipping.count >= 2 ? 2 : 1
        }

        var recoveryPoints = 0
        if let recent = inputs.hrvRecent, let base = inputs.hrvBaseline, base > 0, recent < base * 0.9 {
            let drop = Int(((1 - recent / base) * 100).rounded())
            reasons.append("Your HRV is about \(drop)% below your usual.")
            recoveryPoints = 2
        }
        if let recent = inputs.restingHRRecent, let base = inputs.restingHRBaseline, recent >= base + 3 {
            reasons.append("Your resting heart rate is up about \(Int((recent - base).rounded())) bpm.")
            recoveryPoints += recoveryPoints == 0 ? 2 : 1
        }
        points += recoveryPoints

        if let recent = inputs.energyRecent, let previous = inputs.energyPrevious, recent <= previous - 0.7 {
            reasons.append("Your energy ratings have dropped this week.")
            points += 1
        }

        if noLighterWeek(inputs.completedWeeklyTonnage) {
            reasons.append("It's been \(inputs.completedWeeklyTonnage.count)+ weeks of steady training without a lighter week.")
            points += 1
        }

        guard points >= pointsNeeded, reasons.count >= signalsNeeded else { return nil }
        return DeloadAssessment(reasons: reasons, points: points)
    }

    /// At least 3 sessions in the last two weeks and 5 in the last four.
    static func trainedConsistently(_ inputs: DeloadInputs, calendar: Calendar = .current) -> Bool {
        func count(days: Int) -> Int {
            guard let start = calendar.date(byAdding: .day, value: -days, to: inputs.now) else { return 0 }
            return inputs.sessionDates.filter { $0 >= start && $0 <= inputs.now }.count
        }
        return count(days: 14) >= 3 && count(days: 28) >= 5
    }

    /// Four or more sessions, the last three not improving, and the latest at least 3% under the best.
    static func isSlipping(_ bests: [Double]) -> Bool {
        guard bests.count >= 4, let peak = bests.max(), let last = bests.last else { return false }
        let lastThree = Array(bests.suffix(3))
        let notImproving = zip(lastThree, lastThree.dropFirst()).allSatisfy { $0 >= $1 - 0.001 }
        return notImproving && last <= peak * 0.97
    }

    /// Every one of the last few full weeks was trained, and none was clearly lighter than the rest.
    static func noLighterWeek(_ weekly: [Double]) -> Bool {
        let weeks = Array(weekly.suffix(5))
        guard weeks.count == 5, weeks.allSatisfy({ $0 > 0 }) else { return false }
        let mean = weeks.reduce(0, +) / Double(weeks.count)
        return weeks.allSatisfy { $0 >= mean * 0.75 }
    }

    private static func joined(_ items: [String]) -> String {
        switch items.count {
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default: return items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
        }
    }
}

// MARK: - Building inputs from the app's data

extension DeloadAdvisor {
    @MainActor
    static func inputs(
        sessions: [WorkoutSession],
        cardio: [CardioWorkout],
        checkIns: [DailyCheckIn],
        hrvByDay: [Date: Double],
        restingHRByDay: [Date: Double],
        restingHeartRate: Double?,
        maxHeartRate: Double?,
        now: Date = Date()
    ) -> DeloadInputs {
        let calendar = Calendar.current
        let finished = sessions.filter { $0.endDate != nil && !$0.sets.isEmpty }
        let allSets = finished.flatMap(\.sets)

        var inputs = DeloadInputs(now: now)
        inputs.sessionDates = finished.map(\.startDate)

        let weekly = StressCalculator.weeklyTrainingLoad(from: allSets, weeks: 6, now: now)
        inputs.completedWeeklyTonnage = weekly.dropLast().map(\.tonnageKg)

        inputs.recentStress = StressCalculator.dailyTrend(
            sets: allSets,
            cardioWorkouts: cardio,
            restingHeartRate: restingHeartRate,
            maxHeartRate: maxHeartRate,
            days: 5,
            now: now
        ).map(\.total)

        for lift in BigLift.allCases {
            let bests = finished
                .sorted { $0.startDate < $1.startDate }
                .compactMap { session -> Double? in
                    session.sets
                        .filter { lift.matches($0.exerciseName) && $0.weight > 0 && $0.reps > 0 }
                        .map { OneRM.estimate(weight: $0.weight, reps: $0.reps, rir: $0.rir) }
                        .max()
                }
            if !bests.isEmpty { inputs.liftSessionBests[lift.rawValue] = Array(bests.suffix(6)) }
        }

        func mean(_ values: [Date: Double], from: Int, to: Int) -> Double? {
            let found = (from..<to).compactMap { back -> Double? in
                guard let day = calendar.date(byAdding: .day, value: -back, to: calendar.startOfDay(for: now)) else { return nil }
                return values[day]
            }
            return found.count >= 3 ? found.reduce(0, +) / Double(found.count) : nil
        }
        inputs.hrvRecent = mean(hrvByDay, from: 0, to: 7)
        inputs.hrvBaseline = mean(hrvByDay, from: 7, to: 37)
        inputs.restingHRRecent = mean(restingHRByDay, from: 0, to: 7)
        inputs.restingHRBaseline = mean(restingHRByDay, from: 7, to: 37)

        let samples = checkIns.map(CheckInSample.init)
        let energy = CheckInInsights.average(.energy, in: samples, endingOn: now, days: 7)
        inputs.energyRecent = energy.current
        inputs.energyPrevious = energy.previous
        return inputs
    }
}
