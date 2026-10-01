import Testing
import Foundation
@testable import WorkoutApp

private func session(_ day: Int, _ dayIndex: Int, _ volume: Double) -> CycleSession {
    CycleSession(date: Date(timeIntervalSince1970: Double(day) * 86_400), dayIndex: dayIndex, volumeKg: volume)
}

struct ProgramCycleAnalyticsTests {
    @Test func firstCycleIsBaselineAndLaterCyclesCompare() {
        let sessions = [
            session(1, 0, 1000), session(2, 1, 1000),
            session(8, 0, 1100), session(9, 1, 1100),
            session(15, 0, 1000), session(16, 1, 1000)
        ]
        let cycles = ProgramCycleAnalytics.cycles(from: sessions, dayCount: 2)
        #expect(cycles.count == 3)
        #expect(cycles[0].percentVsBaseline == nil)
        #expect(abs(cycles[1].percentVsBaseline! - 10) < 0.001)
        #expect(abs(cycles[1].percentVsPrevious! - 10) < 0.001)
        #expect(abs(cycles[2].percentVsBaseline! - 0) < 0.001)
        #expect(cycles[2].percentVsPrevious! < 0)
    }

    @Test func lastPartialCycleIsIncomplete() {
        let sessions = [session(1, 0, 500), session(2, 1, 500), session(8, 0, 500)]
        let cycles = ProgramCycleAnalytics.cycles(from: sessions, dayCount: 2)
        #expect(cycles[0].isComplete)
        #expect(!cycles[1].isComplete)
    }

    @Test func noSessionsMeansNoCycles() {
        #expect(ProgramCycleAnalytics.cycles(from: [], dayCount: 3).isEmpty)
    }
}
