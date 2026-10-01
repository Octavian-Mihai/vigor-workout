import SwiftUI
import Charts
import SwiftData

struct TrainingLoadEvolutionChart: View {
    let accent: Color

    @Query(sort: \WorkoutSession.startDate) private var sessions: [WorkoutSession]
    @Query private var programs: [Program]

    private var program: Program? {
        if let active = programs.first(where: \.isActive) { return active }
        let lastUUID = sessions.last(where: { $0.isProgrammed && $0.programUUID != nil })?.programUUID
        return programs.first { $0.uuid == lastUUID }
    }

    private var cycles: [ProgramCycleVolume] {
        guard let program else { return [] }
        let entries = sessions
            .filter { $0.isProgrammed && $0.programUUID == program.uuid && $0.programDayIndex != nil && !$0.sets.isEmpty }
            .map { CycleSession(date: $0.startDate, dayIndex: $0.programDayIndex ?? 0, volumeKg: $0.sets.reduce(0) { $0 + $1.volume }) }
        return ProgramCycleAnalytics.cycles(from: entries, dayCount: program.days.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Training load evolution")
                .font(.headline)
            if let program, !cycles.isEmpty {
                Text("\(program.name): cycle 1 is the baseline; each bar is the change in volume vs. that baseline.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                chart
                ForEach(cycles.suffix(6).reversed()) { cycle in
                    cycleRow(cycle)
                }
            } else {
                Text("Log sessions from a program. Your first full cycle becomes the baseline, and every cycle after it is compared to it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            }
        }
        .padding(16)
        .opaqueCard()
    }

    private var chart: some View {
        Chart {
            RuleMark(y: .value("Baseline", 0))
                .foregroundStyle(.secondary.opacity(0.6))
            ForEach(cycles) { cycle in
                BarMark(
                    x: .value("Cycle", cycle.number),
                    y: .value("% vs baseline", cycle.percentVsBaseline ?? 0)
                )
                .foregroundStyle(color(for: cycle).opacity(cycle.isComplete ? 1 : 0.4))
                .cornerRadius(3)
            }
        }
        .frame(height: 200)
        .chartYAxisLabel("% vs baseline")
        .chartXAxisLabel("Cycle")
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { value in
                AxisValueLabel {
                    if let n = value.as(Int.self) { Text("\(n)") }
                }
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text("\(Int(v))%") }
                }
            }
        }
    }

    private func color(for cycle: ProgramCycleVolume) -> Color {
        guard let pct = cycle.percentVsBaseline else { return .secondary }
        return pct >= 0 ? .green : .red
    }

    private func cycleRow(_ cycle: ProgramCycleVolume) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Cycle \(cycle.number)\(cycle.number == 1 ? " · baseline" : "")\(cycle.isComplete ? "" : " · in progress")")
                .font(.subheadline)
            Spacer()
            if cycle.isComplete, let prev = cycle.percentVsPrevious {
                Text("\(prev >= 0 ? "+" : "")\(Formatters.trimmedNumber(prev, decimals: 1))% vs previous")
                    .font(.caption)
                    .foregroundStyle(prev >= 0 ? .green : .red)
                    .monospacedDigit()
            }
        }
    }
}

struct WeeklyVolumeTrendChart: View {
    let sets: [SetLog]
    let accent: Color

    @AppStorage("weightUnit") private var weightUnitRaw = WeightUnit.kg.rawValue

    private var unit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .kg }
    private var weeklyData: [WeeklyTrainingLoad] {
        StressCalculator.weeklyTrainingLoad(from: sets, weeks: 12)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Weekly volume trend")
                .font(.headline)
            Text("Weight × reps per week, last 12 weeks (Monday start).")
                .font(.caption)
                .foregroundStyle(.secondary)
            Chart(weeklyData) { week in
                BarMark(
                    x: .value("Week", week.weekStart),
                    y: .value("Volume", unit.fromKg(week.tonnageKg)),
                    width: .fixed(14)
                )
                .foregroundStyle(accent)
                .cornerRadius(3)
            }
            .frame(height: 200)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { value in
                    if let date = value.as(Date.self) {
                        AxisValueLabel(Formatters.dayMonth.string(from: date))
                    }
                }
            }
            .chartYAxisLabel(unit.rawValue + "·reps")
        }
        .padding(16)
        .opaqueCard()
    }
}

private struct BodyWeightPoint: Identifiable {
    let id: Date
    let date: Date
    let value: Double
    let average: Double
}

struct BodyWeightTrendChart: View {
    let accent: Color

    @Query(sort: \BodyWeightEntry.date) private var entries: [BodyWeightEntry]
    @AppStorage("weightUnit") private var weightUnitRaw = WeightUnit.kg.rawValue

    private var unit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .kg }

    private var points: [BodyWeightPoint] {
        let values = entries.map { unit.fromKg($0.kilograms) }
        return entries.enumerated().map { index, entry in
            let window = values[max(0, index - 6)...index]
            return BodyWeightPoint(
                id: entry.date,
                date: entry.date,
                value: values[index],
                average: window.reduce(0, +) / Double(window.count)
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bodyweight trend")
                .font(.headline)
            Text("Weigh-ins with a 7-entry moving average.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if points.isEmpty {
                Text("No weigh-ins logged yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                Chart {
                    ForEach(points) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Weigh-in", point.value),
                            series: .value("Series", "Weigh-in")
                        )
                        .foregroundStyle(accent)
                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Weigh-in", point.value)
                        )
                        .foregroundStyle(accent)
                        .symbolSize(24)
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("7-entry average", point.average),
                            series: .value("Series", "7-entry average")
                        )
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 200)
                .chartYAxisLabel(unit.rawValue)
            }
        }
        .padding(16)
        .opaqueCard()
    }
}
