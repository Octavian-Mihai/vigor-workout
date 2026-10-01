import SwiftUI
import WidgetKit

struct WorkoutWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct WorkoutWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> WorkoutWidgetEntry {
        WorkoutWidgetEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (WorkoutWidgetEntry) -> Void) {
        let snapshot = context.isPreview ? WidgetSnapshot.preview : (WidgetSnapshotStore.load() ?? .empty)
        completion(WorkoutWidgetEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WorkoutWidgetEntry>) -> Void) {
        let snapshot = WidgetSnapshotStore.load() ?? (context.isPreview ? .preview : .empty)
        let entry = WorkoutWidgetEntry(date: Date(), snapshot: snapshot)
        let next = Calendar.current.nextDate(
            after: Date(),
            matching: DateComponents(minute: 0),
            matchingPolicy: .nextTime
        ) ?? Date().addingTimeInterval(30 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct WorkoutYearWidget: Widget {
    let kind = "WorkoutYearWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WorkoutWidgetProvider()) { entry in
            WorkoutYearWidgetView(entry: entry)
        }
        .configurationDisplayName("Year")
        .description("Year-in-pixels grid plus workout count for the current year.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct WorkoutStressWidget: Widget {
    let kind = "WorkoutStressWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WorkoutWidgetProvider()) { entry in
            WorkoutStressWidgetView(entry: entry)
        }
        .configurationDisplayName("Today’s stress")
        .description("Today’s training stress score and a 7-day trend.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct WorkoutNextWidget: Widget {
    let kind = "WorkoutNextWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WorkoutWidgetProvider()) { entry in
            WorkoutNextWidgetView(entry: entry)
        }
        .configurationDisplayName("Next workout")
        .description("Last session and the next programmed day.")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct WorkoutWidgets: WidgetBundle {
    var body: some Widget {
        WorkoutYearWidget()
        WorkoutStressWidget()
        WorkoutNextWidget()
        StandByStressWidget()
        StandByNextWidget()
        StandByYearWidget()
        StandByProgressWidget()
        RestTimerLiveActivity()
    }
}
