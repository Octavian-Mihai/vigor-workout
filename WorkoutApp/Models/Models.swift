import SwiftData
import Foundation

enum MuscleCSV {
    static func encode(_ muscles: [String]) -> String {
        muscles.joined(separator: ",")
    }

    static func decode(_ raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

enum SessionSource {
    static let programmed = "programmed"
    static let empty = "empty"
}

@Model
final class Program {
    var uuid: UUID
    var name: String
    var isActive: Bool
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \ProgramDay.program)
    var days: [ProgramDay]

    init(name: String, isActive: Bool = false) {
        self.uuid = UUID()
        self.name = name
        self.isActive = isActive
        self.createdAt = Date()
        self.days = []
    }

    var orderedDays: [ProgramDay] {
        days.sorted { $0.sortIndex < $1.sortIndex }
    }
}

@Model
final class ProgramDay {
    var uuid: UUID
    var name: String
    var sortIndex: Int
    var program: Program?

    @Relationship(deleteRule: .cascade, inverse: \DayExercise.day)
    var exercises: [DayExercise]

    init(name: String, sortIndex: Int) {
        self.uuid = UUID()
        self.name = name
        self.sortIndex = sortIndex
        self.exercises = []
    }

    var orderedExercises: [DayExercise] {
        exercises.sorted { $0.sortIndex < $1.sortIndex }
    }
}

@Model
final class DayExercise {
    var name: String
    var primaryMusclesCSV: String
    var secondaryMusclesCSV: String
    var targetSets: Int
    var targetReps: Int
    var sortIndex: Int
    var equipmentRaw: String = ""
    var restSeconds: Int? = nil
    var supersetGroupID: UUID? = nil
    var day: ProgramDay?

    init(
        name: String,
        primaryMuscles: [String],
        secondaryMuscles: [String],
        targetSets: Int,
        targetReps: Int,
        sortIndex: Int,
        equipment: ExerciseEquipment? = nil,
        supersetGroupID: UUID? = nil
    ) {
        self.name = name
        self.primaryMusclesCSV = MuscleCSV.encode(primaryMuscles)
        self.secondaryMusclesCSV = MuscleCSV.encode(secondaryMuscles)
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.sortIndex = sortIndex
        self.equipmentRaw = equipment?.rawValue ?? ExerciseEquipment.infer(from: name).rawValue
        self.supersetGroupID = supersetGroupID
    }

    var equipment: ExerciseEquipment {
        get { ExerciseEquipment.resolve(raw: equipmentRaw, name: name) }
        set { equipmentRaw = newValue.rawValue }
    }

    var primaryMuscles: [String] {
        get { MuscleCSV.decode(primaryMusclesCSV) }
        set { primaryMusclesCSV = MuscleCSV.encode(newValue) }
    }

    var secondaryMuscles: [String] {
        get { MuscleCSV.decode(secondaryMusclesCSV) }
        set { secondaryMusclesCSV = MuscleCSV.encode(newValue) }
    }
}

@Model
final class WorkoutSession {
    var uuid: UUID
    var startDate: Date
    var endDate: Date?
    var source: String
    var programUUID: UUID?
    var programDayIndex: Int?
    var programDayName: String?
    var durationSeconds: Int

    @Relationship(deleteRule: .cascade, inverse: \SetLog.session)
    var sets: [SetLog]

    init(
        startDate: Date = Date(),
        source: String,
        programUUID: UUID? = nil,
        programDayIndex: Int? = nil,
        programDayName: String? = nil
    ) {
        self.uuid = UUID()
        self.startDate = startDate
        self.endDate = nil
        self.source = source
        self.programUUID = programUUID
        self.programDayIndex = programDayIndex
        self.programDayName = programDayName
        self.durationSeconds = 0
        self.sets = []
    }

    var isProgrammed: Bool {
        source == SessionSource.programmed
    }

    var orderedSets: [SetLog] {
        sets.sorted { $0.timestamp < $1.timestamp }
    }
}

@Model
final class SetLog {
    var exerciseName: String
    var primaryMusclesCSV: String
    var secondaryMusclesCSV: String
    var weight: Double
    var reps: Int
    var rir: Int
    var targetReps: Int?
    var timestamp: Date
    var supersetGroupID: UUID? = nil
    var session: WorkoutSession?

