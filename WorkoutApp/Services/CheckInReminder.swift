import Foundation
import UserNotifications

/// The optional daily nudge to do the check-in.
///
/// A repeating notification can't know you've already checked in, so this schedules the next
/// `scheduleDays` one-off reminders instead and rebuilds the list whenever the app comes to the
/// front or the check-in changes. Today's reminder is dropped once today is done. If the app isn't
/// opened for a month the reminders simply run out rather than nagging forever.
enum CheckInReminder {
    static let enabledKey = "checkInReminderEnabled"
    static let minutesKey = "checkInReminderMinutes"
    /// 8:00 pm — late enough that caffeine and screen time for the day are known.
    static let defaultMinutes = 20 * 60
    static let scheduleDays = 30

    private static let identifierPrefix = "checkin-reminder-"

    // MARK: - Planning

    /// The next `days` reminders. Today is left out if it's already done or the time has passed,
    /// and the window then runs one day further so the count stays the same.
    static func fireDates(
        now: Date,
        minutesIntoDay: Int,
        skipToday: Bool,
        days: Int = scheduleDays,
        calendar: Calendar = .current
    ) -> [Date] {
        let minutes = min(max(minutesIntoDay, 0), 24 * 60 - 1)
        let startOfToday = calendar.startOfDay(for: now)

        var dates: [Date] = []
        var offset = 0
        while dates.count < days, offset <= days {
            defer { offset += 1 }
            guard let day = calendar.date(byAdding: .day, value: offset, to: startOfToday),
                  let fire = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day)
            else { continue }
            if offset == 0, skipToday || fire <= now { continue }
            dates.append(fire)
        }
        return dates
    }

    // MARK: - Scheduling

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Asks for notification permission if it hasn't been asked yet. Returns whether reminders can be delivered.
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        @unknown default:
            return false
        }
    }

    /// Replaces any scheduled check-in reminders with the right set for the current settings.
    static func sync(
        enabled: Bool,
        minutesIntoDay: Int,
        checkedInToday: Bool,
        now: Date = Date()
    ) async {
        let center = UNUserNotificationCenter.current()
        await removeAll(from: center)
        guard enabled, !Task.isCancelled else { return }

        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: break
        default: return
        }

        let calendar = Calendar.current
        let dates = fireDates(now: now, minutesIntoDay: minutesIntoDay, skipToday: checkedInToday, calendar: calendar)
        for date in dates {
            // A newer sync (settings or check-in changed) replaces this one; stop adding stale reminders.
            guard !Task.isCancelled else { return }
            let content = UNMutableNotificationContent()
            content.title = "Daily check-in"
            content.body = "How did you sleep, and how are your mood and energy? It takes about 10 seconds."
            content.sound = .default
            content.threadIdentifier = "checkin-reminder"

            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            let id = identifier(for: parts)
            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }

    private static func removeAll(from center: UNUserNotificationCenter) async {
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        guard !ours.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: ours)
    }

    private static func identifier(for parts: DateComponents) -> String {
        String(format: "%@%04d%02d%02d", identifierPrefix, parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
