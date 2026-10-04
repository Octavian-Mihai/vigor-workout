import Foundation
import WidgetKit

enum WidgetSnapshotSync {
    @MainActor
    static func write(
        sessions: [WorkoutSession],
        programs: [Program],
        cardioWorkouts: [CardioWorkout],
        runDates: Set<Date>,
        restingHeartRate: Double?,
        maxHeartRate: Double?,
        accentHex: String,
        showsRunningActivity: Bool = true,
        showsStressAnalysis: Bool = true
    ) {
        let snapshot = makeSnapshot(
            sessions: sessions,
            programs: programs,
            cardioWorkouts: cardioWorkouts,
            runDates: runDates,
            restingHeartRate: restingHeartRate,
            maxHeartRate: maxHeartRate,
            accentHex: accentHex,
            showsRunningActivity: showsRunningActivity,
            showsStressAnalysis: showsStressAnalysis
        )
        WidgetSnapshotStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    @MainActor
    static func makeSnapshot(
        sessions: [WorkoutSession],
        programs: [Program],
        cardioWorkouts: [CardioWorkout],
        runDates: Set<Date>,
        restingHeartRate: Double?,
        maxHeartRate: Double?,
        accentHex: String,
        showsRunningActivity: Bool = true,
        showsStressAnalysis: Bool = true,
        now: Date = Date()
    ) -> WidgetSnapshot {
        let cal = Calendar.current
        let year = cal.component(.year, from: now)
        let dayOfYear = cal.ordinality(of: .day, in: .year, for: now) ?? 1
        let recentStart = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: now)) ?? now

        var liftDays: Set<TimeInterval> = []
        var liftSessionCount = 0
        var workoutsLast7Days = 0
        for session in sessions where session.endDate != nil {
            let day = cal.startOfDay(for: session.startDate)
            if cal.component(.year, from: day) == year {
                liftDays.insert(day.timeIntervalSince1970)
                liftSessionCount += 1
            }
            if day >= recentStart {
                workoutsLast7Days += 1
            }
        }

        var runDays: Set<TimeInterval> = []
        if showsRunningActivity {
            for date in runDates {
                let day = cal.startOfDay(for: date)
                if cal.component(.year, from: day) == year {
                    runDays.insert(day.timeIntervalSince1970)
                }
            }
        }

        let activityDays = liftDays.union(runDays)
        let recentActivityDays = activityDays.filter { stamp in
            let day = Date(timeIntervalSince1970: stamp)
            return day >= recentStart
        }.count

        let stressCardio = showsRunningActivity
            ? cardioWorkouts
            : cardioWorkouts.filter { $0.activityType != .running }
        let sets = sessions.flatMap(\.sets)
        let today = StressCalculator.todayEstimate(
            sets: sets,
            cardioWorkouts: stressCardio,
            restingHeartRate: restingHeartRate,
            maxHeartRate: maxHeartRate,
            now: now
        )
        let trend = StressCalculator.dailyTrend(
            sets: sets,
            cardioWorkouts: stressCardio,
            restingHeartRate: restingHeartRate,
            maxHeartRate: maxHeartRate,
            days: 7,
            now: now
        )

        let finished = sessions
            .filter { $0.endDate != nil }
            .sorted { $0.startDate > $1.startDate }
        let last = finished.first
        let lastTitle = last?.programDayName
            ?? (last == nil ? nil : (last!.isProgrammed ? "Workout" : "Empty workout"))

        let active = programs.first(where: \.isActive)
        let next = NextWorkoutResolver.nextDay(activeProgram: active, sessions: sessions)

        var weekCal = cal
        weekCal.firstWeekday = 2
        let weekStart = weekCal.dateInterval(of: .weekOfYear, for: now)?.start ?? cal.startOfDay(for: now)
        let lastWeekStart = weekCal.date(byAdding: .weekOfYear, value: -1, to: weekStart) ?? weekStart
        var weekVolume = 0.0
        var lastWeekVolume = 0.0
        for session in finished {
            let volume = session.sets.reduce(0) { $0 + $1.volume }
            if session.startDate >= weekStart {
                weekVolume += volume
            } else if session.startDate >= lastWeekStart {
                lastWeekVolume += volume
            }
        }

        var cycleNumber: Int?
        var cycleVsBaseline: Double?
        if let active {
            let entries = finished
                .filter { $0.isProgrammed && $0.programUUID == active.uuid && $0.programDayIndex != nil && !$0.sets.isEmpty }
                .map { CycleSession(date: $0.startDate, dayIndex: $0.programDayIndex ?? 0, volumeKg: $0.sets.reduce(0) { $0 + $1.volume }) }
            let latest = ProgramCycleAnalytics.cycles(from: entries, dayCount: active.days.count)
                .last { $0.isComplete && $0.percentVsBaseline != nil }
            cycleNumber = latest?.number
            cycleVsBaseline = latest?.percentVsBaseline
        }

        return WidgetSnapshot(
            version: 1,
            updatedAt: now,
            year: year,
            dayOfYear: dayOfYear,
            liftDayStarts: Array(liftDays).sorted(),
            runDayStarts: Array(runDays).sorted(),
            activityDayCount: activityDays.count,
            liftSessionCount: liftSessionCount,
            recentActivityDays: recentActivityDays,
            todayStress: today.total,
            todayLift: today.lift,
            todayRun: today.run,
            trendTotals: trend.map(\.total),
            lastWorkoutTitle: lastTitle,
            lastWorkoutDate: last?.startDate,
            nextDayName: next?.name,
            nextProgramName: active?.name,
            accentHex: accentHex,
            workoutsLast7Days: workoutsLast7Days,
            showsRunningActivity: showsRunningActivity,
            showsStressAnalysis: showsStressAnalysis,
            weekVolumeKg: weekVolume,
            lastWeekVolumeKg: lastWeekVolume,
            cycleNumber: cycleNumber,
            cycleVsBaselinePercent: cycleVsBaseline,
            weightUnit: UserDefaults.standard.string(forKey: "weightUnit") ?? "lb"
        )
    }
}
