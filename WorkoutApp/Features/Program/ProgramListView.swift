import SwiftUI
import SwiftData
import UniformTypeIdentifiers

enum WorkoutPageVisibility {
    static let programsExpandedKey = "workoutProgramsExpanded"
    static let historyExpandedKey = "workoutHistoryExpanded"
    static let historyOlderExpandedKey = "workoutHistoryOlderExpanded"
    static let learnExpandedKey = "workoutLearnExpanded"
    static let customExercisesExpandedKey = "workoutCustomExercisesExpanded"
}

struct ProgramListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Program.createdAt) private var programs: [Program]
    @State private var createdUUID: UUID?
    @State private var showImporter = false
    @State private var showStarterPicker = false
    @State private var pendingStarter: StarterProgramTemplate?
    @State private var pendingBlank = false
    @State private var pendingImport = false
    @State private var importError: String?
    @State private var showImportError = false
    @AppStorage(WorkoutPageVisibility.programsExpandedKey) private var programsExpanded = true

    private var activeProgram: Program? {
        programs.first(where: \.isActive)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $programsExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Spacer()
                    Button {
                        showStarterPicker = true
                    } label: {
                        Label("Create", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                    }
                }

                if programs.isEmpty {
                    EmptyStateView(
                        systemImage: "list.bullet.rectangle",
                        title: "No Programs Yet",
                        message: "Start from a template or create a blank program and add rotating days.",
                        actionTitle: "Create Program",
                        action: { showStarterPicker = true }
                    )
                } else {
                    ForEach(programs) { program in
                        programRow(program)
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("Programs")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                if let name = activeProgram?.name {
                    Text(name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .tint(.secondary)
        .navigationDestination(isPresented: Binding(
            get: { createdUUID != nil },
            set: { if !$0 { createdUUID = nil } }
        )) {
            if let uuid = createdUUID, let program = programs.first(where: { $0.uuid == uuid }) {
                ProgramEditorView(program: program)
            }
        }
        .sheet(isPresented: $showStarterPicker, onDismiss: handleStarterPickerDismiss) {
            StarterProgramPickerView(
                onBlank: { pendingBlank = true },
                onSelect: { pendingStarter = $0 },
                onImport: { pendingImport = true }
            )
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                importPlan(from: url)
            case .failure(let error):
                importError = error.localizedDescription
                showImportError = true
            }
        }
        .alert("Couldn’t import plan", isPresented: $showImportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "The file could not be read.")
        }
    }

    private func programRow(_ program: Program) -> some View {
        HStack(alignment: .center, spacing: 12) {
            NavigationLink {
                ProgramEditorView(program: program)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(program.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("\(program.orderedDays.count) day rotation")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            Toggle("Active", isOn: Binding(
                get: { program.isActive },
                set: { newValue in setActive(program, newValue) }
            ))
            .labelsHidden()
            Menu {
                ShareLink(
                    item: ProgramTemplateService.make(from: program),
                    preview: SharePreview("Export plan")
                ) {
                    Label("Export plan", systemImage: "square.and.arrow.up")
                }
                Button("Set active") { setActive(program, true) }
                Button("Delete", role: .destructive) {
                    modelContext.delete(program)
                }
            } label: {
                Image(systemName: "info.circle")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 32, minHeight: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Program info")
        }
        .padding(12)
        .opaqueCard()
    }

    private func importPlan(from url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer {
            if access { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let data = try Data(contentsOf: url)
            let template = try ProgramTemplateService.decode(data)
            try ProgramTemplateService.importTemplate(template, context: modelContext, existingPrograms: programs)
        } catch {
            importError = error.localizedDescription
            showImportError = true
        }
    }

    private func handleStarterPickerDismiss() {
        if pendingImport {
            pendingImport = false
            DispatchQueue.main.async {
                showImporter = true
            }
            return
        }
        applyPendingStarter()
    }

    private func applyPendingStarter() {
        if pendingBlank {
            pendingBlank = false
            createProgram()
        } else if let template = pendingStarter {
            pendingStarter = nil
            applyStarter(template)
        }
    }

    private func createProgram() {
        if let current = programs.first(where: \.isActive) {
            current.isActive = false
        }
        let program = Program(name: "New program", isActive: true)
        modelContext.insert(program)
        try? modelContext.save()
        createdUUID = program.uuid
    }

    private func applyStarter(_ template: StarterProgramTemplate) {
        do {
            let program = try ProgramTemplateService.applyStarter(
                template,
                context: modelContext,
                existingPrograms: programs
            )
            createdUUID = program.uuid
        } catch {
            importError = error.localizedDescription
            showImportError = true
        }
    }

    private func setActive(_ program: Program, _ isActive: Bool) {
        if isActive {
            for item in programs {
                item.isActive = (item.persistentModelID == program.persistentModelID)
            }
        } else {
            program.isActive = false
        }
        try? modelContext.save()
    }
}

struct StarterProgramPickerView: View {
    var onBlank: () -> Void
    var onSelect: (StarterProgramTemplate) -> Void
    var onImport: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        onBlank()
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Blank program")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text("Start empty and add your own days.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }

                    Button {
                        onImport()
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Import JSON")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text("Load a program from a JSON file.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section {
                    ForEach(StarterProgramTemplates.all) { template in
                        Button {
                            onSelect(template)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(template.name)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(template.dayLabel)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(template.dayNamesLabel)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(template.summary)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    Text("Starter templates")
                } footer: {
                    Text("Copies into a new program using exercises from the catalog. Edit days and sets after you start.")
                }
            }
            .navigationTitle("New program")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
