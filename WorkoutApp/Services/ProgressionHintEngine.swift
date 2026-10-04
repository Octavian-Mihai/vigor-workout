import Foundation

struct ProgressionSuggestion: Equatable {
    let weightKg: Double
    let reps: Int
}

enum ProgressionHintEngine {
    static func suggest(
        setIndex: Int,
        previousSessionSets: [SetLog],
        currentSessionSets: [DraftSet],
        targetReps: Int?,
        unit: WeightUnit,
        lowerIsHarder: Bool = false
    ) -> ProgressionSuggestion? {
        let incrementKg = unit.toKg(unit == .kg ? 2.5 : 5.0)
        let resolvedTarget = targetReps
            ?? previousSessionSets[safe: setIndex]?.reps
            ?? currentSessionSets.last?.reps
            ?? 8

        let referenceSet: (weightKg: Double, reps: Int, rir: Int)? = {
            if setIndex < currentSessionSets.count {
                let set = currentSessionSets[setIndex]
                return (set.weightKg, set.reps, set.rir)
            }
            if let previous = previousSessionSets[safe: setIndex] {
                return (previous.weight, previous.reps, previous.rir)
            }
            if let last = currentSessionSets.last {
                return (last.weightKg, last.reps, last.rir)
            }
            if let last = previousSessionSets.last {
                return (last.weight, last.reps, last.rir)
            }
            return nil
        }()

        guard let reference = referenceSet else { return nil }

        let priorSets = currentSessionSets.prefix(setIndex)
        if !priorSets.isEmpty {
            let allHitTarget = priorSets.allSatisfy { $0.reps >= resolvedTarget && $0.rir <= 2 }
            let anyZeroRIR = priorSets.contains { $0.rir == 0 }
            let anyMissed = priorSets.contains { $0.reps < resolvedTarget }

            if anyZeroRIR {
                return ProgressionSuggestion(weightKg: reference.weightKg, reps: resolvedTarget)
            }
            if anyMissed {
                let eased = lowerIsHarder ? reference.weightKg + incrementKg : max(reference.weightKg - incrementKg, 0)
                return ProgressionSuggestion(
                    weightKg: eased > 0 ? eased : reference.weightKg,
                    reps: resolvedTarget
                )
            }
            if allHitTarget {
                let harder = lowerIsHarder ? max(reference.weightKg - incrementKg, 0) : reference.weightKg + incrementKg
                return ProgressionSuggestion(
                    weightKg: harder,
                    reps: resolvedTarget
                )
            }
        }

        return ProgressionSuggestion(weightKg: reference.weightKg, reps: resolvedTarget)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
