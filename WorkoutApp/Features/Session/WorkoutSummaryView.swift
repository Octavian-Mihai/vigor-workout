import SwiftUI
import UIKit

struct WorkoutSummaryView: View {
    let model: WorkoutSummaryModel
    let accent: Color
    let unit: WeightUnit

    @Environment(AppTheme.self) private var theme
    @Environment(\.colorScheme) private var colorScheme

    static let cardWidth: CGFloat = 390

    private var textPrimary: Color {
        theme.foregroundPrimary(for: colorScheme)
    }

    private var textSecondary: Color {
        theme.foregroundSecondary(for: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            overviewStats
            if !model.prs.isEmpty {
                prSection
            }
            if !model.displayedExercises.isEmpty {
                exercisesSection
            }
            brandingFooter
        }
        .padding(20)
        .frame(width: Self.cardWidth, alignment: .leading)
        .background(theme.groupedBackground)
        .foregroundStyle(textPrimary)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.dayName)
                .font(.title2.weight(.bold))
                .foregroundStyle(textPrimary)
            HStack(spacing: 12) {
                Label(Formatters.shortDate.string(from: model.date), systemImage: "calendar")
                Label(Formatters.duration(model.durationSeconds), systemImage: "clock")
            }
            .font(.subheadline)
            .foregroundStyle(textSecondary)
        }
    }

    private var overviewStats: some View {
        HStack(spacing: 0) {
            statBlock(value: "\(model.totalSets)", label: "Sets")
            divider
            statBlock(
                value: Formatters.compactNumber(unit.fromKg(model.totalVolumeKg)),
                label: "\(unit.rawValue)·reps"
            )
            divider
            statBlock(value: "\(model.exerciseCount)", label: "Exercises")
        }
        .padding(14)
        .opaqueCard()
    }

    private var prSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("\(model.prs.count) new PR\(model.prs.count == 1 ? "" : "s")", systemImage: "trophy.fill")
                .font(.headline)
                .foregroundStyle(accent)
            VStack(spacing: 8) {
                ForEach(model.prs.prefix(5)) { pr in
                    HStack(alignment: .firstTextBaseline) {
                        Text(pr.exerciseName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text("\(unit.format(pr.newE1RMKg, decimals: 1)) est. 1RM")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(textSecondary)
                        Text("+\(unit.format(pr.gainKg, decimals: 1))")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(accent)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opaqueCard()
    }

    private var divider: some View {
        Rectangle()
            .fill(theme.cardBorder)
            .frame(width: 1, height: 36)
    }

    private func statBlock(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(textPrimary)
            Text(label)
                .font(.caption)
                .foregroundStyle(textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var exercisesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Exercises")
                .font(.headline)
                .foregroundStyle(textPrimary)
            VStack(spacing: 0) {
                ForEach(Array(model.displayedExercises.enumerated()), id: \.element.id) { index, exercise in
                    exerciseRow(exercise)
                    if index < model.displayedExercises.count - 1 {
                        Divider()
                            .padding(.leading, thumbnailSize + 12)
                    }
                }
                if model.hiddenExerciseCount > 0 {
                    Divider()
                    Text("+ \(model.hiddenExerciseCount) more exercise\(model.hiddenExerciseCount == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundStyle(textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 10)
                }
            }
            .padding(14)
            .opaqueCard()
        }
    }

    private var thumbnailSize: CGFloat { 64 }
    private var thumbnailCornerRadius: CGFloat { 10 }

    private func exerciseRow(_ exercise: WorkoutSummaryExercise) -> some View {
        HStack(alignment: .top, spacing: 12) {
            exerciseThumbnail(assetName: exercise.imageAssetName)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(textPrimary)
                            .lineLimit(2)
                        Text("\(exercise.setCount) set\(exercise.setCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(textSecondary)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Top")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(textSecondary)
                        Text("\(unit.format(exercise.topSetWeightKg)) × \(exercise.topSetReps)")
                            .font(.subheadline.monospacedDigit().weight(.medium))
                            .foregroundStyle(accent)
                    }
                }

                if !exercise.sets.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(exercise.sets) { set in
                            HStack(spacing: 8) {
                                Text("\(set.id + 1)")
                                    .font(.caption2.monospacedDigit().weight(.semibold))
                                    .foregroundStyle(textSecondary)
                                    .frame(width: 16, alignment: .trailing)
                                Text("\(unit.formatNumber(set.weightKg)) × \(set.reps)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(textPrimary)
                                Text("RIR \(RIRPalette.display(set.rir))")
                                    .font(.caption2)
                                    .foregroundStyle(textSecondary)
                            }
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func exerciseThumbnail(assetName: String) -> some View {
        Group {
            if let image = UIImage(named: assetName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: thumbnailSize, height: thumbnailSize)
                    .background(Color.white)
            } else {
                ZStack {
                    Color.white
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(accent.opacity(0.9))
                }
                .frame(width: thumbnailSize, height: thumbnailSize)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: thumbnailCornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: thumbnailCornerRadius, style: .continuous))
        .layoutPriority(1)
        .accessibilityHidden(true)
    }

    private var brandingFooter: some View {
        VStack(spacing: 10) {
        //    Rectangle()
        //        .fill(accent)
        //        .frame(height: 3)
        //        .clipShape(Capsule())
            HStack {
                Image(systemName: "figure.strengthtraining.traditional")
                    .foregroundStyle(accent)
                Text("Workout")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(textSecondary)
                Spacer()
            }
        }
    }
}
