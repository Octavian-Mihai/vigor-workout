import Foundation

enum Formatters {
    static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    static let dayMonth: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    static let month: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return f
    }()

    static func duration(_ seconds: Int) -> String {
        let s = max(seconds, 0)
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, sec)
        }
        return String(format: "%d:%02d", m, sec)
    }

    /// Like `duration`, but shows an em dash when the length is unknown (0).
    static func workoutDuration(_ seconds: Int) -> String {
        seconds > 0 ? duration(seconds) : "—"
    }

    static func duration(_ interval: TimeInterval) -> String {
        duration(Int(interval.rounded()))
    }

    static func pace(_ minutesPerUnit: Double, unit: DistanceUnit = .km) -> String {
        guard minutesPerUnit.isFinite, minutesPerUnit > 0 else { return "—" }
        let minutes = Int(minutesPerUnit)
        let seconds = Int((minutesPerUnit - Double(minutes)) * 60)
        return String(format: "%d:%02d /%@", minutes, seconds, unit.title)
    }

    static func distance(_ meters: Double, unit: DistanceUnit) -> String {
        String(format: "%.2f %@", unit.fromMeters(meters), unit.title)
    }

    static func compactNumber(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.1fk", value / 1000)
        }
        if value >= 100 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }

    static func trimmedNumber(_ value: Double, decimals: Int = 2) -> String {
        let raw = String(format: "%.\(max(decimals, 0))f", value)
        guard let dot = raw.firstIndex(of: ".") else { return raw }
        var fraction = String(raw[raw.index(after: dot)...])
        let integer = String(raw[..<dot])
        while fraction.last == "0" {
            fraction.removeLast()
        }
        return fraction.isEmpty ? integer : "\(integer).\(fraction)"
    }
}

/// Planned session length from exercise and set counts — an estimate, not a timer.
/// Matches the app's default rest (90s) plus ~45s of work per set, and ~1 min per lift to set up.
enum WorkoutDurationEstimate {
    static let restSecondsPerSet = 90
    static let workSecondsPerSet = 45
    static let setupMinutesPerExercise = 1.0

    static var minutesPerSet: Double {
        Double(restSecondsPerSet + workSecondsPerSet) / 60.0
    }

    static func minutes(exerciseCount: Int, totalSets: Int) -> Int? {
        let exercises = max(exerciseCount, 0)
        let sets = max(totalSets, 0)
        guard exercises > 0 || sets > 0 else { return nil }
        let raw = (Double(sets) * minutesPerSet) + (Double(exercises) * setupMinutesPerExercise)
        return Int(raw.rounded())
    }

    static func label(exerciseCount: Int, totalSets: Int) -> String? {
        guard let minutes = minutes(exerciseCount: exerciseCount, totalSets: totalSets) else { return nil }
        return "~\(minutes) min"
    }

    static func caption(exerciseCount: Int, totalSets: Int) -> String {
        let word = exerciseCount == 1 ? "exercise" : "exercises"
        let base = "\(max(exerciseCount, 0)) \(word)"
        if let estimate = label(exerciseCount: exerciseCount, totalSets: totalSets) {
            return "\(base) · \(estimate)"
        }
        return base
    }
}
