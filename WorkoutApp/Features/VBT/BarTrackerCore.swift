import Accelerate
import CoreGraphics
import CoreMedia
import CoreVideo

/// What the user told us about the scene: two points spanning a known real-world length, e.g.
/// the 50 mm diameter of the barbell sleeve. Normalised coordinates, origin top-left, y down.
struct BarCalibration: Equatable {
    enum Reference: String, CaseIterable, Identifiable {
        case sleeve = "Sleeve (50 mm)"
        case plate = "45 lb / 20 kg plate (450 mm)"
        var id: String { rawValue }
        var meters: Double { self == .sleeve ? 0.050 : 0.450 }
    }

    var p1: CGPoint
    var p2: CGPoint
    var reference: Reference
    /// Size in pixels of the (portrait-rotated) frames the points were picked on.
    var frameSize: CGSize

    var pixelLength: Double {
        hypot((p2.x - p1.x) * frameSize.width, (p2.y - p1.y) * frameSize.height)
    }

    /// Metres represented by one pixel.
    var metersPerPixel: Double { pixelLength > 0 ? reference.meters / pixelLength : 0 }

    /// Centre of the tracked patch, in pixels (origin top-left).
    var centerPx: CGPoint {
        CGPoint(
            x: (p1.x + p2.x) / 2 * frameSize.width,
            y: (p1.y + p2.y) / 2 * frameSize.height
        )
    }

    /// Template size in pixels, multiples of 4. A wide, short strip: the sleeve's horizontal
    /// edges pin down vertical position (the axis we measure), and the collar/plate edge at the
    /// end of the strip keeps horizontal drift from dragging the match off the bar.
    var templateSize: (w: Int, h: Int) {
        let pl = max(8, pixelLength)
        let scale = reference == .sleeve ? 1.0 : 0.25
        func round4(_ v: Double) -> Int { max(16, Int((v / 4).rounded()) * 4) }
        return (round4(min(6 * pl * scale, 240)), round4(min(2.2 * pl * scale, 96)))
    }
}

struct TrackerReading {
    var time: Double
    /// Bar height in metres relative to the calibration point, up = positive.
    var y: Double
    /// Tracked patch, normalised, origin top-left.
    var rect: CGRect
    /// Zero-mean normalised cross-correlation of the best match, 0...1.
    var score: Float
}

/// Fixed-template ZNCC tracker with coarse-to-fine search and sub-pixel refinement.
/// Pure CoreVideo/Accelerate (no AVFoundation, no UIKit) so it can be driven from synthetic
/// frames in tests. Not thread-safe: feed it from one queue.
final class BarTrackerCore {
    private let calibration: BarCalibration
    private let tw: Int
    private let th: Int
    private let searchRadius: Int
    private var template: [Float] = []      // zero-mean, full resolution
    private var templateNorm: Float = 0
    private var templateHalf: [Float] = []  // zero-mean, half resolution
    private var templateHalfNorm: Float = 0
    private var center: CGPoint
    private var previous: CGPoint?
    private let originY: Double

    /// Below this the match is unreliable; the frame is dropped from the sample stream.
    static let minimumScore: Float = 0.55

    init(calibration: BarCalibration, searchRadius: Int = 28) {
        self.calibration = calibration
        let size = calibration.templateSize
        self.tw = size.w
        self.th = size.h
        self.searchRadius = searchRadius & ~1
        self.center = calibration.centerPx
        self.originY = Double(calibration.centerPx.y)
    }

