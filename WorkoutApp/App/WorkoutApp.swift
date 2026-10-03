import SwiftUI
import SwiftData

enum ScreenshotDefaults {
    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITEST_SCREENSHOTS")
            || ProcessInfo.processInfo.environment["UITEST_SCREENSHOTS"] == "1"
    }

    static let accentHex = "41BD75"
    static let backgroundHex = "190000"

    static var accentColor: Color {
        Color(hex: accentHex) ?? AccentOption.green.color
    }

    static func apply() {
        guard isActive else { return }
        let defaults = UserDefaults.standard
        defaults.set(AppearanceMode.dark.rawValue, forKey: AppTheme.appearanceModeKey)
        defaults.set(AccentTheme.customName, forKey: "accentName")
        defaults.set(accentHex, forKey: AccentTheme.customHexKey)
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
                .preferredColorScheme(ScreenshotDefaults.isActive ? .dark : appTheme.resolvedColorScheme)
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
