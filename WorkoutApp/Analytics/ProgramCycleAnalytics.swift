import Foundation

struct CycleSession {
    let date: Date
    let dayIndex: Int
    let volumeKg: Double
}

struct ProgramCycleVolume: Identifiable {
    let number: Int
    let startDate: Date
    let volumeKg: Double
    let sessionCount: Int
    let isComplete: Bool
    /// Change vs. the first cycle (the baseline). Nil for the baseline itself.
    let percentVsBaseline: Double?
    /// Change vs. the cycle before this one. Nil for the baseline itself.
    let percentVsPrevious: Double?

    var id: Int { number }
}

/// Splits a program's sessions into cycles (one pass through the rotating days) and
/// compares each cycle's volume with the first one. Pure; no SwiftData, no SwiftUI.
enum ProgramCycleAnalytics {
    static func cycles(from sessions: [CycleSession], dayCount: Int) -> [ProgramCycleVolume] {
        let ordered = sessions.sorted { $0.date < $1.date }
        var groups: [[CycleSession]] = []
        for session in ordered {
            // A day index that doesn't move forward means the rotation wrapped: new cycle.
            if let last = groups.last?.last, session.dayIndex <= last.dayIndex {
                groups.append([session])
            } else if groups.isEmpty {
                groups.append([session])
            } else {
                groups[groups.count - 1].append(session)
            }
        }

        var result: [ProgramCycleVolume] = []
        for (offset, group) in groups.enumerated() {
            let volume = group.reduce(0) { $0 + $1.volumeKg }
            let isLast = offset == groups.count - 1
            let complete = !isLast || (dayCount > 0 && group.count >= dayCount)
            let baseline = result.first?.volumeKg ?? 0
            let previous = result.last?.volumeKg ?? 0
            result.append(
                ProgramCycleVolume(
                    number: offset + 1,
                    startDate: group[0].date,
                    volumeKg: volume,
                    sessionCount: group.count,
                    isComplete: complete,
                    percentVsBaseline: offset == 0 || baseline <= 0 ? nil : (volume / baseline - 1) * 100,
                    percentVsPrevious: offset == 0 || previous <= 0 ? nil : (volume / previous - 1) * 100
                )
            )
        }
        return result
    }
}
