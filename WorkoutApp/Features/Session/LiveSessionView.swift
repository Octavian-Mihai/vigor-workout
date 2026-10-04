import SwiftUI
import SwiftData
import Combine
import UIKit

struct DraftExercise: Identifiable {
    let id: UUID
    var name: String
    var primaryMuscles: [String]
    var secondaryMuscles: [String]
    var equipment: ExerciseEquipment
    var targetSets: Int
    var targetReps: Int?
    var restSeconds: Int?
    var supersetGroupID: UUID?
    var logged: [DraftSet]

    init(
        id: UUID = UUID(),
        name: String,
        primaryMuscles: [String],
        secondaryMuscles: [String],
        equipment: ExerciseEquipment? = nil,
        targetSets: Int = 0,
        targetReps: Int? = nil,
        restSeconds: Int? = nil,
        supersetGroupID: UUID? = nil,
        logged: [DraftSet] = []
    ) {
        self.id = id
        self.name = name
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.equipment = equipment ?? ExerciseEquipment.infer(from: name)
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.restSeconds = restSeconds
        self.supersetGroupID = supersetGroupID
        self.logged = logged
    }
}

struct DraftSet: Identifiable {
    let id: UUID
    var weightKg: Double
    var reps: Int
    var rir: Int

    init(id: UUID = UUID(), weightKg: Double, reps: Int, rir: Int) {
        self.id = id
        self.weightKg = weightKg
        self.reps = reps
        self.rir = rir
    }
}

private enum TemplateSaveDecision {
    case undecided
    case saved
    case declined
}

enum SessionField: Hashable {
    case weight(UUID, setID: UUID?)
    case reps(UUID, setID: UUID?)

    var exerciseID: UUID {
        switch self {
        case .weight(let id, _), .reps(let id, _):
            return id
        }
    }

    var setID: UUID? {
        switch self {
        case .weight(_, let setID), .reps(_, let setID):
            return setID
        }
    }

    var isWeight: Bool {
        if case .weight = self { return true }
        return false
    }
}

struct ExerciseDraft: Equatable {
    var weightText: String = ""
    var repsText: String = "8"
    var rir: Int = 3
    var didSeed = false
}

@MainActor
final class SessionController: ObservableObject {
    @Published var exercises: [DraftExercise]
    @Published var restDuration: Int
    @Published var restRemaining: Int
    @Published var timerRunning = false
    @Published var restCompletedPulse = 0
    @Published var supersetCueMessage: String?
    @Published var startedAt: Date
    @Published var focusedField: SessionField? {
        didSet {
            if let previous = oldValue?.setID, previous != focusedField?.setID {
                loggedEdits[previous] = nil
            }
        }
    }
    @Published var drafts: [UUID: ExerciseDraft] = [:]
    @Published var loggedEdits: [UUID: ExerciseDraft] = [:]
    @Published var barWeightOverrides: [UUID: Double] = [:]
    @Published var prSetIDs: Set<UUID> = []
    @Published var prPulse = 0
    /// Bumped when the watch asks to finish the workout.
    @Published var watchFinishRequest = 0
    @Published var showSuggestionByExercise: [UUID: Bool] = [:]
    @Published var latestPRExerciseID: UUID?
    @Published var latestPREstimateKg: Double?
    /// Set when a set beats the all-time best (and anything lifted earlier this session).
    @Published var prCelebration: PRCelebration?
    /// Best estimated 1RM logged so far this session, per lowercased exercise name.
    private var sessionBestE1RM: [String: Double] = [:]

    let program: Program?
    let programDay: ProgramDay?
    let isEmpty: Bool
    let originalNames: [String]

    var pastSessions: [WorkoutSession] = []
    private let restTimer: RestTimerService
    private var timerCancellable: AnyCancellable?

    init(
        program: Program?,
        programDay: ProgramDay?,
        defaultRest: Int = 90,
        restTimer: RestTimerService? = nil
    ) {
        self.program = program
        self.programDay = programDay
        self.isEmpty = programDay == nil
        self.restTimer = restTimer ?? RestTimerService.shared
        self.restDuration = defaultRest
        self.restRemaining = defaultRest
        self.startedAt = Date()
        self.focusedField = nil
        if let day = programDay {
            let ordered = day.orderedExercises
            self.originalNames = ordered.map(\.name)
            let list = ordered.map { item in
                DraftExercise(
                    name: item.name,
                    primaryMuscles: item.primaryMuscles,
                    secondaryMuscles: item.secondaryMuscles,
                    equipment: item.equipment,
                    targetSets: item.targetSets,
                    targetReps: item.targetReps > 0 ? item.targetReps : nil,
                    restSeconds: item.restSeconds,
                    supersetGroupID: item.supersetGroupID
                )
            }
            self.exercises = list
            self.drafts = Dictionary(uniqueKeysWithValues: list.map { ($0.id, ExerciseDraft()) })
        } else {
            self.originalNames = []
            self.exercises = []
            self.drafts = [:]
        }
    }

    init(from session: WorkoutSession, defaultRest: Int = 90, restTimer: RestTimerService? = nil) {
        self.program = nil
        self.programDay = nil
        self.isEmpty = true
        self.restTimer = restTimer ?? RestTimerService.shared
        self.restDuration = defaultRest
        self.restRemaining = defaultRest
        self.startedAt = Date()
        self.focusedField = nil

        var exerciseOrder: [String] = []
        var grouped: [String: [SetLog]] = [:]
        for set in session.orderedSets {
            if grouped[set.exerciseName] == nil {
                exerciseOrder.append(set.exerciseName)
                grouped[set.exerciseName] = []
            }
            grouped[set.exerciseName, default: []].append(set)
        }

        self.originalNames = exerciseOrder
        let list = exerciseOrder.compactMap { name -> DraftExercise? in
            guard let sets = grouped[name], let first = sets.first else { return nil }
            return DraftExercise(
                name: name,
                primaryMuscles: first.primaryMuscles,
                secondaryMuscles: first.secondaryMuscles,
                equipment: ExerciseCatalog.equipment(forName: name),
                targetSets: sets.count,
                targetReps: sets.last?.targetReps ?? sets.last?.reps
            )
        }
        self.exercises = list
        self.drafts = Dictionary(uniqueKeysWithValues: list.map { ($0.id, ExerciseDraft()) })
    }

