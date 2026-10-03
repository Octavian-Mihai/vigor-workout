import SwiftUI
import SwiftData

/// Home-screen check-in: three taps to log sleep, mood and energy, then it folds down to a summary.
struct DailyCheckInCard: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppTheme.self) private var theme
    @EnvironmentObject private var health: HealthKitService
    @Query(sort: \DailyCheckIn.date, order: .reverse) private var checkIns: [DailyCheckIn]

    @State private var today = Calendar.current.startOfDay(for: Date())
    @State private var isEditing = false

    private var samples: [CheckInSample] { checkIns.map(CheckInSample.init) }

    private var todayEntry: DailyCheckIn? {
        checkIns.first { Calendar.current.isDate($0.date, inSameDayAs: today) }
    }

    private var isFolded: Bool {
        (todayEntry?.isComplete ?? false) && !isEditing
    }

    private var streak: Int {
        CheckInInsights.currentStreak(samples, today: today)
    }

    var body: some View {
        Group {
            if isFolded, let entry = todayEntry {
                compactRow(for: entry)
            } else {
                fullCard
            }
        }
        .animation(.snappy, value: isFolded)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            let now = Calendar.current.startOfDay(for: Date())
            if now != today {
                today = now
                isEditing = false
            }
        }
        .task(id: health.lastNightSleepHours) {
            CheckInStore.attachSleepHours(health.lastNightSleepHours, to: today, in: context)
        }
    }

    private var fullCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Daily check-in")
                    .font(.headline)
                Spacer(minLength: 8)
                if isEditing {
                    Button("Done") { isEditing = false }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.borderless)
                } else {
                    Text("10 seconds")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            CheckInInputView(day: today, healthSleepHours: health.lastNightSleepHours)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .opaqueCard()
    }

    /// One slim line once everything is answered, so Home stays about workouts.
    private func compactRow(for entry: DailyCheckIn) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(theme.accent)
            NavigationLink {
                CheckInInsightsView()
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(streak >= 2 ? "Checked in · \(streak)-day streak" : "Checked in today")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(summaryLine(for: entry))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            Button("Edit") { isEditing = true }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opaqueCard()
    }

    private func summaryLine(for entry: DailyCheckIn) -> String {
        func value(_ v: Int?) -> String { v.map(String.init) ?? "–" }
        var line = "Sleep \(value(entry.sleepRating)) · Mood \(value(entry.moodRating)) · Energy \(value(entry.energyRating))"
        if let timing = entry.lastCaffeine.flatMap(CaffeineTiming.init(rawValue:)) {
            line += timing == .none ? " · No caffeine" : " · Caffeine \(timing.label.lowercasedFirst)"
        }
        return line
    }
}

private extension String {
    /// "Before 11am" → "before 11am", while leaving times like "2–6pm" alone.
    var lowercasedFirst: String {
        guard let first, first.isLetter else { return self }
        return first.lowercased() + dropFirst()
    }
}
