import CoreMedia
import CoreVideo
import Foundation
import Testing
@testable import WorkoutApp

/// Deterministic noise so failures reproduce.
private struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

/// Bar height for one rep: cosine descent, short pause, cosine ascent. True MCV is `rom / up`.
private func repHeight(_ t: Double, down: Double, up: Double, rom: Double) -> Double {
    if t < down { return rom * 0.5 * (1 + cos(.pi * t / down)) }
    if t < down + 0.3 { return 0 }
    let u = (t - down - 0.3) / up
    return u < 1 ? rom * 0.5 * (1 - cos(.pi * u)) : rom
}

/// 120 fps with timestamp jitter, 5 % dropped frames and ±1.5 mm of tracking noise.
private func syntheticSet(ups: [Double], rom: Double = 0.55, seed: UInt64 = 42) -> [BarSample] {
    var rng = SeededRNG(state: seed)
    var samples: [BarSample] = []
    var offset = 0.0
    for up in ups {
        let cycle = 1.2 + 0.3 + up + 0.8
        var t = 0.0
        while t < cycle {
            if Double.random(in: 0...1, using: &rng) > 0.05 {
                let noise = Double.random(in: -0.0015...0.0015, using: &rng)
                samples.append(BarSample(t: offset + t, y: repHeight(t, down: 1.2, up: up, rom: rom) + noise))
            }
            t += 1.0 / 120.0 + Double.random(in: -0.0005...0.0005, using: &rng)
        }
        offset += cycle
    }
    return samples
}

@Suite("VelocityAnalyzer")
struct VelocityAnalyzerTests {
    @Test("finds every rep and reports ROM")
    func repCountAndROM() {
        let reps = VelocityAnalyzer.analyze(samples: syntheticSet(ups: [0.9, 1.0, 1.15, 1.4, 1.9]), lift: .squat)
        #expect(reps.count == 5)
        for rep in reps { #expect(abs(rep.rom - 0.55) < 0.02) }
    }

    @Test("mean concentric velocity tracks the true value within 10 %")
    func meanVelocityAccuracy() {
        let ups = [1.0, 1.15, 1.4, 1.9]
        let reps = VelocityAnalyzer.analyze(samples: syntheticSet(ups: ups), lift: .squat)
        #expect(reps.count == ups.count)
        for (rep, up) in zip(reps, ups) {
            let truth = 0.55 / up
            #expect(abs(rep.meanVelocity - truth) / truth < 0.10)
        }
    }

    @Test("slower reps show growing velocity loss")
    func velocityLossGrows() {
        let reps = VelocityAnalyzer.analyze(samples: syntheticSet(ups: [0.9, 1.1, 1.4, 1.9]), lift: .bench)
        #expect(reps.count == 4)
        #expect(reps.first!.velocityLoss < 0.05)
        #expect(zip(reps, reps.dropFirst()).allSatisfy { $0.velocityLoss <= $1.velocityLoss + 0.01 })
        #expect(reps.last!.velocityLoss > 0.4)
    }

    @Test("a stall inside one push does not split the rep")
    func stickingPointKeepsRepWhole() {
        var rng = SeededRNG(state: 7)
        var samples: [BarSample] = []
        var t = 0.0
        while t < 4.0 {
            // Up 0→0.2 m, 0.12 s stall near 0.2 m, then up to 0.5 m.
            var y = 0.0
            if t >= 1.0 && t < 1.8 { y = 0.2 * (t - 1.0) / 0.8 }
            else if t >= 1.8 && t < 1.92 { y = 0.2 }
            else if t >= 1.92 && t < 2.8 { y = 0.2 + 0.3 * (t - 1.92) / 0.88 }
            else if t >= 2.8 { y = 0.5 }
            samples.append(BarSample(t: t, y: y + Double.random(in: -0.001...0.001, using: &rng)))
            t += 1.0 / 120.0
        }
        #expect(VelocityAnalyzer.analyze(samples: samples, lift: .squat).count == 1)
    }

    @Test("movement below the minimum ROM is ignored")
    func shortMovementIgnored() {
        let samples = (0..<600).map { i -> BarSample in
            let t = Double(i) / 120
            return BarSample(t: t, y: 0.05 * (1 - cos(2 * .pi * t / 2)) / 2)
        }
        #expect(VelocityAnalyzer.analyze(samples: samples, lift: .squat).isEmpty)
    }

    @Test("too few samples yields no reps")
    func tooFewSamples() {
        #expect(VelocityAnalyzer.analyze(samples: [], lift: .bench).isEmpty)
    }

    @Test("only the three main lifts are supported")
    func liftMapping() {
        #expect(VBTLift(exerciseName: "Back Squat") == .squat)
        #expect(VBTLift(exerciseName: "Barbell Bench Press") == .bench)
        #expect(VBTLift(exerciseName: "Deadlift") == .deadlift)
        #expect(VBTLift(exerciseName: "Romanian Deadlift") == nil)
        #expect(VBTLift(exerciseName: "Leg Press") == nil)
    }
}

@Suite("BarTracker")
struct BarTrackerTests {
    private static let width = 360, height = 640
    private static let sleevePx = 18.0