    func process(_ buffer: CVPixelBuffer, at time: CMTime) -> TrackerReading? {
        let bw = CVPixelBufferGetWidth(buffer)
        let bh = CVPixelBufferGetHeight(buffer)
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        if template.isEmpty {
            let x0 = Int(center.x.rounded()) - tw / 2
            let y0 = Int(center.y.rounded()) - th / 2
            guard x0 >= 0, y0 >= 0, x0 + tw <= bw, y0 + th <= bh else { return nil }
            setTemplate(luma(buffer, x: x0, y: y0, w: tw, h: th))
        }

        // Constant-velocity prediction keeps the search window centred on fast reps.
        var predicted = center
        if let previous { predicted = CGPoint(x: center.x + (center.x - previous.x), y: center.y + (center.y - previous.y)) }
        let r = searchRadius
        let rx0 = Int(predicted.x.rounded()) - tw / 2 - r
        let ry0 = Int(predicted.y.rounded()) - th / 2 - r
        let rw = tw + 2 * r
        let rh = th + 2 * r
        guard rx0 >= 0, ry0 >= 0, rx0 + rw <= bw, ry0 + rh <= bh else { return nil }

        let region = luma(buffer, x: rx0, y: ry0, w: rw, h: rh)

        // Coarse: half resolution over the whole window.
        let regionHalf = downsample(region, w: rw, h: rh)
        let (hw, hh) = (rw / 2, rh / 2)
        let (thw, thh) = (tw / 2, th / 2)
        var bestScore: Float = -1
        var bestDX = 0, bestDY = 0
        let integral = Integral(regionHalf, w: hw, h: hh)
        for dy in 0...(hh - thh) {
            for dx in 0...(hw - thw) {
                let s = integral.zncc(
                    image: regionHalf, imageWidth: hw, template: templateHalf, templateNorm: templateHalfNorm,
                    tw: thw, th: thh, ox: dx, oy: dy
                )
                if s > bestScore { bestScore = s; bestDX = dx; bestDY = dy }
            }
        }

        // Fine: ±2 px at full resolution around the coarse winner.
        let fineIntegral = Integral(region, w: rw, h: rh)
        let fx = bestDX * 2, fy = bestDY * 2
        var scores = [[Float]](repeating: [Float](repeating: -1, count: 5), count: 5)
        var best: Float = -1
        var bi = 2, bj = 2
        for j in 0..<5 {
            for i in 0..<5 {
                let ox = fx + i - 2, oy = fy + j - 2
                guard ox >= 0, oy >= 0, ox + tw <= rw, oy + th <= rh else { continue }
                let s = fineIntegral.zncc(
                    image: region, imageWidth: rw, template: template, templateNorm: templateNorm,
                    tw: tw, th: th, ox: ox, oy: oy
                )
                scores[j][i] = s
                if s > best { best = s; bi = i; bj = j }
            }
        }
        guard best >= Self.minimumScore else { return nil }

        // Parabolic sub-pixel peak on the winning row/column.
        func peak(_ a: Float, _ b: Float, _ c: Float) -> Double {
            let d = a - 2 * b + c
            return d < -1e-6 ? Double(0.5 * (a - c) / d) : 0
        }
        var subX = 0.0, subY = 0.0
        if bi > 0, bi < 4, scores[bj][bi - 1] > -1, scores[bj][bi + 1] > -1 {
            subX = peak(scores[bj][bi - 1], best, scores[bj][bi + 1])
        }
        if bj > 0, bj < 4, scores[bj - 1][bi] > -1, scores[bj + 1][bi] > -1 {
            subY = peak(scores[bj - 1][bi], best, scores[bj + 1][bi])
        }
        let ox = Double(fx + bi - 2) + subX
        let oy = Double(fy + bj - 2) + subY
        let found = CGPoint(
            x: Double(rx0) + ox + Double(tw) / 2,
            y: Double(ry0) + oy + Double(th) / 2
        )
        previous = center
        center = found

        let y = -(Double(found.y) - originY) * calibration.metersPerPixel
        let rect = CGRect(
            x: (Double(found.x) - Double(tw) / 2) / Double(bw),
            y: (Double(found.y) - Double(th) / 2) / Double(bh),
            width: Double(tw) / Double(bw), height: Double(th) / Double(bh)
        )
        return TrackerReading(time: time.seconds, y: y, rect: rect, score: best)
    }

    // MARK: - Helpers

    private func setTemplate(_ patch: [Float]) {
        template = zeroMean(patch)
        templateNorm = norm(template)
        templateHalf = zeroMean(downsample(patch, w: tw, h: th))
        templateHalfNorm = norm(templateHalf)
    }

    private func zeroMean(_ a: [Float]) -> [Float] {
        var mean: Float = 0
        vDSP_meanv(a, 1, &mean, vDSP_Length(a.count))
        var m = -mean
        var out = [Float](repeating: 0, count: a.count)
        vDSP_vsadd(a, 1, &m, &out, 1, vDSP_Length(a.count))
        return out
    }

    private func norm(_ a: [Float]) -> Float {
        var s: Float = 0
        vDSP_svesq(a, 1, &s, vDSP_Length(a.count))
        return s.squareRoot()
    }

    private func downsample(_ a: [Float], w: Int, h: Int) -> [Float] {
        let ow = w / 2, oh = h / 2
        var out = [Float](repeating: 0, count: ow * oh)
        for y in 0..<oh {
            for x in 0..<ow {
                let i = 2 * y * w + 2 * x
                out[y * ow + x] = (a[i] + a[i + 1] + a[i + w] + a[i + w + 1]) * 0.25
            }
        }
        return out
    }

    /// Luma for a rectangle that is fully inside the buffer. Camera frames are NV12 (Y plane is
    /// luma already); BGRA is supported for tests and simulator fallbacks.
    private func luma(_ buffer: CVPixelBuffer, x: Int, y: Int, w: Int, h: Int) -> [Float] {
        var out = [Float](repeating: 0, count: w * h)
        if CVPixelBufferIsPlanar(buffer) {
            guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return out }
            let stride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
            for row in 0..<h {
                let src = base.advanced(by: (y + row) * stride + x).assumingMemoryBound(to: UInt8.self)
                for col in 0..<w { out[row * w + col] = Float(src[col]) }
            }
        } else if let base = CVPixelBufferGetBaseAddress(buffer) {
            let stride = CVPixelBufferGetBytesPerRow(buffer)
            for row in 0..<h {
                let src = base.advanced(by: (y + row) * stride + x * 4).assumingMemoryBound(to: UInt8.self)
                for col in 0..<w {
                    let p = src.advanced(by: col * 4) // BGRA
                    out[row * w + col] = 0.114 * Float(p[0]) + 0.587 * Float(p[1]) + 0.299 * Float(p[2])
                }
            }
        }
        return out
    }
}

