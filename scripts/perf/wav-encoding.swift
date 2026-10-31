import Foundation

// Baseline from AppController at 3e80109, retained for byte-for-byte comparison.
func baseline(_ samples: [Float]) -> Data {
    var result = Data()
    func append<T: FixedWidthInteger>(_ value: T) {
        var value = value.littleEndian
        withUnsafeBytes(of: &value) { result.append(contentsOf: $0) }
    }
    let size = UInt32(samples.count * MemoryLayout<Float>.size)
    result.append(contentsOf: "RIFF".utf8)
    append(size + 36)
    result.append(contentsOf: "WAVEfmt ".utf8)
    append(UInt32(16))
    append(UInt16(3))
    append(UInt16(1))
    append(UInt32(16000))
    append(UInt32(64000))
    append(UInt16(4))
    append(UInt16(32))
    result.append(contentsOf: "data".utf8)
    append(size)
    for sample in samples { append(sample.bitPattern) }
    return result
}

@main struct Benchmark {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("Pass a 16 kHz mono signed 16-bit WAV fixture")
        }
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        // afconvert-produced PCM WAV; AVFoundation handles additional WAV chunks.
        let file = try AVAudioFile(forReading: url)
        guard file.fileFormat.sampleRate == 16000, file.fileFormat.channelCount == 1 else {
            fatalError("Expected 16 kHz mono")
        }
        let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        let samples = Array(
            UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
        precondition(baseline(samples) == RecordingWAV.encode(samples))
        for (name, encode) in [("baseline", baseline), ("optimized", RecordingWAV.encode)] {
            var durations: [Double] = []
            for _ in 0..<101 {
                let start = DispatchTime.now().uptimeNanoseconds
                let output = encode(samples)
                let end = DispatchTime.now().uptimeNanoseconds
                precondition(output.count == 44 + samples.count * 4)
                durations.append(Double(end - start) / 1_000_000)
            }
            durations.sort()
            print(
                "\(name) median_ms=\(durations[50]) p95_ms=\(durations[95]) samples=\(samples.count)"
            )
        }
    }
}
import AVFoundation
