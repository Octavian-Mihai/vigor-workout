import Testing
import Foundation
import SwiftData
@testable import WorkoutApp

@MainActor
private func makeInMemoryContext() throws -> ModelContext {
    let schema = Schema([
        Program.self,
        ProgramDay.self,
        DayExercise.self,
        WorkoutSession.self,
        SetLog.self,
        BodyWeightEntry.self,
        BodyMeasurementEntry.self,
        DailyCheckIn.self
    ])
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [configuration])
    return ModelContext(container)
}

@Suite("SwiftData integration", .serialized)
@MainActor
struct SwiftDataIntegrationTests {
    @Test("deleting a Program cascades to its days and exercises")
    func deletingProgramCascadesToDaysAndExercises() throws {
        let context = try makeInMemoryContext()

        let program = Program(name: "PPL")
        context.insert(program)
        let day = ProgramDay(name: "Push", sortIndex: 0)
        day.program = program
        context.insert(day)
        let exercise = DayExercise(
            name: "Bench Press",
            primaryMuscles: ["Chest"],
            secondaryMuscles: ["Triceps"],
            targetSets: 3,
            targetReps: 8,
            sortIndex: 0
        )
        exercise.day = day
        context.insert(exercise)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<ProgramDay>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<DayExercise>()).count == 1)

        context.delete(program)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Program>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ProgramDay>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<DayExercise>()).isEmpty)
    }

    @Test("deleting a WorkoutSession cascades to its SetLogs")
    func deletingSessionCascadesToSets() throws {
        let context = try makeInMemoryContext()

        let session = WorkoutSession(source: SessionSource.empty)
        context.insert(session)
        let set = SetLog(exerciseName: "Row", primaryMuscles: ["Lats"], secondaryMuscles: [], weight: 60, reps: 10, rir: 2)
        set.session = session
        context.insert(set)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<SetLog>()).count == 1)

        context.delete(session)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<WorkoutSession>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<SetLog>()).isEmpty)
    }

    @Test("orderedDays/orderedExercises/orderedSets sort by their index/timestamp regardless of insertion order")
    func orderedAccessorsSortAfterFetch() throws {
        let context = try makeInMemoryContext()

        let program = Program(name: "PPL")
        context.insert(program)
        let dayB = ProgramDay(name: "Second", sortIndex: 1)
        dayB.program = program
        context.insert(dayB)
        let dayA = ProgramDay(name: "First", sortIndex: 0)
        dayA.program = program
        context.insert(dayA)
        try context.save()

        let fetchedProgram = try #require(try context.fetch(FetchDescriptor<Program>()).first)
        #expect(fetchedProgram.orderedDays.map(\.name) == ["First", "Second"])

        let session = WorkoutSession(source: SessionSource.empty)
        context.insert(session)
        let later = SetLog(exerciseName: "A", primaryMuscles: [], secondaryMuscles: [], weight: 1, reps: 1, rir: 0, timestamp: Date(timeIntervalSince1970: 200))
        later.session = session
        context.insert(later)
        let earlier = SetLog(exerciseName: "B", primaryMuscles: [], secondaryMuscles: [], weight: 1, reps: 1, rir: 0, timestamp: Date(timeIntervalSince1970: 100))
        earlier.session = session
        context.insert(earlier)
        try context.save()

        let fetchedSession = try #require(try context.fetch(FetchDescriptor<WorkoutSession>()).first)
        #expect(fetchedSession.orderedSets.map(\.exerciseName) == ["B", "A"])
    }

    @Test("volume analytics run correctly over SetLogs fetched from a persisted context")
    func analyticsOverFetchedSets() throws {
        let context = try makeInMemoryContext()

        let session = WorkoutSession(source: SessionSource.empty)
        context.insert(session)
        let bench = SetLog(exerciseName: "Bench Press", primaryMuscles: ["Chest"], secondaryMuscles: ["Triceps"], weight: 100, reps: 5, rir: 2)
        bench.session = session
        context.insert(bench)
        let row = SetLog(exerciseName: "Row", primaryMuscles: ["Lats"], secondaryMuscles: [], weight: 60, reps: 10, rir: 1)
        row.session = session
        context.insert(row)
        try context.save()

        let fetchedSets = try context.fetch(FetchDescriptor<SetLog>())
        let entries = fetchedSets.map(SetEntry.init)

        #expect(VolumeAnalytics.totalVolume(from: entries) == 1_100)
        let volume = VolumeAnalytics.muscleVolume(from: entries)
        #expect(volume["Chest"] == 500)
        #expect(volume["Triceps"] == 250)
        #expect(volume["Lats"] == 600)
    }

    @Test("importBackup wires up program/day/exercise and session/set relationships correctly")
    func importBackupWiresRelationships() throws {
        let context = try makeInMemoryContext()

        let backup = WorkoutBackupFile(
            version: 2,
            exportedAt: Date(),
            programs: [
                ProgramBackup(
                    uuid: UUID(),
                    name: "PPL",
                    isActive: true,
                    createdAt: Date(),
                    days: [
                        DayBackup(
                            uuid: UUID(),
                            name: "Push",
                            sortIndex: 0,
                            exercises: [
                                ExerciseBackup(
                                    name: "Bench Press",
                                    primaryMuscles: ["Chest"],
                                    secondaryMuscles: ["Triceps"],
                                    targetSets: 3,
                                    targetReps: 8,
                                    sortIndex: 0,
                                    equipment: "Barbell"
                                )
                            ]
                        )
                    ]
                )
            ],
            sessions: [],
            bodyWeights: [],
            measurements: []
        )

        try WorkoutBackupService.importBackup(
            backup,
            context: context,
            existingPrograms: [],
            existingSessions: [],
            existingWeights: []
        )

        let programs = try context.fetch(FetchDescriptor<Program>())
        #expect(programs.count == 1)
        let program = try #require(programs.first)
        #expect(program.orderedDays.count == 1)
        let day = try #require(program.orderedDays.first)
        #expect(day.program === program)
        #expect(day.orderedExercises.count == 1)
        #expect(day.orderedExercises.first?.day === day)
    }

    @Test("importBackup does not duplicate programs or sessions whose UUID already exists")
    func importBackupSkipsExistingUUIDs() throws {
        let context = try makeInMemoryContext()

        let existingProgram = Program(name: "PPL")
        context.insert(existingProgram)
        try context.save()

        let backup = WorkoutBackupFile(
            version: 2,
            exportedAt: Date(),
            programs: [
                ProgramBackup(uuid: existingProgram.uuid, name: "PPL (duplicate payload)", isActive: false, createdAt: Date(), days: [])
            ],
            sessions: [],
            bodyWeights: [],
            measurements: []
        )

        try WorkoutBackupService.importBackup(
            backup,
            context: context,
            existingPrograms: [existingProgram],
            existingSessions: [],
            existingWeights: []
        )

        #expect(try context.fetch(FetchDescriptor<Program>()).count == 1)
    }

    @Test("importBackup skips a body weight entry already present on the same day within tolerance")
    func importBackupSkipsDuplicateBodyWeight() throws {
        let context = try makeInMemoryContext()

        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let existingWeight = BodyWeightEntry(date: day, kilograms: 82.5)
        context.insert(existingWeight)
        try context.save()

        let backup = WorkoutBackupFile(
            version: 2,
            exportedAt: Date(),
            programs: [],
            sessions: [],
            bodyWeights: [BodyWeightBackup(date: day.addingTimeInterval(60), kilograms: 82.52)],
            measurements: []
        )

        try WorkoutBackupService.importBackup(
            backup,
            context: context,
            existingPrograms: [],
            existingSessions: [],
            existingWeights: [existingWeight]
        )

        #expect(try context.fetch(FetchDescriptor<BodyWeightEntry>()).count == 1)
    }

    // MARK: - Daily check-in

    @Test("the first answer creates the day's check-in and later answers update the same row")
    func checkInStoreKeepsOneRowPerDay() throws {
        let context = try makeInMemoryContext()
        let today = Date()

        CheckInStore.update(on: today, in: context) { $0.moodRating = 4 }
        CheckInStore.update(on: today.addingTimeInterval(60), in: context) { $0.energyRating = 3 }

        let entries = try context.fetch(FetchDescriptor<DailyCheckIn>())
        #expect(entries.count == 1)
        #expect(entries.first?.moodRating == 4)
        #expect(entries.first?.energyRating == 3)
        #expect(entries.first?.isComplete == false)
    }

    @Test("clearing the only answer removes the check-in instead of leaving a blank row")
    func checkInStoreRemovesEmptyEntry() throws {
        let context = try makeInMemoryContext()

        CheckInStore.update(on: Date(), in: context) { $0.moodRating = 4 }
        CheckInStore.update(on: Date(), in: context) { $0.moodRating = nil }

        #expect(try context.fetch(FetchDescriptor<DailyCheckIn>()).isEmpty)
    }

    @Test("import ignores a last-caffeine value outside the scale and clamps ratings")
    func importSanitisesCaffeineAndRatings() throws {
        let context = try makeInMemoryContext()
        let backup = WorkoutBackupFile(
            version: 2, exportedAt: Date(), programs: [], sessions: [], bodyWeights: [], measurements: [],
            checkIns: [
                CheckInBackup(date: Date(timeIntervalSince1970: 1_700_000_000), sleepRating: 9, moodRating: 3, energyRating: nil,
                              lastCaffeine: 42, sleepHours: nil)
            ]
        )
        try WorkoutBackupService.importBackup(backup, context: context, existingPrograms: [], existingSessions: [], existingWeights: [])

        let imported = try #require(try context.fetch(FetchDescriptor<DailyCheckIn>()).first)
        #expect(imported.sleepRating == 5)
        #expect(imported.lastCaffeine == nil)
    }

    @Test("Apple Health sleep hours are attached to today's check-in but never overwrite or leak onto past days")
    func checkInStoreAttachesSleepHoursOnlyToToday() throws {
        let context = try makeInMemoryContext()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!

        CheckInStore.update(on: Date(), in: context, healthSleepHours: 7.5) { $0.sleepRating = 4 }
        CheckInStore.update(on: yesterday, in: context, healthSleepHours: 7.5) { $0.sleepRating = 3 }
        CheckInStore.attachSleepHours(5, to: Date(), in: context)

        let today = try #require(CheckInStore.entry(on: Date(), in: context))
        let past = try #require(CheckInStore.entry(on: yesterday, in: context))
        #expect(today.sleepHours == 7.5)
        #expect(past.sleepHours == nil)
    }

    @Test("check-ins survive a backup round trip, skip days already logged, and old backups still decode")
    func checkInsRoundTripThroughBackup() throws {
        let source = try makeInMemoryContext()
        let day = Date(timeIntervalSince1970: 1_700_000_000)

        let entry = DailyCheckIn(date: day)
        entry.sleepRating = 4
        entry.moodRating = 5
        entry.energyRating = 3
        entry.lastCaffeine = CaffeineTiming.afternoon.rawValue
        entry.sleepHours = 7.25
        source.insert(entry)
        source.insert(DailyCheckIn(date: day.addingTimeInterval(-86_400)))
        try source.save()

        let file = WorkoutBackupService.make(
            programs: [], sessions: [], weights: [],
            checkIns: try source.fetch(FetchDescriptor<DailyCheckIn>())
        )
        // The untouched second row has no answers, so it isn't exported.
        #expect(file.checkIns?.count == 1)

        let decoded = try WorkoutBackupService.decode(try WorkoutBackupService.encode(file))
        let destination = try makeInMemoryContext()
        try WorkoutBackupService.importBackup(
            decoded, context: destination,
            existingPrograms: [], existingSessions: [], existingWeights: []
        )

        let imported = try #require(try destination.fetch(FetchDescriptor<DailyCheckIn>()).first)
        #expect(imported.sleepRating == 4)
        #expect(imported.moodRating == 5)
        #expect(imported.energyRating == 3)
        #expect(imported.lastCaffeine == CaffeineTiming.afternoon.rawValue)
        #expect(imported.sleepHours == 7.25)

        try WorkoutBackupService.importBackup(
            decoded, context: destination,
            existingPrograms: [], existingSessions: [], existingWeights: [],
            existingCheckIns: try destination.fetch(FetchDescriptor<DailyCheckIn>())
        )
        #expect(try destination.fetch(FetchDescriptor<DailyCheckIn>()).count == 1)

        let withoutCheckIns = WorkoutBackupService.make(programs: [], sessions: [], weights: [])
        #expect(withoutCheckIns.checkIns == nil)
        let json = String(decoding: try WorkoutBackupService.encode(withoutCheckIns), as: UTF8.self)
        #expect(!json.contains("checkIns"))
    }

    @Test("a day counts as trained only when a session has sets in it")
    func trainedDaysIgnoreEmptySessions() throws {
        let context = try makeInMemoryContext()
        let calendar = Calendar.current
        let lifted = WorkoutSession(startDate: Date(timeIntervalSince1970: 1_700_000_000), source: SessionSource.empty)
        let abandoned = WorkoutSession(startDate: Date(timeIntervalSince1970: 1_700_000_000 + 3 * 86_400), source: SessionSource.empty)
        context.insert(lifted)
        context.insert(abandoned)
        let set = SetLog(exerciseName: "Row", primaryMuscles: ["Lats"], secondaryMuscles: [], weight: 60, reps: 10, rir: 2)
        set.session = lifted
        context.insert(set)
        try context.save()

        let days = CheckInInsights.trainedDays(sessions: [lifted, abandoned], cardio: [])
        #expect(days == [calendar.startOfDay(for: lifted.startDate)])
    }
}
