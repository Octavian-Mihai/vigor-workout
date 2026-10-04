import SwiftUI

enum ExercisePickerMode {
    case toggleAddRemove
    case select(onSelect: (CatalogExercise) -> Void)
}

struct ExercisePickerView: View {
    var mode: ExercisePickerMode = .toggleAddRemove
    var initialAddedCatalogIDs: Set<String> = []
    var shouldConfirmRemove: ((CatalogExercise) -> Bool)? = nil
    var swappingExercise: DraftExercise? = nil
    var sessionExerciseNames: Set<String> = []
    var onAdd: (CatalogExercise) -> Void
    var onRemove: (CatalogExercise) -> Void
    var onCustom: (String, ExerciseEquipment, [String], [String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppTheme.self) private var theme
    @State private var query = ""
    @State private var showCustom = false
    @State private var previewExercise: CatalogExercise?
    @State private var categoryFilter: ExerciseCategory?
    @State private var equipmentFilter: ExerciseEquipment?
    @State private var muscleFilter: MuscleGroup?
    @State private var pendingCustom: (name: String, equipment: ExerciseEquipment, primary: [String], secondary: [String])?
    @State private var showCustomNotifyAlert = false
    @State private var addedCatalogIDs: Set<String> = []
    @State private var addFeedbackTrigger = 0
    @State private var removeFeedbackTrigger = 0
    @State private var pendingRemoveExercise: CatalogExercise?

    private var accent: Color {
        theme.accent
    }

    private var filtered: [CatalogExercise] {
        ExerciseCatalog.displaySorted(
            ExerciseCatalog.all.filter { item in
                let matchesQuery = query.isEmpty
                    || item.name.localizedCaseInsensitiveContains(query)
                    || item.primaryNames.contains { $0.localizedCaseInsensitiveContains(query) }
                let matchesCategory = categoryFilter == nil || item.category == categoryFilter
                let matchesEquipment = equipmentFilter == nil || item.equipment == equipmentFilter
                let matchesMuscle = muscleFilter == nil
                    || item.primary.contains(muscleFilter!)
                    || item.secondary.contains(muscleFilter!)
                return matchesQuery && matchesCategory && matchesEquipment && matchesMuscle
            }
        )
    }

    private var swapRecommendationContext: (category: ExerciseCategory, primaryMuscles: Set<MuscleGroup>)? {
        guard swappingExercise != nil else { return nil }
        guard case .select = mode else { return nil }
        guard let source = swappingExercise else { return nil }
        let primaryMuscles = Set(source.primaryMuscles.compactMap { MuscleGroup.parse($0) })
        guard !primaryMuscles.isEmpty,
              let category = ExerciseCatalog.match(name: source.name)?.category
        else { return nil }
        return (category, primaryMuscles)
    }

    private var recommendedExercises: [CatalogExercise] {
        guard let context = swapRecommendationContext else { return [] }
        return ExerciseCatalog.displaySorted(
            filtered.filter { item in
                item.category == context.category
                    && item.primary.contains(where: { context.primaryMuscles.contains($0) })
                    && !sessionExerciseNames.contains(item.name.lowercased())
            }
        )
    }

    private var recommendedExerciseIDs: Set<String> {
        Set(recommendedExercises.map(\.id))
    }

    private var groupedFiltered: [(ExerciseCategory, [CatalogExercise])] {
        ExerciseCategory.allCases.compactMap { category in
            let items = filtered.filter {
                $0.category == category && !recommendedExerciseIDs.contains($0.id)
            }
            return items.isEmpty ? nil : (category, items)
        }
    }

    private var navigationTitle: String {
        switch mode {
        case .toggleAddRemove:
            return "Add exercise"
        case .select:
            return "Swap exercise"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            List {
                if filtered.isEmpty {
                    Text("No exercises match your search or filters.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                } else {
                    if !recommendedExercises.isEmpty {
                        Section("Recommended") {
                            ForEach(recommendedExercises) { item in
                                switch mode {
                                case .toggleAddRemove:
                                    ExercisePickerRow(
                                        exercise: item,
                                        isAdded: addedCatalogIDs.contains(item.id),
                                        onPreview: { previewExercise = item },
                                        onToggle: { toggleExercise(item) }
                                    )
                                case .select(let onSelect):
                                    ExercisePickerSelectRow(
                                        exercise: item,
                                        onPreview: { previewExercise = item },
                                        onSelect: {
                                            onSelect(item)
                                            dismiss()
                                        }
                                    )
                                }
                            }
                        }
                    }
                    ForEach(groupedFiltered, id: \.0) { category, items in
                        Section(category.rawValue) {
                            ForEach(items) { item in
                                switch mode {
                                case .toggleAddRemove:
                                    ExercisePickerRow(
                                        exercise: item,
                                        isAdded: addedCatalogIDs.contains(item.id),
                                        onPreview: { previewExercise = item },
                                        onToggle: { toggleExercise(item) }
                                    )
                                case .select(let onSelect):
                                    ExercisePickerSelectRow(
                                        exercise: item,
                                        onPreview: { previewExercise = item },
                                        onSelect: {
                                            onSelect(item)
                                            dismiss()
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .background(theme.groupedBackground)
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search exercises or muscles"
        )
        .compactNavigationTitle(navigationTitle)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Custom") { showCustom = true }
            }
        }
        .sheet(isPresented: $showCustom) {
            NavigationStack {
                CustomExerciseForm { name, equipment, primary, secondary in
                    pendingCustom = (name, equipment, primary, secondary)
                    showCustomNotifyAlert = true
                }
            }
        }
        .sheet(item: $previewExercise) { exercise in
            switch mode {
            case .toggleAddRemove:
                ExercisePreviewSheet(
                    exercise: exercise,
                    isAdded: addedCatalogIDs.contains(exercise.id)
                ) {
                    if !addedCatalogIDs.contains(exercise.id) {
                        toggleExercise(exercise)
                    }
                }
            case .select(let onSelect):
                ExercisePreviewSheet(
                    exercise: exercise,
                    isAdded: false,
                    confirmTitle: "Select"
                ) {
                    onSelect(exercise)
                    dismiss()
                }
            }
        }
        .onAppear {
            if case .toggleAddRemove = mode {
                addedCatalogIDs = initialAddedCatalogIDs
            }
        }
        .sensoryFeedback(.selection, trigger: addFeedbackTrigger)
        .sensoryFeedback(.impact, trigger: removeFeedbackTrigger)
        .alert("Add custom exercise", isPresented: $showCustomNotifyAlert) {
            Button("Add only") {
                finalizeCustom(notifyAdmin: false)
            }
            Button("Add & notify admin") {
                finalizeCustom(notifyAdmin: true)
            }
            Button("Cancel", role: .cancel) {
                pendingCustom = nil
            }
        } message: {
            Text("Request inclusion in the global catalog by notifying the admin, or add this exercise to your program only.")
        }
        .alert("Remove exercise?", isPresented: Binding(
            get: { pendingRemoveExercise != nil },
            set: { if !$0 { pendingRemoveExercise = nil } }
        )) {
            Button("Remove", role: .destructive) {
                if let exercise = pendingRemoveExercise {
                    performRemove(exercise)
                    pendingRemoveExercise = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingRemoveExercise = nil
            }
        } message: {
            if let exercise = pendingRemoveExercise {
                Text("\(exercise.name) has logged sets. Removing it will delete those sets.")
            }
        }
    }

    private func finalizeCustom(notifyAdmin: Bool) {
        guard let pending = pendingCustom else { return }
        onCustom(pending.name, pending.equipment, pending.primary, pending.secondary)
        pendingCustom = nil
        if case .select = mode {
            dismiss()
        }
        if notifyAdmin {
            _ = ExerciseSubmissionService.openMail(
                exerciseName: pending.name,
                equipment: pending.equipment,
                primaryMuscles: pending.primary,
                secondaryMuscles: pending.secondary
            )
        }
    }

    private func toggleExercise(_ exercise: CatalogExercise) {
        if addedCatalogIDs.contains(exercise.id) {
            if shouldConfirmRemove?(exercise) == true {
                pendingRemoveExercise = exercise
                return
            }
            performRemove(exercise)
        } else {
            onAdd(exercise)
            addedCatalogIDs.insert(exercise.id)
            addFeedbackTrigger += 1
        }
    }

    private func performRemove(_ exercise: CatalogExercise) {
        onRemove(exercise)
        addedCatalogIDs.remove(exercise.id)
        removeFeedbackTrigger += 1
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "All", selected: categoryFilter == nil && equipmentFilter == nil && muscleFilter == nil) {
                    categoryFilter = nil
                    equipmentFilter = nil
                    muscleFilter = nil
                }

                Menu {
                    Button("All categories") { categoryFilter = nil }
                    Divider()
                    ForEach(ExerciseCategory.allCases) { cat in
                        Button(cat.rawValue) { categoryFilter = cat }
                    }
                } label: {
                    FilterChipLabel(
                        title: categoryFilter?.rawValue ?? "Category",
                        selected: categoryFilter != nil
                    )
                }

                Menu {
                    Button("All equipment") { equipmentFilter = nil }
                    Divider()
                    ForEach(ExerciseEquipment.allCases) { eq in
                        Button(eq.displayTitle) { equipmentFilter = eq }
                    }
                } label: {
                    FilterChipLabel(
                        title: equipmentFilter?.displayTitle ?? "Equipment",
                        selected: equipmentFilter != nil
                    )
                }

                Menu {
                    Button("All muscles") { muscleFilter = nil }
                    Divider()
                    ForEach(MuscleGroup.allCases.sorted { $0.rawValue < $1.rawValue }) { muscle in
                        Button(muscle.rawValue) { muscleFilter = muscle }
                    }
                } label: {
                    FilterChipLabel(
                        title: muscleFilter?.rawValue ?? "Muscle",
                        selected: muscleFilter != nil
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(theme.cardFill)
        .overlay(alignment: .bottom) { Divider() }
    }
}

private struct ExercisePickerSelectRow: View {
    let exercise: CatalogExercise
    var onPreview: () -> Void
    var onSelect: () -> Void
    @Environment(AppTheme.self) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(exercise.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    HStack(spacing: 8) {
                        Text(exercise.primaryNames.joined(separator: ", "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                        Text(exercise.equipment.shortBadge)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(theme.mutedFill)
                            .clipShape(Capsule())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Select \(exercise.name)")

            Button(action: onPreview) {
                Image(systemName: "info.circle")
                    .font(.title3)
                    .foregroundStyle(theme.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Preview \(exercise.name)")
        }
    }
}

private struct ExercisePickerRow: View {
    let exercise: CatalogExercise
    var isAdded: Bool
    var onPreview: () -> Void
    var onToggle: () -> Void
    @Environment(AppTheme.self) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPreview) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(exercise.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    HStack(spacing: 8) {
                        Text(exercise.primaryNames.joined(separator: ", "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                        Text(exercise.equipment.shortBadge)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(theme.mutedFill)
                            .clipShape(Capsule())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Preview \(exercise.name)")

            Button(action: onToggle) {
                Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(theme.accent)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isAdded ? "Remove \(exercise.name)" : "Add \(exercise.name)")
        }
    }
}

struct FilterChip: View {
    let title: String
    let selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            FilterChipLabel(title: title, selected: selected)
        }
        .buttonStyle(.plain)
    }
}

struct FilterChipLabel: View {
    let title: String
    let selected: Bool
    @Environment(AppTheme.self) private var theme

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(selected ? Color.white : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(selected ? Color.accentColor : theme.mutedFill)
            .clipShape(Capsule())
    }
}

enum CustomExerciseFormMode: Equatable {
    case add
    case edit(originalName: String)

    var navigationTitle: String {
        switch self {
        case .add: return "Custom exercise"
        case .edit: return "Edit exercise"
        }
    }

    var saveTitle: String {
        switch self {
        case .add: return "Add"
        case .edit: return "Save"
        }
    }
}

struct CustomExerciseForm: View {
    var mode: CustomExerciseFormMode = .add
    var initialName: String = ""
    var initialEquipment: ExerciseEquipment = .barbell
    var initialPrimary: [String] = []
    var initialSecondary: [String] = []
    var onSave: (String, ExerciseEquipment, [String], [String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var equipment: ExerciseEquipment = .barbell
    @State private var primary: Set<String> = []
    @State private var secondary: Set<String> = []

    var body: some View {
        Form {
            TextField("Exercise name", text: $name)
            HStack {
                Text("Equipment")
                Spacer()
                Menu {
                    ForEach(ExerciseEquipment.allCases) { item in
                        Button(item.displayTitle) { equipment = item }
                    }
                } label: {
                    FilterChipLabel(
                        title: equipment.displayTitle,
                        selected: true
                    )
                }
                .buttonStyle(.plain)
            }
            Section("Primary muscles") {
                ForEach(MuscleGroup.allCases) { muscle in
                    Toggle(muscle.rawValue, isOn: primaryBinding(muscle.rawValue))
                        .disabled(secondary.contains(muscle.rawValue))
                }
            }
            Section("Secondary muscles") {
                ForEach(MuscleGroup.allCases) { muscle in
                    Toggle(muscle.rawValue, isOn: secondaryBinding(muscle.rawValue))
                        .disabled(primary.contains(muscle.rawValue))
                }
            }
        }
        .navigationTitle(mode.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            name = initialName
            equipment = initialEquipment
            primary = Set(initialPrimary)
            secondary = Set(initialSecondary)
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(mode.saveTitle) {
                    onSave(name.trimmingCharacters(in: .whitespaces), equipment, Array(primary), Array(secondary))
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func primaryBinding(_ value: String) -> Binding<Bool> {
        Binding(
            get: { primary.contains(value) },
            set: { isOn in
                if isOn {
                    primary.insert(value)
                    secondary.remove(value)
                } else {
                    primary.remove(value)
                }
            }
        )
    }

    private func secondaryBinding(_ value: String) -> Binding<Bool> {
        Binding(
            get: { secondary.contains(value) },
            set: { isOn in
                if isOn {
                    secondary.insert(value)
                    primary.remove(value)
                } else {
                    secondary.remove(value)
                }
            }
        )
    }
}
