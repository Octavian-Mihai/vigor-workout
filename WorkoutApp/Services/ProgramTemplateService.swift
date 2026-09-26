import Foundation
import SwiftData
import UniformTypeIdentifiers
import CoreTransferable

struct ProgramTemplateFile: Codable, Transferable {
    var version: Int
    var exportedAt: Date
    var program: ProgramBackup

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { file in
            let sanitized = file.program.name
                .lowercased()
                .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            let filename = sanitized.isEmpty ? "program" : "program-\(sanitized)"
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(filename).json")
            let data = try ProgramTemplateService.encode(file)
            try data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

enum ProgramTemplateService {
    static func make(from program: Program) -> ProgramTemplateFile {
        ProgramTemplateFile(
            version: 1,
            exportedAt: Date(),
            program: WorkoutBackupService.programBackup(from: program)
        )
    }

    static func encode(_ file: ProgramTemplateFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(file)
    }

    static func decode(_ data: Data) throws -> ProgramTemplateFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ProgramTemplateFile.self, from: data)
    }

    @MainActor
    static func importTemplate(
        _ file: ProgramTemplateFile,
        context: ModelContext,
        existingPrograms: [Program]
    ) throws {
        let existingNames = Set(existingPrograms.map(\.name))
        var programName = file.program.name
        if existingNames.contains(programName) {
            programName += " (imported)"
        }

        let model = Program(name: programName, isActive: false)
        model.createdAt = file.program.createdAt
        context.insert(model)

        for day in file.program.days.sorted(by: { $0.sortIndex < $1.sortIndex }) {
            let dayModel = ProgramDay(name: day.name, sortIndex: day.sortIndex)
            dayModel.program = model
            context.insert(dayModel)
            for item in day.exercises.sorted(by: { $0.sortIndex < $1.sortIndex }) {
                let equipment = ExerciseEquipment.resolve(raw: item.equipment, name: item.name)
                let exercise = DayExercise(
                    name: item.name,
                    primaryMuscles: item.primaryMuscles,
                    secondaryMuscles: item.secondaryMuscles,
                    targetSets: item.targetSets,
                    targetReps: item.targetReps,
                    sortIndex: item.sortIndex,
                    equipment: equipment,
                    supersetGroupID: item.supersetGroupID
                )
                exercise.restSeconds = item.restSeconds
                exercise.day = dayModel
                context.insert(exercise)
            }
        }

        try context.save()
    }

    @MainActor
    static func applyStarter(
        _ template: StarterProgramTemplate,
        context: ModelContext,
        existingPrograms: [Program],
        makeActive: Bool = true
    ) throws -> Program {
        if makeActive {
            for item in existingPrograms where item.isActive {
                item.isActive = false
            }
        }

        let program = Program(
            name: uniqueProgramName(template.name, existing: existingPrograms),
            isActive: makeActive
        )
        context.insert(program)

        for (dayIndex, daySpec) in template.days.enumerated() {
            let day = ProgramDay(name: daySpec.name, sortIndex: dayIndex)
            day.program = program
            context.insert(day)

            for (liftIndex, lift) in daySpec.lifts.enumerated() {
                guard let catalog = ExerciseCatalog.all.first(where: { $0.id == lift.catalogID }) else {
                    assertionFailure("Starter template \(template.id) references missing catalog exercise \(lift.catalogID)")
                    continue
                }
                let exercise = DayExercise(
                    name: catalog.name,
                    primaryMuscles: catalog.primaryNames,
                    secondaryMuscles: catalog.secondaryNames,
                    targetSets: lift.targetSets,
                    targetReps: lift.targetReps,
                    sortIndex: liftIndex,
                    equipment: catalog.equipment
                )
                exercise.day = day
                context.insert(exercise)
            }
        }

        try context.save()
        return program
    }

    private static func uniqueProgramName(_ base: String, existing: [Program]) -> String {
        let names = Set(existing.map(\.name))
        if !names.contains(base) { return base }
        var index = 2
        while names.contains("\(base) \(index)") {
            index += 1
        }
        return "\(base) \(index)"
    }
}

struct StarterLift: Hashable {
    let catalogID: String
    let targetSets: Int
    let targetReps: Int

    init(_ catalogID: String, sets: Int, reps: Int) {
        self.catalogID = catalogID
        self.targetSets = sets
        self.targetReps = reps
    }
}

