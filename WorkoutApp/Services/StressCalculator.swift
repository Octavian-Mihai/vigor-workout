import Foundation
import HealthKit

struct StressEstimate {
    var total: Double
    var lift: Double
    var run: Double
}

struct DailyStress: Identifiable {
    var date: Date
    var total: Double
    var lift: Double
    var run: Double

    var id: Date { date }
}

enum StressBand: String {
    case recovery = "Recovery / easy"
    case productive = "Productive"
    case high = "High — watch sleep/fatigue"
    case veryHigh = "Very high — consider backing off"

    static func band(for score: Double) -> StressBand {
        switch score {
        case ..<30.5: return .recovery
        case ..<55.5: return .productive
        case ..<75.5: return .high
        default: return .veryHigh
        }
    }
}

enum StressCalculator {
    static let windowDays: Double = 7
    /// Overnight leftover-fatigue decay (~36h half-life). A 100% day is ~65 the next morning.
    static let residualDecayPerDay = 0.65
    /// Days of isolated load used to seed the residual series before the 7-day display window.
    static let residualSeedDays = 14

    static func band(for score: Double) -> StressBand {
        StressBand.band(for: score)
    }

    static func totalVolume(from sets: [SetLog]) -> Double {
        VolumeAnalytics.totalVolume(from: sets.map(SetEntry.init))
    }

    static func totalReps(from sets: [SetLog]) -> Int {
        VolumeAnalytics.totalReps(from: sets.map(SetEntry.init))
    }

    static func sets(inLastDays days: Double, from sets: [SetLog], now: Date = Date()) -> [SetLog] {
        let cutoff = now.addingTimeInterval(-days * 86_400)
        return sets.filter { $0.timestamp >= cutoff }
    }

    static func estimatedMaxHeartRate(dateOfBirth: Date?, now: Date = Date()) -> Double {
        guard let dateOfBirth else { return 190 }
        let age = Calendar.current.dateComponents([.year], from: dateOfBirth, to: now).year ?? 30
        return max(140, 220 - Double(age))
    }

