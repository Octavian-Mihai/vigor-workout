import SwiftUI
import SwiftData
import UIKit
import UserNotifications

/// Keeps the scheduled reminders in step with the settings and with whether today is already logged.
/// Applied once at the root so it runs whichever tab is showing.
struct CheckInReminderSync: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(CheckInReminder.enabledKey) private var enabled = false
    @AppStorage(CheckInReminder.minutesKey) private var minutes = CheckInReminder.defaultMinutes
    @Query(sort: \DailyCheckIn.date, order: .reverse) private var checkIns: [DailyCheckIn]

    private struct SyncKey: Hashable {
        let enabled: Bool
        let minutes: Int
        let checkedInToday: Bool
        let isActive: Bool
    }

    private var checkedInToday: Bool {
        checkIns.contains { Calendar.current.isDateInToday($0.date) && $0.isComplete }
    }

    func body(content: Content) -> some View {
        content.task(id: SyncKey(
            enabled: enabled,
            minutes: minutes,
            checkedInToday: checkedInToday,
            isActive: scenePhase == .active
        )) {
            guard scenePhase == .active else { return }
            await CheckInReminder.sync(enabled: enabled, minutesIntoDay: minutes, checkedInToday: checkedInToday)
        }
    }
}

/// Settings rows for the reminder: an on/off switch and the time it should arrive.
struct CheckInReminderSettingsRows: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(CheckInReminder.enabledKey) private var enabled = false
    @AppStorage(CheckInReminder.minutesKey) private var minutes = CheckInReminder.defaultMinutes
    @State private var status: UNAuthorizationStatus = .notDetermined
    @State private var triedAndDenied = false

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
            },
            set: { newValue in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                minutes = (parts.hour ?? 20) * 60 + (parts.minute ?? 0)
            }
        )
    }

    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { enabled },
            set: { wantsOn in
                guard wantsOn else {
                    enabled = false
                    return
                }
                Task {
                    let granted = await CheckInReminder.requestAuthorization()
                    enabled = granted
                    triedAndDenied = !granted
                    status = await CheckInReminder.authorizationStatus()
                }
            }
        )
    }

    private var blockedBySystem: Bool {
        status == .denied && (enabled || triedAndDenied)
    }

    var body: some View {
        Toggle("Daily reminder", isOn: toggleBinding)
            .task(id: scenePhase) {
                // Also re-checks after the person comes back from iOS Settings.
                guard scenePhase == .active else { return }
                status = await CheckInReminder.authorizationStatus()
            }

        if enabled {
            DatePicker("Remind me at", selection: timeBinding, displayedComponents: .hourAndMinute)
        }

        if blockedBySystem {
            Text("Notifications are turned off for this app in iOS Settings, so the reminder can’t be delivered.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Open iOS Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        } else {
            Text("A notification at the time you choose, only on days you haven’t checked in yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
