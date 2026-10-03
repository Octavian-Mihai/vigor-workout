import Testing
import Foundation
@testable import WorkoutApp

private let calendar: Calendar = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    return cal
}()

private func date(_ day: Int, hour: Int, minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
}

struct CheckInReminderTests {
    private let eightPM = 20 * 60

    @Test func startsTodayWhenTheTimeIsStillAhead() {
        let dates = CheckInReminder.fireDates(now: date(3, hour: 9), minutesIntoDay: eightPM, skipToday: false, days: 3, calendar: calendar)
        #expect(dates == [date(3, hour: 20), date(4, hour: 20), date(5, hour: 20)])
    }

    @Test func startsTomorrowOnceTodaysTimeHasPassed() {
        let dates = CheckInReminder.fireDates(now: date(3, hour: 21), minutesIntoDay: eightPM, skipToday: false, days: 2, calendar: calendar)
        #expect(dates == [date(4, hour: 20), date(5, hour: 20)])
    }

    @Test func skipsTodayOnceTheCheckInIsDone() {
        let dates = CheckInReminder.fireDates(now: date(3, hour: 9), minutesIntoDay: eightPM, skipToday: true, days: 2, calendar: calendar)
        #expect(dates == [date(4, hour: 20), date(5, hour: 20)])
    }

    @Test func honoursMinutesNotJustHours() {
        let dates = CheckInReminder.fireDates(now: date(3, hour: 6), minutesIntoDay: 7 * 60 + 45, skipToday: false, days: 1, calendar: calendar)
        #expect(dates == [date(3, hour: 7, minute: 45)])
    }

    @Test func schedulesTheWholeWindowAndClampsBadTimes() {
        let dates = CheckInReminder.fireDates(now: date(3, hour: 9), minutesIntoDay: 99_999, skipToday: false, calendar: calendar)
        #expect(dates.count == CheckInReminder.scheduleDays)
        #expect(dates.first == date(3, hour: 23, minute: 59))
    }

    @Test func zeroDaysSchedulesNothing() {
        #expect(CheckInReminder.fireDates(now: date(3, hour: 9), minutesIntoDay: eightPM, skipToday: false, days: 0, calendar: calendar).isEmpty)
    }
}