    var loggedSetCount: Int {
        exercises.reduce(0) { $0 + $1.logged.count }
    }

    var exerciseListChanged: Bool {
        guard !isEmpty else { return false }
        return exercises.map(\.name) != originalNames
    }

    func tick() {
        guard timerRunning else { return }
        restRemaining = restTimer.remainingSeconds()
        if restTimer.syncFromWallClock() {
            timerRunning = false
            restRemaining = 0
            restCompletedPulse += 1
            stopTimer()
        } else if restRemaining == 0 {
            timerRunning = false
            restCompletedPulse += 1
            stopTimer()
            restTimer.resetRest()
        }
    }

    func startRest(for exerciseID: UUID? = nil) {
        restRemaining = restDuration
        timerRunning = true
        let exercise = exerciseID.flatMap { id in exercises.first(where: { $0.id == id }) }
        restTimer.startRest(
            duration: restDuration,
            exerciseName: exercise?.name,
            sessionLabel: programDay?.name ?? "Workout",
            setsCompleted: exercise?.logged.count ?? 0,
            targetSets: exercise?.targetSets ?? 0
        )
        ensureTimer()
        WatchSessionSync.shared.pushSnapshot(from: self)
    }

    func resetRest() {
        restRemaining = restDuration
        timerRunning = false
        restTimer.resetRest()
        stopTimer()
        WatchSessionSync.shared.pushSnapshot(from: self)
    }

    func stopTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    func showSuggestion(for exerciseID: UUID) -> Bool {
        showSuggestionByExercise[exerciseID] ?? false
    }

    func toggleSuggestion(for exerciseID: UUID) {
        showSuggestionByExercise[exerciseID] = !(showSuggestionByExercise[exerciseID] ?? false)
    }

