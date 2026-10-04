import SwiftUI
import SwiftData

struct ProgramEditorView: View {
    @Bindable var program: Program
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppTheme.self) private var theme
    @State private var showOverview = false
    @State private var popAfterOverview = false

    var body: some View {
        List {
            Section("Name") {
                TextField("Program name", text: $program.name)
                    .submitLabel(.done)
            }
            Section {
                Toggle("Active program", isOn: Binding(
                    get: { program.isActive },
                    set: { newValue in
                        let all = (try? modelContext.fetch(FetchDescriptor<Program>())) ?? []
                        for item in all {
                            item.isActive = newValue && item.uuid == program.uuid
                        }
                    }
                ))
                Text("Workouts cycle through these days in order. Empty workouts do not advance the rotation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                ForEach(program.orderedDays) { day in
                    NavigationLink {
                        DayEditorView(day: day)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(day.name)
                            Text(dayDurationCaption(day))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onMove(perform: moveDays)
                .onDelete(perform: deleteDays)

                Button {
                    addDay()
                } label: {
                    Label("Add day", systemImage: "plus")
                }
            } header: {
                HStack {
                    Text("Days (rotation)")
                    Spacer()
                    EditButton()
                        .font(.subheadline)
                        .textCase(.none)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Program")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    try? modelContext.save()
                    showOverview = true
                }
                .fontWeight(.semibold)
            }
            ToolbarItem(placement: .primaryAction) {
                ShareLink(
                    item: ProgramTemplateService.make(from: program),
                    preview: SharePreview("Export plan")
                ) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: $showOverview, onDismiss: {
            if popAfterOverview {
                popAfterOverview = false
                dismiss()
            }
        }) {
            ProgramOverviewView(program: program) {
                popAfterOverview = true
                showOverview = false
            }
            .environment(theme)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .onDisappear { try? modelContext.save() }
    }

    private func dayDurationCaption(_ day: ProgramDay) -> String {
        let exercises = day.orderedExercises
        return WorkoutDurationEstimate.caption(
            exerciseCount: exercises.count,
            totalSets: exercises.reduce(0) { $0 + max($1.targetSets, 0) }
        )
    }

    private func addDay() {
        let index = program.days.count
        let day = ProgramDay(name: "Day \(index + 1)", sortIndex: index)
        day.program = program
        modelContext.insert(day)
        try? modelContext.save()
    }

    private func deleteDays(at offsets: IndexSet) {
        let ordered = program.orderedDays
        for offset in offsets {
            modelContext.delete(ordered[offset])
        }
        reindexDays()
    }

    private func moveDays(from source: IndexSet, to destination: Int) {
        var ordered = program.orderedDays
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, day) in ordered.enumerated() {
            day.sortIndex = index
        }
    }

    private func reindexDays() {
        for (index, day) in program.orderedDays.enumerated() {
            day.sortIndex = index
        }
    }
}

struct DayEditorView: View {
    @Bindable var day: ProgramDay
    @Environment(\.modelContext) private var modelContext
    @State private var showPicker = false
    @State private var durationTick = 0

    var body: some View {
        List {
            Section("Day name") {
                TextField("Name", text: $day.name)
                    .submitLabel(.done)
            }
            Section {
                let ordered = day.orderedExercises
                ForEach(Array(ordered.enumerated()), id: \.element.persistentModelID) { index, exercise in
                    DayExerciseEditorRow(
                        exercise: exercise,
                        isLinkedWithNext: index + 1 < ordered.count
                            && exercise.supersetGroupID != nil
                            && exercise.supersetGroupID == ordered[index + 1].supersetGroupID,
                        showLinkToggle: index + 1 < ordered.count,
                        onToggleLinkWithNext: { toggleSuperset(after: exercise) }
                    ) {
                        durationTick += 1
                    }
                }
                .onMove(perform: move)
                .onDelete(perform: delete)

                Button {
                    showPicker = true
                } label: {
                    Label("Add exercise", systemImage: "plus")
                }
            } header: {
                HStack {
                    Text("Exercises")
                    Spacer()
                    if let estimate = durationLabel {
                        Text(estimate)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(.none)
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(day.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar { EditButton() }
        .sheet(isPresented: $showPicker) {
            NavigationStack {
                ExercisePickerView(
                    initialAddedCatalogIDs: existingCatalogIDs,
                    onAdd: { catalog in
                        addExercise(
                            name: catalog.name,
                            primary: catalog.primaryNames,
                            secondary: catalog.secondaryNames,
                            equipment: catalog.equipment
                        )
                    },
                    onRemove: { catalog in
                        removeExercise(matching: catalog)
                    },
                    onCustom: { name, equipment, primary, secondary in
                        addExercise(name: name, primary: primary, secondary: secondary, equipment: equipment)
                    }
                )
            }
        }
    }

    private var durationLabel: String? {
        let _ = durationTick
        let exercises = day.orderedExercises
        return WorkoutDurationEstimate.label(
            exerciseCount: exercises.count,
            totalSets: exercises.reduce(0) { $0 + max($1.targetSets, 0) }
        )
    }

    private var existingCatalogIDs: Set<String> {
        Set(day.orderedExercises.compactMap { ExerciseCatalog.match(name: $0.name)?.id })
    }

    private func addExercise(
        name: String,
        primary: [String],
        secondary: [String],
        equipment: ExerciseEquipment
    ) {
        let item = DayExercise(
            name: name,
            primaryMuscles: primary,
            secondaryMuscles: secondary,
            targetSets: 3,
            targetReps: 8,
            sortIndex: day.exercises.count,
            equipment: equipment
        )
        item.day = day
        modelContext.insert(item)
        durationTick += 1
        try? modelContext.save()
    }

    private func toggleSuperset(after exercise: DayExercise) {
        let ordered = day.orderedExercises
        guard let index = ordered.firstIndex(where: { $0 === exercise }), index + 1 < ordered.count else { return }
        let next = ordered[index + 1]
        if let groupID = exercise.supersetGroupID, groupID == next.supersetGroupID {
            exercise.supersetGroupID = nil
            next.supersetGroupID = nil
        } else {
            let groupID = UUID()
            exercise.supersetGroupID = groupID
            next.supersetGroupID = groupID
        }
        try? modelContext.save()
    }

    private func removeExercise(matching catalog: CatalogExercise) {
        guard let item = day.orderedExercises.last(where: { $0.name == catalog.name }) else { return }
        modelContext.delete(item)
        reindex()
        durationTick += 1
        try? modelContext.save()
    }

    private func delete(at offsets: IndexSet) {
        let ordered = day.orderedExercises
        for offset in offsets {
            modelContext.delete(ordered[offset])
        }
        reindex()
        durationTick += 1
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ordered = day.orderedExercises
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, item) in ordered.enumerated() {
            item.sortIndex = index
        }
    }

    private func reindex() {
        for (index, item) in day.orderedExercises.enumerated() {
            item.sortIndex = index
        }
    }
}

struct DayExerciseEditorRow: View {
    @Bindable var exercise: DayExercise
    var isLinkedWithNext: Bool = false
    var showLinkToggle: Bool = false
    var onToggleLinkWithNext: () -> Void = {}
    var onSetsChanged: () -> Void = {}
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Program.createdAt) private var programs: [Program]
    @Query(sort: \WorkoutSession.startDate, order: .reverse) private var sessions: [WorkoutSession]
    @State private var showEdit = false
    @State private var updateErrorMessage: String?

    private var isCustom: Bool {
        ExerciseCatalog.match(name: exercise.name) == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if exercise.supersetGroupID != nil {
                Text("SUPERSET")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.14))
                    .clipShape(Capsule())
            }
            HStack(alignment: .center, spacing: 8) {
                Text(exercise.name)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isCustom {
                    Button {
                        showEdit = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit \(exercise.name)")
                }
                Stepper(value: Binding(
                    get: { exercise.targetSets },
                    set: { newValue in
                        exercise.targetSets = newValue
                        onSetsChanged()
                    }
                ), in: 0...30) {
                    Text("\(exercise.targetSets) sets")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .fixedSize()
            }
            Text(exercise.primaryMuscles.joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(.secondary)
            if !exercise.secondaryMuscles.isEmpty {
                Text("Secondary: \(exercise.secondaryMuscles.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Stepper(value: Binding(
                    get: { exercise.targetReps },
                    set: { exercise.targetReps = $0 }
                ), in: 1...30) {
                    Text("\(exercise.targetReps) reps target")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Stepper(value: Binding(
                    get: { exercise.restSeconds ?? ExerciseRestDefaults.seconds(for: exercise, fallback: 90) },
                    set: { exercise.restSeconds = $0 }
                ), in: 15...300, step: 15) {
                    Text("Rest \(Formatters.duration(exercise.restSeconds ?? ExerciseRestDefaults.seconds(for: exercise, fallback: 90)))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if showLinkToggle {
                Button(action: onToggleLinkWithNext) {
                    Label(
                        isLinkedWithNext ? "Unlink from next exercise" : "Link with next exercise as superset",
                        systemImage: isLinkedWithNext ? "link.badge.plus" : "link"
                    )
                    .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(isLinkedWithNext ? Color.accentColor : .secondary)
            }
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showEdit) {
            NavigationStack {
                CustomExerciseForm(
                    mode: .edit(originalName: exercise.name),
                    initialName: exercise.name,
                    initialEquipment: exercise.equipment,
                    initialPrimary: exercise.primaryMuscles,
                    initialSecondary: exercise.secondaryMuscles
                ) { newName, equipment, primary, secondary in
                    saveEdit(
                        oldName: exercise.name,
                        newName: newName,
                        equipment: equipment,
                        primary: primary,
                        secondary: secondary
                    )
                }
            }
        }
        .alert("Could not save exercise", isPresented: Binding(
            get: { updateErrorMessage != nil },
            set: { if !$0 { updateErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                updateErrorMessage = nil
            }
        } message: {
            if let updateErrorMessage {
                Text(updateErrorMessage)
            }
        }
    }

    private func saveEdit(
        oldName: String,
        newName: String,
        equipment: ExerciseEquipment,
        primary: [String],
        secondary: [String]
    ) {
        do {
            try CustomExerciseCollector.update(
                oldName: oldName,
                newName: newName,
                equipment: equipment,
                primary: primary,
                secondary: secondary,
                programs: programs,
                sessions: sessions,
                in: modelContext
            )
        } catch {
            updateErrorMessage = error.localizedDescription
        }
    }
}
