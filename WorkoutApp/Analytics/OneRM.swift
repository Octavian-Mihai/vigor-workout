import Foundation

/// Assisted pull-ups/dips are logged as the counterweight the machine takes off, so a smaller number is harder.
/// Progress, PRs and volume use the load actually lifted: body weight minus the assistance.
enum AssistedLoad {
    static let bodyWeightKey = "latestBodyWeightKg"

    static func isAssisted(_ exerciseName: String) -> Bool {
        exerciseName.lowercased().contains("assisted")
    }

    static var bodyWeightKg: Double? {
        let value = UserDefaults.standard.double(forKey: bodyWeightKey)
        return value > 0 ? value : nil
    }

    static let bodyWeightDateKey = "latestBodyWeightDate"

    /// Remembers the most recent body weight so pure analytics code can read it without a database query.
    static func noteBodyWeight(kilograms: Double, date: Date) {
        let defaults = UserDefaults.standard
        let stored = defaults.double(forKey: bodyWeightDateKey)
        guard kilograms > 0, date.timeIntervalSince1970 >= stored else { return }
        defaults.set(kilograms, forKey: bodyWeightKey)
        defaults.set(date.timeIntervalSince1970, forKey: bodyWeightDateKey)
    }

    /// Weight to feed into volume / 1RM maths. Unchanged for ordinary lifts; 0 when body weight is unknown.
    static func effectiveKg(exerciseName: String, loggedKg: Double) -> Double {
        guard isAssisted(exerciseName) else { return loggedKg }
        guard let bodyWeight = bodyWeightKg else { return 0 }
        return max(bodyWeight - loggedKg, 0)
    }
}

enum OneRM {
    static func estimate(exerciseName: String, weight: Double, reps: Int, rir: Int) -> Double {
        estimate(
            weight: AssistedLoad.effectiveKg(exerciseName: exerciseName, loggedKg: weight),
            reps: reps,
            rir: rir
        )
    }

    /// Epley with RIR counted as extra reps: weight × (1 + (reps + RIR) / 30)
    static func estimate(weight: Double, reps: Int, rir: Int) -> Double {
        let extra = Double(max(reps, 0) + max(rir, 0))
        return weight * (1.0 + extra / 30.0)
    }
}

enum BigLift: String, CaseIterable, Identifiable {
    case squat = "Squat"
    case bench = "Bench"
    case deadlift = "Deadlift"
    case ohp = "OHP"
    case row = "Row"

    var id: String { rawValue }

    func matches(_ exerciseName: String) -> Bool {
        let n = exerciseName.lowercased()
        switch self {
        case .squat:
            return n.contains("squat") && !n.contains("split") && !n.contains("hack")
        case .bench:
            return n.contains("bench")
        case .deadlift:
            return n.contains("deadlift")
                && !n.contains("romanian")
                && !n.contains("rdl")
                && !n.contains("stiff")
        case .ohp:
            return n.contains("overhead press")
                || n.contains("ohp")
                || n.contains("military press")
                || (n.contains("shoulder press") && !n.contains("dumbbell"))
        case .row:
            return n.contains("row") && !n.contains("face")
        }
    }
}
