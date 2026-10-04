import SwiftUI
import SwiftData
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppTheme.self) private var appTheme
    @Environment(AppTourController.self) private var tour
    @EnvironmentObject private var health: HealthKitService
    @Query private var programs: [Program]
    @Query private var sessions: [WorkoutSession]
    @Query private var weightEntries: [BodyWeightEntry]
    @Query private var measurementEntries: [BodyMeasurementEntry]
    @Query private var checkInEntries: [DailyCheckIn]
    @AppStorage("weightUnit") private var weightUnitRaw = WeightUnit.lb.rawValue
    @AppStorage("lengthUnit") private var lengthUnitRaw = LengthUnit.cm.rawValue
    @AppStorage("distanceUnit") private var distanceUnitRaw = DistanceUnit.km.rawValue
    @AppStorage("defaultRestSeconds") private var defaultRestSeconds = 90
    @AppStorage("restTimerHaptics") private var restTimerHaptics = true
    @AppStorage(RestTimerSettings.notificationsKey) private var restTimerNotifications = true
    @AppStorage(EquipmentSettings.barbellBarKgKey) private var barbellBarKg = EquipmentSettings.defaultBarKg
    @AppStorage(EquipmentSettings.barbellBarLbKey) private var barbellBarLb = EquipmentSettings.defaultBarLb
    @AppStorage(StressVisibility.showAnalysisKey) private var showStressAnalysis = true
    @AppStorage(StressVisibility.colorPresetKey) private var stressColorPresetRaw = StressColorPreset.classic.rawValue
    @AppStorage(CheckInVisibility.showOnHomeKey) private var showDailyCheckIn = true
    @AppStorage(InfoPageVisibility.showVolumeChartsKey) private var showVolumeCharts = true
    @AppStorage(InfoPageVisibility.showEstimated1RMKey) private var showEstimated1RM = true
    @AppStorage(InfoPageVisibility.showTrainingLoadEvolutionKey) private var showTrainingLoadEvolution = true
    @AppStorage(RunningVisibility.showTabKey) private var showRunningTab = true
    @AppStorage(RunningVisibility.showActivityKey) private var showRunningActivity = true
    @AppStorage(HealthKitService.writeStrengthToHealthKitKey) private var writeStrengthToHealthKit = false
    @State private var showDeleteConfirm = false
    @State private var showImporter = false
    @State private var showExport = false
    @State private var dataError: String?
    @State private var showDataError = false

    private var versionLabel: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var unit: WeightUnit {
        WeightUnit(rawValue: weightUnitRaw) ?? .lb
    }

    var body: some View {
        @Bindable var theme = appTheme

        NavigationStack {
            ScrollViewReader { proxy in
            List {
                Section("Accent") {
                    AccentPickerDashboard(accentName: $theme.accentName, customHex: $theme.customAccentHex)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }

                Section("Appearance") {
                    Picker("Mode", selection: $theme.appearanceMode) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    BackgroundPickerDashboard(
                        backgroundName: $theme.backgroundName,
                        customHex: $theme.customBackgroundHex
                    )
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))

                    Text("Cards use opaque fills and borders — no glass or ultra-thin materials.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Units") {
                    Picker("Weight", selection: $weightUnitRaw) {
                        ForEach(WeightUnit.allCases) { unit in
                            Text(unit.title).tag(unit.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("Lifting loads and body weight are stored in kilograms and converted for display.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Length", selection: $lengthUnitRaw) {
                        ForEach(LengthUnit.allCases) { unit in
                            Text(unit.title).tag(unit.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("Body circumferences and height are stored in centimeters and converted for display.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Distance", selection: $distanceUnitRaw) {
                        ForEach(DistanceUnit.allCases) { unit in
                            Text(unit.title).tag(unit.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("Running distance and pace use this unit. Values from Health stay in meters internally.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tourTarget(.settings)
                .id(AppTourTargetID.settings)

                Section("Session") {
                    Stepper("Default rest \(defaultRestSeconds)s", value: $defaultRestSeconds, in: 15...300, step: 15)
                    Toggle("Rest-timer haptics", isOn: $restTimerHaptics)
                    Toggle("Rest timer notifications", isOn: $restTimerNotifications)
                }

                Section("Stress") {
                    Toggle("Show stress analysis", isOn: $showStressAnalysis)
                    Text("Turn off to hide stress scores on Home, Info, Running, and widgets.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Today’s stress colors")
                        .font(.subheadline.weight(.semibold))
                    StressColorPresetPicker(presetRaw: $stressColorPresetRaw)
                    Text("Lift, cardio, and total meters and charts use the selected palette.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Daily check-in") {
                    Toggle("Show check-in on Home", isOn: $showDailyCheckIn)
                    Text("Log sleep, mood and energy. After a couple of weeks, Info → Daily check-in shows what seems to affect how you feel. Turn off to hide the card on Home; your entries stay.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    CheckInReminderSettingsRows()
                }

                Section("Info page") {
                    Toggle("Show volume charts (weekly trend, per muscle)", isOn: $showVolumeCharts)
                    Toggle("Show estimated 1RM", isOn: $showEstimated1RM)
                    Toggle("Show training load evolution", isOn: $showTrainingLoadEvolution)
                    Text("Hidden sections do not appear on the Info tab.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Running") {
                    Toggle("Show Running tab", isOn: $showRunningTab)
                    Toggle("Show cardio activity", isOn: $showRunningActivity)
                    Text("Turn off the Running tab to hide it. Turn off cardio activity to hide runs, rides, walks and other cardio on the Home and widget activity grids.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Equipment") {
                    if unit == .kg {
                        Stepper(
                            "Barbell bar \(Formatters.trimmedNumber(barbellBarKg)) kg",
                            value: $barbellBarKg,
                            in: 5...40,
                            step: 2.5
                        )
                    } else {
                        Stepper(
                            "Barbell bar \(Formatters.trimmedNumber(barbellBarLb)) lb",
                            value: $barbellBarLb,
                            in: 15...70,
                            step: 5
                        )
                    }
                    Text("The plate calculator subtracts bar weight for barbell exercises, then shows plates per side. Machine and functional-trainer exercises use the logged weight directly.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Measurements") {
                    NavigationLink("Measurements") {
                        MeasurementsView()
                    }
                }

                Section("Health") {
                    Toggle("Write finished workouts to Apple Health", isOn: $writeStrengthToHealthKit)
                    Text("When this is on, finishing a strength session adds a Traditional Strength Training workout to Apple Health. When it’s off, sessions stay in this app only. Running is read from Health. Body weight is read from and saved to Health.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Re-request HealthKit access") {
                        Task { await health.requestAndLoad() }
                    }
                    Button("Open Apple Health") {
                        if let url = URL(string: "x-apple-health://") {
                            UIApplication.shared.open(url)
                        }
                    }
                }

                Section("Privacy") {
                    NavigationLink("What we store") {
                        PrivacyInfoView()
                    }
                }

                Section("Data") {
                    Button {
                        showExport = true
                    } label: {
                        Label("Export data", systemImage: "square.and.arrow.up")
                    }
                    Button("Import workout data") {
                        showImporter = true
                    }
                    Button("Delete all local data", role: .destructive) {
                        showDeleteConfirm = true
                    }
                }

                Section("About") {
                    Button {
                        tour.start()
                    } label: {
                        HStack {
                            Text("How to use this app")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(versionLabel)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.groupedBackground)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .alert("Delete all local data?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) { deleteAllLocalData() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes programs, workout history, measurements, and body-weight entries from this device. Apple Health data is not deleted.")
            }
            .onChange(of: writeStrengthToHealthKit) { _, isOn in
                if isOn {
                    Task { await health.requestAndLoad() }
                }
            }
            .alert("Couldn’t import workout data", isPresented: $showDataError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(dataError ?? "The file could not be read.")
            }
            .sheet(isPresented: $showExport) {
                ExportDataView(
                    programs: programs,
                    sessions: sessions,
                    weights: weightEntries,
                    measurements: measurementEntries,
                    checkIns: checkInEntries
                )
                .environmentObject(health)
                .environment(appTheme)
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    importWorkoutData(from: url)
                case .failure(let error):
                    dataError = error.localizedDescription
                    showDataError = true
                }
            }
            .onChange(of: tour.step) { _, step in
                if step == .settings {
                    DispatchQueue.main.async {
                        withAnimation {
                            proxy.scrollTo(AppTourTargetID.settings, anchor: .center)
                        }
                    }
                }
            }
            }
        }
    }

    private func importWorkoutData(from url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer {
            if access { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let data = try Data(contentsOf: url)
            let backup = try WorkoutBackupService.decode(data)
            try WorkoutBackupService.importBackup(
                backup,
                context: modelContext,
                existingPrograms: programs,
                existingSessions: sessions,
                existingWeights: weightEntries,
                existingMeasurements: measurementEntries,
                existingCheckIns: checkInEntries
            )
        } catch {
            dataError = error.localizedDescription
            showDataError = true
        }
    }

    private func deleteAllLocalData() {
        for item in programs { modelContext.delete(item) }
        for item in sessions { modelContext.delete(item) }
        for item in weightEntries { modelContext.delete(item) }
        for item in checkInEntries { modelContext.delete(item) }
        for item in measurementEntries {
            ProgressPhotoStorage.delete(filename: item.photoFilename)
            modelContext.delete(item)
        }
        try? modelContext.save()
    }
}

struct PrivacyInfoView: View {
    var body: some View {
        List {
            Section("On this device") {
                Text("Programs, workout sessions, sets (weight, reps, RIR), body-weight entries, and daily check-ins (sleep, mood, energy, last caffeine) are stored locally with SwiftData. Nothing is uploaded to a server.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Section("Apple Health") {
                Text("Running workouts, GPS routes, distance, heart rate, and last night’s sleep hours (shown beside your daily check-in) are read only. Body weight is read from and written to Apple Health when you use the weight log. Finished strength sessions are written to Health as Traditional Strength Training workouts only if you turn on writing workouts in Settings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Section("Encryption") {
                Text("The app does not use non-exempt encryption. Workout data stays in the device’s standard app container.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .compactNavigationTitle("Privacy")
    }
}