struct StarterProgramDay: Hashable {
    let name: String
    let lifts: [StarterLift]
}

struct StarterProgramTemplate: Identifiable, Hashable {
    let id: String
    let name: String
    let summary: String
    let days: [StarterProgramDay]

    var dayCount: Int { days.count }

    var dayLabel: String {
        "\(dayCount)-day rotation"
    }

    var dayNamesLabel: String {
        days.map(\.name).joined(separator: " · ")
    }
}

enum StarterProgramTemplates {
    static let all: [StarterProgramTemplate] = [
        threeDayFullBody,
        fourDaySplit,
        pushPullLegs,
        upperLower,
        fiveThreeOne,
        fullBody,
    ]

    /// Classic 3-day full-body A/B/C.
    static let threeDayFullBody = StarterProgramTemplate(
        id: "three-day-full-body",
        name: "3-Day Full Body",
        summary: "Three rotating full-body days. Run A/B/C through the week.",
        days: [
            StarterProgramDay(name: "Full Body A", lifts: [
                StarterLift("back-squat", sets: 3, reps: 5),
                StarterLift("barbell-bench-press", sets: 3, reps: 8),
                StarterLift("barbell-row", sets: 3, reps: 8),
                StarterLift("overhead-press", sets: 3, reps: 8),
                StarterLift("hanging-leg-raise", sets: 3, reps: 10),
            ]),
            StarterProgramDay(name: "Full Body B", lifts: [
                StarterLift("deadlift", sets: 3, reps: 5),
                StarterLift("pull-up", sets: 3, reps: 8),
                StarterLift("incline-dumbbell-press", sets: 3, reps: 8),
                StarterLift("bulgarian-split-squat", sets: 3, reps: 8),
                StarterLift("face-pull", sets: 3, reps: 12),
            ]),
            StarterProgramDay(name: "Full Body C", lifts: [
                StarterLift("front-squat", sets: 3, reps: 8),
                StarterLift("dumbbell-shoulder-press", sets: 3, reps: 8),
                StarterLift("one-arm-dumbbell-row", sets: 3, reps: 10),
                StarterLift("romanian-deadlift", sets: 3, reps: 8),
                StarterLift("dips", sets: 3, reps: 8),
            ]),
        ]
    )

    /// Classic 4-day body-part split.
    static let fourDaySplit = StarterProgramTemplate(
        id: "four-day-split",
        name: "4-Day Split",
        summary: "Chest, back, legs, and shoulders — a classic body-part week.",
        days: [
            StarterProgramDay(name: "Chest", lifts: [
                StarterLift("barbell-bench-press", sets: 4, reps: 8),
                StarterLift("incline-dumbbell-press", sets: 3, reps: 10),
                StarterLift("cable-fly", sets: 3, reps: 12),
                StarterLift("dips", sets: 3, reps: 10),
                StarterLift("tricep-pushdown", sets: 3, reps: 12),
            ]),
            StarterProgramDay(name: "Back", lifts: [
                StarterLift("pull-up", sets: 3, reps: 8),
                StarterLift("barbell-row", sets: 4, reps: 8),
                StarterLift("lat-pulldown", sets: 3, reps: 10),
                StarterLift("seated-cable-row", sets: 3, reps: 10),
                StarterLift("face-pull", sets: 3, reps: 12),
                StarterLift("barbell-curl", sets: 3, reps: 10),
            ]),
            StarterProgramDay(name: "Legs", lifts: [
                StarterLift("back-squat", sets: 4, reps: 8),
                StarterLift("romanian-deadlift", sets: 3, reps: 8),
                StarterLift("leg-press", sets: 3, reps: 10),
                StarterLift("bulgarian-split-squat", sets: 3, reps: 10),
                StarterLift("seated-leg-curl", sets: 3, reps: 12),
                StarterLift("calf-raise", sets: 3, reps: 12),
            ]),
            StarterProgramDay(name: "Shoulders", lifts: [
                StarterLift("overhead-press", sets: 4, reps: 6),
                StarterLift("dumbbell-shoulder-press", sets: 3, reps: 10),
                StarterLift("lateral-raise", sets: 3, reps: 12),
                StarterLift("rear-delt-fly", sets: 3, reps: 12),
                StarterLift("skull-crusher", sets: 3, reps: 10),
                StarterLift("dumbbell-curl", sets: 3, reps: 10),
            ]),
        ]
    )

