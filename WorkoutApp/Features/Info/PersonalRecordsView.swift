import SwiftUI
import SwiftData

struct PersonalRecordsView: View {
    @Query(sort: \WorkoutSession.startDate, order: .reverse) private var sessions: [WorkoutSession]
    @Environment(AppTheme.self) private var theme
    @AppStorage("weightUnit") private var weightUnitRaw = WeightUnit.lb.rawValue

    private var unit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .lb }

    private var records: [LiftPersonalRecord] {
        PersonalRecordTracker.summaries(in: sessions)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Best estimated 1RMs on the main compounds. Projected PRs follow recent e1RM trend and are estimates, not logged records.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(records) { record in
                    liftCard(record)
                }
            }
            .padding(16)
        }
        .background(theme.groupedBackground.ignoresSafeArea())
        .compactNavigationTitle("Personal records")
    }

    private func liftCard(_ record: LiftPersonalRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(record.lift.rawValue)
                .font(.headline)

            if let best = record.bestE1RMKg, let set = record.bestSet {
                HStack(alignment: .firstTextBaseline) {
                    Text("Best e1RM")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(unit.format(best, decimals: 1))
                        .font(.title3.weight(.bold).monospacedDigit())
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(set.exerciseName)  ·  \(unit.format(set.weightKg, decimals: 1)) × \(set.reps) @ RIR \(set.rir)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(Formatters.shortDate.string(from: set.date))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if let projected = record.projectedE1RMKg {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Estimated next")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(unit.format(projected, decimals: 1))
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                    }
                    Text("Estimate from recent e1RMs — not a logged PR.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    Text("Not enough upward trend to estimate a new PR.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text("No logged sets yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .opaqueCard()
    }
}
