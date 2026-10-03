import Foundation

/// One tracked bar position. `y` is metres, positive = up, relative to the first sample.
struct BarSample: Equatable {
    var t: Double
    var y: Double
}

struct RepMetric: Identifiable, Equatable {
    let id: Int
    /// Concentric start/end, seconds from the first sample.
    let startTime: Double
    let endTime: Double
    /// Mean concentric velocity (displacement / duration), m/s.
    let meanVelocity: Double
    let peakVelocity: Double
    /// Concentric range of motion, metres.
    let rom: Double
    var duration: Double { endTime - startTime }
    /// Loss in MCV versus the fastest rep of the set, 0...1.
    var velocityLoss: Double = 0
}

enum VBTLift: String, CaseIterable {
    case squat, bench, deadlift

    /// Maps catalog exercise names to a supported lift. Variants are deliberately excluded
    /// until their velocity profiles are validated.
    init?(exerciseName: String) {
        switch exerciseName {
        case "Back Squat": self = .squat
        case "Barbell Bench Press": self = .bench
        case "Deadlift", "Sumo Deadlift": self = .deadlift
        default: return nil
        }
    }

    var title: String {
        switch self {
        case .squat: return "Squat"
        case .bench: return "Bench"
        case .deadlift: return "Deadlift"
        }
    }

    /// Smallest upward travel (metres) that counts as a rep; rejects re-racks and jitter.
    var minimumROM: Double {
        switch self {
        case .squat: return 0.30
        case .bench: return 0.15
        case .deadlift: return 0.25
        }
    }
}

enum VelocityAnalyzer {
    /// Half-width (s) of the local quadratic fit used for smoothing and differentiation.
    static let smoothingHalfWindow = 0.075
    /// Upward speed (m/s) that marks the bar as "moving up".
    static let moveThreshold = 0.03
    /// Where a push is considered to begin/end when walking outward from the core of the run.
    /// Slightly above the noise floor so stationary pauses don't get absorbed into the rep.
    static let turnaroundThreshold = 0.012
    /// Gaps shorter than this inside one upward push (sticking point) don't split a rep.
    static let mergeGap = 0.20
    static let minimumPeakVelocity = 0.10

    struct Smoothed {
        var t: [Double]
        var position: [Double]
        var velocity: [Double]
    }

    /// Local weighted quadratic regression. Handles uneven timestamps (dropped frames) and
    /// yields position and velocity together, which beats finite differences on noisy tracking.
    static func smooth(_ samples: [BarSample], halfWindow: Double = smoothingHalfWindow) -> Smoothed {
        let n = samples.count
        var pos = [Double](repeating: 0, count: n)
        var vel = [Double](repeating: 0, count: n)
        var lo = 0
        var hi = 0
        for i in 0..<n {
            let ti = samples[i].t
            while samples[lo].t < ti - halfWindow { lo += 1 }
            while hi < n - 1, samples[hi + 1].t <= ti + halfWindow { hi += 1 }
            guard hi - lo >= 4 else {
                pos[i] = samples[i].y
                vel[i] = i > 0 && samples[i].t > samples[i - 1].t
                    ? (samples[i].y - samples[i - 1].y) / (samples[i].t - samples[i - 1].t) : 0
                continue
            }
            // Normal equations for y ≈ a + b·dt + c·dt², tricube weights.
            var s0 = 0.0, s1 = 0.0, s2 = 0.0, s3 = 0.0, s4 = 0.0
            var r0 = 0.0, r1 = 0.0, r2 = 0.0
            for j in lo...hi {
                let dt = samples[j].t - ti
                let u = abs(dt) / halfWindow
                let w = pow(max(0, 1 - u * u * u), 3)
                let y = samples[j].y
                s0 += w; s1 += w * dt; s2 += w * dt * dt; s3 += w * dt * dt * dt; s4 += w * dt * dt * dt * dt
                r0 += w * y; r1 += w * dt * y; r2 += w * dt * dt * y
            }
            if let (a, b) = solveQuadratic(s0, s1, s2, s3, s4, r0, r1, r2) {
                pos[i] = a
                vel[i] = b
            } else {
                pos[i] = samples[i].y
            }
        }
        return Smoothed(t: samples.map(\.t), position: pos, velocity: vel)
    }

    private static func solveQuadratic(
        _ s0: Double, _ s1: Double, _ s2: Double, _ s3: Double, _ s4: Double,
        _ r0: Double, _ r1: Double, _ r2: Double
    ) -> (Double, Double)? {
        // Cramer's rule on [[s0 s1 s2],[s1 s2 s3],[s2 s3 s4]]·[a b c] = [r0 r1 r2].
        func det(_ m: [[Double]]) -> Double {
            m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1])
                - m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0])
                + m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0])
        }
        let m = [[s0, s1, s2], [s1, s2, s3], [s2, s3, s4]]
        let d = det(m)
        guard abs(d) > 1e-18 else { return nil }
        let a = det([[r0, s1, s2], [r1, s2, s3], [r2, s3, s4]]) / d
        let b = det([[s0, r0, s2], [s1, r1, s3], [s2, r2, s4]]) / d
        return (a, b)
    }

    /// Splits a set into reps by finding concentric (upward) pushes.
    static func analyze(samples raw: [BarSample], lift: VBTLift) -> [RepMetric] {
        guard raw.count >= 10, let t0 = raw.first?.t else { return [] }
        let samples = raw.map { BarSample(t: $0.t - t0, y: $0.y) }
        let s = smooth(samples)
        let n = samples.count

        // 1. Runs where the bar is moving up.
        var runs: [(Int, Int)] = []
        var i = 0
        while i < n {
            if s.velocity[i] > moveThreshold {
                var j = i
                while j + 1 < n, s.velocity[j + 1] > moveThreshold { j += 1 }
                runs.append((i, j))
                i = j + 1
            } else {
                i += 1
            }
        }

        // 2. Merge runs split by a brief stall (sticking point).
        var merged: [(Int, Int)] = []
        for run in runs {
            if let last = merged.last, s.t[run.0] - s.t[last.1] < mergeGap,
               s.position[run.0] >= s.position[last.1] - 0.01 {
                merged[merged.count - 1].1 = run.1
            } else {
                merged.append(run)
            }
        }

        // 3. Extend each run outward to the true turnaround (velocity zero crossing).
        var reps: [RepMetric] = []
        for (a0, b0) in merged {
            var a = a0, b = b0
            while a > 0, s.velocity[a - 1] > turnaroundThreshold { a -= 1 }
            while b < n - 1, s.velocity[b + 1] > turnaroundThreshold { b += 1 }
            let rom = s.position[b] - s.position[a]
            let dur = s.t[b] - s.t[a]
            let peak = s.velocity[a...b].max() ?? 0
            guard rom >= lift.minimumROM, dur > 0.15, peak >= minimumPeakVelocity else { continue }
            reps.append(RepMetric(
                id: reps.count + 1, startTime: s.t[a], endTime: s.t[b],
                meanVelocity: rom / dur, peakVelocity: peak, rom: rom
            ))
        }

        if let best = reps.map(\.meanVelocity).max(), best > 0 {
            for k in reps.indices { reps[k].velocityLoss = max(0, (best - reps[k].meanVelocity) / best) }
        }
        return reps
    }
}