    /// 6-day push / pull / legs with A and B variants.
    static let pushPullLegs = StarterProgramTemplate(
        id: "push-pull-legs",
        name: "Push / Pull / Legs",
        summary: "Six-day PPL: two push, pull, and leg days in rotation.",
        days: [
            StarterProgramDay(name: "Push A", lifts: [
                StarterLift("barbell-bench-press", sets: 4, reps: 6),
                StarterLift("overhead-press", sets: 3, reps: 8),
                StarterLift("incline-dumbbell-press", sets: 3, reps: 10),
                StarterLift("lateral-raise", sets: 3, reps: 12),
                StarterLift("tricep-pushdown", sets: 3, reps: 12),
                StarterLift("dips", sets: 3, reps: 10),
            ]),
            StarterProgramDay(name: "Pull A", lifts: [
                StarterLift("deadlift", sets: 3, reps: 5),
                StarterLift("pull-up", sets: 3, reps: 8),
                StarterLift("barbell-row", sets: 4, reps: 8),
                StarterLift("face-pull", sets: 3, reps: 12),
                StarterLift("barbell-curl", sets: 3, reps: 10),
                StarterLift("dumbbell-shrug", sets: 3, reps: 12),
            ]),
            StarterProgramDay(name: "Legs A", lifts: [
                StarterLift("back-squat", sets: 4, reps: 6),
                StarterLift("romanian-deadlift", sets: 3, reps: 8),
                StarterLift("leg-press", sets: 3, reps: 10),
                StarterLift("seated-leg-curl", sets: 3, reps: 12),
                StarterLift("calf-raise", sets: 3, reps: 12),
                StarterLift("hanging-leg-raise", sets: 3, reps: 10),
            ]),
            StarterProgramDay(name: "Push B", lifts: [
                StarterLift("overhead-press", sets: 4, reps: 6),
                StarterLift("incline-barbell-bench-press", sets: 3, reps: 8),
                StarterLift("dumbbell-bench-press", sets: 3, reps: 10),
                StarterLift("cable-lateral-raise", sets: 3, reps: 12),
                StarterLift("skull-crusher", sets: 3, reps: 10),
                StarterLift("pec-deck", sets: 3, reps: 12),
            ]),
            StarterProgramDay(name: "Pull B", lifts: [
                StarterLift("barbell-row", sets: 4, reps: 8),
                StarterLift("lat-pulldown", sets: 3, reps: 10),
                StarterLift("chest-supported-dumbbell-row", sets: 3, reps: 10),
                StarterLift("chin-up", sets: 3, reps: 8),
                StarterLift("reverse-pec-deck", sets: 3, reps: 12),
                StarterLift("hammer-curl", sets: 3, reps: 10),
            ]),
            StarterProgramDay(name: "Legs B", lifts: [
                StarterLift("front-squat", sets: 4, reps: 8),
                StarterLift("barbell-hip-thrust", sets: 3, reps: 10),
                StarterLift("walking-lunge", sets: 3, reps: 10),
                StarterLift("lying-leg-curl", sets: 3, reps: 12),
                StarterLift("leg-extension", sets: 3, reps: 12),
                StarterLift("cable-crunch", sets: 3, reps: 12),
            ]),
        ]
    )

