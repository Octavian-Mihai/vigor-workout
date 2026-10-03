import AVFoundation
import Charts
import SwiftUI

/// Where a portrait frame lands inside a container when shown aspect-fit.
private struct FrameFit {
    let frame: CGSize
    let container: CGSize

    var rect: CGRect {
        guard frame.width > 0, frame.height > 0 else { return CGRect(origin: .zero, size: container) }
        let s = min(container.width / frame.width, container.height / frame.height)
        let size = CGSize(width: frame.width * s, height: frame.height * s)
        return CGRect(x: (container.width - size.width) / 2, y: (container.height - size.height) / 2, width: size.width, height: size.height)
    }

    func viewRect(fromNormalized n: CGRect) -> CGRect {
        let r = rect
        return CGRect(x: r.minX + n.minX * r.width, y: r.minY + n.minY * r.height, width: n.width * r.width, height: n.height * r.height)
    }
}

struct VBTCaptureView: View {
    let lift: VBTLift
    @StateObject private var controller: VBTController
    @Environment(\.dismiss) private var dismiss

    init(lift: VBTLift) {
        self.lift = lift
        _controller = StateObject(wrappedValue: VBTController(lift: lift))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch controller.phase {
            case .calibrating:
                if let image = controller.frozen {
                    VBTCalibrationView(
                        image: image,
                        onConfirm: { p1, p2, ref in controller.confirmCalibration(p1: p1, p2: p2, reference: ref) },
                        onCancel: { controller.cancelCalibration() }
                    )
                }
            case .finished:
                if let result = controller.result {
                    VBTResultView(
                        result: result,
                        onAnother: { controller.newSet() },
                        onRecalibrate: { controller.recalibrate() },
                        onDone: { dismiss() }
                    )
                }
            default:
                liveLayer
            }
        }
        .statusBarHidden(controller.phase == .calibrating)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            controller.start()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            controller.stop()
        }
    }

    // MARK: Live preview + controls

    private var liveLayer: some View {
        VStack(spacing: 0) {
            topBar
            GeometryReader { geo in
                ZStack {
                    #if targetEnvironment(simulator)
                    if let img = controller.previewImage {
                        Image(uiImage: img).resizable().scaledToFit().frame(width: geo.size.width, height: geo.size.height)
                    }
                    #else
                    VBTPreviewLayerView(session: controller.session)
                    #endif
                    if let rect = controller.trackRect, controller.phase == .tracking || controller.phase == .recording {
                        let fit = FrameFit(frame: controller.frameSize, container: geo.size)
                        let r = fit.viewRect(fromNormalized: rect)
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(controller.trackingLost ? Color.red : Color.green, lineWidth: 2)
                            .frame(width: r.width, height: r.height)
                            .position(x: r.midX, y: r.midY)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .clipped()
            bottomPanel
        }
    }

    private var topBar: some View {
        HStack(alignment: .top) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.headline).foregroundStyle(.white)
                    .frame(width: 40, height: 40).background(.white.opacity(0.18), in: Circle())
            }
            .accessibilityLabel("Close VBT")
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(lift.title) · VBT").font(.subheadline.weight(.semibold))
                if !controller.formatDescription.isEmpty {
                    Text(controller.formatDescription).font(.caption2)
                }
                if controller.liveFPS > 0 {
                    Text(String(format: "%.0f fps processed", controller.liveFPS)).font(.caption2)
                }
            }
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    @ViewBuilder
    private var bottomPanel: some View {
        VStack(spacing: 12) {
            if let message = controller.cameraMessage {
                Text(message).font(.footnote).foregroundStyle(.white).multilineTextAlignment(.center)
            }
            switch controller.phase {
            case .preview:
                Text("Tripod side-on, ~2 m away, at bar height. Keep the barbell sleeve in frame and the bar still, then calibrate.")
                    .font(.footnote).foregroundStyle(.white).multilineTextAlignment(.center)
                Picker("Frame rate", selection: Binding(get: { controller.targetFPS }, set: { controller.setTargetFPS($0) })) {
                    Text("60").tag(60); Text("120").tag(120); Text("240").tag(240)
                }
                .pickerStyle(.segmented)
                .environment(\.colorScheme, .dark)
                primaryButton("Calibrate", icon: "scope") { controller.beginCalibration() }
            case .tracking:
                if let note = controller.calibrationNote {
                    Text("Calibrated: \(note)").font(.caption).foregroundStyle(.white.opacity(0.8))
                }
                statusLine
                primaryButton("Start set", icon: "record.circle") { controller.startSet() }
                Button("Recalibrate") { controller.recalibrate() }.font(.footnote).foregroundStyle(.white.opacity(0.8))
            case .recording:
                recordingStats
                primaryButton("Finish set", icon: "stop.circle") { controller.finishSet() }
            default:
                EmptyView()
            }
        }
        .padding(16)
    }

    private var statusLine: some View {
        HStack(spacing: 6) {
            Circle().fill(controller.trackingLost ? .red : .green).frame(width: 8, height: 8)
            Text(controller.trackingLost ? "Tracking lost: re-center the sleeve" : String(format: "Tracking · match %.0f%%", controller.trackScore * 100))
                .font(.caption).foregroundStyle(.white)
        }
    }

    private var recordingStats: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                stat("Reps", "\(controller.liveReps.count)")
                stat("Last MCV", controller.liveReps.last.map { String(format: "%.2f", $0.meanVelocity) } ?? "–", unit: "m/s")
                stat("Loss", controller.liveReps.last.map { String(format: "%.0f", $0.velocityLoss * 100) } ?? "–", unit: "%")
                stat("Time", String(format: "%.0f", controller.elapsed), unit: "s")
            }
            statusLine
        }
    }

    private func stat(_ title: String, _ value: String, unit: String = "") -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.white.opacity(0.7))
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.title2.weight(.bold).monospacedDigit()).foregroundStyle(.white)
                if !unit.isEmpty { Text(unit).font(.caption2).foregroundStyle(.white.opacity(0.7)) }
            }
        }
    }

    private func primaryButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Preview layer

