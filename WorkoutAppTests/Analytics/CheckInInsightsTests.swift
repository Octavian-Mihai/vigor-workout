import Testing
import Foundation
@testable import WorkoutApp

private let calendar: Calendar = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    return cal
}()

private let origin = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))

private func day(_ offset: Int) -> Date {
    calendar.date(byAdding: .day, value: offset, to: origin)!
}

private func sample(
    _ offset: Int,
    sleep: Int? = nil,
    mood: Int? = nil,
    energy: Int? = nil,
    lastCaffeine: Int? = nil,
    hours: Double? = nil
) -> CheckInSample {
    CheckInSample(date: day(offset), sleep: sleep, mood: mood, energy: energy, lastCaffeine: lastCaffeine, sleepHours: hours)
}

struct CheckInInsightsTests {
    @Test func longerSleepFollowedByHighEnergyIsSurfaced() {
        // Hours slept alternate 8 / 5.5; energy follows, with a little variation inside each group.
        let samples = (0..<24).map { d -> CheckInSample in
            let long = d % 2 == 0
            let wobble = (d / 2) % 2
            return sample(d, mood: 3, energy: (long ? 4 : 2) + wobble, hours: long ? 8 : 5.5)
        }

        let insights = CheckInInsights.analyze(samples: samples, trainedDays: [], calendar: calendar)
        let found = insights.first { $0.driver == .sleepHours && $0.outcome == .energy }

        #expect(found?.isPositive == true)
        #expect(found?.headline == "Energy is higher after 6h+ of sleep")
        #expect(found?.confidence == .pattern)
        #expect(!insights.contains { $0.outcome == .mood })
    }

    @Test func selfRatedSleepIsNeverUsedToExplainMoodOrEnergy() {
        // Sleep rating and mood move together, but both are self-reports, so that isn't an insight.
        let samples = (0..<24).map { d -> CheckInSample in
            let good = d % 2 == 0
            return sample(d, sleep: good ? 5 : 1, mood: good ? 5 : 1, energy: good ? 5 : 1)
        }
        #expect(CheckInInsights.analyze(samples: samples, trainedDays: [], calendar: calendar).isEmpty)
    }

    @Test func lateCaffeineLinksToTheFollowingNightsSleep() {
        // Last caffeine alternates between before 11 and after 6.
        var samples: [CheckInSample] = []
        for d in 0..<24 {
            let lateYesterday = d >= 1 && (d - 1) % 2 == 1
            let wobble = (d / 2) % 2
            samples.append(sample(
                d,
                sleep: (lateYesterday ? 2 : 4) - wobble,
                lastCaffeine: d % 2 == 1 ? CaffeineTiming.evening.rawValue : CaffeineTiming.morning.rawValue
            ))
        }

        let insights = CheckInInsights.analyze(samples: samples, trainedDays: [], calendar: calendar)
        let found = insights.first { $0.driver == .caffeineTiming && $0.outcome == .sleep }

        #expect(found?.lag == 1)
        #expect(found?.isPositive == false)
        #expect(found?.headline == "Sleep quality is lower after days with caffeine after 6pm")
    }

    @Test func noCaffeineCountsAsEarlierThanAnyCaffeine() {
        // No caffeine vs. a morning coffee: morning coffee is the "later" side of the split.
        var samples: [CheckInSample] = []
        for d in 0..<24 {
            let coffeeYesterday = d >= 1 && (d - 1) % 2 == 1
            let wobble = (d / 2) % 2
            samples.append(sample(
                d,
                sleep: (coffeeYesterday ? 2 : 4) - wobble,
                lastCaffeine: d % 2 == 1 ? CaffeineTiming.morning.rawValue : CaffeineTiming.none.rawValue
            ))
        }

        let found = CheckInInsights
            .analyze(samples: samples, trainedDays: [], calendar: calendar)
            .first { $0.outcome == .sleep && $0.driver == .caffeineTiming }

        #expect(found?.isPositive == false)
        #expect(found?.headline == "Sleep quality is lower after days with caffeine")
    }

    @Test func trainingDaysComeFromWorkoutDataNotTheCheckIn() {
        // Trained every third day; energy is higher the day after. Training isn't part of the check-in itself.
        let trained = Set((0..<30).filter { $0 % 3 == 0 }.map(day))
        let samples = (1..<30).map { d -> CheckInSample in
            let afterTraining = (d - 1) % 3 == 0
            let wobble = (d / 3) % 2
            return sample(d, energy: (afterTraining ? 4 : 2) + wobble)
        }

        let insights = CheckInInsights.analyze(samples: samples, trainedDays: trained, calendar: calendar)
        let found = insights.first { $0.driver == .training && $0.outcome == .energy && $0.lag == 1 }

        #expect(found?.isPositive == true)
        #expect(found?.headline == "Energy is higher the day after training")
    }

    @Test func hrvDropsTheDayAfterTrainingAndIsFlaggedUnfavourable() {
        // Trained every third day; HRV the next morning is lower. No check-in answers needed for this one.
        let trained = Set((0..<30).filter { $0 % 3 == 0 }.map(day))
        let hrv = Dictionary(uniqueKeysWithValues: (1..<30).map { d -> (Date, Double) in
            let afterTraining = (d - 1) % 3 == 0
            return (day(d), (afterTraining ? 45 : 60) + Double((d / 3) % 3))
        })
        let samples = CheckInInsights.merging([sample(1, mood: 3)], hrv: hrv, restingHR: [:], sleepHours: [:], calendar: calendar)

        let found = CheckInInsights
            .analyze(samples: samples, trainedDays: trained, calendar: calendar)
            .first { $0.driver == .training && $0.outcome == .hrv }

        #expect(found?.lag == 1)
        #expect(found?.isPositive == false)
        #expect(found?.isFavourable == false)
        #expect(found?.headline == "HRV is lower the day after training")
        #expect(found?.formattedDifference == "−15")
    }

