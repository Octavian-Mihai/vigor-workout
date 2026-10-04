import SwiftUI

enum AppTab: Hashable {
    case home
    case workout
    case running
    case info
    case settings
}

enum AppTourTargetID: String, Hashable {
    case homeYearGrid
    case homeTodayStress
    case homeStartWorkout
    case workoutPrograms
    case workoutLearn
    case workoutLibrary
    case infoAnalytics
    case running
    case settings
}

enum AppTourStep: Int, CaseIterable, Identifiable, Hashable {
    case homeYearGrid
    case homeTodayStress
    case homeStartWorkout
    case workoutPrograms
    case workoutLearn
    case workoutLibrary
    case infoAnalytics
    case running
    case settings

    var id: Self { self }

    var tab: AppTab {
        switch self {
        case .homeYearGrid, .homeTodayStress, .homeStartWorkout:
            return .home
        case .workoutPrograms, .workoutLearn, .workoutLibrary:
            return .workout
        case .infoAnalytics:
            return .info
        case .running:
            return .running
        case .settings:
            return .settings
        }
    }

    var targetID: AppTourTargetID {
        switch self {
        case .homeYearGrid: return .homeYearGrid
        case .homeTodayStress: return .homeTodayStress
        case .homeStartWorkout: return .homeStartWorkout
        case .workoutPrograms: return .workoutPrograms
        case .workoutLearn: return .workoutLearn
        case .workoutLibrary: return .workoutLibrary
        case .infoAnalytics: return .infoAnalytics
        case .running: return .running
        case .settings: return .settings
        }
    }

    var title: String {
        switch self {
        case .homeYearGrid: return "Year grid"
        case .homeTodayStress: return "Muscle freshness"
        case .homeStartWorkout: return "Start a session"
        case .workoutPrograms: return "Programs"
        case .workoutLearn: return "Learn"
        case .workoutLibrary: return "History & custom exercises"
        case .infoAnalytics: return "Stress and analytics"
        case .running: return "Cardio"
        case .settings: return "Settings"
        }
    }

    var message: String {
        switch self {
        case .homeYearGrid:
            return "Lifting days light up here, along with runs, rides, hikes and other cardio if cardio activity is on. Above it, the daily check-in logs sleep, mood and energy; a streak builds as you go. Tap the grid for longer trends."
        case .homeTodayStress:
            return "Per-muscle recovery from recent training. Tap for the full list, or edit which muscles show here. Below it, Home suggests which day of your program fits today, and recommends a deload when fatigue stays high. Turn stress off in Settings → Stress if you prefer."
        case .homeStartWorkout:
            return "If a program is active, start the next day here. Otherwise use Start empty workout. In a session, log weight, reps, and RIR; barbell lifts show a plate calculator, and beating your best estimated 1RM triggers a PR celebration. VBT mode tracks bar speed on supported lifts. When you finish, share a summary card as a PNG."
        case .workoutPrograms:
            return "Create from a starter template, import a plan, or build your own. Mark one active so Home knows what comes next. Programs remember whether they’re expanded or collapsed."
        case .workoutLearn:
            return "The exercise catalog and movement notes — reference material you can open anytime, separate from this tour."
        case .workoutLibrary:
            return "Custom exercises you added live here — share them to the developer or delete them. History lists finished workouts with unit labels; swipe or tap Delete to remove a session."
        case .infoAnalytics:
            return "Today’s stress, daily check-in insights, personal records with projected next PRs, exercise history, plus weekly volume, volume per muscle, training load evolution across program cycles, and bodyweight trend. Hide individual analytics sections or turn off all stress in Settings."
        case .running:
            return "Cardio comes from Apple Health. Filter by activity, open a route, and see pace and cardio stress. Hide this tab in Settings if you don’t want it."
        case .settings:
            return "Units, accent color and appearance, rest timer, bar weight for the plate calculator, stress visibility, the daily check-in and its reminder, and Running. About → How to use this app replays this tour."
        }
    }

    static func visibleSteps(showRunningTab: Bool, showStressAnalysis: Bool = true) -> [AppTourStep] {
        allCases.filter { step in
            if step == .running && !showRunningTab { return false }
            if step == .homeTodayStress && !showStressAnalysis { return false }
            return true
        }
    }
}

enum TourCoordinateSpace {
    static let name = "appTourRoot"
}

@Observable
final class AppTourController {
    var isActive = false
    var step: AppTourStep = .homeYearGrid
    var selectedTab: AppTab = .home
    var frames: [AppTourTargetID: CGRect] = [:]
    /// Bumped after start / tab changes so already-laid-out Home targets re-publish frames.
    var anchorEpoch = 0

    func start() {
        step = .homeYearGrid
        selectedTab = .home
        isActive = true
        requestFrameRefresh()
    }

    func advance(showRunningTab: Bool, showStressAnalysis: Bool = true) {
        let steps = AppTourStep.visibleSteps(showRunningTab: showRunningTab, showStressAnalysis: showStressAnalysis)
        guard let index = steps.firstIndex(of: step), index + 1 < steps.count else {
            finish()
            return
        }
        let next = steps[index + 1]
        step = next
        selectedTab = next.tab
        requestFrameRefresh()
    }

    func finish() {
        isActive = false
        frames.removeAll()
    }

    func requestFrameRefresh() {
        DispatchQueue.main.async {
            self.anchorEpoch += 1
        }
    }

    func updateFrame(_ id: AppTourTargetID, _ frame: CGRect) {
        guard frame.width > 1, frame.height > 1 else { return }
        if frames[id] != frame {
            frames[id] = frame
        }
    }

