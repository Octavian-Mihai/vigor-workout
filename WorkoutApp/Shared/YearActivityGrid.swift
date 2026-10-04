import SwiftUI
import SwiftData

struct YearDayCell: Identifiable {
    let id: Date
    let date: Date
    let inYear: Bool
    let hasLift: Bool
    let hasRun: Bool

    var kind: YearActivityKind {
        switch (hasLift, hasRun) {
        case (true, true): return .both
        case (true, false): return .weights
        case (false, true): return .running
        case (false, false): return .none
        }
    }
}

enum YearActivityKind {
    case none, weights, running, both

    var color: Color? {
        switch self {
        case .none: return nil
        case .weights: return YearActivityPalette.weights
        case .running: return YearActivityPalette.running
        case .both: return YearActivityPalette.both
        }
    }
}

enum YearActivityPalette {
    static let weights = Color(red: 0x6E / 255, green: 0xA8 / 255, blue: 0xFE / 255)
    static let running = Color(red: 0xFE / 255, green: 0xE4 / 255, blue: 0x40 / 255)
    static let both = Color(red: 0xFF / 255, green: 0x6B / 255, blue: 0x7A / 255)
}

enum YearGridBuilder {
    static func cells(
        year: Int,
        sessions: [WorkoutSession],
        runDates: Set<Date>,
        calendar: Calendar = .current
    ) -> [YearDayCell] {
        var cal = calendar
        cal.firstWeekday = YearGridWeekdays.firstWeekday

        var liftDays: Set<Date> = []
        for session in sessions where session.endDate != nil {
            liftDays.insert(cal.startOfDay(for: session.startDate))
        }

        let runDays = Set(runDates.map { cal.startOfDay(for: $0) })

        guard let jan1 = cal.date(from: DateComponents(year: year, month: 1, day: 1)) else { return [] }
        let weekday = cal.component(.weekday, from: jan1)
        let offset = weekday - cal.firstWeekday
        guard let start = cal.date(byAdding: .day, value: -offset, to: jan1) else { return [] }

        var result: [YearDayCell] = []
        result.reserveCapacity(53 * 7)
        for i in 0..<(53 * 7) {
            guard let date = cal.date(byAdding: .day, value: i, to: start) else { continue }
            let day = cal.startOfDay(for: date)
            let inYear = cal.component(.year, from: date) == year
            result.append(
                YearDayCell(
                    id: date,
                    date: date,
                    inYear: inYear,
                    hasLift: inYear && liftDays.contains(day),
                    hasRun: inYear && runDays.contains(day)
                )
            )
        }
        return result
    }
}

struct YearActivityGrid: View {
    let sessions: [WorkoutSession]
    var runDates: Set<Date> = []
    var showsRunningActivity: Bool = true
    var year: Int = Calendar.current.component(.year, from: Date())
    var onSelect: ((Date) -> Void)? = nil

    @Environment(\.calendar) private var calendar
    @Environment(AppTheme.self) private var theme

    private static let monthLetters = ["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"]

    private var cells: [YearDayCell] {
        YearGridBuilder.cells(year: year, sessions: sessions, runDates: runDates, calendar: calendar)
    }

    private var workoutsThisYear: Int {
        sessions.filter { session in
            session.endDate != nil && calendar.component(.year, from: session.startDate) == year
        }.count
    }

    private var runsThisYear: Int {
        Set(runDates.map { calendar.startOfDay(for: $0) })
            .filter { calendar.component(.year, from: $0) == year }
            .count
    }

    private var dayOfYear: Int {
        let now = Date()
        if calendar.component(.year, from: now) == year {
            return calendar.ordinality(of: .day, in: .year, for: now) ?? 1
        }
        return daysInYear
    }