    /// NV12 frame with a plate, collar and a 18 px "sleeve" centred on `row` (top-left origin).
    private func frame(sleeveRow row: Double) -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, Self.width, Self.height, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, nil, &pb)
        let buffer = pb!
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0)!
        let ctx = CGContext(
            data: base, width: Self.width, height: Self.height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRowOfPlane(buffer, 0),
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        ctx.translateBy(x: 0, y: CGFloat(Self.height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.setFillColor(gray: 0.55, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: Self.width, height: Self.height))
        var rng = SeededRNG(state: 3)
        for _ in 0..<80 {
            ctx.setFillColor(gray: CGFloat.random(in: 0.3...0.8, using: &rng), alpha: 1)
            ctx.fill(CGRect(x: Double.random(in: 0...320, using: &rng), y: Double.random(in: 0...600, using: &rng), width: 30, height: 20))
        }
        ctx.setFillColor(gray: 0.1, alpha: 1); ctx.fill(CGRect(x: 100, y: row - 75, width: 20, height: 150))
        ctx.setFillColor(gray: 0.85, alpha: 1); ctx.fill(CGRect(x: 120, y: row - 22, width: 24, height: 44))
        ctx.setFillColor(gray: 0.95, alpha: 1); ctx.fill(CGRect(x: 144, y: row - Self.sleevePx / 2, width: 100, height: Self.sleevePx))
        return buffer
    }

    private func calibration(row: Double, tapErrorPx: Double = 0) -> BarCalibration {
        BarCalibration(
            p1: CGPoint(x: 0.5, y: (row - Self.sleevePx / 2 + tapErrorPx) / Double(Self.height)),
            p2: CGPoint(x: 0.5, y: (row + Self.sleevePx / 2 + tapErrorPx / 2) / Double(Self.height)),
            reference: .sleeve, frameSize: CGSize(width: Self.width, height: Self.height)
        )
    }

    @Test("edge snapping recovers the sleeve width from sloppy taps")
    func edgeSnapping() throws {
        let row = 300.0
        let buffer = frame(sleeveRow: row)
        for error in [-3.0, -1.5, 1.5, 3.0] {
            let raw = calibration(row: row, tapErrorPx: error)
            let snapped = try #require(raw.snappedToEdges(in: buffer))
            #expect(abs(snapped.pixelLength - Self.sleevePx) < 0.3, "tap error \(error) px")
        }
    }

    @Test("tracks vertical motion and converts it to metres")
    func tracksMotion() throws {
        let start = 300.0
        let cal = calibration(row: start)
        let core = BarTrackerCore(calibration: cal)
        let travelPx = 80.0
        let steps = 40
        var last: TrackerReading?
        for i in 0...steps {
            // Sub-pixel steps, moving up the frame (row decreases).
            let row = start - travelPx * Double(i) / Double(steps)
            last = core.process(frame(sleeveRow: row), at: CMTime(seconds: Double(i) / 120, preferredTimescale: 600))
            #expect(last != nil, "lost track at step \(i)")
        }
        let expected = travelPx * cal.metersPerPixel
        #expect(abs(try #require(last).y - expected) < 0.05 * expected)
    }
}
