import SwiftUI
import SwiftData

/// Up to two slim rows on Home: a deload suggestion (only when several signals agree) and what to
/// train today based on muscle freshness. Each is hidden when it has nothing useful to say.
struct TrainingCoachView: View {
    @Environment(AppTheme.self) private var theme
    @EnvironmentObject private var sessionStore: ActiveSessionStore
    @EnvironmentObject private var health: HealthKitService
    @Query(sort: \WorkoutSession.startDate, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \Program.createdAt) private var programs: [Program]
    @Query(sort: \DailyCheckIn.date, order: .reverse) private var checkIns: [DailyCheckIn]
    @AppStorage(StressVisibility.showAnalysisKey) private var showStressAnalysis = true
    @AppStorage(DeloadSettings.dismissedUntilKey) private var dismissedUntil = 0.0
    @State private var showDeload = false

    private var activeProgram: Program? { programs.first(where: \.isActive) }

    private var deload: DeloadAssessment? {
        guard dismissedUntil < Date().timeIntervalSince1970 else { return nil }
        return DeloadAdvisor.assess(
            DeloadAdvisor.inputs(
                sessions: sessions,
                cardio: health.cardioWorkouts,
                checkIns: checkIns,
                hrvByDay: health.dailyHRV,
                restingHRByDay: health.dailyRestingHR,
                restingHeartRate: health.restingHeartRate,
                maxHeartRate: health.maxHeartRate
            )
        )
    }

    private var advice: TrainTodayAdvice? {
        guard showStressAnalysis, sessions.contains(where: { $0.endDate != nil }) else { return nil }
        let freshness = StressCalculator.allMuscleFreshness(sessions: sessions)
        let days = activeProgram?.orderedDays.map(TrainDayPlan.init(day:)) ?? []
        let planned = NextWorkoutResolver.nextDayIndex(activeProgram: activeProgram, sessions: sessions)
        return TrainTodayAdvisor.advise(days: days, plannedIndex: planned, freshness: freshness)
    }

    var body: some View {
        Group {
            if let deload {
                deloadRow(deload)
            }
            if let advice {
                trainRow(advice)
            }
        }
        .sheet(isPresented: $showDeload) {
            if let deload {
                DeloadDetailSheet(assessment: deload) {
                    dismissedUntil = Date().addingTimeInterval(7 * 86_400).timeIntervalSince1970
                    showDeload = false
                }
                .environment(theme)
            }
        }
    }

    private func deloadRow(_ assessment: DeloadAssessment) -> some View {
        Button {
            showDeload = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "battery.25percent")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Deload week suggested")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(assessment.reasons.first ?? "")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opaqueCard()
        }
        .buttonStyle(.plain)
    }

    private func trainRow(_ advice: TrainTodayAdvice) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon(for: advice.kind))
                .foregroundStyle(color(for: advice.kind))
            VStack(alignment: .leading, spacing: 1) {
                Text(advice.headline)
                    .font(.caption.weight(.semibold))
                if let detail = advice.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if case .switchDay(let index, _) = advice.kind,
               let program = activeProgram,
               let day = program.orderedDays.first(where: { $0.sortIndex == index }) {
                Button("Start") {
                    sessionStore.start(program: program, programDay: day)
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opaqueCard()
        .accessibilityElement(children: .combine)
    }

    private func icon(for kind: TrainTodayAdvice.Kind) -> String {
        switch kind {
        case .followPlan: return "checkmark.circle.fill"
        case .switchDay: return "arrow.triangle.swap"
        case .rest: return "bed.double.fill"
        case .muscleFocus: return "figure.strengthtraining.traditional"
        }
    }

    private func color(for kind: TrainTodayAdvice.Kind) -> Color {
        switch kind {
        case .followPlan: return .green
        case .switchDay: return theme.accent
        case .rest: return .orange
        case .muscleFocus: return theme.accent
        }
    }
}

enum DeloadSettings {
    static let dismissedUntilKey = "deloadDismissedUntil"
}

private struct DeloadDetailSheet: View {
    let assessment: DeloadAssessment
    var onSnooze: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppTheme.self) private var theme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Why a lighter week")
                            .font(.headline)
                        ForEach(assessment.reasons, id: \.self) { reason in
                            Label(reason, systemImage: "exclamationmark.circle")
                                .font(.subheadline)
                                .labelStyle(.titleAndIcon)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.primary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .opaqueCard()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("What to do")
                            .font(.headline)
                        Text(DeloadAdvisor.recommendation)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .opaqueCard()

                    Text("This is a suggestion from your own training and recovery data, not medical advice. If you feel fine and your lifts are moving, it's okay to keep going.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Button(action: onSnooze) {
                        Text("Remind me in a week")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(16)
            }
            .background(theme.groupedBackground.ignoresSafeArea())
            .navigationTitle("Deload week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
