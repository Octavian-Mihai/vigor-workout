import Testing
import Foundation
@testable import WorkoutApp

private func set(_ name: String, _ weight: Double, _ reps: Int, rir: Int = 0) -> SetEntry {
    SetEntry(exerciseName: name, primaryMuscles: [], secondaryMuscles: [], weight: weight, reps: reps, rir: rir, timestamp: Date())
}

struct PRDetectorTests {
    @Test func beatingAnEarlierBestIsAPRWithItsGain() {
        let prs = PRDetector.sessionPRs(
            sessionSets: [set("Bench Press", 100, 5), set("Bench Press", 90, 5)],
            previousSets: [set("bench press", 95, 5)]
        )
        #expect(prs.count == 1)
        #expect(prs.first?.exerciseName == "Bench Press")
        #expect(prs.first?.weightKg == 100)
        #expect((prs.first?.gainKg ?? 0) > 0)
    }

    @Test func aFirstEverLogIsABaselineNotARecord() {
        #expect(PRDetector.sessionPRs(sessionSets: [set("Squat", 140, 5)], previousSets: []).isEmpty)
    }

    @Test func matchingOrLoweringYourBestIsNotAPR() {
        let prs = PRDetector.sessionPRs(sessionSets: [set("Row", 80, 8)], previousSets: [set("Row", 85, 8)])
        #expect(prs.isEmpty)
    }

    @Test func prsAreOrderedByBiggestRelativeGain() {
        let prs = PRDetector.sessionPRs(
            sessionSets: [set("A", 101, 5), set("B", 120, 5)],
            previousSets: [set("A", 100, 5), set("B", 100, 5)]
        )
        #expect(prs.map(\.exerciseName) == ["B", "A"])
    }

    @Test func bodyweightSetsWithNoLoadNeverCount() {
        #expect(PRDetector.sessionPRs(sessionSets: [set("Pull-up", 0, 12)], previousSets: [set("Pull-up", 0, 8)]).isEmpty)
    }

    @Test func celebrationNeedsHistoryAndANewHighForThisSession() {
        #expect(PRDetector.celebratedPreviousBest(estimate: 120, pastBest: nil, sessionBest: nil) == nil)
        #expect(PRDetector.celebratedPreviousBest(estimate: 110, pastBest: 100, sessionBest: nil) == 100)
        // Same top set again, or a lower one, after already celebrating this session.
        #expect(PRDetector.celebratedPreviousBest(estimate: 110, pastBest: 100, sessionBest: 110) == nil)
        #expect(PRDetector.celebratedPreviousBest(estimate: 105, pastBest: 100, sessionBest: 110) == nil)
        #expect(PRDetector.celebratedPreviousBest(estimate: 115, pastBest: 100, sessionBest: 110) == 100)
        #expect(PRDetector.celebratedPreviousBest(estimate: 90, pastBest: 100, sessionBest: nil) == nil)
    }
}

struct TrainTodayAdvisorTests {
    private let push = TrainDayPlan(name: "Push", index: 0, muscleWeights: ["Chest": 8, "Triceps": 4, "Anterior Delts": 3])
    private let legs = TrainDayPlan(name: "Legs", index: 1, muscleWeights: ["Quadriceps": 8, "Hamstrings": 4, "Glutes": 4])

    @Test func followsThePlanWhenTheDayIsFresh() {
        let advice = TrainTodayAdvisor.advise(days: [push, legs], plannedIndex: 0, freshness: [:])
        #expect(advice?.kind == .followPlan)
        #expect(advice?.headline == "Push is a good fit")
    }

    @Test func suggestsAFresherDayWhenThePlannedOneIsTired() {
        let freshness: [String: Double] = ["Chest": 30, "Triceps": 35, "Anterior Delts": 40]
        let advice = TrainTodayAdvisor.advise(days: [push, legs], plannedIndex: 0, freshness: freshness)
        #expect(advice?.kind == .switchDay(index: 1, name: "Legs"))
        #expect(advice?.detail?.contains("still recovering") == true)
    }

