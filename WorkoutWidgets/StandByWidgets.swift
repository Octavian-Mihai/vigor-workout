import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Configuration

enum StandByStyle: String, AppEnum {
    case accent
    case nightRed

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Style"
    static var caseDisplayRepresentations: [StandByStyle: DisplayRepresentation] = [
        .accent: "App accent",
        .nightRed: "Night red"
    ]
}

struct StandByStyleIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Style"
    static var description = IntentDescription("Use your app accent colour, or a dim red-on-black look for bedside use.")

    @Parameter(title: "Style", default: .accent)
    var style: StandByStyle
}

struct StandByEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let style: StandByStyle
}

struct StandByProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> StandByEntry {
        StandByEntry(date: Date(), snapshot: .preview, style: .accent)
    }

    func snapshot(for configuration: StandByStyleIntent, in context: Context) async -> StandByEntry {
        let snapshot = context.isPreview ? WidgetSnapshot.preview : (WidgetSnapshotStore.load() ?? .empty)
        return StandByEntry(date: Date(), snapshot: snapshot, style: configuration.style)
    }

    func timeline(for configuration: StandByStyleIntent, in context: Context) async -> Timeline<StandByEntry> {
        let snapshot = WidgetSnapshotStore.load() ?? (context.isPreview ? .preview : .empty)
        let entry = StandByEntry(date: Date(), snapshot: snapshot, style: configuration.style)
        let next = Calendar.current.nextDate(
            after: Date(),
            matching: DateComponents(minute: 0),
            matchingPolicy: .nextTime
        ) ?? Date().addingTimeInterval(30 * 60)
        return Timeline(entries: [entry], policy: .after(next))
    }
}

// MARK: - Palette

private struct StandByPalette {
    let isRed: Bool
    let accent: Color

    init(entry: StandByEntry) {
        isRed = entry.style == .nightRed
        accent = WidgetChrome.accent(from: entry.snapshot.accentHex)
    }

    static let red = Color(red: 1.0, green: 0.22, blue: 0.18)

    var tint: Color { isRed ? Self.red : accent }
    var primary: Color { isRed ? Self.red : .primary }
    var secondary: Color { isRed ? Self.red.opacity(0.6) : .secondary }
    var background: Color { isRed ? .black : Color(uiColor: .secondarySystemBackground) }

    func stress(_ score: Double) -> Color {
        isRed ? Self.red : WidgetChrome.stressColor(for: score)
    }

    /// Green when volume is up, red when down (single red in night mode).
    func delta(_ value: Double) -> Color {
        if isRed { return Self.red }
        return value >= 0 ? Color(red: 0.30, green: 0.72, blue: 0.48) : Color(red: 0.90, green: 0.25, blue: 0.28)
    }
}

private extension View {
    func standByChrome(_ palette: StandByPalette) -> some View {
        self
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(for: .widget) { palette.background }
    }
}

private func signedPercent(_ value: Double) -> String {
    let rounded = Int(value.rounded())
    return "\(rounded >= 0 ? "+" : "")\(rounded)%"
}

private func compactVolume(_ kg: Double, unit: String) -> String {
    let value = unit == "lb" ? kg * 2.20462 : kg
    if value >= 10_000 { return String(format: "%.1fk", value / 1000) }
    if value >= 1000 { return String(format: "%.2fk", value / 1000) }
    return "\(Int(value.rounded()))"
}

// MARK: - Stress

struct StandByStressWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StandByEntry

    var body: some View {
        let snap = entry.snapshot
        let p = StandByPalette(entry: entry)
        let score = snap.todayStress
        let color = p.stress(score)
        Group {
            if !snap.showsStressAnalysis {
                Text("Stress hidden — enable in app Settings")
                    .font(.caption)
                    .foregroundStyle(p.secondary)
            } else {
                switch family {
                case .accessoryCircular:
                    Gauge(value: min(max(score, 0), 100), in: 0...100) {
                        Text("Stress")
                    } currentValueLabel: {
                        Text("\(Int(score.rounded()))")
                    }
                    .gaugeStyle(.accessoryCircular)
                case .accessoryRectangular:
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Stress \(Int(score.rounded())) · \(WidgetChrome.stressLabel(for: score))")
                            .font(.headline)
                        StressSparkline(values: snap.trendTotals, color: .primary)
                            .frame(height: 22)
                    }
                case .accessoryInline:
                    Text("Stress \(Int(score.rounded())) · \(WidgetChrome.stressLabel(for: score))")
                default:
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Stress")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(p.secondary)
                        Text("\(Int(score.rounded()))")
                            .font(.system(size: 52, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(color)
                        Text(WidgetChrome.stressLabel(for: score))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(p.primary)
                        Spacer(minLength: 0)
                        StressSparkline(values: snap.trendTotals, color: color)
                            .frame(height: 22)
                    }
                }
            }
        }
        .standByChrome(p)
    }
}

