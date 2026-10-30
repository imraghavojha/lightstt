import Foundation

public struct RecordingSegment: Codable, Hashable, Sendable {
    public let start: Double
    public let end: Double

    public init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }
}

public enum AudioProcessing {
    public static func recordingError(samples: [Float], duration: TimeInterval, pushToTalk: Bool)
        -> String?
    {
        if samples.isEmpty {
            return "Microphone delivered no audio. Check the selected input and microphone access."
        }
        if samples.allSatisfy({ $0 == 0 }) {
            return "Microphone input is silent: check the selected mic / input volume."
        }
        if duration < 0.5 {
            return pushToTalk
                ? "Recording was too short. Hold the push-to-talk shortcut while speaking."
                : "Recording was too short. Speak for at least half a second."
        }
        return nil
    }
    public static func waveform(_ samples: [Float], bins: Int = 48) -> [Float] {
        guard !samples.isEmpty, bins > 0 else {
            return []
        }
        return (0..<bins).map { bin in
            let start = bin * samples.count / bins
            let end = max(start + 1, (bin + 1) * samples.count / bins)
            guard start < samples.count else {
                return 0
            }
            let slice = samples[start..<min(end, samples.count)]
            return min(1, sqrt(slice.reduce(Float.zero) { $0 + $1 * $1 } / Float(slice.count)) * 8)
        }
    }
    public static func speechSegments(_ samples: [Float]) -> [RecordingSegment] {
        let frameSize = 320
        guard !samples.isEmpty else {
            return []
        }
        let count = (samples.count + frameSize - 1) / frameSize
        var kept = [Bool](repeating: false, count: count)
        for frame in 0..<count {
            let start = frame * frameSize
            let end = min(start + frameSize, samples.count)
            let energy =
                samples[start..<end].reduce(Float.zero) { $0 + $1 * $1 } / Float(end - start)
            if energy > 0.0001 {
                for index in max(0, frame - 10)...min(count - 1, frame + 10) {
                    kept[index] = true
                }
            }
        }
        var ranges: [RecordingSegment] = []
        var start: Int?
        for frame in 0...count {
            let active = frame < count && kept[frame]
            if active && start == nil {
                start = frame
            }
            if !active, let first = start {
                ranges.append(
                    RecordingSegment(
                        start: Double(first * frameSize) / 16000,
                        end: Double(min(frame * frameSize, samples.count)) / 16000))
                start = nil
            }
        }
        return ranges
    }
    public static func apply(_ samples: [Float], removeSilence: Bool, normalize: Bool) -> [Float] {
        guard !samples.isEmpty else {
            return samples
        }
        var result = samples
        if removeSilence {
            let frameSize = 320  // 20 ms at 16 kHz
            let count = (samples.count + frameSize - 1) / frameSize
            var voiced = [Bool](repeating: false, count: count)
            for frame in 0..<count {
                let start = frame * frameSize
                let end = min(start + frameSize, samples.count)
                let energy =
                    samples[start..<end].reduce(Float.zero) { $0 + $1 * $1 } / Float(end - start)
                if energy > 0.0001 {
                    voiced[frame] = true
                }
            }
            var kept = [Bool](repeating: false, count: count)
            for index in voiced.indices where voiced[index] {
                for nearby in max(0, index - 10)...min(count - 1, index + 10) {
                    kept[nearby] = true
                }
            }
            result = []
            for index in kept.indices where kept[index] {
                let start = index * frameSize
                result.append(contentsOf: samples[start..<min(start + frameSize, samples.count)])
            }
        }
        if normalize && !result.isEmpty {
            let frameSize = 16_000
            for start in stride(from: 0, to: result.count, by: frameSize) {
                let end = min(start + frameSize, result.count)
                let rms = sqrt(
                    result[start..<end].reduce(Float.zero) { $0 + $1 * $1 } / Float(end - start))
                let gain = min(4, 0.12 / max(rms, 0.01))
                for index in start..<end {
                    result[index] = max(-1, min(1, result[index] * gain))
                }
            }
        }
        return result
    }
}
