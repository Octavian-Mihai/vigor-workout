import SwiftUI
import SwiftData

/// Everything needed to rebuild an in-progress workout after the app was closed or killed.
struct ActiveWorkoutSnapshot: Codable {
    var startedAt: Date
    var lastActivityAt: Date
    var programUUID: UUID?
    var programDayUUID: UUID?
    var isEmpty: Bool
    var originalNames: [String]
    var restDuration: Int
    var exercises: [DraftExercise]
    var drafts: [UUID: ExerciseDraft]
    var barWeightOverrides: [UUID: Double]
    var prSetIDs: Set<UUID>

    /// The part that counts as user activity (excludes timers and timestamps).
    struct Content: Equatable {
        var exercises: [DraftExercise]
        var drafts: [UUID: ExerciseDraft]
    }
}

/// Stores the active workout as a JSON file so it survives the app being closed or killed.
enum ActiveWorkoutPersistence {
    static var fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("ActiveWorkout.json")
    }()

    static func save(_ snapshot: ActiveWorkoutSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func load() -> ActiveWorkoutSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(ActiveWorkoutSnapshot.self, from: data)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

enum ActiveWorkoutPolicy {
    /// A workout with no changes for this long is treated as forgotten.
    static let staleAfter: TimeInterval = 3 * 3600

    static func isStale(lastActivity: Date, now: Date = Date()) -> Bool {
        now.timeIntervalSince(lastActivity) > staleAfter
    }
}

/// Writes a workout into the history. Pass `durationSeconds` 0 when the length is unknown.
@MainActor
enum WorkoutSaver {
    @discardableResult
    static func save(
        controller: SessionController,
        context: ModelContext,
        durationSeconds: Int,
        endDate: Date?
    ) -> WorkoutSession {
        let session = WorkoutSession(
            startDate: controller.startedAt,
            source: controller.isEmpty ? SessionSource.empty : SessionSource.programmed,
            programUUID: controller.program?.uuid,
            programDayIndex: controller.programDay.map { day in
                controller.program?.orderedDays.firstIndex(where: { $0.uuid == day.uuid })
            } ?? nil,
            programDayName: controller.programDay?.name
        )
        // `endDate != nil` marks a session as finished across the app, so it is always set.
        session.endDate = endDate ?? controller.startedAt
        session.durationSeconds = durationSeconds
        context.insert(session)

        for exercise in controller.exercises {
            for set in exercise.logged {
                let log = SetLog(
                    exerciseName: exercise.name,
                    primaryMuscles: exercise.primaryMuscles,
                    secondaryMuscles: exercise.secondaryMuscles,
                    weight: set.weightKg,
                    reps: set.reps,
                    rir: set.rir,
                    targetReps: exercise.targetReps,
                    timestamp: set.loggedAt
                )
                log.session = session
                context.insert(log)
            }
        }
        try? context.save()
        return session
    }
}

@MainActor
final class ActiveSessionStore: ObservableObject {
    @Published var controller: SessionController?
    @Published var isPresented = false
    /// True while the restored workout is forgotten and waiting for Save / Continue / Discard.
    @Published var isStale = false
    @Published var showStalePrompt = false

    var isMinimized: Bool { controller != nil && !isPresented && !isStale }

    /// Brings back a workout that was in progress when the app was closed.
    func restoreIfNeeded(context: ModelContext) {
        guard controller == nil, let snapshot = ActiveWorkoutPersistence.load() else { return }
        var program: Program?
        var day: ProgramDay?
        if let programUUID = snapshot.programUUID {
            let programs = (try? context.fetch(FetchDescriptor<Program>())) ?? []
            program = programs.first { $0.uuid == programUUID }
            if let dayUUID = snapshot.programDayUUID {
                day = program?.orderedDays.first { $0.uuid == dayUUID }
            }
        }
        let restored = SessionController(restoring: snapshot, program: program, programDay: day)
        if restored.loggedSetCount == 0 {
            // Nothing worth keeping if no set was ever logged and it has gone stale.
            if ActiveWorkoutPolicy.isStale(lastActivity: snapshot.lastActivityAt) {
                ActiveWorkoutPersistence.clear()
                return
            }
        }
        controller = restored
        if ActiveWorkoutPolicy.isStale(lastActivity: snapshot.lastActivityAt) {
            markStale()
        } else {
            isPresented = true
        }
    }

    /// Re-checks staleness when the app returns to the foreground.
    func checkStale() {
        guard let controller, !isStale, ActiveWorkoutPolicy.isStale(lastActivity: controller.lastActivityAt) else { return }
        isPresented = false
        markStale()
    }

    private func markStale() {
        isStale = true
        showStalePrompt = true
    }

    func start(program: Program?, programDay: ProgramDay?) {
        if guardExisting() { return }
        let rest = UserDefaults.standard.object(forKey: "defaultRestSeconds") as? Int ?? 90
        controller = SessionController(program: program, programDay: programDay, defaultRest: rest)
        isPresented = true
    }

    func start(from session: WorkoutSession) {
        if guardExisting() { return }
        let rest = UserDefaults.standard.object(forKey: "defaultRestSeconds") as? Int ?? 90
        controller = SessionController(from: session, defaultRest: rest)
        isPresented = true
    }

    /// Returns true when a workout already exists (the caller must not start another).
    private func guardExisting() -> Bool {
        guard controller != nil else { return false }
        if isStale {
            showStalePrompt = true
        } else {
            isPresented = true
        }
        return true
    }

    func minimize() {
        isPresented = false
    }

    func resume() {
        guard controller != nil else { return }
        if isStale {
            showStalePrompt = true
        } else {
            isPresented = true
        }
    }

    /// Keep working on a forgotten workout; the clock restarts from now.
    func continueStale() {
        controller?.restartClock()
        isStale = false
        showStalePrompt = false
        isPresented = true
    }

    /// Saves a forgotten workout on the day it started. `durationSeconds` 0 means unknown.
    func saveStale(context: ModelContext, durationSeconds: Int) {
        guard let controller else { return }
        if controller.loggedSetCount > 0 {
            let end = durationSeconds > 0 ? controller.startedAt.addingTimeInterval(TimeInterval(durationSeconds)) : nil
            WorkoutSaver.save(controller: controller, context: context, durationSeconds: durationSeconds, endDate: end)
        }
        finish()
    }

    func finish() {
        controller?.stopTimer()
        controller?.endPersistence()
        RestTimerService.shared.resetRest()
        controller = nil
        isStale = false
        showStalePrompt = false
        isPresented = false
    }

    func discard() {
        finish()
    }
}

/// Shown when a workout was left unfinished for hours: save it, keep going, or throw it away.
struct StaleWorkoutSheet: View {
    @ObservedObject var controller: SessionController
    var onSave: (Int) -> Void
    var onContinue: () -> Void
    var onDiscard: () -> Void

    @State private var minutesText = ""
    @State private var confirmDiscard = false

    private var startLabel: String {
        controller.startedAt.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("You started a workout on \(startLabel) and never finished it. It has \(controller.loggedSetCount) logged sets.")
                }
                Section {
                    HStack {
                        Text("Duration (min)")
                        Spacer()
                        TextField("Unknown", text: $minutesText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                } footer: {
                    Text("Optional. Leave blank if you don't remember; no duration is recorded.")
                }
                Section {
                    Button("Save workout on \(controller.startedAt.formatted(date: .abbreviated, time: .omitted))") {
                        onSave(max(Int(minutesText) ?? 0, 0) * 60)
                    }
                    .disabled(controller.loggedSetCount == 0)
                    Button("Continue workout", action: onContinue)
                    Button("Discard workout", role: .destructive) {
                        if controller.loggedSetCount > 0 { confirmDiscard = true } else { onDiscard() }
                    }
                }
            }
            .navigationTitle("Unfinished workout")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Discard this workout?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard workout", role: .destructive, action: onDiscard)
                Button("Cancel", role: .cancel) {}
            }
        }
        .interactiveDismissDisabled()
    }
}
