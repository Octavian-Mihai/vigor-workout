import Foundation

/// A program day reduced to what the advisor needs: which muscles it loads, and how heavily.
struct TrainDayPlan: Equatable {
    let name: String
    let index: Int
    /// Muscle name → relative weight (sets; secondary muscles count half).
    let muscleWeights: [String: Double]
}

extension TrainDayPlan {
    init(day: ProgramDay) {
        var weights: [String: Double] = [:]
        for exercise in day.orderedExercises {
            let sets = Double(max(exercise.targetSets, 1))
            for muscle in exercise.primaryMuscles { weights[muscle, default: 0] += sets }
            for muscle in exercise.secondaryMuscles { weights[muscle, default: 0] += sets * 0.5 }
        }
        self.init(name: day.name, index: day.sortIndex, muscleWeights: weights)
    }
}

struct TrainTodayAdvice: Equatable {
    enum Kind: Equatable {
        /// The planned day is a good fit — nothing to change.
        case followPlan
        /// A different program day is clearly fresher than the planned one.
        case switchDay(index: Int, name: String)
        /// Everything is still recovering.
        case rest
        /// No program: just say what's ready and what isn't.
        case muscleFocus
    }

    let kind: Kind
    let headline: String
    let detail: String?
}

/// Picks what to train today from per-muscle freshness (0–100, 100 = fully recovered).
enum TrainTodayAdvisor {
    static let readyThreshold = 60.0
    static let tiredThreshold = 45.0
    /// A different day must beat the planned one by this many points before it's suggested.
    static let switchMargin = 12.0

    static func advise(days: [TrainDayPlan], plannedIndex: Int?, freshness: [String: Double]) -> TrainTodayAdvice? {
        guard !days.isEmpty else { return muscleFocus(freshness: freshness) }

        let scored = days.map { (plan: $0, score: score($0, freshness: freshness)) }
        guard let best = scored.max(by: { $0.score < $1.score }) else { return nil }
        let planned = scored.first { $0.plan.index == plannedIndex } ?? best

        if best.score < tiredThreshold + 5 {
            return TrainTodayAdvice(
                kind: .rest,
                headline: "Still recovering",
                detail: "Every day in your plan hits muscles that are still fatigued. A rest day, mobility or easy cardio fits today."
            )
        }

        if planned.plan.index != best.plan.index, best.score - planned.score >= switchMargin {
            let tired = tiredMuscles(planned.plan, freshness: freshness)
            let plannedNote = tired.isEmpty
                ? "\(planned.plan.name) is \(Int(planned.score.rounded()))% fresh"
                : "\(list(tired).capitalizedFirst) still recovering"
            return TrainTodayAdvice(
                kind: .switchDay(index: best.plan.index, name: best.plan.name),
                headline: "\(best.plan.name) fits better today",
                detail: "\(plannedNote) · \(best.plan.name) is \(Int(best.score.rounded()))% fresh."
            )
        }

        let focus = list(topMuscles(planned.plan))
        return TrainTodayAdvice(
            kind: .followPlan,
            headline: "\(planned.plan.name) is a good fit",
            detail: focus.isEmpty ? nil : "\(focus.capitalizedFirst) \(focus.contains(",") || focus.contains(" and ") ? "are" : "is") \(Int(planned.score.rounded()))% fresh."
        )
    }

    /// Weighted mean freshness of the muscles a day loads.
    static func score(_ plan: TrainDayPlan, freshness: [String: Double]) -> Double {
        var total = 0.0
        var weight = 0.0
        for (muscle, w) in plan.muscleWeights {
            total += (freshness[muscle] ?? 100) * w
            weight += w
        }
        return weight > 0 ? total / weight : 100
    }

    private static func muscleFocus(freshness: [String: Double]) -> TrainTodayAdvice? {
        let big: [MuscleGroup] = [.chest, .lats, .anteriorDelts, .lateralDelts, .quadriceps, .hamstrings, .glutes, .biceps, .triceps]
        let ready = big.filter { (freshness[$0.rawValue] ?? 100) >= 70 }
        let tired = big.filter { (freshness[$0.rawValue] ?? 100) < tiredThreshold }
        guard !ready.isEmpty || !tired.isEmpty else { return nil }
        if ready.isEmpty {
            return TrainTodayAdvice(kind: .rest, headline: "Still recovering", detail: "Most big muscle groups are fatigued. Take it easy today.")
        }
        let detail = tired.isEmpty ? nil : "Still recovering: \(list(tired.map(\.compactName)))."
        return TrainTodayAdvice(
            kind: .muscleFocus,
            headline: "Ready today: \(list(ready.prefix(4).map(\.compactName)))",
            detail: detail
        )
    }

    private static func tiredMuscles(_ plan: TrainDayPlan, freshness: [String: Double]) -> [String] {
        plan.muscleWeights
            .filter { (freshness[$0.key] ?? 100) < tiredThreshold }
            .sorted { $0.value > $1.value }
            .prefix(2)
            .map { display($0.key) }
    }

    private static func topMuscles(_ plan: TrainDayPlan) -> [String] {
        plan.muscleWeights
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(2)
            .map { display($0.key) }
    }

    private static func display(_ muscle: String) -> String {
        (MuscleGroup(rawValue: muscle)?.compactName ?? muscle).lowercased()
    }

    private static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default: return items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
        }
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
