import SwiftUI
import SwiftData

enum ScreenshotDefaults {
    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITEST_SCREENSHOTS")
            || ProcessInfo.processInfo.environment["UITEST_SCREENSHOTS"] == "1"
    }

    static let backgroundHex = "FFFFFF"

    static var accentColor: Color { AccentOption.orange.color }

    static func apply() {
        guard isActive else { return }
        let defaults = UserDefaults.standard
        defaults.set(AppearanceMode.light.rawValue, forKey: AppTheme.appearanceModeKey)
        defaults.set(AccentOption.orange.rawValue, forKey: "accentName")
        defaults.set(BackgroundTheme.customName, forKey: BackgroundTheme.backgroundNameKey)
        defaults.set(backgroundHex, forKey: BackgroundTheme.customHexKey)
        defaults.set(true, forKey: "hasSeenAppGuide")
        defaults.synchronize()
    }
}

private let _applyScreenshotDefaults: Void = ScreenshotDefaults.apply()

@main
struct WorkoutApp: App {
    @State private var appTheme: AppTheme

    init() {
        ScreenshotDefaults.apply()
        _appTheme = State(initialValue: AppTheme())
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(appTheme)
                .tint(ScreenshotDefaults.isActive ? ScreenshotDefaults.accentColor : appTheme.accent)
                .preferredColorScheme(ScreenshotDefaults.isActive ? .light : appTheme.resolvedColorScheme)
        }
        .modelContainer(for: [
            Program.self,
            ProgramDay.self,
            DayExercise.self,
            WorkoutSession.self,
            SetLog.self,
            BodyWeightEntry.self,
            BodyMeasurementEntry.self,
            DailyCheckIn.self
        ])
    }
}
