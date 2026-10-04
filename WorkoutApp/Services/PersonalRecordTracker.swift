import Foundation

struct LiftPRBestSet {
    let exerciseName: String
    let weightKg: Double
    let reps: Int
    let rir: Int
    let date: Date
    let e1RMKg: Double
}

struct LiftPersonalRecord: Identifiable {
    let lift: BigLift
    let bestE1RMKg: Double?
    let bestSet: LiftPRBestSet?
    /// Projected next e1RM from recent session trend. Nil when there is no honest upward trend.
    let projectedE1RMKg: Double?

    var id: String { lift.id }
}

enum PersonalRecordTracker {
    static func bestEstimate(for exerciseName: String, in sessions: [WorkoutSession]) -> Double? {
        matchingSets(named: exerciseName, in: sessions)
            .map { OneRM.estimate(exerciseName: $0.exerciseName, weight: $0.weight, reps: $0.reps, rir: $0.rir) }
            .max()
    }

    static func isNewPR(
        weightKg: Double,
        reps: Int,
        rir: Int,
        exerciseName: String,
        sessions: [WorkoutSession]
    ) -> Bool {
        let estimate = OneRM.estimate(exerciseName: exerciseName, weight: weightKg, reps: reps, rir: rir)
        guard estimate > 0 else { return false }
        guard let best = bestEstimate(for: exerciseName, in: sessions) else { return true }
        return estimate > best + 0.001
    }

    static func summaries(in sessions: [WorkoutSession]) -> [LiftPersonalRecord] {
        BigLift.allCases.map { summary(for: $0, in: sessions) }
    }

    static func summary(for lift: BigLift, in sessions: [WorkoutSession]) -> LiftPersonalRecord {
        let finished = sessions.filter { $0.endDate != nil }.sorted { $0.startDate < $1.startDate }
        var bestSet: LiftPRBestSet?
        var sessionBests: [Double] = []

        for session in finished {
            let matching = session.orderedSets.filter {
                lift.matches($0.exerciseName) && $0.weight > 0 && $0.reps > 0
            }
            guard !matching.isEmpty else { continue }

            let sessionBest = matching.max { lhs, rhs in
                OneRM.estimate(weight: lhs.weight, reps: lhs.reps, rir: lhs.rir)
                    < OneRM.estimate(weight: rhs.weight, reps: rhs.reps, rir: rhs.rir)
            }!
            let e1RM = OneRM.estimate(weight: sessionBest.weight, reps: sessionBest.reps, rir: sessionBest.rir)
            sessionBests.append(e1RM)

            if bestSet == nil || e1RM > (bestSet?.e1RMKg ?? 0) {
                bestSet = LiftPRBestSet(
                    exerciseName: sessionBest.exerciseName,
                    weightKg: sessionBest.weight,
                    reps: sessionBest.reps,
                    rir: sessionBest.rir,
                    date: session.endDate ?? session.startDate,
                    e1RMKg: e1RM
                )
            }
        }

        let bestE1RM = bestSet?.e1RMKg
        let projected = projectedNextE1RM(sessionBests: sessionBests, currentBest: bestE1RM ?? 0)

        return LiftPersonalRecord(
            lift: lift,
            bestE1RMKg: bestE1RM,
            bestSet: bestSet,
            projectedE1RMKg: projected
        )
    }

    /// Linear trend of recent session e1RMs, one workout ahead. Returns nil unless the trend is clearly up.
    static func projectedNextE1RM(sessionBests: [Double], currentBest: Double) -> Double? {
        let recent = Array(sessionBests.suffix(6))
        guard recent.count >= 3 else { return nil }
        guard let last = recent.last, let previous = recent.dropLast().last else { return nil }
        // A fresh dip is not a PR projection.
        guard last + 0.01 >= previous * 0.97 else { return nil }

        let n = Double(recent.count)
        let xs = recent.indices.map(Double.init)
        let sumX = xs.reduce(0, +)
        let sumY = recent.reduce(0, +)
        let sumXY = zip(xs, recent).reduce(0.0) { $0 + $1.0 * $1.1 }
        let sumX2 = xs.reduce(0.0) { $0 + $1 * $1 }
        let denom = n * sumX2 - sumX * sumX
        guard abs(denom) > 0.0001 else { return nil }

        let slope = (n * sumXY - sumX * sumY) / denom
        guard slope > 0.25 else { return nil }

        let raw = last + slope
        let capped = min(raw, last * 1.05, last + 7.5)
        guard capped > currentBest + 0.25 else { return nil }
        return capped
    }

    private static func matchingSets(named exerciseName: String, in sessions: [WorkoutSession]) -> [SetLog] {
        sessions
            .filter { $0.endDate != nil }
            .flatMap(\.orderedSets)
            .filter { $0.exerciseName.compare(exerciseName, options: .caseInsensitive) == .orderedSame }
            .filter { $0.weight > 0 && $0.reps > 0 }
    }
}
