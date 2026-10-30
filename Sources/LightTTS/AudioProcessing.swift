import Foundation

enum AudioProcessing {
    static func apply(_ samples: [Float], removeSilence: Bool, normalize: Bool) -> [Float] {
        guard !samples.isEmpty else { return samples }
        var result = samples
        if removeSilence {
            let frameSize = 320 // 20 ms at 16 kHz
            let count = (samples.count + frameSize - 1) / frameSize
            var voiced = [Bool](repeating: false, count: count)
            for frame in 0..<count {
                let start = frame * frameSize, end = min(start + frameSize, samples.count)
                let energy = samples[start..<end].reduce(Float.zero) { $0 + $1 * $1 } / Float(end - start)
                if energy > 0.0001 { voiced[frame] = true }
            }
            var kept = [Bool](repeating: false, count: count)
            for index in voiced.indices where voiced[index] {
                for nearby in max(0, index - 10)...min(count - 1, index + 10) { kept[nearby] = true }
            }
            result = []
            for index in kept.indices where kept[index] { let start = index * frameSize; result.append(contentsOf: samples[start..<min(start + frameSize, samples.count)]) }
        }
        if normalize && !result.isEmpty {
            let frameSize = 16_000
            for start in stride(from: 0, to: result.count, by: frameSize) {
                let end = min(start + frameSize, result.count)
                let rms = sqrt(result[start..<end].reduce(Float.zero) { $0 + $1 * $1 } / Float(end - start))
                let gain = min(4, 0.12 / max(rms, 0.01))
                for index in start..<end { result[index] = max(-1, min(1, result[index] * gain)) }
            }
        }
        return result
    }
}

/// One-pole stereo low-pass used by the system audio tap.
struct StereoLowPass {
    private var alpha: Float = 0.1
    private var left: Float = 0
    private var right: Float = 0
    mutating func prepare(sampleRate: Double) { alpha = Float(1 - exp(-2 * Double.pi * 700 / sampleRate)); left = 0; right = 0 }
    mutating func process(_ samples: UnsafeMutablePointer<Float>, frameCount: Int, channelCount: Int) {
        guard channelCount == 2 else { return }
        for frame in 0..<frameCount {
            let index = frame * 2
            left += alpha * (samples[index] - left); right += alpha * (samples[index + 1] - right)
            samples[index] = left * 0.3; samples[index + 1] = right * 0.3
        }
    }
}