// MARK: - Next workout

struct StandByNextWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StandByEntry

    var body: some View {
        let snap = entry.snapshot
        let p = StandByPalette(entry: entry)
        let next = snap.nextDayName ?? "No program"
        Group {
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.caption)
                        Text(next)
                            .font(.caption2.weight(.semibold))
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                    }
                    .padding(4)
                }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text("Next · \(next)")
                        .font(.headline)
                        .lineLimit(1)
                    if let program = snap.nextProgramName {
                        Text(program).font(.caption)
                    }
                    if let last = snap.lastWorkoutTitle {
                        Text("Last: \(last)").font(.caption2)
                    }
                }
            case .accessoryInline:
                Text("Next: \(next)")
            default:
                VStack(alignment: .leading, spacing: 6) {
                    Text("Next workout")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(p.secondary)
                    Text(next)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(p.tint)
                        .minimumScaleFactor(0.6)
                        .lineLimit(2)
                    if let program = snap.nextProgramName {
                        Text(program)
                            .font(.subheadline)
                            .foregroundStyle(p.primary)
                    }
                    Spacer(minLength: 0)
                    if let last = snap.lastWorkoutTitle {
                        Text("Last: \(last)")
                            .font(.caption)
                            .foregroundStyle(p.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .standByChrome(p)
    }
}

// MARK: - Year grid

struct StandByYearWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StandByEntry

    var body: some View {
        let snap = entry.snapshot
        let p = StandByPalette(entry: entry)
        Group {
            switch family {
            case .accessoryCircular:
                Gauge(value: Double(min(snap.recentActivityDays, 7)), in: 0...7) {
                    Text("Days")
                } currentValueLabel: {
                    Text("\(snap.recentActivityDays)")
                }
                .gaugeStyle(.accessoryCircular)
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "\(snap.year)")
                        .font(.caption2.weight(.semibold))
                    Text("\(snap.activityDayCount) active days")
                        .font(.headline)
                    Text("\(snap.recentActivityDays) of last 7 days")
                        .font(.caption)
                }
            case .accessoryInline:
                Text("\(snap.activityDayCount) active days in \(String(snap.year))")
            case .systemMedium:
                VStack(alignment: .leading, spacing: 4) {
                    header(snap, p)
                    WidgetYearGridView(snapshot: snap, showMonths: true, dense: false, tint: p.isRed ? p.tint : nil)
                }
            default:
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: String(snap.year))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(p.secondary)
                    Text("\(snap.activityDayCount)")
                        .font(.system(size: 52, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(p.tint)
                    Text("active days")
                        .font(.subheadline)
                        .foregroundStyle(p.primary)
                    Spacer(minLength: 0)
                    Text("\(snap.recentActivityDays) of last 7 days")
                        .font(.caption)
                        .foregroundStyle(p.secondary)
                }
            }
        }
        .standByChrome(p)
    }

    private func header(_ snap: WidgetSnapshot, _ p: StandByPalette) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: String(snap.year))
                .font(.caption.weight(.semibold))
                .foregroundStyle(p.secondary)
            Spacer()
            Text("\(snap.activityDayCount) active days")
                .font(.caption.weight(.semibold))
                .foregroundStyle(p.tint)
        }
    }
}

// MARK: - Weekly progress