    /// 4-day upper / lower with A and B variants.
    static let upperLower = StarterProgramTemplate(
        id: "upper-lower",
        name: "Upper / Lower",
        summary: "Four-day upper/lower with two variants of each.",
        days: [
            StarterProgramDay(name: "Upper A", lifts: [
                StarterLift("barbell-bench-press", sets: 4, reps: 6),
                StarterLift("barbell-row", sets: 4, reps: 8),
                StarterLift("overhead-press", sets: 3, reps: 8),
                StarterLift("pull-up", sets: 3, reps: 8),
                StarterLift("lateral-raise", sets: 3, reps: 12),
                StarterLift("barbell-curl", sets: 3, reps: 10),
                StarterLift("tricep-pushdown", sets: 3, reps: 12),
            ]),
            StarterProgramDay(name: "Lower A", lifts: [
                StarterLift("back-squat", sets: 4, reps: 6),
                StarterLift("romanian-deadlift", sets: 3, reps: 8),
                StarterLift("bulgarian-split-squat", sets: 3, reps: 10),
                StarterLift("seated-leg-curl", sets: 3, reps: 12),
                StarterLift("calf-raise", sets: 3, reps: 12),
                StarterLift("hanging-leg-raise", sets: 3, reps: 10),
            ]),
            StarterProgramDay(name: "Upper B", lifts: [
                StarterLift("overhead-press", sets: 4, reps: 6),
                StarterLift("chin-up", sets: 3, reps: 8),
                StarterLift("incline-dumbbell-press", sets: 3, reps: 10),
                StarterLift("seated-cable-row", sets: 3, reps: 10),
                StarterLift("face-pull", sets: 3, reps: 12),
                StarterLift("dips", sets: 3, reps: 10),
                StarterLift("hammer-curl", sets: 3, reps: 10),
            ]),
            StarterProgramDay(name: "Lower B", lifts: [
                StarterLift("deadlift", sets: 3, reps: 5),
                StarterLift("front-squat", sets: 3, reps: 8),
                StarterLift("leg-press", sets: 3, reps: 10),
                StarterLift("barbell-hip-thrust", sets: 3, reps: 10),
                StarterLift("lying-leg-curl", sets: 3, reps: 12),
                StarterLift("calf-raise", sets: 3, reps: 12),
            ]),
        ]
    )

    /// Wendler-style 4-day 5/3/1. No %1RM cycle in the app — mains start as 3×5 (5s week).
    static let fiveThreeOne = StarterProgramTemplate(
        id: "five-three-one",
        name: "5/3/1 Powerlifting",
        summary: "Press, deadlift, bench, squat. Mains are 3×5 for the 5s week — log RIR and drop to 3s/1s as you go.",
        days: [
            StarterProgramDay(name: "Press", lifts: [
                StarterLift("overhead-press", sets: 3, reps: 5),
                StarterLift("chin-up", sets: 5, reps: 8),
                StarterLift("dips", sets: 3, reps: 10),
                StarterLift("face-pull", sets: 3, reps: 15),
            ]),
            StarterProgramDay(name: "Deadlift", lifts: [
                StarterLift("deadlift", sets: 3, reps: 5),
                StarterLift("good-morning", sets: 3, reps: 8),
                StarterLift("hanging-leg-raise", sets: 3, reps: 10),
                StarterLift("barbell-shrug", sets: 3, reps: 12),
            ]),
            StarterProgramDay(name: "Bench", lifts: [
                StarterLift("barbell-bench-press", sets: 3, reps: 5),
                StarterLift("barbell-row", sets: 5, reps: 8),
                StarterLift("skull-crusher", sets: 3, reps: 10),
                StarterLift("dumbbell-curl", sets: 3, reps: 10),
            ]),
            StarterProgramDay(name: "Squat", lifts: [
                StarterLift("back-squat", sets: 3, reps: 5),
                StarterLift("leg-press", sets: 3, reps: 10),
                StarterLift("seated-leg-curl", sets: 3, reps: 10),
                StarterLift("ab-wheel", sets: 3, reps: 8),
            ]),
        ]
    )

    /// 2-day full body, run 2–3 times per week.
    static let fullBody = StarterProgramTemplate(
        id: "full-body",
        name: "Full Body",
        summary: "Two full-body days. Run A/B two or three times per week.",
        days: [
            StarterProgramDay(name: "Full Body A", lifts: [
                StarterLift("back-squat", sets: 3, reps: 5),
                StarterLift("barbell-bench-press", sets: 3, reps: 8),
                StarterLift("barbell-row", sets: 3, reps: 8),
                StarterLift("romanian-deadlift", sets: 3, reps: 8),
                StarterLift("overhead-press", sets: 3, reps: 8),
                StarterLift("hanging-leg-raise", sets: 3, reps: 10),
            ]),
            StarterProgramDay(name: "Full Body B", lifts: [
                StarterLift("deadlift", sets: 3, reps: 5),
                StarterLift("pull-up", sets: 3, reps: 8),
                StarterLift("incline-dumbbell-press", sets: 3, reps: 8),
                StarterLift("bulgarian-split-squat", sets: 3, reps: 8),
                StarterLift("lateral-raise", sets: 3, reps: 12),
                StarterLift("dips", sets: 3, reps: 8),
            ]),
        ]
    )
}
