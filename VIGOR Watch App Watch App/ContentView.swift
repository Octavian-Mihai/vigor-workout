import Combine
import SwiftUI
import WatchKit

struct ContentView: View {
    @ObservedObject private var connectivity = PhoneConnectivity.shared
    @ObservedObject private var workoutManager = WatchWorkoutManager.shared

    private enum Field { case weight, reps, rir }

    @State private var now = Date()
    @State private var weight: Double = 20
    @State private var reps: Int = 8
    @State private var rir: Int = 2
    @State private var field: Field = .weight
    @State private var crownTicks: Double = 0
    @State private var showFinishConfirm = false
    @State private var wasResting = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let kgPerLb = 0.45359237

    private var snapshot: WatchSessionSnapshot { connectivity.snapshot }
    private var usesPounds: Bool { snapshot.weightUnit == "lb" }
    private var unitLabel: String { usesPounds ? "lb" : "kg" }
    private var weightStep: Double { usesPounds ? 5 : 2.5 }

    private var currentExercise: WatchSessionSnapshot.ExerciseInfo? {
        guard snapshot.exercises.indices.contains(snapshot.currentExerciseIndex) else { return nil }
        return snapshot.exercises[snapshot.currentExerciseIndex]
    }

    private var isComplete: Bool {
        !snapshot.exercises.isEmpty
            && snapshot.exercises.allSatisfy { $0.completedSets >= max($0.targetSets, 1) }
    }

    private var restRemaining: Int {
        guard snapshot.isResting, let end = snapshot.restEndDate else { return 0 }
        return max(0, Int(end.timeIntervalSince(now).rounded(.up)))
    }

    private var isShowingRest: Bool { restRemaining > 0 && !isComplete }

    private var phase: String {
        if !snapshot.isActive { return "idle" }
        if isComplete { return "complete" }
        if isShowingRest { return "rest-\(currentExercise?.id ?? "")" }
        return "log-\(currentExercise?.id ?? "")"
    }