    @Test func smallDifferencesDoNotTriggerASwitch() {
        let freshness: [String: Double] = ["Chest": 75, "Triceps": 75, "Anterior Delts": 75, "Quadriceps": 85, "Hamstrings": 85, "Glutes": 85]
        #expect(TrainTodayAdvisor.advise(days: [push, legs], plannedIndex: 0, freshness: freshness)?.kind == .followPlan)
    }

    @Test func saysRestWhenEveryDayIsFatigued() {
        let tired: [String: Double] = ["Chest": 20, "Triceps": 20, "Anterior Delts": 20, "Quadriceps": 25, "Hamstrings": 25, "Glutes": 25]
        #expect(TrainTodayAdvisor.advise(days: [push, legs], plannedIndex: 0, freshness: tired)?.kind == .rest)
    }

    @Test func withoutAProgramItListsReadyAndRecoveringMuscles() {
        let advice = TrainTodayAdvisor.advise(days: [], plannedIndex: nil, freshness: ["Quadriceps": 30, "Hamstrings": 30, "Glutes": 30])
        #expect(advice?.kind == .muscleFocus)
        #expect(advice?.headline.hasPrefix("Ready today:") == true)
        #expect(advice?.detail?.contains("Quadriceps") == true)
    }
}

struct DeloadAdvisorTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func steady() -> DeloadInputs {
        var inputs = DeloadInputs(now: now)
        inputs.sessionDates = (0..<8).map { now.addingTimeInterval(-Double($0) * 3 * 86_400) }
        return inputs
    }

    @Test func staysQuietWithoutRecentTraining() {
        var inputs = DeloadInputs(now: now)
        inputs.recentStress = [80, 80, 80, 80, 80]
        inputs.hrvRecent = 40; inputs.hrvBaseline = 60
        #expect(DeloadAdvisor.assess(inputs) == nil)
    }

    @Test func aSingleStrongSignalIsNotEnough() {
        var inputs = steady()
        inputs.recentStress = [70, 72, 68, 75, 71]
        #expect(DeloadAdvisor.assess(inputs) == nil)
    }

    @Test func highFatigueAndLowHRVTogetherSuggestADeload() {
        var inputs = steady()
        inputs.recentStress = [70, 72, 68, 75, 71]
        inputs.hrvRecent = 45; inputs.hrvBaseline = 60
        let assessment = DeloadAdvisor.assess(inputs)
        #expect(assessment != nil)
        #expect(assessment?.reasons.count == 2)
        #expect(assessment?.reasons.last?.contains("25%") == true)
    }

    @Test func slippingStrengthOnTwoLiftsPlusARisingRestingHRSuggestsOne() {
        var inputs = steady()
        inputs.liftSessionBests = ["Bench": [100, 104, 103, 101, 99], "Squat": [150, 155, 152, 150, 148]]
        inputs.restingHRRecent = 61; inputs.restingHRBaseline = 56
        let assessment = DeloadAdvisor.assess(inputs)
        #expect(assessment?.reasons.first == "Estimated strength has slipped on Bench and Squat.")
    }

    @Test func improvingLiftsAreNotSlipping() {
        #expect(!DeloadAdvisor.isSlipping([100, 102, 104, 106]))
        #expect(!DeloadAdvisor.isSlipping([100, 101, 100]))
        #expect(DeloadAdvisor.isSlipping([100, 104, 102, 101, 99]))
    }

    @Test func aLighterWeekBreaksTheBlock() {
        #expect(DeloadAdvisor.noLighterWeek([10, 11, 10, 12, 11]))
        #expect(!DeloadAdvisor.noLighterWeek([10, 11, 5, 12, 11]))
        #expect(!DeloadAdvisor.noLighterWeek([10, 11, 0, 12, 11]))
        #expect(!DeloadAdvisor.noLighterWeek([10, 11, 12]))
    }
}
