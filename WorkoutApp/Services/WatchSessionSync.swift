import Foundation
import WatchConnectivity

/// Mirrors the same shape as the watch target's own `WatchSessionSnapshot`
/// (VIGOR Watch App Watch App/WatchSession.swift) — no shared source file between
/// the two targets, kept in sync by convention like the widget's JSON snapshot.
struct WatchSessionSnapshot: Codable, Equatable {
    struct ExerciseInfo: Codable, Equatable {
        var id: String
        var name: String
        var targetSets: Int
        var targetReps: Int?
        var completedSets: Int
        var isSupersetGroup: Bool
        /// Suggested starting values for the next set (last set this session, else the same set last time).
        var lastWeightKg: Double?
        var lastReps: Int?
        var lastRIR: Int?
        var isAssisted: Bool?
    }

    var isActive: Bool
    var sessionLabel: String
    var exercises: [ExerciseInfo]
    var currentExerciseIndex: Int
    var isResting: Bool
    var restEndDate: Date?
    var restTotalSeconds: Int?
    var weightUnit: String?

    static let inactive = WatchSessionSnapshot(
        isActive: false,
        sessionLabel: "",
        exercises: [],
        currentExerciseIndex: 0,
        isResting: false,
        restEndDate: nil,
        restTotalSeconds: nil,
        weightUnit: nil
    )
}

private struct WatchLogSetMessage: Codable {
    var exerciseID: String
    var weightKg: Double
    var reps: Int
    var rir: Int
}

/// Bridges the live session on the phone to the watch app over WatchConnectivity.
/// `SessionController` calls `pushSnapshot` whenever session state changes; incoming
/// "log set" messages from the watch are applied back into whichever controller is
/// currently attached, exactly as if the set had been logged locally.
@MainActor
final class WatchSessionSync: NSObject {
    static let shared = WatchSessionSync()

    private weak var controller: SessionController?

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func attach(_ controller: SessionController) {
        self.controller = controller
        pushSnapshot(from: controller)
    }

    func detach() {
        controller = nil
        send(.inactive)
    }

    func pushSnapshot(from controller: SessionController) {
        guard self.controller === controller else { return }
        let exercises = controller.exercises.map { exercise in
            let previous = previousSets(for: exercise.name, in: controller.pastSessions)
            let suggestion: (weightKg: Double, reps: Int, rir: Int)? = {
                if let last = exercise.logged.last { return (last.weightKg, last.reps, last.rir) }
                if let set = previous[safe: exercise.logged.count] ?? previous.last {
                    return (set.weight, set.reps, set.rir)
                }
                return nil
            }()
            return WatchSessionSnapshot.ExerciseInfo(
                id: exercise.id.uuidString,
                name: exercise.name,
                targetSets: exercise.targetSets,
                targetReps: exercise.targetReps,
                completedSets: exercise.logged.count,
                isSupersetGroup: exercise.supersetGroupID != nil,
                lastWeightKg: suggestion?.weightKg,
                lastReps: suggestion?.reps,
                lastRIR: suggestion?.rir,
                isAssisted: AssistedLoad.isAssisted(exercise.name)
            )
        }
        let currentIndex = controller.exercises.firstIndex { $0.logged.count < max($0.targetSets, 1) } ?? 0
        let snapshot = WatchSessionSnapshot(
            isActive: true,
            sessionLabel: controller.programDay?.name ?? "Workout",
            exercises: exercises,
            currentExerciseIndex: currentIndex,
            isResting: controller.timerRunning,
            restEndDate: controller.timerRunning ? Date().addingTimeInterval(TimeInterval(controller.restRemaining)) : nil,
            restTotalSeconds: controller.restDuration,
            weightUnit: UserDefaults.standard.string(forKey: "weightUnit") ?? "kg"
        )
        send(snapshot)
    }

    private func previousSets(for name: String, in sessions: [WorkoutSession]) -> [SetLog] {
        for session in sessions where session.endDate != nil {
            let sets = session.orderedSets.filter {
                $0.exerciseName.compare(name, options: .caseInsensitive) == .orderedSame
            }
            if !sets.isEmpty { return sets }
        }
        return []
    }

    private func send(_ snapshot: WatchSessionSnapshot) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              let data = try? JSONEncoder().encode(snapshot)
        else { return }
        try? WCSession.default.updateApplicationContext(["snapshot": data])
    }

    private func applyLogSet(_ message: WatchLogSetMessage) {
        guard let controller,
              let uuid = UUID(uuidString: message.exerciseID)
        else { return }
        controller.logSet(exerciseID: uuid, weightKg: message.weightKg, reps: message.reps, rir: message.rir)
    }
}

extension WatchSessionSync: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if message["endWorkout"] != nil {
            Task { @MainActor in self.controller?.watchFinishRequest += 1 }
            return
        }
        guard let data = message["logSet"] as? Data,
              let decoded = try? JSONDecoder().decode(WatchLogSetMessage.self, from: data)
        else { return }
        Task { @MainActor in
            self.applyLogSet(decoded)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        if userInfo["endWorkout"] != nil {
            Task { @MainActor in self.controller?.watchFinishRequest += 1 }
            return
        }
        guard let data = userInfo["logSet"] as? Data,
              let decoded = try? JSONDecoder().decode(WatchLogSetMessage.self, from: data)
        else { return }
        Task { @MainActor in
            self.applyLogSet(decoded)
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
