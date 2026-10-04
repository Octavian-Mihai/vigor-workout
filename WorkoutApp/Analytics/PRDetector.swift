import Foundation

/// A lift where this session beat the best estimated 1RM from every earlier session.
struct SessionPR: Identifiable, Equatable {
    let exerciseName: String
    let weightKg: Double
    let reps: Int
    let newE1RMKg: Double
    let previousE1RMKg: Double

    var id: String { exerciseName.lowercased() }
    var gainKg: Double { newE1RMKg - previousE1RMKg }
    var gainFraction: Double { previousE1RMKg > 0 ? gainKg / previousE1RMKg : 0 }
}

/// Pure PR logic over `SetEntry`. A first-ever log of a lift is a baseline, not a record, so it never counts.
enum PRDetector {
    /// PRs a finished session set, biggest relative gain first.
    static func sessionPRs(sessionSets: [SetEntry], previousSets: [SetEntry]) -> [SessionPR] {
        let previousBest = bestByExercise(previousSets)
        var best: [String: (set: SetEntry, e1RM: Double)] = [:]
        var order: [String] = []

        for set in sessionSets where set.weight > 0 && set.reps > 0 {
            let key = set.exerciseName.lowercased()
            let estimate = OneRM.estimate(exerciseName: set.exerciseName, weight: set.weight, reps: set.reps, rir: set.rir)
            if let current = best[key] {
                if estimate > current.e1RM { best[key] = (set, estimate) }
            } else {
                best[key] = (set, estimate)
                order.append(key)
            }
        }

        return order
            .compactMap { key -> SessionPR? in
                guard let top = best[key], let previous = previousBest[key], top.e1RM > previous + 0.001 else { return nil }
                return SessionPR(
                    exerciseName: top.set.exerciseName,
                    weightKg: AssistedLoad.effectiveKg(exerciseName: top.set.exerciseName, loggedKg: top.set.weight),
                    reps: top.set.reps,
                    newE1RMKg: top.e1RM,
                    previousE1RMKg: previous
                )
            }
            .sorted { $0.gainFraction > $1.gainFraction }
    }

    /// For the set just logged: the all-time previous best if this set deserves a celebration, otherwise nil.
    /// It must beat the all-time best *and* anything already lifted earlier in this session, so three
    /// ascending sets celebrate once each, but repeating the same top weight doesn't celebrate again.
    /// With no history at all there's nothing to beat, so no celebration.
    static func celebratedPreviousBest(estimate: Double, pastBest: Double?, sessionBest: Double?) -> Double? {
        guard let pastBest else { return nil }
        let bar = max(pastBest, sessionBest ?? 0)
        return estimate > bar + 0.001 ? pastBest : nil
    }

    private static func bestByExercise(_ sets: [SetEntry]) -> [String: Double] {
        var result: [String: Double] = [:]
        for set in sets where set.weight > 0 && set.reps > 0 {
            let key = set.exerciseName.lowercased()
            let estimate = OneRM.estimate(exerciseName: set.exerciseName, weight: set.weight, reps: set.reps, rir: set.rir)
            result[key] = max(result[key] ?? 0, estimate)
        }
        return result
    }
}
