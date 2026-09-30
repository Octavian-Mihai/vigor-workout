import Foundation
import SwiftData
import UniformTypeIdentifiers
import CoreTransferable

struct WorkoutBackupFile: Codable, Equatable, Transferable {
    var version: Int
    var exportedAt: Date
    var programs: [ProgramBackup]
    var sessions: [SessionBackup]
    var bodyWeights: [BodyWeightBackup]
    var measurements: [MeasurementBackup]
    /// Cardio sessions come from Apple Health; exported for reference, never re-imported.
    var cardio: [CardioBackup]? = nil
    /// The exporter's app colours, so the coach portal can match them.
    var theme: ThemeBackup? = nil
    /// Day boundaries used by the app's stress model; the portal buckets days in this zone.
    var timeZone: String? = nil
    var restingHeartRate: Double? = nil
    var maxHeartRate: Double? = nil

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { file in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("workout-data.json")
            let data = try WorkoutBackupService.encode(file)
            try data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

struct ProgramBackup: Codable, Equatable {
    var uuid: UUID
    var name: String
    var isActive: Bool
    var createdAt: Date
    var days: [DayBackup]
}

struct DayBackup: Codable, Equatable {
    var uuid: UUID
    var name: String
    var sortIndex: Int
    var exercises: [ExerciseBackup]
}

struct ExerciseBackup: Codable, Equatable {
    var name: String
    var primaryMuscles: [String]
    var secondaryMuscles: [String]
    var targetSets: Int
    var targetReps: Int
    var sortIndex: Int
    var equipment: String?
    var restSeconds: Int? = nil
    var supersetGroupID: UUID? = nil
}

struct SessionBackup: Codable, Equatable {
    var uuid: UUID
    var startDate: Date
    var endDate: Date?
    var source: String
    var programUUID: UUID?
    var programDayIndex: Int?
    var programDayName: String?
    var durationSeconds: Int
    var sets: [SetBackup]
}

struct SetBackup: Codable, Equatable {
    var exerciseName: String
    var primaryMuscles: [String]
    var secondaryMuscles: [String]
    var weight: Double
    var reps: Int
    var rir: Int
    var targetReps: Int?
    var timestamp: Date
}

struct BodyWeightBackup: Codable, Equatable {
    var date: Date
    var kilograms: Double
}

struct ThemeBackup: Codable, Equatable {
    var accentHex: String
    var backgroundHex: String
    var cardHex: String
    var isDark: Bool
}

struct CardioBackup: Codable, Equatable {
    var start: Date
    var end: Date
    var sport: String
    var durationSeconds: Int
    var distanceKm: Double
    var averageHeartRate: Double?
    var elevationGainMeters: Double?
    /// Cardio stress exactly as the app calculates it (uses the exporter's resting and max heart rate).
    var stress: Double? = nil
}

struct MeasurementBackup: Codable, Equatable {
    var date: Date
    var photoFilename: String?
    var kilograms: Double?
    var caloriesKcal: Int?
    var heightCm: Double?
    var neckCm: Double?
    var shouldersCm: Double?
    var chestCm: Double?
    var leftBicepsCm: Double?
    var rightBicepsCm: Double?
    var leftForearmCm: Double?
    var rightForearmCm: Double?
    var waistCm: Double?
    var hipsCm: Double?
    var leftThighCm: Double?
    var rightThighCm: Double?
    var leftCalfCm: Double?
    var rightCalfCm: Double?
}

enum WorkoutBackupService {
    static func programBackup(from program: Program) -> ProgramBackup {
        ProgramBackup(
            uuid: program.uuid,
            name: program.name,
            isActive: program.isActive,
            createdAt: program.createdAt,
            days: program.orderedDays.map { day in
                DayBackup(
                    uuid: day.uuid,
                    name: day.name,
                    sortIndex: day.sortIndex,
                    exercises: day.orderedExercises.map { item in
                        ExerciseBackup(
                            name: item.name,
                            primaryMuscles: item.primaryMuscles,
                            secondaryMuscles: item.secondaryMuscles,
                            targetSets: item.targetSets,
                            targetReps: item.targetReps,
                            sortIndex: item.sortIndex,
                            equipment: item.equipmentRaw,
                            restSeconds: item.restSeconds,
                            supersetGroupID: item.supersetGroupID
                        )
                    }
                )
            }
        )
    }

    static func measurementBackup(from entry: BodyMeasurementEntry) -> MeasurementBackup {
        MeasurementBackup(
            date: entry.date,
            photoFilename: entry.photoFilename,
            kilograms: entry.kilograms,
            caloriesKcal: entry.caloriesKcal,
            heightCm: entry.heightCm,
            neckCm: entry.neckCm,
            shouldersCm: entry.shouldersCm,
            chestCm: entry.chestCm,
            leftBicepsCm: entry.leftBicepsCm,
            rightBicepsCm: entry.rightBicepsCm,
            leftForearmCm: entry.leftForearmCm,
            rightForearmCm: entry.rightForearmCm,
            waistCm: entry.waistCm,
            hipsCm: entry.hipsCm,
            leftThighCm: entry.leftThighCm,
            rightThighCm: entry.rightThighCm,
            leftCalfCm: entry.leftCalfCm,
            rightCalfCm: entry.rightCalfCm
        )
    }

    static func make(
        programs: [Program],
        sessions: [WorkoutSession],
        weights: [BodyWeightEntry],
        measurements: [BodyMeasurementEntry] = []
    ) -> WorkoutBackupFile {
        WorkoutBackupFile(
            version: 2,
            exportedAt: Date(),
            programs: programs.map { programBackup(from: $0) },
            sessions: sessions.map { session in
                SessionBackup(
                    uuid: session.uuid,
                    startDate: session.startDate,
                    endDate: session.endDate,
                    source: session.source,
                    programUUID: session.programUUID,
                    programDayIndex: session.programDayIndex,
                    programDayName: session.programDayName,
                    durationSeconds: session.durationSeconds,
                    sets: session.orderedSets.map { log in
                        SetBackup(
                            exerciseName: log.exerciseName,
                            primaryMuscles: log.primaryMuscles,
                            secondaryMuscles: log.secondaryMuscles,
                            weight: log.weight,
                            reps: log.reps,
                            rir: log.rir,
                            targetReps: log.targetReps,
                            timestamp: log.timestamp
                        )
                    }
                )
            },
            bodyWeights: weights.map { BodyWeightBackup(date: $0.date, kilograms: $0.kilograms) },
            measurements: measurements.map { measurementBackup(from: $0) }
        )
    }

    static func cardioBackup(from run: CardioWorkout, restingHeartRate: Double?, maxHeartRate: Double?) -> CardioBackup {
        CardioBackup(
            start: run.start,
            end: run.end,
            sport: run.sportLabel,
            durationSeconds: Int(run.duration),
            distanceKm: run.distanceKilometers,
            averageHeartRate: run.averageHeartRate,
            elevationGainMeters: run.elevationGainMeters,
            stress: run.stress(restingHeartRate: restingHeartRate, maxHeartRate: maxHeartRate)
        )
    }

    static func encode(_ backup: WorkoutBackupFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(backup)
    }

    static func decode(_ data: Data) throws -> WorkoutBackupFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let backup = try? decoder.decode(WorkoutBackupFile.self, from: data) {
            return backup
        }
        struct LegacyWorkoutBackupFile: Codable {
            var version: Int
            var exportedAt: Date
            var programs: [ProgramBackup]
            var sessions: [SessionBackup]
            var bodyWeights: [BodyWeightBackup]
        }
        let legacy = try decoder.decode(LegacyWorkoutBackupFile.self, from: data)
        return WorkoutBackupFile(
            version: legacy.version,
            exportedAt: legacy.exportedAt,
            programs: legacy.programs,
            sessions: legacy.sessions,
            bodyWeights: legacy.bodyWeights,
            measurements: []
        )
    }

    @MainActor
    static func importBackup(
        _ backup: WorkoutBackupFile,
        context: ModelContext,
        existingPrograms: [Program],
        existingSessions: [WorkoutSession],
        existingWeights: [BodyWeightEntry],
        existingMeasurements: [BodyMeasurementEntry] = []
    ) throws {
        let existingProgramIDs = Set(existingPrograms.map(\.uuid))
        let existingSessionIDs = Set(existingSessions.map(\.uuid))
        let importedHasActive = backup.programs.contains(where: \.isActive)

        if importedHasActive {
            for program in existingPrograms where program.isActive {
                program.isActive = false
            }
        }

        for program in backup.programs where !existingProgramIDs.contains(program.uuid) {
            let model = Program(name: program.name, isActive: program.isActive)
            model.uuid = program.uuid
            model.createdAt = program.createdAt
            context.insert(model)
            for day in program.days {
                let dayModel = ProgramDay(name: day.name, sortIndex: day.sortIndex)
                dayModel.uuid = day.uuid
                dayModel.program = model
                context.insert(dayModel)
                for item in day.exercises {
                    let equipment = ExerciseEquipment.resolve(raw: item.equipment, name: item.name)
                    let exercise = DayExercise(
                        name: item.name,
                        primaryMuscles: item.primaryMuscles,
                        secondaryMuscles: item.secondaryMuscles,
                        targetSets: item.targetSets,
                        targetReps: item.targetReps,
                        sortIndex: item.sortIndex,
                        equipment: equipment
                    )
                    exercise.restSeconds = item.restSeconds
                    exercise.supersetGroupID = item.supersetGroupID
                    exercise.day = dayModel
                    context.insert(exercise)
                }
            }
        }

        for session in backup.sessions where !existingSessionIDs.contains(session.uuid) {
            let model = WorkoutSession(
                startDate: session.startDate,
                source: session.source,
                programUUID: session.programUUID,
                programDayIndex: session.programDayIndex,
                programDayName: session.programDayName
            )
            model.uuid = session.uuid
            model.endDate = session.endDate
            model.durationSeconds = session.durationSeconds
            context.insert(model)
            for log in session.sets {
                let set = SetLog(
                    exerciseName: log.exerciseName,
                    primaryMuscles: log.primaryMuscles,
                    secondaryMuscles: log.secondaryMuscles,
                    weight: log.weight,
                    reps: log.reps,
                    rir: log.rir,
                    targetReps: log.targetReps,
                    timestamp: log.timestamp
                )
                set.session = model
                context.insert(set)
            }
        }

        let calendar = Calendar.current
        for weight in backup.bodyWeights {
            let exists = existingWeights.contains { entry in
                calendar.isDate(entry.date, inSameDayAs: weight.date)
                    && abs(entry.kilograms - weight.kilograms) < 0.05
            }
            if !exists {
                context.insert(BodyWeightEntry(date: weight.date, kilograms: weight.kilograms))
            }
        }

        for measurement in backup.measurements {
            let exists = existingMeasurements.contains { entry in
                calendar.isDate(entry.date, inSameDayAs: measurement.date)
            }
            if !exists {
                let model = BodyMeasurementEntry(date: measurement.date)
                model.photoFilename = measurement.photoFilename
                model.kilograms = measurement.kilograms
                model.caloriesKcal = measurement.caloriesKcal
                model.heightCm = measurement.heightCm
                model.neckCm = measurement.neckCm
                model.shouldersCm = measurement.shouldersCm
                model.chestCm = measurement.chestCm
                model.leftBicepsCm = measurement.leftBicepsCm
                model.rightBicepsCm = measurement.rightBicepsCm
                model.leftForearmCm = measurement.leftForearmCm
                model.rightForearmCm = measurement.rightForearmCm
                model.waistCm = measurement.waistCm
                model.hipsCm = measurement.hipsCm
                model.leftThighCm = measurement.leftThighCm
                model.rightThighCm = measurement.rightThighCm
                model.leftCalfCm = measurement.leftCalfCm
                model.rightCalfCm = measurement.rightCalfCm
                context.insert(model)
            }
        }

        try context.save()
    }
}