    var body: some View {
        ZStack {
            if !snapshot.isActive {
                idleView.transition(.opacity)
            } else if isComplete {
                completeView.transition(.scale(scale: 0.9).combined(with: .opacity))
            } else if let exercise = currentExercise {
                Group {
                    if isShowingRest {
                        restView(exercise)
                    } else {
                        logView(exercise)
                    }
                }
                .id(phase)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            }
        }
        .animation(.smooth(duration: 0.35), value: phase)
        .onReceive(timer) { tick in
            now = tick
            let resting = snapshot.isActive && restRemaining > 0
            if wasResting && !resting && snapshot.isActive {
                WKInterfaceDevice.current().play(.notification)
            }
            wasResting = resting
        }
        .onAppear {
            workoutManager.requestAuthorization()
            applyDefaults()
        }
        .onChange(of: currentExercise?.id) { _, _ in applyDefaults() }
        .onChange(of: currentExercise?.completedSets) { _, _ in applyDefaults() }
        .onChange(of: snapshot.isActive) { _, isActive in
            if isActive {
                workoutManager.start()
            } else {
                workoutManager.end()
            }
        }
        .confirmationDialog("Finish workout?", isPresented: $showFinishConfirm, titleVisibility: .visible) {
            Button("Finish on iPhone") {
                WKInterfaceDevice.current().play(.success)
                connectivity.endWorkout()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - States

    private var idleView: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 34))
                .foregroundStyle(.orange)
            Text("No active workout")
                .font(.headline)
            Text("Start a session on your iPhone to see it here.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var completeView: some View {
        let totalSets = snapshot.exercises.reduce(0) { $0 + $1.completedSets }
        return VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)
            Text("Workout complete")
                .font(.headline)
            Text("\(snapshot.exercises.count) exercises · \(totalSets) sets")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button("Finish") { showFinishConfirm = true }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
        }
        .padding()
    }

    private func restView(_ exercise: WatchSessionSnapshot.ExerciseInfo) -> some View {
        let total = max(snapshot.restTotalSeconds ?? 90, 1)
        let progress = min(1, Double(restRemaining) / Double(total))
        let nextSet = min(exercise.completedSets + 1, max(exercise.targetSets, 1))
        return VStack(spacing: 6) {
            ZStack {
                Circle().stroke(.orange.opacity(0.2), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(.orange, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: restRemaining)
                VStack(spacing: 0) {
                    Text(timeString(restRemaining))
                        .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText(countsDown: true))
                    Text("Rest")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 110, height: 110)
            Text("Next: \(exercise.name) · set \(nextSet)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal)
    }

    private func logView(_ exercise: WatchSessionSnapshot.ExerciseInfo) -> some View {
        VStack(spacing: 8) {
            VStack(spacing: 2) {
                if exercise.isSupersetGroup {
                    Text("SUPERSET")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.orange)
                }
                Text(exercise.name)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)
                setDots(exercise)
            }

            HStack(spacing: 6) {
                tile(
                    title: exercise.isAssisted == true ? "\(unitLabel) assist" : unitLabel,
                    value: weight.formatted(.number.precision(.fractionLength(0...1))),
                    selected: field == .weight
                ) { select(.weight) }
                tile(title: "reps", value: "\(reps)", selected: field == .reps) { select(.reps) }
                tile(title: "RIR", value: "\(rir)", selected: field == .rir) { select(.rir) }
            }

            Button {
                WKInterfaceDevice.current().play(.success)
                connectivity.logSet(
                    exerciseID: exercise.id,
                    weightKg: usesPounds ? weight * kgPerLb : weight,
                    reps: reps,
                    rir: rir
                )
            } label: {
                Text("Log set \(min(exercise.completedSets + 1, max(exercise.targetSets, exercise.completedSets + 1)))")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)

            Button("Finish workout") { showFinishConfirm = true }
                .font(.caption2)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
        .focusable()
        .digitalCrownRotation(
            $crownTicks,
            from: 0,
            through: 1000,
            by: 1,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: crownTicks) { _, ticks in crownMoved(to: ticks) }
    }

    // MARK: - Pieces

    private func tile(title: String, value: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(title)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(selected ? Color.orange.opacity(0.28) : Color.gray.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selected ? Color.orange : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2), value: selected)
    }

    private func setDots(_ exercise: WatchSessionSnapshot.ExerciseInfo) -> some View {
        let total = max(exercise.targetSets, exercise.completedSets, 1)
        return HStack(spacing: 4) {
            ForEach(0..<min(total, 8), id: \.self) { index in
                Circle()
                    .fill(index < exercise.completedSets ? Color.orange : Color.gray.opacity(0.35))
                    .frame(width: 7, height: 7)
            }
            if let reps = exercise.targetReps {
                Text("· \(reps)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .animation(.snappy, value: exercise.completedSets)
    }

    // MARK: - Logic

    private func select(_ newField: Field) {
        field = newField
        crownTicks = ticks(for: newField)
        WKInterfaceDevice.current().play(.click)
    }

    private func ticks(for field: Field) -> Double {
        switch field {
        case .weight: return weight / weightStep
        case .reps: return Double(reps)
        case .rir: return Double(rir)
        }
    }

    private func crownMoved(to ticks: Double) {
        switch field {
        case .weight: weight = max(0, (ticks * weightStep * 10).rounded() / 10)
        case .reps: reps = min(max(Int(ticks.rounded()), 0), 50)
        case .rir: rir = min(max(Int(ticks.rounded()), 0), 5)
        }
    }

    /// Pre-fills the steppers from the last set (or the same set last session) so a typical set is one tap.
    private func applyDefaults() {
        guard let exercise = currentExercise else { return }
        let kg = exercise.lastWeightKg ?? (weight * (usesPounds ? kgPerLb : 1))
        let displayed = usesPounds ? kg / kgPerLb : kg
        weight = (displayed / weightStep).rounded() * weightStep
        reps = exercise.lastReps ?? exercise.targetReps ?? reps
        rir = exercise.lastRIR ?? rir
        crownTicks = ticks(for: field)
    }

    private func timeString(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

#Preview {
    ContentView()
}
