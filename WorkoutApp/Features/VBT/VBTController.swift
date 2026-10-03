import AVFoundation
import Combine
import CoreImage
import UIKit

struct VBTSetResult {
    var reps: [RepMetric]
    /// Smoothed bar height over time (metres), decimated for charting.
    var path: [BarSample]
    var trackedFrames: Int
    var totalFrames: Int
    var duration: Double
    var averageFPS: Double
    var lift: VBTLift

    var trackedFraction: Double { totalFrames > 0 ? Double(trackedFrames) / Double(totalFrames) : 0 }
}

/// Owns the camera session and the tracking pipeline for one VBT screen.
/// All mutable pipeline state is confined to `queue`; `@Published` values are only written on main.
final class VBTController: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    enum Phase { case preview, calibrating, tracking, recording, finished }

    let lift: VBTLift
    let session = AVCaptureSession()

    @Published private(set) var phase: Phase = .preview
    @Published private(set) var cameraMessage: String?
    @Published private(set) var formatDescription = ""
    @Published private(set) var frameSize: CGSize = .zero
    @Published private(set) var liveFPS: Double = 0
    @Published private(set) var trackRect: CGRect?
    @Published private(set) var trackScore: Float = 0
    @Published private(set) var trackingLost = false
    @Published private(set) var frozen: UIImage?
    @Published private(set) var calibrationNote: String?
    @Published private(set) var liveReps: [RepMetric] = []
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var result: VBTSetResult?
    /// Simulator only: frames from the synthetic source, since there is no capture preview layer.
    @Published private(set) var previewImage: UIImage?
    @Published var targetFPS = 120

    private let queue = DispatchQueue(label: "vbt.camera", qos: .userInitiated)
    private let ciContext = CIContext()
    private var device: AVCaptureDevice?
    private var configured = false

    // Queue-confined pipeline state.
    private var core: BarTrackerCore?
    private var calibration: BarCalibration?
    private var frozenBuffer: CVPixelBuffer?
    private var freezeRequested = false
    private var recording = false
    private var samples: [BarSample] = []
    private var frameCount = 0
    private var trackedCount = 0
    private var firstRecordedTime: Double?
    private var lastReadingTime: Double?
    private var lastUIUpdate = CFAbsoluteTimeGetCurrent()
    private var uiTick = 0
    private var fpsWindowStart = CFAbsoluteTimeGetCurrent()
    private var fpsWindowFrames = 0
    private var lastFrameTime: Double = 0
    #if targetEnvironment(simulator)
    private var synthetic: VBTSyntheticSource?
    #endif

    init(lift: VBTLift) {
        self.lift = lift
        super.init()
    }

    // MARK: - Lifecycle

    func start() {
        #if targetEnvironment(simulator)
        queue.async { [weak self] in self?.startSynthetic() }
        #else
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            queue.async { [weak self] in self?.configureAndRun() }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                if granted { self.queue.async { self.configureAndRun() } } else { self.publish { $0.cameraMessage = "Camera access is off. Enable it in Settings to use VBT." } }
            }
        default:
            publish { $0.cameraMessage = "Camera access is off. Enable it in Settings to use VBT." }
        }
        #endif
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            #if targetEnvironment(simulator)
            self.synthetic?.stop()
            #endif
            if self.session.isRunning { self.session.stopRunning() }
            self.unlockDevice()
        }
    }

    // MARK: - Flow

    func beginCalibration() {
        queue.async { [weak self] in self?.freezeRequested = true }
    }

    func cancelCalibration() {
        publish { $0.phase = .preview; $0.frozen = nil }
        queue.async { [weak self] in self?.frozenBuffer = nil }
    }

    func confirmCalibration(p1: CGPoint, p2: CGPoint, reference: BarCalibration.Reference) {
        queue.async { [weak self] in
            guard let self, let buffer = self.frozenBuffer else { return }
            let size = CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
            let raw = BarCalibration(p1: p1, p2: p2, reference: reference, frameSize: size)
            let snapped = raw.snappedToEdges(in: buffer)
            let cal = snapped ?? raw
            let note = String(
                format: "%.1f px = %.0f mm (%@)",
                cal.pixelLength, reference.meters * 1000, snapped == nil ? "taps only, no edge found" : "edge-snapped"
            )
            self.calibration = cal
            self.core = BarTrackerCore(calibration: cal)
            self.frozenBuffer = nil
            self.lockDevice()
            self.publish { $0.calibrationNote = note; $0.frozen = nil; $0.phase = .tracking; $0.trackingLost = false }
        }
    }

    func recalibrate() {
        queue.async { [weak self] in
            guard let self else { return }
            self.core = nil
            self.recording = false
            self.unlockDevice()
            self.publish { $0.phase = .preview; $0.trackRect = nil; $0.result = nil }
        }
    }

    func startSet() {
        queue.async { [weak self] in
            guard let self, self.core != nil else { return }
            self.samples = []
            self.frameCount = 0
            self.trackedCount = 0
            self.firstRecordedTime = nil
            self.recording = true
            #if targetEnvironment(simulator)
            self.synthetic?.startReps()
            #endif
            self.publish { $0.phase = .recording; $0.liveReps = []; $0.elapsed = 0; $0.result = nil }
        }
    }

    func finishSet() {
        queue.async { [weak self] in
            guard let self else { return }
            self.recording = false
            let reps = VelocityAnalyzer.analyze(samples: self.samples, lift: self.lift)
            var path: [BarSample] = []
            if self.samples.count >= 10, let t0 = self.samples.first?.t {
                let s = VelocityAnalyzer.smooth(self.samples.map { BarSample(t: $0.t - t0, y: $0.y) })
                let step = max(1, s.t.count / 500)
                path = stride(from: 0, to: s.t.count, by: step).map { BarSample(t: s.t[$0], y: s.position[$0]) }
            }
            let duration = (self.samples.last?.t ?? 0) - (self.samples.first?.t ?? 0)
            let res = VBTSetResult(
                reps: reps, path: path, trackedFrames: self.trackedCount, totalFrames: self.frameCount,
                duration: duration, averageFPS: duration > 0 ? Double(self.samples.count) / duration : 0, lift: self.lift
            )
            self.publish { $0.result = res; $0.phase = .finished }
        }
    }

    func newSet() {
        publish { $0.phase = .tracking; $0.result = nil; $0.liveReps = [] }
    }

    func setTargetFPS(_ fps: Int) {
        targetFPS = fps
        #if !targetEnvironment(simulator)
        queue.async { [weak self] in
            guard let self, self.configured, self.device != nil else { return }
            self.applyFormat()
        }
        #endif
    }

    // MARK: - Camera

    #if !targetEnvironment(simulator)
    private func configureAndRun() {
        guard !configured else { if !session.isRunning { session.startRunning() }; return }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            publish { $0.cameraMessage = "No back camera available." }
            return
        }
        self.device = device
        session.beginConfiguration()
        session.sessionPreset = .inputPriority
        if session.canAddInput(input) { session.addInput(input) }
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }
        // Portrait frames: vertical bar travel maps to the buffer's y axis.
        if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        session.commitConfiguration()
        configured = true
        applyFormat()
        session.startRunning()
    }

    /// Picks the largest ≤1080p format that can deliver `targetFPS`, falling back to the fastest available.
    private func applyFormat() {
        guard let device else { return }
        let want = Double(targetFPS)
        func maxFPS(_ f: AVCaptureDevice.Format) -> Double { f.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0 }
        func pixels(_ f: AVCaptureDevice.Format) -> Int {
            let d = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
            return Int(d.width) * Int(d.height)
        }
        let capped = device.formats.filter { pixels($0) <= 1920 * 1080 }
        let format = capped.filter { maxFPS($0) >= want }.max { pixels($0) < pixels($1) }
            ?? capped.max { maxFPS($0) < maxFPS($1) }
        guard let format else { return }
        do {
            try device.lockForConfiguration()
            device.activeFormat = format
            let fps = min(want, maxFPS(format))
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
            device.unlockForConfiguration()
            let d = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            publish { $0.formatDescription = "\(d.width)×\(d.height) @ \(Int(fps)) fps" }
        } catch {
            publish { $0.cameraMessage = "Couldn't set camera format: \(error.localizedDescription)" }
        }
    }
    #endif

    /// Locks focus and exposure for the set so the image the template was cut from stays comparable.
    private func lockDevice() {
        guard let device, (try? device.lockForConfiguration()) != nil else { return }
        if device.isFocusModeSupported(.locked) { device.focusMode = .locked }
        if device.isExposureModeSupported(.locked) { device.exposureMode = .locked }
        device.unlockForConfiguration()
    }

    private func unlockDevice() {
        guard let device, (try? device.lockForConfiguration()) != nil else { return }
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
        device.unlockForConfiguration()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        handle(buffer, time: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    }

    // MARK: - Pipeline (queue only)

    fileprivate func handle(_ buffer: CVPixelBuffer, time: CMTime, previewImage image: UIImage? = nil) {
        let now = CFAbsoluteTimeGetCurrent()
        fpsWindowFrames += 1
        let size = CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        lastFrameTime = time.seconds

        if freezeRequested {
            freezeRequested = false
            if let copy = Self.copy(buffer) {
                frozenBuffer = copy
                let img = image ?? uiImage(from: buffer)
                publish { $0.frozen = img; $0.frameSize = size; $0.phase = .calibrating }
            }
        }

        var reading: TrackerReading?
        if let core {
            reading = core.process(buffer, at: time)
            if let r = reading { lastReadingTime = r.time }
            if recording {
                frameCount += 1
                if let r = reading {
                    trackedCount += 1
                    samples.append(BarSample(t: r.time, y: r.y))
                    if firstRecordedTime == nil { firstRecordedTime = r.time }
                }
            }
        }

        guard now - lastUIUpdate >= 1.0 / 15.0 else { return }
        lastUIUpdate = now
        uiTick += 1
        var fps: Double?
        if now - fpsWindowStart >= 1 {
            fps = Double(fpsWindowFrames) / (now - fpsWindowStart)
            fpsWindowStart = now
            fpsWindowFrames = 0
        }
        let lost = core != nil && time.seconds - (lastReadingTime ?? time.seconds) > 0.3
        var reps: [RepMetric]?
        if recording, uiTick % 4 == 0 { reps = VelocityAnalyzer.analyze(samples: samples, lift: lift) }
        let elapsed = recording ? time.seconds - (firstRecordedTime ?? time.seconds) : 0
        publish {
            if $0.frameSize != size { $0.frameSize = size }
            if let fps { $0.liveFPS = fps }
            if image != nil { $0.previewImage = image }
            if $0.phase == .tracking || $0.phase == .recording { $0.trackRect = reading?.rect ?? $0.trackRect; $0.trackScore = reading?.score ?? 0 }
            $0.trackingLost = lost
            if let reps { $0.liveReps = reps }
            if $0.phase == .recording { $0.elapsed = elapsed }
        }
    }

    private func publish(_ change: @escaping (VBTController) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            change(self)
        }
    }

    private func uiImage(from buffer: CVPixelBuffer) -> UIImage? {
        let ci = CIImage(cvPixelBuffer: buffer)
        guard let cg = ciContext.createCGImage(ci, from: ci.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    private static func copy(_ src: CVPixelBuffer) -> CVPixelBuffer? {
        var dst: CVPixelBuffer?
        let w = CVPixelBufferGetWidth(src), h = CVPixelBufferGetHeight(src)
        guard CVPixelBufferCreate(nil, w, h, CVPixelBufferGetPixelFormatType(src), nil, &dst) == kCVReturnSuccess, let dst else { return nil }
        CVPixelBufferLockBaseAddress(src, .readOnly)
        CVPixelBufferLockBaseAddress(dst, [])
        defer {
            CVPixelBufferUnlockBaseAddress(dst, [])
            CVPixelBufferUnlockBaseAddress(src, .readOnly)
        }
        if CVPixelBufferIsPlanar(src) {
            for plane in 0..<CVPixelBufferGetPlaneCount(src) {
                guard let s = CVPixelBufferGetBaseAddressOfPlane(src, plane), let d = CVPixelBufferGetBaseAddressOfPlane(dst, plane) else { continue }
                let rows = CVPixelBufferGetHeightOfPlane(src, plane)
                let sStride = CVPixelBufferGetBytesPerRowOfPlane(src, plane), dStride = CVPixelBufferGetBytesPerRowOfPlane(dst, plane)
                for r in 0..<rows { memcpy(d + r * dStride, s + r * sStride, min(sStride, dStride)) }
            }
        } else if let s = CVPixelBufferGetBaseAddress(src), let d = CVPixelBufferGetBaseAddress(dst) {
            let sStride = CVPixelBufferGetBytesPerRow(src), dStride = CVPixelBufferGetBytesPerRow(dst)
            for r in 0..<h { memcpy(d + r * dStride, s + r * sStride, min(sStride, dStride)) }
        }
        return dst
    }

    // MARK: - Simulator source

    #if targetEnvironment(simulator)
    private func startSynthetic() {
        let source = VBTSyntheticSource { [weak self] buffer, time, image in
            self?.handle(buffer, time: time, previewImage: image)
        }
        synthetic = source
        publish { $0.formatDescription = "Simulated 720×1280 @ 60 fps"; $0.cameraMessage = nil }
        source.start(on: queue)
    }
    #endif
}
