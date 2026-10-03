#if targetEnvironment(simulator)
import CoreGraphics
import CoreMedia
import CoreVideo
import UIKit

/// Stand-in camera for the simulator: renders a barbell sleeve that holds still until a set
/// starts, then performs five squat-like reps that slow down (so velocity loss is visible).
/// Time is simulated (frame index / fps), so results don't depend on how fast the debug build runs.
final class VBTSyntheticSource {
    private let width = 720, height = 1280
    private let fps = 60.0
    private let sleevePx = 24.0
    private var timer: DispatchSourceTimer?
    private var frame = 0
    private var repsStart: Double?
    private var texture: [CGRect] = []
    private let onFrame: (CVPixelBuffer, CMTime, UIImage?) -> Void

    /// Concentric durations (s): each rep slower than the last.
    private let ups = [0.8, 0.9, 1.05, 1.3, 1.7]
    private let rom = 0.50
    private let down = 1.2
    private let pause = 0.25
    private var mPerPx: Double { 0.050 / sleevePx }

    init(onFrame: @escaping (CVPixelBuffer, CMTime, UIImage?) -> Void) {
        self.onFrame = onFrame
        var rng = SystemRandomNumberGenerator()
        texture = (0..<160).map { _ in
            CGRect(x: Double.random(in: 0...680, using: &rng), y: Double.random(in: 0...1240, using: &rng), width: 40, height: 28)
        }
    }

    func start(on queue: DispatchQueue) {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: 1.0 / fps)
        t.setEventHandler { [weak self] in self?.tick() }
        timer = t
        t.resume()
    }

    func stop() { timer?.cancel(); timer = nil }

    func startReps() { repsStart = Double(frame) / fps }

    /// Bar offset (m) below lockout at time `t` since the set started.
    private func offset(at t: Double) -> Double {
        var t = t
        for up in ups {
            if t < down { return -rom * 0.5 * (1 - cos(.pi * t / down)) }
            t -= down
            if t < pause { return -rom }
            t -= pause
            if t < up { return -rom * 0.5 * (1 + cos(.pi * t / up)) }
            t -= up
            if t < 0.5 { return 0 }
            t -= 0.5
        }
        return 0
    }

    private func tick() {
        let simTime = Double(frame) / fps
        frame += 1
        let d = repsStart.map { offset(at: simTime - $0) } ?? 0
        let centerRow = 420.0 - d / mPerPx // rows grow downward

        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, nil, &pb)
        guard let buffer = pb else { return }
        CVPixelBufferLockBaseAddress(buffer, [])
        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0),
              let ctx = CGContext(
                data: base, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRowOfPlane(buffer, 0),
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
              ) else { CVPixelBufferUnlockBaseAddress(buffer, []); return }
        // Neutral chroma, otherwise the uninitialised plane decodes as solid green.
        if let chroma = CVPixelBufferGetBaseAddressOfPlane(buffer, 1) {
            memset(chroma, 128, CVPixelBufferGetBytesPerRowOfPlane(buffer, 1) * CVPixelBufferGetHeightOfPlane(buffer, 1))
        }
        // CGContext origin is bottom-left; flip so we draw in top-left pixel rows.
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.setFillColor(gray: 0.55, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        var seed = 11
        for r in texture {
            seed = (seed &* 1103515245 &+ 12345) & 0x7fffffff
            ctx.setFillColor(gray: 0.3 + 0.5 * CGFloat(seed % 100) / 100, alpha: 1)
            ctx.fill(r)
        }
        let c = centerRow
        ctx.setFillColor(gray: 0.1, alpha: 1); ctx.fill(CGRect(x: 200, y: c - 150, width: 40, height: 300))
        ctx.setFillColor(gray: 0.85, alpha: 1); ctx.fill(CGRect(x: 240, y: c - 30, width: 46, height: 60))
        ctx.setFillColor(gray: 0.95, alpha: 1); ctx.fill(CGRect(x: 286, y: c - sleevePx / 2, width: 150, height: sleevePx))
        ctx.setFillColor(gray: 0.3, alpha: 1); ctx.fill(CGRect(x: 436, y: c - sleevePx / 2, width: 6, height: sleevePx))

        // Preview at ~15 Hz only; encoding every frame would dominate the debug build.
        let image = frame % 4 == 0 ? ctx.makeImage().map { UIImage(cgImage: $0) } : nil
        CVPixelBufferUnlockBaseAddress(buffer, [])
        onFrame(buffer, CMTime(seconds: simTime, preferredTimescale: 600), image)
    }
}
#endif