    init(
        exerciseName: String,
        primaryMuscles: [String],
        secondaryMuscles: [String],
        weight: Double,
        reps: Int,
        rir: Int,
        targetReps: Int? = nil,
        timestamp: Date = Date(),
        supersetGroupID: UUID? = nil
    ) {
        self.exerciseName = exerciseName
        self.primaryMusclesCSV = MuscleCSV.encode(primaryMuscles)
        self.secondaryMusclesCSV = MuscleCSV.encode(secondaryMuscles)
        self.weight = weight
        self.reps = reps
        self.rir = rir
        self.targetReps = targetReps
        self.timestamp = timestamp
        self.supersetGroupID = supersetGroupID
    }

    var primaryMuscles: [String] {
        get { MuscleCSV.decode(primaryMusclesCSV) }
        set { primaryMusclesCSV = MuscleCSV.encode(newValue) }
    }

    var secondaryMuscles: [String] {
        get { MuscleCSV.decode(secondaryMusclesCSV) }
        set { secondaryMusclesCSV = MuscleCSV.encode(newValue) }
    }

    var volume: Double {
        AssistedLoad.effectiveKg(exerciseName: exerciseName, loggedKg: weight) * Double(reps)
    }
}

@Model
final class BodyWeightEntry {
    var date: Date
    var kilograms: Double

    init(date: Date = Date(), kilograms: Double) {
        self.date = date
        self.kilograms = kilograms
        AssistedLoad.noteBodyWeight(kilograms: kilograms, date: date)
    }
}

@Model
final class BodyMeasurementEntry {
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

    init(date: Date = Date()) {
        self.date = date
    }
}

/// One row per calendar day: how last night's sleep, today's mood and today's energy felt (1...5),
/// plus two quick things that may explain them. Every field is optional so a day can be half-logged.
@Model
final class DailyCheckIn {
    /// Start of the day this check-in belongs to.
    var date: Date
    var sleepRating: Int?
    var moodRating: Int?
    var energyRating: Int?
    /// `CaffeineTiming.rawValue` — when the last caffeine was (0 = none that day).
    var lastCaffeine: Int?
    /// Hours asleep last night as Apple Health reported them when this was logged.
    var sleepHours: Double?

    init(date: Date = Date()) {
        self.date = Calendar.current.startOfDay(for: date)
    }

    var loggedRatingCount: Int {
        [sleepRating, moodRating, energyRating].compactMap { $0 }.count
    }

    /// Sleep, mood, energy and last caffeine are all answered.
    var isComplete: Bool { loggedRatingCount == 3 && lastCaffeine != nil }

    var isEmpty: Bool {
        loggedRatingCount == 0 && lastCaffeine == nil
    }
}

enum CheckInScale {
    static let ratings = 1...5

    static func clampedRating(_ value: Int) -> Int {
        min(max(value, ratings.lowerBound), ratings.upperBound)
    }
}

/// When the last caffeinated drink was. Later doses are the ones that tend to cost sleep.
/// Raw values run in order of lateness, which is what the insights compare.
enum CaffeineTiming: Int, CaseIterable, Identifiable {
    case none = 0
    case morning = 1
    case midday = 2
    case afternoon = 3
    case evening = 4

    var id: Int { rawValue }

    /// Chip label.
    var label: String {
        switch self {
        case .none: return "None"
        case .morning: return "Before 11"
        case .midday: return "11–2"
        case .afternoon: return "2–6"
        case .evening: return "After 6"
        }
    }

    /// Full wording for summaries and VoiceOver.
    var spoken: String {
        switch self {
        case .none: return "No caffeine"
        case .morning: return "Before 11am"
        case .midday: return "11am–2pm"
        case .afternoon: return "2–6pm"
        case .evening: return "After 6pm"
        }
    }

    /// The clock time this window starts at, as it reads in "caffeine after 2pm".
    var startLabel: String? {
        switch self {
        case .none, .morning: return nil
        case .midday: return "11am"
        case .afternoon: return "2pm"
        case .evening: return "6pm"
        }
    }
}
