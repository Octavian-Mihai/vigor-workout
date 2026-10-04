import Combine
import Foundation
import HealthKit
import WatchConnectivity

/// Compact mirror of the phone's live session state, pushed over WatchConnectivity.
/// Kept independent from the phone-side DTO (WorkoutApp/Services/WatchSessionSync.swift) —
/// same shape by convention, no shared source file between the two targets.
struct WatchSessionSnapshot: Codable, Equatable {
    struct ExerciseInfo: Codable, Equatable, Identifiable {
        var id: String
        var name: String
        var targetSets: Int
        var targetReps: Int?
        var completedSets: Int
        var isSupersetGroup: Bool
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

    static let empty = WatchSessionSnapshot(
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

struct WatchLogSetMessage: Codable {
    var exerciseID: String
    var weightKg: Double
    var reps: Int
    var rir: Int
}

@MainActor
final class PhoneConnectivity: NSObject, ObservableObject {
    static let shared = PhoneConnectivity()

    @Published private(set) var snapshot: WatchSessionSnapshot = .empty

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func logSet(exerciseID: String, weightKg: Double, reps: Int, rir: Int) {
        let message = WatchLogSetMessage(exerciseID: exerciseID, weightKg: weightKg, reps: reps, rir: rir)
        guard let data = try? JSONEncoder().encode(message) else { return }
        let payload = ["logSet": data]
        let session = WCSession.default
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in
                session.transferUserInfo(payload)
            }
        } else {
            session.transferUserInfo(payload)
        }
    }

    /// Asks the phone to finish and save the session; the watch workout ends when the phone reports it inactive.
    func endWorkout() {
        let payload: [String: Any] = ["endWorkout": true]
        let session = WCSession.default
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in
                session.transferUserInfo(payload)
            }
        } else {
            session.transferUserInfo(payload)
        }
    }

    private func apply(applicationContext: [String: Any]) {
        guard let data = applicationContext["snapshot"] as? Data,
              let decoded = try? JSONDecoder().decode(WatchSessionSnapshot.self, from: data)
        else { return }
        snapshot = decoded
    }
}

extension PhoneConnectivity: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.apply(applicationContext: applicationContext)
        }
    }
}

@MainActor
final class WatchWorkoutManager: NSObject, ObservableObject {
    static let shared = WatchWorkoutManager()

    @Published private(set) var isRunning = false

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    func requestAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let share: Set = [HKQuantityType.workoutType()]
        let read: Set<HKObjectType> = [HKQuantityType(.heartRate)]
        healthStore.requestAuthorization(toShare: share, read: read) { _, _ in }
    }

    func start() {
        guard session == nil, HKHealthStore.isHealthDataAvailable() else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        do {
            let newSession = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let newBuilder = newSession.associatedWorkoutBuilder()
            newBuilder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            newSession.delegate = self
            newBuilder.delegate = self
            session = newSession
            builder = newBuilder
            let startDate = Date()
            newSession.startActivity(with: startDate)
            newBuilder.beginCollection(withStart: startDate) { _, _ in }
            isRunning = true
        } catch {
            print("WatchWorkoutManager failed to start session: \(error)")
        }
    }

    func end() {
        guard let session else { return }
        session.end()
        builder?.endCollection(withEnd: Date()) { [weak self] _, _ in
            self?.builder?.finishWorkout { _, _ in }
        }
        self.session = nil
        self.builder = nil
        isRunning = false
    }
}

extension WatchWorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {}
}

extension WatchWorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {}
}