    static func recoveryContextLabel(hrvSDNN: Double?, sleepHours: Double?) -> String? {
        var parts: [String] = []
        if let sleep = sleepHours {
            parts.append(String(format: "Sleep: %.1fh", sleep))
        }
        if let hrv = hrvSDNN {
            parts.append(String(format: "HRV: %.0fms", hrv))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Cardio stress 0–100.
    /// HR path: Banister-style TRIMP from duration × HR reserve.
    /// No HR: duration × relative intensity vs an easy 8:00/km baseline.
    static func runStress(
        duration: TimeInterval,
        distanceMeters: Double,
        averageHeartRate: Double?,
        restingHeartRate: Double? = nil,
        maxHeartRate: Double? = nil,
        elevationGainMeters: Double? = nil,
        activityType: HKWorkoutActivityType = .running
    ) -> Double {
        let resting = restingHeartRate ?? 60
        let maxHR = maxHeartRate ?? 190
        let minutes = max(duration / 60.0, 0)

        var score: Double
        if let hr = averageHeartRate, hr > 0, maxHR > resting {
            let hrr = min(max((hr - resting) / (maxHR - resting), 0), 1.05)
            let trimp = minutes * hrr * 0.64 * exp(1.92 * hrr)
            score = min(100, trimp / 1.5)
        } else {
            let km = distanceMeters / 1000.0
            if km > 0, minutes > 0 {
                let paceMinPerKm = minutes / km
                let easyPace = 8.0
                let relative = min(easyPace / max(paceMinPerKm, 3.0), 2.0)
                score = min(100, (minutes / 60.0) * relative * 70.0)
            } else {
                score = min(100, minutes / 60.0 * 40.0)
            }
        }

        if let elevation = elevationGainMeters, elevation > 0 {
            let elevationFactor = 1.0 + min(elevation / 300.0, 0.35)
            score *= elevationFactor
        }

        score *= activityWeight(for: activityType)
        return min(100, score)
    }

    private static func activityWeight(for activityType: HKWorkoutActivityType) -> Double {
        switch activityType {
        case .running: return 1.0
        case .hiking: return 0.85
        case .cycling: return 0.75
        case .walking: return 0.50
        default: return 1.0
        }
    }

    static func averageRunStress(
        _ workouts: [CardioWorkout],
        restingHeartRate: Double? = nil,
        maxHeartRate: Double? = nil,
        now: Date = Date()
    ) -> Double {
        let cutoff = now.addingTimeInterval(-windowDays * 86_400)
        let recent = workouts.filter { $0.start >= cutoff }
        guard !recent.isEmpty else { return 0 }
        let mean = recent
            .map { $0.stress(restingHeartRate: restingHeartRate, maxHeartRate: maxHeartRate) }
            .reduce(0, +) / Double(recent.count)
        return min(100, mean)
    }

    /// Leftover fatigue for today: today’s residual from the decaying lift/run series.
    static func todayEstimate(
        sets: [SetLog],
        cardioWorkouts: [CardioWorkout],
        restingHeartRate: Double? = nil,
        maxHeartRate: Double? = nil,
        now: Date = Date()
    ) -> StressEstimate {
        guard let today = residualSeries(
            sets: sets,
            cardioWorkouts: cardioWorkouts,
            restingHeartRate: restingHeartRate,
            maxHeartRate: maxHeartRate,
            now: now
        ).last else {
            return StressEstimate(total: 0, lift: 0, run: 0)
        }
        return StressEstimate(total: today.total, lift: today.lift, run: today.run)
    }

    /// Last `days` of leftover-fatigue residuals (seeded over `residualSeedDays`).
    static func dailyTrend(
        sets: [SetLog],
        cardioWorkouts: [CardioWorkout],
        restingHeartRate: Double? = nil,
        maxHeartRate: Double? = nil,
        days: Int = 7,
        now: Date = Date()
    ) -> [DailyStress] {
        let series = residualSeries(
            sets: sets,
            cardioWorkouts: cardioWorkouts,
            restingHeartRate: restingHeartRate,
            maxHeartRate: maxHeartRate,
            now: now
        )
        return Array(series.suffix(days))
    }

    static func blend(lift: Double, run: Double) -> Double {
        if lift > 0, run > 0 {
            return min(100, lift * 0.65 + run * 0.35)
        }
        return min(100, max(lift, run))
    }

    /// Harder leftover channel counts in full; the smaller one adds at half, capped at 100.
    static func combineResiduals(lift: Double, run: Double) -> Double {
        min(100, max(lift, run) + 0.5 * min(lift, run))
    }

    static func dayLiftScore(_ sets: [SetLog]) -> Double {
        guard !sets.isEmpty else { return 0 }
        let volumeScore = min(60.0, totalVolume(from: sets) / 400.0)
        let intensities = sets.map { max(0, 5.0 - Double(min($0.rir, 5))) / 5.0 }
        let avgIntensity = intensities.reduce(0, +) / Double(intensities.count)
        return min(100, volumeScore + avgIntensity * 40.0)
    }

    static func dayRunScore(
        _ workouts: [CardioWorkout],
        restingHeartRate: Double? = nil,
        maxHeartRate: Double? = nil
    ) -> Double {
        guard !workouts.isEmpty else { return 0 }
        let total = workouts
            .map { $0.stress(restingHeartRate: restingHeartRate, maxHeartRate: maxHeartRate) }
            .reduce(0, +)
        return min(100, total)
    }

    /// Walks `residualSeedDays` of isolated daily load into decaying lift/run residuals.
    private static func residualSeries(
        sets: [SetLog],
        cardioWorkouts: [CardioWorkout],
        restingHeartRate: Double?,
        maxHeartRate: Double?,
        now: Date
    ) -> [DailyStress] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        var liftResidual = 0.0
        var runResidual = 0.0
        var series: [DailyStress] = []
        series.reserveCapacity(residualSeedDays)
        for offset in 0..<residualSeedDays {
            guard let day = cal.date(byAdding: .day, value: -(residualSeedDays - 1 - offset), to: today) else {
                continue
            }
            let slice = daySlice(
                sets: sets,
                cardioWorkouts: cardioWorkouts,
                dayStart: day,
                calendar: cal,
                restingHeartRate: restingHeartRate,
                maxHeartRate: maxHeartRate
            )
            liftResidual = min(100, slice.lift + liftResidual * residualDecayPerDay)
            runResidual = min(100, slice.run + runResidual * residualDecayPerDay)
            series.append(
                DailyStress(
                    date: day,
                    total: combineResiduals(lift: liftResidual, run: runResidual),
                    lift: liftResidual,
                    run: runResidual
                )
            )
        }
        return series
    }

    private static func daySlice(
        sets: [SetLog],
        cardioWorkouts: [CardioWorkout],
        dayStart: Date,
        calendar: Calendar,
        restingHeartRate: Double?,
        maxHeartRate: Double?
    ) -> StressEstimate {
        let end = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        let daySets = sets.filter { $0.timestamp >= dayStart && $0.timestamp < end }
        let dayWorkouts = cardioWorkouts.filter { $0.start >= dayStart && $0.start < end }
        let lift = dayLiftScore(daySets)
        let run = dayRunScore(dayWorkouts, restingHeartRate: restingHeartRate, maxHeartRate: maxHeartRate)
        return StressEstimate(total: blend(lift: lift, run: run), lift: lift, run: run)
    }

    static func weeklyTrainingLoad(from sets: [SetLog], weeks: Int = 12, now: Date = Date()) -> [WeeklyTrainingLoad] {
        VolumeAnalytics.weeklyTrainingLoad(from: sets.map(SetEntry.init), weeks: weeks, now: now)
    }

    /// Per-muscle daily load 0–100 using primary 100% / secondary 50% volume weighting.
    static func muscleDailyLoad(from sets: [SetLog]) -> [String: Double] {
        VolumeAnalytics.muscleDailyLoad(from: sets.map(SetEntry.init))
    }

    /// Residual fatigue converted to freshness 0–100 for one muscle.
    static func muscleFreshness(for muscle: String, now: Date = Date(), sessions: [WorkoutSession]) -> Double {
        let allSets = sessions.flatMap(\.sets)
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        var residual = 0.0

        for offset in 0..<residualSeedDays {
            guard let day = cal.date(byAdding: .day, value: -(residualSeedDays - 1 - offset), to: today) else {
                continue
            }
            let end = cal.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
            let daySets = allSets.filter { $0.timestamp >= day && $0.timestamp < end }
            let load = muscleDailyLoad(from: daySets)[muscle] ?? 0
            residual = min(100, load + residual * residualDecayPerDay)
        }

        return max(0, 100 - residual)
    }

    static func allMuscleFreshness(now: Date = Date(), sessions: [WorkoutSession]) -> [String: Double] {
        var result: [String: Double] = [:]
        for muscle in MuscleGroup.allCases {
            result[muscle.rawValue] = muscleFreshness(for: muscle.rawValue, now: now, sessions: sessions)
        }
        return result
    }

    static func freshnessLabel(for score: Double) -> String {
        switch score {
        case 70...: return "Fresh"
        case 40..<70: return "Moderate"
        default: return "Fatigued"
        }
    }

    static func freshnessColor(for score: Double) -> (red: Double, green: Double, blue: Double) {
        switch score {
        case 70...:
            return (0.30, 0.72, 0.48)
        case 40..<70:
            return (0.95, 0.58, 0.18)
        default:
            return (0.90, 0.25, 0.28)
        }
    }

    static func lastLoadDate(for muscle: String, sessions: [WorkoutSession], now: Date = Date()) -> Date? {
        let cal = Calendar.current
        let cutoff = now.addingTimeInterval(-Double(residualSeedDays) * 86_400)
        let matchingSets = sessions
            .flatMap(\.sets)
            .filter { set in
                set.timestamp >= cutoff
                    && (set.primaryMuscles.contains(muscle) || set.secondaryMuscles.contains(muscle))
            }
            .sorted { $0.timestamp > $1.timestamp }
        guard let latest = matchingSets.first else { return nil }
        return cal.startOfDay(for: latest.timestamp)
    }

    static func sessionFatigueHint(
        primaryMuscles: [String],
        sessions: [WorkoutSession],
        now: Date = Date()
    ) -> String? {
        var worstMuscle: String?
        var worstFreshness = 100.0

        for muscle in primaryMuscles {
            let freshness = muscleFreshness(for: muscle, now: now, sessions: sessions)
            if freshness < worstFreshness {
                worstFreshness = freshness
                worstMuscle = muscle
            }
        }

        guard let muscle = worstMuscle, worstFreshness < 40 else { return nil }

        if let loadDate = lastLoadDate(for: muscle, sessions: sessions, now: now) {
            let dayName = Formatters.weekday.string(from: loadDate)
            return "\(muscle) still fatigued from \(dayName)"
        }
        return "\(muscle) still fatigued from recent training"
    }

    static func bestEstimated1RM(for exerciseName: String, in sets: [SetLog], now: Date = Date()) -> Double {
        VolumeAnalytics.bestEstimated1RM(for: exerciseName, in: sets.map(SetEntry.init), now: now)
    }
}
