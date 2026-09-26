import Combine
import SwiftUI

struct ContentView: View {
    @ObservedObject private var connectivity = PhoneConnectivity.shared
    @ObservedObject private var workoutManager = WatchWorkoutManager.shared

    @State private var now = Date()
    @State private var weightKg: Double = 20
    @State private var reps: Int = 8

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var snapshot: WatchSessionSnapshot { connectivity.snapshot }

    private var currentExercise: WatchSessionSnapshot.ExerciseInfo? {
        guard snapshot.exercises.indices.contains(snapshot.currentExerciseIndex) else { return nil }
        return snapshot.exercises[snapshot.currentExerciseIndex]
    }

    private var restRemaining: Int {
        guard let end = snapshot.restEndDate else { return 0 }
        return max(0, Int(end.timeIntervalSince(now).rounded(.up)))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if !snapshot.isActive {
                    Text("No active workout")
                        .font(.headline)
                    Text("Start a session on your iPhone to see it here.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else if let exercise = currentExercise {
                    if exercise.isSupersetGroup {
                        Text("SUPERSET")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.orange)
                    }
                    Text(exercise.name)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    Text(setsLabel(for: exercise))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if snapshot.isResting && restRemaining > 0 {
                        Text(timeString(restRemaining))
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(.orange)
                        Text("Resting")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Stepper(value: $weightKg, in: 0...400, step: 2.5) {
                            Text("\(weightKg, specifier: "%.1f") kg")
                                .font(.caption.monospacedDigit())
                        }
                        Stepper(value: $reps, in: 0...50) {
                            Text("\(reps) reps")
                                .font(.caption.monospacedDigit())
                        }
                        Button {
                            connectivity.logSet(exerciseID: exercise.id, weightKg: weightKg, reps: reps, rir: 2)
                        } label: {
                            Text("Log Set")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }

                    Button(role: .destructive) {
                        workoutManager.end()
                    } label: {
                        Text("End Workout")
                            .font(.caption)
                    }
                } else {
                    Text("Workout complete")
                        .font(.headline)
                }
            }
            .padding()
        }
        .onReceive(timer) { now = $0 }
        .onAppear {
            workoutManager.requestAuthorization()
        }
        .onChange(of: currentExercise?.id) { _, _ in
            reps = currentExercise?.targetReps ?? reps
        }
        .onChange(of: snapshot.isActive) { _, isActive in
            if isActive {
                workoutManager.start()
            } else {
                workoutManager.end()
            }
        }
    }

    private func setsLabel(for exercise: WatchSessionSnapshot.ExerciseInfo) -> String {
        var label = "\(exercise.completedSets)/\(exercise.targetSets) sets"
        if let targetReps = exercise.targetReps {
            label += " · \(targetReps) reps"
        }
        return label
    }

    private func timeString(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

#Preview {
    ContentView()
}