struct StandByProgressWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StandByEntry

    private var weekChange: Double? {
        let snap = entry.snapshot
        guard snap.lastWeekVolumeKg > 0 else { return nil }
        return (snap.weekVolumeKg / snap.lastWeekVolumeKg - 1) * 100
    }

    var body: some View {
        let snap = entry.snapshot
        let p = StandByPalette(entry: entry)
        Group {
            switch family {
            case .accessoryCircular:
                Gauge(value: Double(min(snap.workoutsLast7Days, 7)), in: 0...7) {
                    Text("Wk")
                } currentValueLabel: {
                    Text("\(snap.workoutsLast7Days)")
                }
                .gaugeStyle(.accessoryCircular)
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(snap.workoutsLast7Days) workouts · 7d")
                        .font(.headline)
                    if let change = weekChange {
                        Text("Volume \(signedPercent(change)) vs last week")
                            .font(.caption)
                    }
                    if let cycle = snap.cycleNumber, let pct = snap.cycleVsBaselinePercent {
                        Text("Cycle \(cycle) \(signedPercent(pct)) vs baseline")
                            .font(.caption2)
                    }
                }
            case .accessoryInline:
                Text("\(snap.workoutsLast7Days) workouts · \(weekChange.map(signedPercent) ?? "—") volume")
            default:
                VStack(alignment: .leading, spacing: 4) {
                    Text("This week")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(p.secondary)
                    Text("\(snap.workoutsLast7Days)")
                        .font(.system(size: 52, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(p.tint)
                    Text("workouts in 7 days")
                        .font(.caption)
                        .foregroundStyle(p.primary)
                    Spacer(minLength: 0)
                    if let change = weekChange {
                        row("Volume", signedPercent(change), color: p.delta(change), p)
                    } else {
                        row("Volume", "\(compactVolume(snap.weekVolumeKg, unit: snap.weightUnit)) \(snap.weightUnit)", color: p.primary, p)
                    }
                    if let cycle = snap.cycleNumber, let pct = snap.cycleVsBaselinePercent {
                        row("Cycle \(cycle)", signedPercent(pct), color: p.delta(pct), p)
                    }
                }
            }
        }
        .standByChrome(p)
    }

    private func row(_ title: String, _ value: String, color: Color, _ p: StandByPalette) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(p.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
        }
    }
}

// MARK: - Widgets

private let standByFamilies: [WidgetFamily] = [
    .systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline
]

struct StandByStressWidget: Widget {
    let kind = "StandByStressWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: StandByStyleIntent.self, provider: StandByProvider()) { entry in
            StandByStressWidgetView(entry: entry)
        }
        .configurationDisplayName("Stress · StandBy & Lock Screen")
        .description("Today’s stress score for StandBy and the Lock Screen.")
        .supportedFamilies(standByFamilies)
    }
}

struct StandByNextWidget: Widget {
    let kind = "StandByNextWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: StandByStyleIntent.self, provider: StandByProvider()) { entry in
            StandByNextWidgetView(entry: entry)
        }
        .configurationDisplayName("Next workout · StandBy & Lock Screen")
        .description("Your next programmed day for StandBy and the Lock Screen.")
        .supportedFamilies(standByFamilies)
    }
}

struct StandByYearWidget: Widget {
    let kind = "StandByYearWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: StandByStyleIntent.self, provider: StandByProvider()) { entry in
            StandByYearWidgetView(entry: entry)
        }
        .configurationDisplayName("Year · StandBy & Lock Screen")
        .description("Active days this year, with the year grid in the wide size.")
        .supportedFamilies(standByFamilies + [.systemMedium])
    }
}

struct StandByProgressWidget: Widget {
    let kind = "StandByProgressWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: StandByStyleIntent.self, provider: StandByProvider()) { entry in
            StandByProgressWidgetView(entry: entry)
        }
        .configurationDisplayName("Weekly progress · StandBy & Lock Screen")
        .description("Workouts this week, volume vs last week, and program cycle vs baseline.")
        .supportedFamilies(standByFamilies)
    }
}

#Preview("Progress", as: .systemSmall) {
    StandByProgressWidget()
} timeline: {
    StandByEntry(date: .now, snapshot: .preview, style: .accent)
    StandByEntry(date: .now, snapshot: .preview, style: .nightRed)
}