struct VBTPreviewLayerView: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        // Aspect-fit so the on-screen frame matches the buffer the tracker sees (overlay math relies on it).
        view.previewLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

// MARK: - Calibration

struct VBTCalibrationView: View {
    let image: UIImage
    let onConfirm: (CGPoint, CGPoint, BarCalibration.Reference) -> Void
    let onCancel: () -> Void

    @State private var points: [CGPoint] = []
    @State private var reference: BarCalibration.Reference = .sleeve
    @State private var resetCount = 0

    private var rough: Double? {
        guard points.count == 2 else { return nil }
        return hypot((points[0].x - points[1].x) * image.size.width, (points[0].y - points[1].y) * image.size.height)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZoomableFramePicker(image: image, points: $points, resetCount: resetCount)
            controls
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Text(points.isEmpty ? "Pinch to zoom on the sleeve, then tap its top edge and bottom edge."
                 : points.count == 1 ? "Now tap the opposite edge of the sleeve."
                 : String(format: "%.1f px = %.0f mm. Edges will be snapped automatically.", rough ?? 0, reference.meters * 1000))
                .font(.footnote).foregroundStyle(.white).multilineTextAlignment(.center)
                .frame(minHeight: 36) // fixed height so the picker doesn't jump as the hint changes
            Picker("Reference", selection: $reference) {
                ForEach(BarCalibration.Reference.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .environment(\.colorScheme, .dark)
            if reference == .plate {
                Text("For a plate, tap the top and bottom of the plate's outer edge.").font(.caption2).foregroundStyle(.white.opacity(0.7))
            }
            HStack(spacing: 10) {
                Button("Cancel", action: onCancel)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(.white)
                Button("Reset") { points = []; resetCount += 1 }
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(.white)
                Button("Confirm") {
                    if points.count == 2 { onConfirm(points[0], points[1], reference) }
                }
                .disabled(points.count < 2)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(points.count == 2 ? Color.accentColor : .gray.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(16)
        .background(.black)
    }
}

/// Pinch-to-zoom image with tap-to-place points, on a native scroll view. UIKit's recognisers keep
/// the pinch anchored under the fingers and report taps in content coordinates, which matters when
/// the job is placing two points to a fraction of a pixel.
struct ZoomableFramePicker: UIViewRepresentable {
    let image: UIImage
    @Binding var points: [CGPoint]
    let resetCount: Int

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PickerView {
        let view = PickerView(image: image)
        view.onTap = { context.coordinator.add($0) }
        return view
    }

    func updateUIView(_ view: PickerView, context: Context) {
        context.coordinator.parent = self
        view.points = points
        if context.coordinator.lastReset != resetCount {
            context.coordinator.lastReset = resetCount
            view.resetZoom()
        }
    }

    final class Coordinator {
        var parent: ZoomableFramePicker
        var lastReset: Int
        init(_ parent: ZoomableFramePicker) { self.parent = parent; lastReset = parent.resetCount }

        func add(_ p: CGPoint) {
            if parent.points.count >= 2 { parent.points = [] }
            parent.points.append(p)
        }
    }

    final class PickerView: UIView, UIScrollViewDelegate {
        private let scroll = UIScrollView()
        private let content = UIView()
        private let imageView: UIImageView
        private let markers = CAShapeLayer()
        private var imageFrame: CGRect = .zero
        var onTap: ((CGPoint) -> Void)?
        var points: [CGPoint] = [] { didSet { updateMarkers() } }

        init(image: UIImage) {
            imageView = UIImageView(image: image)
            super.init(frame: .zero)
            backgroundColor = .black
            scroll.delegate = self
            scroll.minimumZoomScale = 1
            scroll.maximumZoomScale = 16
            scroll.showsHorizontalScrollIndicator = false
            scroll.showsVerticalScrollIndicator = false
            scroll.bouncesZoom = true
            addSubview(scroll)
            scroll.addSubview(content)
            content.addSubview(imageView)
            markers.fillColor = nil
            markers.strokeColor = UIColor.systemYellow.cgColor
            content.layer.addSublayer(markers)
            content.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
        }

        required init?(coder: NSCoder) { fatalError() }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard scroll.zoomScale == 1 else { return }
            scroll.frame = bounds
            content.frame = bounds
            scroll.contentSize = bounds.size
            let s = min(bounds.width / imageView.image!.size.width, bounds.height / imageView.image!.size.height)
            let size = CGSize(width: imageView.image!.size.width * s, height: imageView.image!.size.height * s)
            imageFrame = CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
            imageView.frame = imageFrame
            updateMarkers()
        }

        func resetZoom() { scroll.setZoomScale(1, animated: true) }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { content }
        func scrollViewDidZoom(_ scrollView: UIScrollView) { updateMarkers() }

        @objc private func tapped(_ g: UITapGestureRecognizer) {
            let p = g.location(in: content)
            guard imageFrame.contains(p) else { return }
            onTap?(CGPoint(x: (p.x - imageFrame.minX) / imageFrame.width, y: (p.y - imageFrame.minY) / imageFrame.height))
        }

        /// Thin horizontal ticks with a small ring: the sleeve edges we're hitting are horizontal lines.
        /// Sizes are divided by the zoom so the marker stays hairline-thin however far you zoom in.
        private func updateMarkers() {
            let z = max(scroll.zoomScale, 1)
            let path = UIBezierPath()
            for p in points {
                let c = CGPoint(x: imageFrame.minX + p.x * imageFrame.width, y: imageFrame.minY + p.y * imageFrame.height)
                path.move(to: CGPoint(x: c.x - 20 / z, y: c.y))
                path.addLine(to: CGPoint(x: c.x + 20 / z, y: c.y))
                path.append(UIBezierPath(arcCenter: c, radius: 4 / z, startAngle: 0, endAngle: .pi * 2, clockwise: true))
            }
            markers.lineWidth = 1 / z
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            markers.path = path.cgPath
            CATransaction.commit()
        }
    }
}

// MARK: - Results

struct VBTResultView: View {
    let result: VBTSetResult
    let onAnother: () -> Void
    let onRecalibrate: () -> Void
    let onDone: () -> Void

    private var meanMCV: Double? {
        result.reps.isEmpty ? nil : result.reps.map(\.meanVelocity).reduce(0, +) / Double(result.reps.count)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summary
                    if result.reps.isEmpty {
                        Text("No reps detected. Check that the sleeve stayed in frame and the tracking box stayed green.")
                            .font(.subheadline).foregroundStyle(.orange)
                    }
                    chart
                    repTable
                    diagnostics
                    Text("Prototype: this set is not saved to your workout yet.")
                        .font(.caption).foregroundStyle(.secondary)
                    VStack(spacing: 10) {
                        Button(action: onAnother) {
                            Text("Record another set").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(.white)
                        }
                        Button("Recalibrate", action: onRecalibrate)
                    }
                }
                .padding(16)
            }
            .background(Color(.systemBackground))
            .navigationTitle("\(result.lift.title) set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", action: onDone) } }
        }
        .environment(\.colorScheme, .dark)
    }

    private var summary: some View {
        HStack(spacing: 0) {
            tile("Reps", "\(result.reps.count)")
            tile("Avg MCV", meanMCV.map { String(format: "%.2f m/s", $0) } ?? "–")
            tile("Best", result.reps.map(\.meanVelocity).max().map { String(format: "%.2f m/s", $0) } ?? "–")
            tile("Loss", result.reps.last.map { String(format: "%.0f%%", $0.velocityLoss * 100) } ?? "–")
        }
    }

    private func tile(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title3.weight(.bold).monospacedDigit()).minimumScaleFactor(0.7).lineLimit(1)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Bar path").font(.subheadline.weight(.semibold))
            Chart {
                ForEach(result.reps) { rep in
                    RectangleMark(xStart: .value("Start", rep.startTime), xEnd: .value("End", rep.endTime))
                        .foregroundStyle(Color.accentColor.opacity(0.18))
                }
                ForEach(Array(result.path.enumerated()), id: \.offset) { _, s in
                    LineMark(x: .value("Time", s.t), y: .value("Height", s.y))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .chartXAxisLabel("seconds")
            .chartYAxisLabel("metres")
            .frame(height: 180)
        }
    }

    private var repTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reps").font(.subheadline.weight(.semibold))
            ForEach(result.reps) { rep in
                HStack {
                    Text("\(rep.id)").font(.subheadline.weight(.semibold)).frame(width: 24, alignment: .leading)
                    Text(String(format: "%.2f m/s", rep.meanVelocity)).font(.subheadline.monospacedDigit())
                    Spacer()
                    Text(String(format: "peak %.2f · %.0f cm · %.1f s", rep.peakVelocity, rep.rom * 100, rep.duration))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Text(rep.velocityLoss < 0.005 ? "–" : String(format: "-%.0f%%", rep.velocityLoss * 100))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(rep.velocityLoss > 0.2 ? .orange : .secondary)
                        .frame(width: 44, alignment: .trailing)
                }
            }
        }
    }

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tracking quality").font(.subheadline.weight(.semibold))
            Text(String(format: "%d of %d frames tracked (%.0f%%) · %.0f samples/s · %.1f s",
                        result.trackedFrames, result.totalFrames, result.trackedFraction * 100, result.averageFPS, result.duration))
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}