    private func ensureTimer() {
        guard timerCancellable == nil else { return }
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    func logSet(exerciseID: UUID, weightKg: Double, reps: Int, rir: Int) {
        guard let index = exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        let exercise = exercises[index]
        let set = DraftSet(weightKg: weightKg, reps: reps, rir: rir)
        exercises[index].logged.append(set)
        let estimate = OneRM.estimate(exerciseName: exercise.name, weight: weightKg, reps: reps, rir: rir)
        let bestKey = exercise.name.lowercased()
        if let previous = PRDetector.celebratedPreviousBest(
            estimate: estimate,
            pastBest: PersonalRecordTracker.bestEstimate(for: exercise.name, in: pastSessions),
            sessionBest: sessionBestE1RM[bestKey]
        ) {
            prCelebration = PRCelebration(exerciseName: exercise.name, estimateKg: estimate, previousKg: previous)
        }
        sessionBestE1RM[bestKey] = max(sessionBestE1RM[bestKey] ?? 0, estimate)
        if PersonalRecordTracker.isNewPR(
            weightKg: weightKg,
            reps: reps,
            rir: rir,
            exerciseName: exercise.name,
            sessions: pastSessions
        ) {
            prSetIDs.insert(set.id)
            prPulse += 1
            latestPRExerciseID = exerciseID
            latestPREstimateKg = estimate
        }
        if let partner = nextSupersetPartner(after: exerciseID) {
            supersetCueMessage = "No rest — up next: \(partner.name)"
            WatchSessionSync.shared.pushSnapshot(from: self)
        } else {
            supersetCueMessage = nil
            startRest(for: exerciseID)
        }
    }

    /// The next exercise sharing this one's superset group, later in the list order.
    /// Returns nil for standalone exercises or when this is the last member of its group,
    /// which means "log this set as normal, then rest."
    func nextSupersetPartner(after exerciseID: UUID) -> DraftExercise? {
        guard let index = exercises.firstIndex(where: { $0.id == exerciseID }),
              let groupID = exercises[index].supersetGroupID
        else { return nil }
        return exercises[(index + 1)...].first { $0.supersetGroupID == groupID }
    }

    func updateSet(exerciseID: UUID, setID: UUID, weightKg: Double, reps: Int, rir: Int) {
        guard let exerciseIndex = exercises.firstIndex(where: { $0.id == exerciseID }),
              let setIndex = exercises[exerciseIndex].logged.firstIndex(where: { $0.id == setID })
        else { return }
        exercises[exerciseIndex].logged[setIndex].weightKg = weightKg
        exercises[exerciseIndex].logged[setIndex].reps = reps
        exercises[exerciseIndex].logged[setIndex].rir = rir
    }

    func ensureLoggedEdit(exerciseID: UUID, setID: UUID, unit: WeightUnit) {
        if loggedEdits[setID] != nil { return }
        guard let exercise = exercises.first(where: { $0.id == exerciseID }),
              let set = exercise.logged.first(where: { $0.id == setID })
        else { return }
        loggedEdits[setID] = ExerciseDraft(
            weightText: unit.formatNumber(set.weightKg),
            repsText: "\(set.reps)",
            rir: set.rir,
            didSeed: true
        )
    }

    func activeDraft(for field: SessionField) -> ExerciseDraft {
        if let setID = field.setID {
            return loggedEdits[setID] ?? ExerciseDraft()
        }
        return draft(for: field.exerciseID)
    }

    func updateActiveDraft(for field: SessionField, _ body: (inout ExerciseDraft) -> Void) {
        if let setID = field.setID {
            var value = loggedEdits[setID] ?? ExerciseDraft()
            body(&value)
            loggedEdits[setID] = value
            return
        }
        updateDraft(for: field.exerciseID, body)
    }

    func ensureDraft(for exerciseID: UUID, unit: WeightUnit, previousSets: [SetLog]) {
        guard let exercise = exercises.first(where: { $0.id == exerciseID }) else { return }
        var draft = drafts[exerciseID] ?? ExerciseDraft()
        if !draft.didSeed {
            if let last = exercise.logged.last {
                draft.weightText = unit.formatNumber(last.weightKg)
                draft.repsText = "\(last.reps)"
                draft.rir = last.rir
            } else if let last = previousSets.last {
                draft.weightText = unit.formatNumber(last.weight)
                draft.repsText = "\(last.reps)"
                draft.rir = last.rir
            }
            draft.didSeed = true
        }
        drafts[exerciseID] = draft
    }

    func carryDraftForward(exerciseID: UUID, weightText: String, repsText: String, rir: Int) {
        updateDraft(for: exerciseID) { draft in
            draft.weightText = weightText
            draft.repsText = repsText
            draft.rir = rir
        }
    }

    func removeSet(exerciseID: UUID, setID: UUID) {
        guard let index = exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        exercises[index].logged.removeAll { $0.id == setID }
        loggedEdits[setID] = nil
        if focusedField?.setID == setID {
            focusedField = nil
        }
    }

    func addExercise(_ catalog: CatalogExercise) {
        let exercise = DraftExercise(
            name: catalog.name,
            primaryMuscles: catalog.primaryNames,
            secondaryMuscles: catalog.secondaryNames,
            equipment: catalog.equipment
        )
        exercises.append(exercise)
        drafts[exercise.id] = ExerciseDraft()
        WatchSessionSync.shared.pushSnapshot(from: self)
    }

    func addCustom(name: String, equipment: ExerciseEquipment, primary: [String], secondary: [String]) {
        let exercise = DraftExercise(
            name: name,
            primaryMuscles: primary,
            secondaryMuscles: secondary,
            equipment: equipment
        )
        exercises.append(exercise)
        drafts[exercise.id] = ExerciseDraft()
        WatchSessionSync.shared.pushSnapshot(from: self)
    }

    func removeExercise(id: UUID) {
        guard let index = exercises.firstIndex(where: { $0.id == id }) else { return }
        let removed = exercises.remove(at: index)
        drafts.removeValue(forKey: removed.id)
        barWeightOverrides.removeValue(forKey: removed.id)
        if focusedField?.exerciseID == removed.id {
            focusedField = nil
        }
        for set in removed.logged {
            loggedEdits.removeValue(forKey: set.id)
        }
        WatchSessionSync.shared.pushSnapshot(from: self)
    }

    func removeExercise(matching catalog: CatalogExercise) {
        guard let exercise = exercises.last(where: { $0.name == catalog.name }) else { return }
        removeExercise(id: exercise.id)
    }

    func moveExercises(from source: IndexSet, to destination: Int) {
        exercises.move(fromOffsets: source, toOffset: destination)
        WatchSessionSync.shared.pushSnapshot(from: self)
    }

    func swapExercise(id: UUID, with catalog: CatalogExercise) {
        guard let index = exercises.firstIndex(where: { $0.id == id }) else { return }
        let existing = exercises[index]
        for set in existing.logged {
            loggedEdits.removeValue(forKey: set.id)
        }
        exercises[index] = DraftExercise(
            id: existing.id,
            name: catalog.name,
            primaryMuscles: catalog.primaryNames,
            secondaryMuscles: catalog.secondaryNames,
            equipment: catalog.equipment,
            targetSets: existing.targetSets,
            targetReps: existing.targetReps,
            restSeconds: existing.restSeconds,
            logged: []
        )
        drafts[existing.id] = ExerciseDraft()
        if focusedField?.exerciseID == id {
            focusedField = nil
        }
    }

    func swapCustom(id: UUID, name: String, equipment: ExerciseEquipment, primary: [String], secondary: [String]) {
        guard let index = exercises.firstIndex(where: { $0.id == id }) else { return }
        let existing = exercises[index]
        for set in existing.logged {
            loggedEdits.removeValue(forKey: set.id)
        }
        exercises[index] = DraftExercise(
            id: existing.id,
            name: name,
            primaryMuscles: primary,
            secondaryMuscles: secondary,
            equipment: equipment,
            targetSets: existing.targetSets,
            targetReps: existing.targetReps,
            restSeconds: existing.restSeconds,
            logged: []
        )
        drafts[existing.id] = ExerciseDraft()
        if focusedField?.exerciseID == id {
            focusedField = nil
        }
    }

    func draft(for id: UUID) -> ExerciseDraft {
        drafts[id] ?? ExerciseDraft()
    }

    func updateDraft(for id: UUID, _ body: (inout ExerciseDraft) -> Void) {
        var value = drafts[id] ?? ExerciseDraft()
        body(&value)
        drafts[id] = value
    }

    func effectiveBarWeight(for exerciseID: UUID, unit: WeightUnit, barKg: Double, barLb: Double) -> Double {
        if let override = barWeightOverrides[exerciseID] {
            return override
        }
        return EquipmentSettings.plateBaseWeight(
            for: .barbell,
            unit: unit,
            barKg: barKg,
            barLb: barLb
        )
    }

    func adjustBarWeight(for exerciseID: UUID, unit: WeightUnit, delta: Double, barKg: Double, barLb: Double) {
        let current = effectiveBarWeight(for: exerciseID, unit: unit, barKg: barKg, barLb: barLb)
        let minimum: Double = unit == .kg ? 5 : 15
        let maximum: Double = unit == .kg ? 40 : 70
        let next = min(max(current + delta, minimum), maximum)
        let defaultWeight = EquipmentSettings.plateBaseWeight(
            for: .barbell,
            unit: unit,
            barKg: barKg,
            barLb: barLb
        )
        if abs(next - defaultWeight) < 0.001 {
            barWeightOverrides.removeValue(forKey: exerciseID)
        } else {
            barWeightOverrides[exerciseID] = next
        }
    }
}

struct LiveSessionView: View {
    @ObservedObject var controller: SessionController
    var onMinimize: () -> Void
    var onFinished: () -> Void
    var onDiscard: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(AppTheme.self) private var theme
    @EnvironmentObject private var health: HealthKitService
    @Query(sort: \WorkoutSession.startDate, order: .reverse) private var pastSessions: [WorkoutSession]
    @AppStorage("weightUnit") private var weightUnitRaw = WeightUnit.lb.rawValue
    @AppStorage("defaultRestSeconds") private var defaultRestSeconds = 90
    @AppStorage("restTimerHaptics") private var restTimerHaptics = true
    @AppStorage(StressVisibility.showAnalysisKey) private var showStressAnalysis = true
    @AppStorage(HealthKitService.writeStrengthToHealthKitKey) private var writeStrengthToHealthKit = false
    @AppStorage(EquipmentSettings.barbellBarKgKey) private var barbellBarKg = EquipmentSettings.defaultBarKg
    @AppStorage(EquipmentSettings.barbellBarLbKey) private var barbellBarLb = EquipmentSettings.defaultBarLb