/// Summed-area tables so each ZNCC denominator costs O(1); the numerator is one vectorised
/// dot product per template row.
private struct Integral {
    let w: Int
    var sum: [Double]
    var sumSq: [Double]

    init(_ image: [Float], w: Int, h: Int) {
        self.w = w
        let stride = w + 1
        sum = [Double](repeating: 0, count: stride * (h + 1))
        sumSq = sum
        for y in 0..<h {
            var rowSum = 0.0, rowSq = 0.0
            for x in 0..<w {
                let v = Double(image[y * w + x])
                rowSum += v
                rowSq += v * v
                sum[(y + 1) * stride + x + 1] = sum[y * stride + x + 1] + rowSum
                sumSq[(y + 1) * stride + x + 1] = sumSq[y * stride + x + 1] + rowSq
            }
        }
    }

    private func rect(_ table: [Double], _ x: Int, _ y: Int, _ rw: Int, _ rh: Int) -> Double {
        let s = w + 1
        return table[(y + rh) * s + x + rw] - table[y * s + x + rw] - table[(y + rh) * s + x] + table[y * s + x]
    }

    func zncc(image: [Float], imageWidth: Int, template: [Float], templateNorm: Float, tw: Int, th: Int, ox: Int, oy: Int) -> Float {
        var num: Float = 0
        image.withUnsafeBufferPointer { img in
            template.withUnsafeBufferPointer { tpl in
                for row in 0..<th {
                    var d: Float = 0
                    vDSP_dotpr(img.baseAddress! + (oy + row) * imageWidth + ox, 1, tpl.baseAddress! + row * tw, 1, &d, vDSP_Length(tw))
                    num += d
                }
            }
        }
        let n = Double(tw * th)
        let s = rect(sum, ox, oy, tw, th)
        let variance = rect(sumSq, ox, oy, tw, th) - s * s / n
        guard variance > 1e-3, templateNorm > 0 else { return -1 }
        return num / (Float(variance.squareRoot()) * templateNorm)
    }
}

// MARK: - Calibration edge snapping

extension BarCalibration {
    /// Moves each tapped point vertically onto the nearest strong horizontal edge (the sleeve's
    /// top and bottom), to sub-pixel precision. A finger tap is good to ~2–3 px; on a ~35 px
    /// sleeve that alone would be a 6–8 % scale error, so this matters more than any filtering.
    /// Returns nil if no clear edge is found near either point (keeps the user's taps).
    func snappedToEdges(in buffer: CVPixelBuffer, searchPx: Int = 6, columns: Int = 24) -> BarCalibration? {
        let bw = CVPixelBufferGetWidth(buffer), bh = CVPixelBufferGetHeight(buffer)
        guard frameSize.width == CGFloat(bw), frameSize.height == CGFloat(bh) else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard CVPixelBufferIsPlanar(buffer), let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return nil }
        let stride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let ptr = base.assumingMemoryBound(to: UInt8.self)

        func snap(_ p: CGPoint) -> Double? {
            let cx = Int((p.x * CGFloat(bw)).rounded()), cy = Int((p.y * CGFloat(bh)).rounded())
            let x0 = cx - columns / 2, x1 = cx + columns / 2
            guard x0 >= 0, x1 < bw, cy - searchPx - 2 >= 0, cy + searchPx + 2 < bh else { return nil }
            // Row-mean luma, then central-difference gradient.
            func rowMean(_ y: Int) -> Double {
                var s = 0
                for x in x0..<x1 { s += Int(ptr[y * stride + x]) }
                return Double(s) / Double(x1 - x0)
            }
            var grad: [Double] = []
            for dy in -searchPx...searchPx { grad.append(abs(rowMean(cy + dy + 1) - rowMean(cy + dy - 1)) / 2) }
            guard let k = grad.indices.max(by: { grad[$0] < grad[$1] }), grad[k] > 4 else { return nil }
            var sub = 0.0
            if k > 0, k < grad.count - 1 {
                let d = grad[k - 1] - 2 * grad[k] + grad[k + 1]
                if d < -1e-6 { sub = 0.5 * (grad[k - 1] - grad[k + 1]) / d }
            }
            return Double(cy + k - searchPx) + sub
        }

        guard let y1 = snap(p1), let y2 = snap(p2) else { return nil }
        var out = self
        out.p1 = CGPoint(x: p1.x, y: CGFloat(y1) / CGFloat(bh))
        out.p2 = CGPoint(x: p2.x, y: CGFloat(y2) / CGFloat(bh))
        return out
    }
}