    private var daysInYear: Int {
        let jan1 = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? Date()
        return calendar.range(of: .day, in: .year, for: jan1)?.count ?? 365
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(verbatim: String(year))
                    .font(.headline)
                Spacer()
                HStack(spacing: 8) {
                    legendLabel("Weights (\(workoutsThisYear))", color: YearActivityPalette.weights)
                    if showsRunningActivity {
                        legendLabel("Cardio (\(runsThisYear))", color: YearActivityPalette.running)
                        legendLabel("Both", color: YearActivityPalette.both)
                    }
                }
            }

            HStack(spacing: 8) {
                Text("\(dayOfYear) / \(daysInYear) days")
                Spacer(minLength: 0)
            }
            .font(.caption.monospacedDigit().weight(.medium))
            .foregroundStyle(.secondary)

            GeometryReader { geo in
                let spacing: CGFloat = 1.5
                let columns = 53
                let weekdayWidth: CGFloat = 8
                let weekdayGap: CGFloat = 2
                let gridWidth = max(geo.size.width - weekdayWidth - weekdayGap, 1)
                let raw = (gridWidth - CGFloat(columns - 1) * spacing) / CGFloat(columns)
                let cell = min(5.5, max(3, raw))

                VStack(alignment: .leading, spacing: 3) {
                    monthLabels(cell: cell, spacing: spacing, leadingInset: weekdayWidth + weekdayGap)
                    HStack(alignment: .top, spacing: weekdayGap) {
                        weekdayLabels(cell: cell, spacing: spacing)
                            .frame(width: weekdayWidth)
                        HStack(alignment: .top, spacing: spacing) {
                            ForEach(0..<columns, id: \.self) { col in
                                VStack(spacing: spacing) {
                                    ForEach(0..<7, id: \.self) { row in
                                        let index = col * 7 + row
                                        if index < cells.count {
                                            dayDot(cells[index], size: cell)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .frame(height: 68)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Year activity grid")
            .accessibilityAddTraits(onSelect == nil ? [] : .isButton)
            .onTapGesture {
                onSelect?(Date())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .opaqueCard()
    }

    private func legendLabel(_ title: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func weekdayLabels(cell: CGFloat, spacing: CGFloat) -> some View {
        let letters = YearGridWeekdays.letters(calendar: calendar)
        return VStack(spacing: spacing) {
            ForEach(0..<7, id: \.self) { row in
                Text(letters[row])
                    .font(.system(size: 6, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 8, height: cell)
            }
        }
        .accessibilityHidden(true)
    }

    private func monthLabels(cell: CGFloat, spacing: CGFloat, leadingInset: CGFloat) -> some View {
        let labels = monthStarts()
        return HStack(spacing: 0) {
            Color.clear.frame(width: leadingInset)
            ForEach(labels, id: \.offset) { item in
                Text(item.label)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: cell + spacing, alignment: .leading)
                if item.offset < labels.count - 1 {
                    let gap = labels[item.offset + 1].column - item.column - 1
                    Spacer().frame(width: max(0, CGFloat(gap) * (cell + spacing)))
                }
            }
            Spacer(minLength: 0)
        }
        .frame(height: 9)
    }

    private func monthStarts() -> [(offset: Int, column: Int, label: String)] {
        var seen: Set<Int> = []
        var result: [(offset: Int, column: Int, label: String)] = []
        for (index, cell) in cells.enumerated() where cell.inYear {
            let month = calendar.component(.month, from: cell.date)
            if seen.insert(month).inserted {
                let col = index / 7
                let letter = Self.monthLetters[month - 1]
                result.append((result.count, col, letter))
            }
        }
        return result
    }

    @ViewBuilder
    private func dayDot(_ cell: YearDayCell, size: CGFloat) -> some View {
        Circle()
            .fill(cell.kind.color ?? (cell.inYear ? theme.mutedFill : Color.clear))
            .frame(width: size, height: size)
            .overlay {
                if cell.inYear && calendar.isDateInToday(cell.date) {
                    Circle().strokeBorder(Color.primary.opacity(0.45), lineWidth: 1)
                }
            }
    }
}