    @State private var showAddExercise = false
    @State private var showReorderSheet = false
    @State private var showSaveTemplate = false
    @State private var showMidWorkoutSaveTemplate = false
    @State private var templateSaveDecision: TemplateSaveDecision = .undecided
    @State private var showDiscardConfirm = false
    @State private var showFinishConfirm = false
    @State private var finishedSession: WorkoutSession?
    @State private var showSummary = false
    @State private var setLoggedTick = 0

    private var accent: Color {
        theme.accent
    }

    private var unit: WeightUnit {
        WeightUnit(rawValue: weightUnitRaw) ?? .lb
    }

    var body: some View {
        VStack(spacing: 0) {
            compactRestTimer
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if controller.exercises.isEmpty {
                        Text("Add an exercise to start logging sets.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .opaqueCard()
                    }
                    if let cue = controller.supersetCueMessage {
                        Text(cue)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(accent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(accent.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    ForEach(controller.exercises) { exercise in
                        SessionExerciseCard(
                            controller: controller,
                            exercise: exercise,
                            unit: unit,
                            accent: accent,
                            previousSets: previousSets(for: exercise.name),
                            sessions: pastSessions,
                            showStressAnalysis: showStressAnalysis,
                            onReorder: { showReorderSheet = true },
                            onStructureChanged: noteExerciseStructureChanged,
                            onDeleteSet: { setID in
                                controller.removeSet(exerciseID: exercise.id, setID: setID)
                            }
                        )
                    }

                    Button {
                        showFinishConfirm = true
                    } label: {
                        Text("Finish workout")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .disabled(controller.loggedSetCount == 0)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
                    .confirmationDialog(
                        "Finish workout?",
                        isPresented: $showFinishConfirm,
                        titleVisibility: .visible
                    ) {
                        Button("Finish workout") { finish() }
                        Button("Cancel", role: .cancel) {}
                    }

                    Button("Discard workout", role: .destructive) {
                        if controller.loggedSetCount > 0 {
                            showDiscardConfirm = true
                        } else {
                            onDiscard()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 24)
                }
                .padding(16)
            }
        }
        .background(theme.groupedBackground.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            sessionKeyboard
        }
        .compactNavigationTitle(controller.programDay?.name ?? "Empty workout")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") { onMinimize() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddExercise = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .onDisappear {
            controller.focusedField = nil
        }
        .sheet(isPresented: $showAddExercise) {
            NavigationStack {
                ExercisePickerView(
                    initialAddedCatalogIDs: Set(controller.exercises.compactMap { ExerciseCatalog.match(name: $0.name)?.id }),
                    shouldConfirmRemove: { catalog in
                        guard let exercise = controller.exercises.last(where: { $0.name == catalog.name }) else {
                            return false
                        }
                        return !exercise.logged.isEmpty
                    },
                    onAdd: {
                        controller.addExercise($0)
                        noteExerciseStructureChanged()
                    },
                    onRemove: {
                        controller.removeExercise(matching: $0)
                        noteExerciseStructureChanged()
                    },
                    onCustom: { name, equipment, primary, secondary in
                        controller.addCustom(name: name, equipment: equipment, primary: primary, secondary: secondary)
                        noteExerciseStructureChanged()
                    }
                )
            }
        }
        .sheet(isPresented: $showReorderSheet) {
            SessionExerciseReorderView(controller: controller)
        }
        .onChange(of: showReorderSheet) { _, isShowing in
            if !isShowing {
                noteExerciseStructureChanged()
            }
        }
        .alert("Save this day as a template?", isPresented: $showMidWorkoutSaveTemplate) {
            Button("Save template") {
                rewriteDayTemplate()
                templateSaveDecision = .saved
            }
            Button("Don't save", role: .cancel) {
                templateSaveDecision = .declined
            }
        } message: {
            Text("Exercises were added, removed, or reordered. Save them to this program day, or keep the original template.")
        }
        .alert("Save this day as a template?", isPresented: $showSaveTemplate) {
            Button("Save template") {
                rewriteDayTemplate()
                onFinished()
            }
            Button("Don't save", role: .cancel) {
                onFinished()
            }
        } message: {
            Text("Exercises were added, removed, or reordered. Save them to this program day, or keep the original template.")
        }
        .alert("Discard this workout?", isPresented: $showDiscardConfirm) {
            Button("Discard", role: .destructive) { onDiscard() }
            Button("Keep", role: .cancel) {}
        } message: {
            Text("Logged sets will be lost.")
        }
        .sheet(isPresented: $showSummary, onDismiss: handleSummaryDismissed) {
            if let session = finishedSession {
                WorkoutSummarySheet(
                    model: WorkoutSummaryModel(
                        session: session,
                        previousSessions: pastSessions.filter { $0.startDate < session.startDate && $0.endDate != nil }
                    ),
                    accent: accent,
                    unit: unit,
                    onDone: {
                        showSummary = false
                        handleSummaryDismissed()
                    }
                )
            }
        }
        .gatedHaptic(.success, trigger: setLoggedTick)
        .sensoryFeedback(.success, trigger: restTimerHaptics ? controller.restCompletedPulse : 0)
        .sensoryFeedback(.impact(weight: .medium), trigger: restTimerHaptics ? controller.prPulse : 0)
        .sensoryFeedback(.success, trigger: restTimerHaptics ? controller.prCelebration?.id : nil)
        .overlay(alignment: .top) {
            if let celebration = controller.prCelebration {
                PRCelebrationBanner(celebration: celebration, unit: unit, accent: accent)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: celebration.id) {
                        try? await Task.sleep(nanoseconds: 3_800_000_000)
                        guard !Task.isCancelled else { return }
                        withAnimation(.easeOut(duration: 0.3)) {
                            if controller.prCelebration?.id == celebration.id { controller.prCelebration = nil }
                        }
                    }
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: controller.prCelebration)
        .onChange(of: controller.restCompletedPulse) { _, pulse in
            if pulse > 0 {
                RestTimerSound.play()
            }
        }
        .task(id: controller.supersetCueMessage) {
            guard controller.supersetCueMessage != nil else { return }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled { controller.supersetCueMessage = nil }
        }
        .onAppear {
            controller.pastSessions = pastSessions
            WatchSessionSync.shared.attach(controller)
        }
        .onDisappear {
            WatchSessionSync.shared.detach()
        }
        .onChange(of: pastSessions.count) { _, _ in
            controller.pastSessions = pastSessions
        }
        .onChange(of: controller.watchFinishRequest) { _, _ in
            if controller.loggedSetCount > 0, finishedSession == nil { finish() }
        }
    }

    @ViewBuilder
    private var sessionKeyboard: some View {
        if let field = controller.focusedField {
            let id = field.exerciseID
            let exerciseName = controller.exercises.first(where: { $0.id == id })?.name ?? ""
            let equipment = controller.exercises.first(where: { $0.id == id })?.equipment
                ?? ExerciseCatalog.equipment(forName: exerciseName)
            SessionInputKeyboard(
                mode: field.isWeight ? .weight : .reps,
                focusIdentity: field,
                accent: accent,
                unit: unit,
                equipment: equipment,
                weightText: Binding(
                    get: { controller.activeDraft(for: field).weightText },
                    set: { newValue in controller.updateActiveDraft(for: field) { $0.weightText = newValue } }
                ),
                repsText: Binding(
                    get: { controller.activeDraft(for: field).repsText },
                    set: { newValue in controller.updateActiveDraft(for: field) { $0.repsText = newValue } }
                ),
                rir: Binding(
                    get: { controller.activeDraft(for: field).rir },
                    set: { newValue in controller.updateActiveDraft(for: field) { $0.rir = newValue } }
                ),
                completeTitle: field.setID == nil ? "Complete Set" : "Save",
                barWeight: controller.effectiveBarWeight(
                    for: id,
                    unit: unit,
                    barKg: barbellBarKg,
                    barLb: barbellBarLb
                ),
                onAdjustBarWeight: equipment == .barbell
                    ? { delta in
                        controller.adjustBarWeight(
                            for: id,
                            unit: unit,
                            delta: delta,
                            barKg: barbellBarKg,
                            barLb: barbellBarLb
                        )
                    }
                    : nil,
                onDismiss: { controller.focusedField = nil },
                onNext: { controller.focusedField = .reps(id, setID: field.setID) },
                onCompleteSet: {
                    if let setID = field.setID {
                        saveLoggedSet(exerciseID: id, setID: setID)
                    } else {
                        completeSet(exerciseID: id)
                    }
                }
            )
        }
    }

    private func completeSet(exerciseID: UUID) {
        let draft = controller.draft(for: exerciseID)
        let weightText = draft.weightText
        let repsText = draft.repsText
        let weight = Double(weightText) ?? 0
        let reps = Int(repsText) ?? 0
        let rir = draft.rir
        guard weight > 0, reps > 0 else { return }
        controller.logSet(
            exerciseID: exerciseID,
            weightKg: unit.toKg(weight),
            reps: reps,
            rir: rir
        )
        controller.carryDraftForward(exerciseID: exerciseID, weightText: weightText, repsText: repsText, rir: rir)
        setLoggedTick += 1
        controller.focusedField = nil
    }

    private func saveLoggedSet(exerciseID: UUID, setID: UUID) {
        let draft = controller.loggedEdits[setID] ?? controller.draft(for: exerciseID)
        let weight = Double(draft.weightText) ?? 0
        let reps = Int(draft.repsText) ?? 0
        guard weight > 0, reps > 0 else { return }
        controller.updateSet(
            exerciseID: exerciseID,
            setID: setID,
            weightKg: unit.toKg(weight),
            reps: reps,
            rir: draft.rir
        )
        controller.loggedEdits[setID] = nil
        setLoggedTick += 1
        controller.focusedField = nil
    }

    private var compactRestTimer: some View {
        HStack(spacing: 10) {
            Text(Formatters.duration(controller.restRemaining))
                .font(.title3.monospacedDigit().weight(.bold))
                .foregroundStyle(controller.timerRunning ? accent : .primary)
                .contentTransition(.numericText(countsDown: true))
                .animation(.snappy, value: controller.restRemaining)
                .frame(minWidth: 64, alignment: .leading)
            Text("Rest")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Stepper(
                value: Binding(
                    get: { controller.restDuration },
                    set: { newValue in
                        controller.restDuration = newValue
                        defaultRestSeconds = newValue
                        if !controller.timerRunning {
                            controller.restRemaining = newValue
                        }
                    }
                ),
                in: 15...300,
                step: 15
            ) {
                Text("\(controller.restDuration)s")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .labelsHidden()
            .frame(width: 92)
            Button(controller.timerRunning ? "Reset" : "Start") {
                if controller.timerRunning {
                    controller.resetRest()
                } else {
                    controller.startRest(for: nil)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(theme.cardFill)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func previousSets(for name: String) -> [SetLog] {
        for session in pastSessions where session.endDate != nil {
            let sets = session.orderedSets.filter {
                $0.exerciseName.compare(name, options: .caseInsensitive) == .orderedSame
            }
            if !sets.isEmpty { return sets }
        }
        return []
    }

    private func finish() {
        let session = WorkoutSession(
            startDate: controller.startedAt,
            source: controller.isEmpty ? SessionSource.empty : SessionSource.programmed,
            programUUID: controller.program?.uuid,
            programDayIndex: controller.programDay.map { day in
                controller.program?.orderedDays.firstIndex(where: { $0.uuid == day.uuid })
            } ?? nil,
            programDayName: controller.programDay?.name
        )
        session.endDate = Date()
        session.durationSeconds = max(Int(Date().timeIntervalSince(controller.startedAt)), 1)
        modelContext.insert(session)

        for exercise in controller.exercises {
            for set in exercise.logged {
                let log = SetLog(
                    exerciseName: exercise.name,
                    primaryMuscles: exercise.primaryMuscles,
                    secondaryMuscles: exercise.secondaryMuscles,
                    weight: set.weightKg,
                    reps: set.reps,
                    rir: set.rir,
                    targetReps: exercise.targetReps
                )
                log.session = session
                modelContext.insert(log)
            }
        }
        try? modelContext.save()

        if writeStrengthToHealthKit {
            let start = session.startDate
            let end = session.endDate ?? Date()
            let sessionUUID = session.uuid
            Task {
                await health.saveStrengthWorkout(start: start, end: end, sessionUUID: sessionUUID)
            }
        }

        finishedSession = session
        showSummary = true
    }

    private func handleSummaryDismissed() {
        guard finishedSession != nil else { return }
        finishedSession = nil
        if controller.exerciseListChanged, templateSaveDecision == .undecided {
            showSaveTemplate = true
        } else {
            onFinished()
        }
    }

    private func noteExerciseStructureChanged() {
        guard controller.program != nil,
              controller.programDay != nil,
              controller.exerciseListChanged,
              templateSaveDecision == .undecided
        else { return }
        showMidWorkoutSaveTemplate = true
    }

    private func rewriteDayTemplate() {
        guard let day = controller.programDay else { return }
        for existing in day.exercises {
            modelContext.delete(existing)
        }
        for (index, exercise) in controller.exercises.enumerated() {
            let item = DayExercise(
                name: exercise.name,
                primaryMuscles: exercise.primaryMuscles,
                secondaryMuscles: exercise.secondaryMuscles,
                targetSets: exercise.targetSets,
                targetReps: exercise.targetReps ?? 0,
                sortIndex: index,
                equipment: exercise.equipment,
                supersetGroupID: exercise.supersetGroupID
            )
            item.restSeconds = exercise.restSeconds
            item.day = day
            modelContext.insert(item)
        }
        try? modelContext.save()
    }
}

struct SessionExerciseCard: View {
    @ObservedObject var controller: SessionController
    let exercise: DraftExercise
    let unit: WeightUnit
    let accent: Color
    let previousSets: [SetLog]
    var sessions: [WorkoutSession] = []
    var showStressAnalysis: Bool = true
    var onReorder: () -> Void
    var onStructureChanged: () -> Void
    var onDeleteSet: (UUID) -> Void

    @State private var showHistory = false
    @State private var showDetails = false
    @State private var showVBT = false
    @State private var showSwapPicker = false
    @State private var showRemoveConfirm = false
    @State private var showSwapConfirm = false
    @State private var pendingSwapCatalog: CatalogExercise?
    @State private var pendingSwapCustom: (name: String, equipment: ExerciseEquipment, primary: [String], secondary: [String])?

    private var live: DraftExercise {
        controller.exercises.first(where: { $0.id == exercise.id }) ?? exercise
    }

    private var draft: ExerciseDraft {
        controller.draft(for: exercise.id)
    }

    private var weightFocused: Bool {
        controller.focusedField == .weight(exercise.id, setID: nil)
    }

    private var repsFocused: Bool {
        controller.focusedField == .reps(exercise.id, setID: nil)
    }

    private var nextSetNumber: Int {
        live.logged.count + 1
    }

    private var fatigueHint: String? {
        guard showStressAnalysis else { return nil }
        return StressCalculator.sessionFatigueHint(
            primaryMuscles: live.primaryMuscles,
            sessions: sessions
        )
    }

    private var showSuggestion: Bool {
        controller.showSuggestion(for: exercise.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if live.supersetGroupID != nil {
                Text("SUPERSET")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(accent.opacity(0.14))
                    .clipShape(Capsule())
            }
            if controller.latestPRExerciseID == exercise.id,
               let estimate = controller.latestPREstimateKg {
                Text("New estimated 1RM PR — \(unit.format(estimate))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            HStack(alignment: .top, spacing: 12) {
                Button {
                    showDetails = true
                } label: {
                    exerciseThumbnail
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Exercise details")

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(live.name)
                            .font(.headline)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            showHistory = true
                        } label: {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(accent)
                                .frame(width: 32, height: 32)
                                .background(accent.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .layoutPriority(1)
                        .accessibilityLabel("Exercise history and 1RM")
                        Menu {
                            Button {
                                showDetails = true
                            } label: {
                                Label("Exercise details", systemImage: "info.circle")
                            }
                            if VBTLift(exerciseName: live.name) != nil {
                                Button {
                                    showVBT = true
                                } label: {
                                    Label("VBT mode", systemImage: "speedometer")
                                }
                            }
                            Button {
                                onReorder()
                            } label: {
                                Label("Reorder exercises", systemImage: "line.3.horizontal")
                            }
                            Button {
                                showSwapPicker = true
                            } label: {
                                Label("Swap exercise", systemImage: "arrow.triangle.2.circlepath")
                            }
                            Button(role: .destructive) {
                                if live.logged.isEmpty {
                                    controller.removeExercise(id: exercise.id)
                                    onStructureChanged()
                                } else {
                                    showRemoveConfirm = true
                                }
                            } label: {
                                Label("Remove exercise", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(accent)
                                .frame(width: 32, height: 32)
                                .background(accent.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .layoutPriority(1)
                        .accessibilityLabel("Exercise actions")
                    }
                    if let fatigueHint {
                        Text(fatigueHint)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(.top, 4)
                    }
                    Spacer(minLength: 0)
                    if !live.primaryMuscles.isEmpty || live.targetSets > 0 {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            if !live.primaryMuscles.isEmpty {
                                Text(live.primaryMuscles.joined(separator: ", "))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                Spacer(minLength: 0)
                            }
                            if live.targetSets > 0 {
                                Text("\(live.logged.count) out of \(live.targetSets) sets done")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                    }
                }
                .frame(minHeight: thumbnailSize, alignment: .top)
            }

            setColumnHeader

            if !live.logged.isEmpty {
                List {
                    ForEach(Array(live.logged.enumerated()), id: \.element.id) { index, set in
                        let editing = controller.loggedEdits[set.id]
                        let isEditingSet = controller.focusedField?.setID == set.id
                        SetGridRow(
                            setNumber: index + 1,
                            previousSet: previousSets[safe: index],
                            suggestion: ProgressionHintEngine.suggest(
                                setIndex: index,
                                previousSessionSets: previousSets,
                                currentSessionSets: live.logged,
                                targetReps: live.targetReps,
                                unit: unit,
                                lowerIsHarder: AssistedLoad.isAssisted(live.name)
                            ),
                            showSuggestion: showSuggestion,
                            isPR: controller.prSetIDs.contains(set.id),
                            weightText: editing?.weightText ?? unit.formatNumber(set.weightKg),
                            repsText: editing?.repsText ?? "\(set.reps)",
                            rir: editing?.rir ?? set.rir,
                            unit: unit,
                            accent: accent,
                            isPreview: false,
                            weightFocused: controller.focusedField == .weight(exercise.id, setID: set.id),
                            repsFocused: controller.focusedField == .reps(exercise.id, setID: set.id),
                            onPreviousTap: { controller.toggleSuggestion(for: exercise.id) },
                            onWeightTap: {
                                controller.ensureLoggedEdit(exerciseID: exercise.id, setID: set.id, unit: unit)
                                controller.focusedField = .weight(exercise.id, setID: set.id)
                            },
                            onRepsTap: {
                                controller.ensureLoggedEdit(exerciseID: exercise.id, setID: set.id, unit: unit)
                                controller.focusedField = .reps(exercise.id, setID: set.id)
                            }
                        )
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 4))
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isEditingSet ? accent.opacity(0.18) : Color.clear)
                        )
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                onDeleteSet(set.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollDisabled(true)
                .scrollContentBackground(.hidden)
                .frame(height: CGFloat(live.logged.count) * 52)
            }

            SetGridRow(
                setNumber: nextSetNumber,
                previousSet: previousSets[safe: live.logged.count],
                suggestion: ProgressionHintEngine.suggest(
                    setIndex: live.logged.count,
                    previousSessionSets: previousSets,
                    currentSessionSets: live.logged,
                    targetReps: live.targetReps,
                    unit: unit,
                    lowerIsHarder: AssistedLoad.isAssisted(live.name)
                ),
                showSuggestion: showSuggestion,
                isPR: false,
                weightText: draft.weightText.isEmpty ? "" : draft.weightText,
                repsText: draft.repsText.isEmpty ? "" : draft.repsText,
                rir: draft.rir,
                unit: unit,
                accent: accent,
                isPreview: true,
                weightFocused: weightFocused,
                repsFocused: repsFocused,
                onPreviousTap: { controller.toggleSuggestion(for: exercise.id) },
                onWeightTap: {
                    controller.ensureDraft(for: exercise.id, unit: unit, previousSets: previousSets)
                    controller.focusedField = .weight(exercise.id, setID: nil)
                },
                onRepsTap: {
                    controller.ensureDraft(for: exercise.id, unit: unit, previousSets: previousSets)
                    controller.focusedField = .reps(exercise.id, setID: nil)
                }
            )
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.opacity(weightFocused || repsFocused ? 0.18 : 0.10))
            )
            .opacity(weightFocused || repsFocused ? 1 : 0.72)
        }
        .padding(16)
        .opaqueCard()
        .overlay(alignment: .leading) {
            if live.supersetGroupID != nil {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(accent)
                    .frame(width: 3)
                    .padding(.vertical, 6)
            }
        }
        .onAppear {
            controller.ensureDraft(for: exercise.id, unit: unit, previousSets: previousSets)
        }
        .fullScreenCover(isPresented: $showVBT) {
            if let lift = VBTLift(exerciseName: live.name) {
                VBTCaptureView(lift: lift)
            }
        }
        .sheet(isPresented: $showHistory) {
            NavigationStack {
                ExerciseHistoryView(exerciseName: live.name, unit: unit, accent: accent)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showHistory = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showDetails) {
            if let catalog = ExerciseCatalog.match(name: live.name) {
                ExercisePreviewSheet(exercise: catalog)
            } else {
                CustomExerciseDetailsSheet(
                    name: live.name,
                    equipment: live.equipment,
                    primaryMuscles: live.primaryMuscles,
                    secondaryMuscles: live.secondaryMuscles
                )
            }
        }
        .sheet(isPresented: $showSwapPicker) {
            NavigationStack {
                ExercisePickerView(
                    mode: .select(onSelect: { catalog in
                        handleSwapSelection(catalog: catalog)
                    }),
                    swappingExercise: live,
                    sessionExerciseNames: Set(controller.exercises.map { $0.name.lowercased() }),
                    onAdd: { _ in },
                    onRemove: { _ in },
                    onCustom: { name, equipment, primary, secondary in
                        handleSwapCustom(name: name, equipment: equipment, primary: primary, secondary: secondary)
                    }
                )
            }
        }
        .alert("Remove exercise?", isPresented: $showRemoveConfirm) {
            Button("Remove", role: .destructive) {
                controller.removeExercise(id: exercise.id)
                onStructureChanged()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(live.name) has logged sets. Removing it will delete those sets.")
        }
        .alert("Swap exercise?", isPresented: $showSwapConfirm) {
            Button("Swap", role: .destructive) {
                performPendingSwap()
            }
            Button("Cancel", role: .cancel) {
                pendingSwapCatalog = nil
                pendingSwapCustom = nil
            }
        } message: {
            Text("\(live.name) has logged sets. Swapping it will clear those sets.")
        }
    }

    private func handleSwapSelection(catalog: CatalogExercise) {
        if live.logged.isEmpty {
            controller.swapExercise(id: exercise.id, with: catalog)
            onStructureChanged()
        } else {
            pendingSwapCatalog = catalog
            pendingSwapCustom = nil
            showSwapConfirm = true
        }
    }

    private func handleSwapCustom(name: String, equipment: ExerciseEquipment, primary: [String], secondary: [String]) {
        if live.logged.isEmpty {
            controller.swapCustom(id: exercise.id, name: name, equipment: equipment, primary: primary, secondary: secondary)
            onStructureChanged()
        } else {
            pendingSwapCustom = (name, equipment, primary, secondary)
            pendingSwapCatalog = nil
            showSwapConfirm = true
        }
    }

    private func performPendingSwap() {
        if let catalog = pendingSwapCatalog {
            controller.swapExercise(id: exercise.id, with: catalog)
        } else if let custom = pendingSwapCustom {
            controller.swapCustom(
                id: exercise.id,
                name: custom.name,
                equipment: custom.equipment,
                primary: custom.primary,
                secondary: custom.secondary
            )
        }
        pendingSwapCatalog = nil
        pendingSwapCustom = nil
        onStructureChanged()
    }

    private var thumbnailSize: CGFloat { 64 }
    private var thumbnailCornerRadius: CGFloat { 10 }

    @ViewBuilder
    private var exerciseThumbnail: some View {
        Group {
            if let image = UIImage(named: thumbnailAssetName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: thumbnailSize)
                    .background(Color.white)
            } else {
                ZStack {
                    Color.white
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(accent.opacity(0.9))
                }
                .frame(width: thumbnailSize, height: thumbnailSize) 
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: thumbnailCornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: thumbnailCornerRadius, style: .continuous))
        .layoutPriority(1)
        .accessibilityHidden(true)
    }

    private var thumbnailAssetName: String {
        if let catalog = ExerciseCatalog.match(name: live.name) {
            return ExerciseCatalog.imageAssetName(for: catalog)
        }
        return "exercise-custom"
    }

    private var setColumnHeader: some View {
        HStack(spacing: 8) {
            Text("Set")
                .frame(width: 32, alignment: .center)
            Text(showSuggestion ? "Suggest" : "Last")
                .frame(width: 88, alignment: .center)
            Text(AssistedLoad.isAssisted(live.name) ? "\(unit.rawValue) assist" : unit.rawValue)
                .frame(maxWidth: .infinity, alignment: .center)
            Text("Reps")
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.tertiary)
        .textCase(.uppercase)
        .padding(.trailing, 10)
    }
}

private struct SetGridRow: View {
    let setNumber: Int
    let previousSet: SetLog?
    let suggestion: ProgressionSuggestion?
    let showSuggestion: Bool
    let isPR: Bool
    let weightText: String
    let repsText: String
    let rir: Int
    let unit: WeightUnit
    let accent: Color
    let isPreview: Bool
    let weightFocused: Bool
    let repsFocused: Bool
    var onPreviousTap: () -> Void
    var onWeightTap: () -> Void
    var onRepsTap: () -> Void
    @Environment(AppTheme.self) private var theme

    var body: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                Text("\(setNumber)")
                    .font(.body.weight(.bold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(theme.mutedFill)
                    .clipShape(Circle())
                if isPR {
                    Text("PR")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(accent)
                        .clipShape(Capsule())
                        .offset(x: 6, y: -6)
                }
            }

            previousCell
                .frame(width: 88, alignment: .center)

            inputCell(
                value: weightText,
                placeholder: "—",
                focused: weightFocused,
                action: onWeightTap
            )
            .frame(maxWidth: .infinity)

            repsCell(isInput: true)
                .frame(maxWidth: .infinity)
        }
        .padding(.trailing, 14)
    }

    @ViewBuilder
    private var previousCell: some View {
        Button(action: onPreviousTap) {
            if showSuggestion, let suggestion {
                Text("\(unit.formatNumber(suggestion.weightKg)) × \(suggestion.reps)")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            } else if let previousSet {
                HStack(spacing: 4) {
                    Text("\(unit.formatNumber(previousSet.weight)) × \(previousSet.reps)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    RIRDot(rir: previousSet.rir, size: 14)
                }
            } else {
                Text("—")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }

    private func inputCell(value: String, placeholder: String, focused: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(value.isEmpty ? placeholder : value)
                .font(.body.monospacedDigit().weight(.semibold))
                .foregroundStyle(value.isEmpty ? Color.secondary : Color.primary)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.2), value: value)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(theme.mutedFill)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(focused ? accent : Color.clear, lineWidth: 2)
                        .animation(.snappy(duration: 0.2), value: focused)
                )
        }
        .buttonStyle(.borderless)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func repsCell(isInput: Bool) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if isInput {
                    Button(action: onRepsTap) {
                        repsFieldContent(isInput: true)
                    }
                    .buttonStyle(.borderless)
                    .contentShape(Rectangle())
                } else {
                    repsFieldContent(isInput: false)
                }
            }

            RIRDot(rir: rir, size: 24)
                .offset(x: 5, y: 5)
                .zIndex(10)
                .allowsHitTesting(false)
        }
    }

    private func repsFieldContent(isInput: Bool) -> some View {
        Text(repsText.isEmpty && isInput ? "—" : repsText)
            .font(.body.monospacedDigit().weight(.semibold))
            .foregroundStyle(repsText.isEmpty && isInput ? Color.secondary : Color.primary)
            .contentTransition(.numericText())
            .animation(.snappy(duration: 0.2), value: repsText)
            .frame(maxWidth: .infinity, minHeight: 36)
            .padding(.trailing, 12)
            .background(isInput ? (isPreview ? theme.mutedFill : theme.mutedFill.opacity(0.72)) : theme.mutedFill.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isInput && repsFocused ? accent : Color.clear, lineWidth: 2)
                    .animation(.snappy(duration: 0.2), value: repsFocused)
            )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
