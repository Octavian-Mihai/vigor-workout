import Foundation

struct WeeklyTrainingLoad: Identifiable {
    let weekStart: Date
    let tonnageKg: Double
    let setCount: Int
    let repCount: Int

    var id: Date { weekStart }
}

/// Pure volume/tonnage/1RM/intensity math over `SetEntry`. No SwiftData, no SwiftUI.
enum VolumeAnalytics {
    static func setVolume(_ set: SetEntry) -> Double {
        set.weight * Double(set.reps)
    }

    /// Primary muscles get full volume; secondary muscles get half.
    static func muscleVolume(from sets: [SetEntry]) -> [String: Double] {
        var result: [String: Double] = [:]
        for set in sets {
            let vol = setVolume(set)
            for muscle in set.primaryMuscles {
                result[muscle, default: 0] += vol
            }
            for muscle in set.secondaryMuscles {
                result[muscle, default: 0] += vol * 0.5
            }
        }
        return result
    }

    /// Primary muscles get full reps; secondary muscles get half.
    static func muscleReps(from sets: [SetEntry]) -> [String: Double] {
        var result: [String: Double] = [:]
        for set in sets {
            let reps = Double(set.reps)
            for muscle in set.primaryMuscles {
                result[muscle, default: 0] += reps
            }
            for muscle in set.secondaryMuscles {
                result[muscle, default: 0] += reps * 0.5
            }
        }
        return result
    }

    static func totalVolume(from sets: [SetEntry]) -> Double {
        sets.reduce(0) { $0 + setVolume($1) }
    }

    static func totalReps(from sets: [SetEntry]) -> Int {
        sets.reduce(0) { $0 + $1.reps }
    }

    static func sets(inLastDays days: Double, from sets: [SetEntry], now: Date = Date()) -> [SetEntry] {
        let cutoff = now.addingTimeInterval(-days * 86_400)
        return sets.filter { $0.timestamp >= cutoff }
    }

    static func weekStartContaining(_ date: Date, calendar: Calendar = Calendar.current) -> Date {
        var cal = calendar
        cal.firstWeekday = 2
        return cal.dateInterval(of: .weekOfYear, for: date)?.start ?? cal.startOfDay(for: date)
    }

    static func weeklyTrainingLoad(from sets: [SetEntry], weeks: Int = 12, now: Date = Date()) -> [WeeklyTrainingLoad] {
        var cal = Calendar.current
        cal.firstWeekday = 2
        guard let currentWeekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start,
              let earliestWeekStart = cal.date(byAdding: .weekOfYear, value: -(weeks - 1), to: currentWeekStart) else {
            return []
        }

        var buckets: [Date: (tonnage: Double, sets: Int, reps: Int)] = [:]
        for set in sets {
            let week = weekStartContaining(set.timestamp, calendar: cal)
            guard week >= earliestWeekStart else { continue }
            var bucket = buckets[week, default: (0, 0, 0)]
            bucket.tonnage += setVolume(set)
            bucket.sets += 1
            bucket.reps += set.reps
            buckets[week] = bucket
        }

        var result: [WeeklyTrainingLoad] = []
        result.reserveCapacity(weeks)
        for offset in 0..<weeks {
            guard let week = cal.date(byAdding: .weekOfYear, value: offset, to: earliestWeekStart) else { continue }
            let bucket = buckets[week] ?? (0, 0, 0)
            result.append(
                WeeklyTrainingLoad(
                    weekStart: week,
                    tonnageKg: bucket.tonnage,
                    setCount: bucket.sets,
                    repCount: bucket.reps
                )
            )
        }
        return result
    }

    /// Per-muscle daily load 0–100 using primary 100% / secondary 50% volume weighting.
    static func muscleDailyLoad(from sets: [SetEntry]) -> [String: Double] {
        let volumeByMuscle = muscleVolume(from: sets)
        var result: [String: Double] = [:]
        for (muscle, volume) in volumeByMuscle {
            let muscleSets = sets.filter {
                $0.primaryMuscles.contains(muscle) || $0.secondaryMuscles.contains(muscle)
            }
            let intensities = muscleSets.map { max(0, 5.0 - Double(min($0.rir, 5))) / 5.0 }
            let avgIntensity = intensities.isEmpty ? 0 : intensities.reduce(0, +) / Double(intensities.count)
            let volumeScore = min(60.0, volume / 400.0)
            result[muscle] = min(100, volumeScore + avgIntensity * 40.0)
        }
        return result
    }

    static func bestEstimated1RM(for exerciseName: String, in sets: [SetEntry], now: Date = Date()) -> Double {
        let cutoff = now.addingTimeInterval(-90 * 86_400)
        let family = BigLift.allCases.first { $0.matches(exerciseName) }
        let candidates = sets.filter { set in
            guard set.timestamp >= cutoff, set.weight > 0, set.reps > 0 else { return false }
            if let family {
                return family.matches(set.exerciseName)
            }
            return set.exerciseName.compare(exerciseName, options: .caseInsensitive) == .orderedSame
        }
        return candidates.map { OneRM.estimate(weight: $0.weight, reps: $0.reps, rir: $0.rir) }.max() ?? 0
    }
}
