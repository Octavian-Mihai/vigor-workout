import SwiftUI
import SwiftData

enum CheckInVisibility {
    static let showOnHomeKey = "showDailyCheckIn"
}

// MARK: - Storage

enum CheckInStore {
    @MainActor
    static func entry(on day: Date, in context: ModelContext) -> DailyCheckIn? {
        let start = Calendar.current.startOfDay(for: day)
        var descriptor = FetchDescriptor<DailyCheckIn>(predicate: #Predicate { $0.date == start })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Applies one change to the day's check-in, creating it on first use and removing it again
    /// if the change leaves it empty, so un-tapping an answer never strands a blank row.
    @MainActor
    static func update(
        on day: Date,
        in context: ModelContext,
        healthSleepHours: Double? = nil,
        _ change: (DailyCheckIn) -> Void
    ) {
        let entry = entry(on: day, in: context) ?? {
            let created = DailyCheckIn(date: day)
            context.insert(created)
            return created
        }()
        change(entry)
        if entry.sleepHours == nil, let healthSleepHours, Calendar.current.isDateInToday(entry.date) {
            entry.sleepHours = healthSleepHours
        }
        if entry.isEmpty {
            context.delete(entry)
        }
        try? context.save()
    }

    /// Apple Health's sleep total can arrive after the first tap; fill it in once it does.
    @MainActor
    static func attachSleepHours(_ hours: Double?, to day: Date, in context: ModelContext) {
        guard let hours, let entry = entry(on: day, in: context), entry.sleepHours == nil,
              Calendar.current.isDateInToday(entry.date) else { return }
        entry.sleepHours = hours
        try? context.save()
    }
}

// MARK: - Answer choices

enum CheckInGlyph {
    /// A drawn face, 1 (very low) to 5 (great). Drawn rather than emoji so it follows the theme colours.
    case face(Int)
    case symbol(String)
    case text(String)
}

struct CheckInChoice: Identifiable {
    let value: Int
    let glyph: CheckInGlyph
    /// What VoiceOver says and what the row shows once chosen.
    let spoken: String

    var id: Int { value }
}

enum CheckInChoices {
    static let sleep: [CheckInChoice] = [
        CheckInChoice(value: 1, glyph: .text("1"), spoken: "Terrible"),
        CheckInChoice(value: 2, glyph: .text("2"), spoken: "Poor"),
        CheckInChoice(value: 3, glyph: .text("3"), spoken: "Okay"),
        CheckInChoice(value: 4, glyph: .text("4"), spoken: "Good"),
        CheckInChoice(value: 5, glyph: .text("5"), spoken: "Great")
    ]

    static let mood: [CheckInChoice] = [
        CheckInChoice(value: 1, glyph: .face(1), spoken: "Very low"),
        CheckInChoice(value: 2, glyph: .face(2), spoken: "Low"),
        CheckInChoice(value: 3, glyph: .face(3), spoken: "Neutral"),
        CheckInChoice(value: 4, glyph: .face(4), spoken: "Good"),
        CheckInChoice(value: 5, glyph: .face(5), spoken: "Great")
    ]

    static let energy: [CheckInChoice] = [
        CheckInChoice(value: 1, glyph: .symbol("battery.0percent"), spoken: "Drained"),
        CheckInChoice(value: 2, glyph: .symbol("battery.25percent"), spoken: "Low"),
        CheckInChoice(value: 3, glyph: .symbol("battery.50percent"), spoken: "Steady"),
        CheckInChoice(value: 4, glyph: .symbol("battery.75percent"), spoken: "Good"),
        CheckInChoice(value: 5, glyph: .symbol("battery.100percent"), spoken: "Full")
    ]

    static let caffeineTiming: [CheckInChoice] = CaffeineTiming.allCases.map {
        CheckInChoice(value: $0.rawValue, glyph: .text($0.label), spoken: $0.spoken)
    }

    /// Short name for a summary line, e.g. "Good" for a 4 on any of the 1–5 scales.
    static func spoken(_ value: Int?, in choices: [CheckInChoice]) -> String? {
        choices.first { $0.value == value }?.spoken
    }
}

// MARK: - Row

/// A single question answered with one tap. Tapping the chosen answer again clears it.
struct CheckInChoiceRow: View {
    let title: String
    let systemImage: String
    var detail: String? = nil
    var hint: String
    let choices: [CheckInChoice]
    @Binding var selection: Int?

    @Environment(AppTheme.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Label(title, systemImage: systemImage)
                    .font(.subheadline.weight(.semibold))
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(CheckInChoices.spoken(selection, in: choices) ?? hint)
                    .font(.caption)
                    .foregroundStyle(selection == nil ? .tertiary : .secondary)
            }

            HStack(spacing: 6) {
                ForEach(choices) { choice in
                    let isSelected = selection == choice.value
                    Button {
                        selection = isSelected ? nil : choice.value
                    } label: {
                        glyph(choice.glyph, selected: isSelected)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(
                                isSelected ? theme.accent : theme.mutedFill,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(title): \(choice.spoken)")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    @ViewBuilder
    private func glyph(_ glyph: CheckInGlyph, selected: Bool) -> some View {
        switch glyph {
        case .face(let level):
            MoodFace(level: level, color: selected ? Color.white : Color.primary)
        case .symbol(let name):
            Image(systemName: name)
                .font(.body.weight(.semibold))
                .foregroundStyle(selected ? Color.white : Color.primary)
        case .text(let text):
            Text(text)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 2)
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
    }
}

/// A simple round face whose mouth runs from a frown (1) to a wide smile (5).
struct MoodFace: View {
    let level: Int
    let color: Color

    private var curve: CGFloat {
        switch level {
        case ...1: return -1
        case 2: return -0.5
        case 3: return 0
        case 4: return 0.7
        default: return 1.3
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(color, lineWidth: 2)
            HStack(spacing: 7) {
                Circle().fill(color).frame(width: 3.5, height: 3.5)
                Circle().fill(color).frame(width: 3.5, height: 3.5)
            }
            .offset(y: -4)
            MoodMouth(curve: curve)
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 11, height: 6)
                .offset(y: curve < 0 ? 6 : 4)
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }
}

private struct MoodMouth: Shape {
    /// −1 frowns, 0 is flat, +1 smiles.
    var curve: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY),
            control: CGPoint(x: rect.midX, y: rect.midY + curve * rect.height)
        )
        return path
    }
}

// MARK: - Input

/// The check-in questions for one day. Reads and writes through `CheckInStore`, so it works the
/// same on Home and in the editor sheet, and nothing is saved until the first answer is tapped.
struct CheckInInputView: View {
    @Environment(\.modelContext) private var context
    @Query private var matches: [DailyCheckIn]

    private let day: Date
    private let healthSleepHours: Double?
    private let showsExtras: Bool

    init(day: Date, healthSleepHours: Double? = nil, showsExtras: Bool = true) {
        let start = Calendar.current.startOfDay(for: day)
        self.day = start
        self.healthSleepHours = healthSleepHours
        self.showsExtras = showsExtras
        _matches = Query(filter: #Predicate<DailyCheckIn> { $0.date == start })
    }

    private var entry: DailyCheckIn? { matches.first }

    private func binding(_ keyPath: ReferenceWritableKeyPath<DailyCheckIn, Int?>) -> Binding<Int?> {
        Binding(
            get: { entry?[keyPath: keyPath] },
            set: { newValue in
                CheckInStore.update(on: day, in: context, healthSleepHours: healthSleepHours) {
                    $0[keyPath: keyPath] = newValue
                }
            }
        )
    }

    private var sleepDetail: String? {
        let hours = entry?.sleepHours ?? (Calendar.current.isDateInToday(day) ? healthSleepHours : nil)
        guard let hours else { return nil }
        return "· \(Formatters.trimmedNumber(hours, decimals: 1))h in Health"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CheckInChoiceRow(
                title: "Sleep",
                systemImage: "moon.zzz.fill",
                detail: sleepDetail,
                hint: "How was last night?",
                choices: CheckInChoices.sleep,
                selection: binding(\.sleepRating)
            )
            CheckInChoiceRow(
                title: "Mood",
                systemImage: "face.smiling",
                hint: "How are you feeling?",
                choices: CheckInChoices.mood,
                selection: binding(\.moodRating)
            )
            CheckInChoiceRow(
                title: "Energy",
                systemImage: "bolt.fill",
                hint: "How's your energy?",
                choices: CheckInChoices.energy,
                selection: binding(\.energyRating)
            )

            if showsExtras {
                Divider()
                CheckInChoiceRow(
                    title: "Last caffeine",
                    systemImage: "cup.and.saucer.fill",
                    hint: "What time was it?",
                    choices: CheckInChoices.caffeineTiming,
                    selection: binding(\.lastCaffeine)
                )
            }
        }
    }
}