    @Test func aLowerRestingHeartRateCountsAsFavourable() {
        // Longer sleep goes with a lower resting heart rate.
        let rhr = Dictionary(uniqueKeysWithValues: (0..<24).map { d -> (Date, Double) in
            (day(d), (d % 2 == 0 ? 52 : 60) + Double((d / 2) % 2))
        })
        let hours = Dictionary(uniqueKeysWithValues: (0..<24).map { d -> (Date, Double) in
            (day(d), d % 2 == 0 ? 8 : 5.5)
        })
        let samples = CheckInInsights.merging([], hrv: [:], restingHR: rhr, sleepHours: hours, calendar: calendar)

        let found = CheckInInsights
            .analyze(samples: samples, trainedDays: [], calendar: calendar)
            .first { $0.driver == .sleepHours && $0.outcome == .restingHR }

        #expect(found?.isPositive == false)
        #expect(found?.isFavourable == true)
        #expect(found?.headline == "Resting heart rate is lower after 6h+ of sleep")
    }

    @Test func healthDataFillsMissingSleepHoursButNeverOverridesTheCheckIn() {
        let merged = CheckInInsights.merging(
            [sample(0, hours: 6), sample(1)],
            hrv: [:], restingHR: [:], sleepHours: [day(0): 8, day(1): 7.5, day(2): 7],
            calendar: calendar
        )
        let byDay = Dictionary(uniqueKeysWithValues: merged.map { ($0.date, $0) })
        #expect(byDay[day(0)]?.sleepHours == 6)
        #expect(byDay[day(1)]?.sleepHours == 7.5)
        #expect(byDay[day(2)]?.sleepHours == 7)
        // A Health-only day is a comparison day, not a logged check-in.
        #expect(CheckInInsights.loggedDayCount(merged, calendar: calendar) == 0)
    }

    @Test func tooFewDaysSurfacesNothing() {
        let samples = (0..<8).map { d in
            sample(d, sleep: d % 2 == 0 ? 5 : 1, energy: d % 2 == 0 ? 5 : 1)
        }
        #expect(CheckInInsights.analyze(samples: samples, trainedDays: [], calendar: calendar).isEmpty)
    }

    @Test func flatLogSurfacesNothing() {
        let samples = (0..<30).map { d in
            sample(d, sleep: 3, mood: 3, energy: 3, lastCaffeine: d % 2, hours: 7)
        }
        #expect(CheckInInsights.analyze(samples: samples, trainedDays: [day(1), day(5)], calendar: calendar).isEmpty)
    }

    @Test func sleepHoursSplitOnAHalfHourBoundary() {
        // 5.5h and 8h nights; mood tracks them.
        let samples = (0..<24).map { d -> CheckInSample in
            let long = d % 2 == 0
            let wobble = (d / 2) % 2
            return sample(d, mood: (long ? 4 : 2) + wobble, hours: long ? 8 : 5.5)
        }
        let found = CheckInInsights
            .analyze(samples: samples, trainedDays: [], calendar: calendar)
            .first { $0.driver == .sleepHours && $0.outcome == .mood }

        #expect(found != nil)
        #expect(found?.headline.contains("h+ of sleep") == true)
    }

    @Test func streakCountsConsecutiveLoggedDaysAndForgivesToday() {
        let samples = [sample(-1, mood: 3), sample(-2, mood: 4), sample(-3, energy: 2), sample(-5, mood: 3)]
        #expect(CheckInInsights.currentStreak(samples, today: day(0), calendar: calendar) == 3)

        let withToday = samples + [sample(0, sleep: 4)]
        #expect(CheckInInsights.currentStreak(withToday, today: day(0), calendar: calendar) == 4)

        #expect(CheckInInsights.currentStreak([], today: day(0), calendar: calendar) == 0)
        #expect(CheckInInsights.currentStreak([sample(-4, mood: 3)], today: day(0), calendar: calendar) == 0)
    }

    @Test func caffeineAloneDoesNotCountAsALoggedDay() {
        let samples = [sample(0, lastCaffeine: 2), sample(-1, mood: 3)]
        #expect(CheckInInsights.loggedDayCount(samples, calendar: calendar) == 1)
    }

    @Test func averagesCompareTheLastWeekWithTheOneBefore() {
        var samples: [CheckInSample] = []
        for back in 0..<7 { samples.append(sample(-back, mood: 4)) }
        for back in 7..<14 { samples.append(sample(-back, mood: 2)) }

        let mood = CheckInInsights.average(.mood, in: samples, endingOn: day(0), days: 7, calendar: calendar)
        #expect(mood.current == 4)
        #expect(mood.previous == 2)
        #expect(mood.delta == 2)

        let energy = CheckInInsights.average(.energy, in: samples, endingOn: day(0), days: 7, calendar: calendar)
        #expect(energy.current == nil)
        #expect(energy.delta == nil)
    }

    @Test func ratingsAreClampedToTheScale() {
        #expect(CheckInScale.clampedRating(0) == 1)
        #expect(CheckInScale.clampedRating(9) == 5)
        #expect(CheckInScale.clampedRating(3) == 3)
    }
}