    func currentFrame() -> CGRect? {
        frames[step.targetID]
    }
}

private struct TourFramesKey: PreferenceKey {
    static var defaultValue: [AppTourTargetID: CGRect] = [:]

    static func reduce(value: inout [AppTourTargetID: CGRect], nextValue: () -> [AppTourTargetID: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct TourTargetModifier: ViewModifier {
    let id: AppTourTargetID
    @Environment(AppTourController.self) private var tour

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geo in
                    let frame = geo.frame(in: .global)
                    Color.clear
                        .preference(key: TourFramesKey.self, value: [id: frame])
                        .task(id: Self.token(epoch: tour.anchorEpoch, frame: frame)) {
                            tour.updateFrame(id, frame)
                        }
                }
                .allowsHitTesting(false)
            }
            .onPreferenceChange(TourFramesKey.self) { frames in
                guard let frame = frames[id] else { return }
                DispatchQueue.main.async {
                    tour.updateFrame(id, frame)
                }
            }
    }

    private static func token(epoch: Int, frame: CGRect) -> String {
        "\(epoch)-\(frame.origin.x.rounded())-\(frame.origin.y.rounded())-\(frame.width.rounded())-\(frame.height.rounded())"
    }
}

extension View {
    func tourTarget(_ id: AppTourTargetID) -> some View {
        modifier(TourTargetModifier(id: id))
    }
}

struct AppTourOverlay: View {
    @Bindable var tour: AppTourController
    var showRunningTab: Bool
    var showStressAnalysis: Bool = true
    var accent: Color
    var cardFill: Color
    var cardBorder: Color
    var onFinished: () -> Void

    var body: some View {
        GeometryReader { geo in
            let hole = resolvedHole(in: geo)
            let steps = AppTourStep.visibleSteps(showRunningTab: showRunningTab, showStressAnalysis: showStressAnalysis)
            let stepNumber = (steps.firstIndex(of: tour.step) ?? 0) + 1
            let isLast = tour.step == steps.last

            ZStack(alignment: .topLeading) {
                dimming(hole: hole, size: geo.size)

                if let hole {
                    RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                        .strokeBorder(accent, lineWidth: 2)
                        .frame(width: hole.width, height: hole.height)
                        .position(x: hole.midX, y: hole.midY)
                        .allowsHitTesting(false)
                }

                tooltip(hole: hole, size: geo.size, stepNumber: stepNumber, total: steps.count, isLast: isLast)
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.28), value: tour.step)
        .animation(.easeInOut(duration: 0.28), value: tour.frames[tour.step.targetID])
    }

    private func resolvedHole(in geo: GeometryProxy) -> CGRect? {
        guard let reported = tour.currentFrame() else { return nil }
        let origin = geo.frame(in: .global).origin
        let local = reported.offsetBy(dx: -origin.x, dy: -origin.y)
        let padded = local.insetBy(dx: -8, dy: -8)
        let bounds = CGRect(origin: .zero, size: geo.size).insetBy(dx: 8, dy: 8)
        let intersection = padded.intersection(bounds)
        guard intersection.width > 8, intersection.height > 8 else { return nil }
        return intersection
    }

    private func dimming(hole: CGRect?, size: CGSize) -> some View {
        Path { path in
            path.addRect(CGRect(origin: .zero, size: size))
            if let hole {
                path.addRoundedRect(
                    in: hole,
                    cornerSize: CGSize(width: Theme.cardCorner, height: Theme.cardCorner),
                    style: .continuous
                )
            }
        }
        .fill(Color.black.opacity(0.58), style: FillStyle(eoFill: true))
        .contentShape(Rectangle())
    }

    private func tooltip(
        hole: CGRect?,
        size: CGSize,
        stepNumber: Int,
        total: Int,
        isLast: Bool
    ) -> some View {
        let width = min(size.width - 32, 360)
        let estimatedHeight: CGFloat = 176
        let placement = tooltipOrigin(hole: hole, size: size, width: width, height: estimatedHeight)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(tour.step.title)
                    .font(.headline)
                Spacer(minLength: 8)
                Text("\(stepNumber) / \(total)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Text(tour.step.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Skip") {
                    tour.finish()
                    onFinished()
                }
                .foregroundStyle(.secondary)

                Spacer()

                Button(isLast ? "Done" : "Next") {
                    if isLast {
                        tour.finish()
                        onFinished()
                    } else {
                        tour.advance(showRunningTab: showRunningTab, showStressAnalysis: showStressAnalysis)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: width, alignment: .leading)
        .background(cardFill, in: RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                .strokeBorder(cardBorder, lineWidth: 1)
        )
        .offset(x: placement.x, y: placement.y)
    }

    private func tooltipOrigin(hole: CGRect?, size: CGSize, width: CGFloat, height: CGFloat) -> CGPoint {
        let margin: CGFloat = 16
        let gap: CGFloat = 12
        let minY = margin
        let maxY = size.height - height - 90
        let minX = margin
        let maxX = max(minX, size.width - width - margin)

        guard let hole else {
            return CGPoint(x: (size.width - width) / 2, y: max(minY, min(maxY, size.height * 0.38)))
        }

        let below = hole.maxY + gap
        let above = hole.minY - gap - height
        let y: CGFloat
        if below + height <= maxY + height {
            y = min(below, maxY)
        } else if above >= minY {
            y = above
        } else {
            y = min(max(below, minY), maxY)
        }

        let aligned = hole.midX - width / 2
        let x = min(max(aligned, minX), maxX)
        return CGPoint(x: x, y: max(minY, min(y, maxY)))
    }
}
