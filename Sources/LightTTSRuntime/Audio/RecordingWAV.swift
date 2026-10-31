import Foundation

/// Serializes captured 16 kHz mono Float32 samples as a little-endian IEEE float WAV.
public enum RecordingWAV {
    public static func encode(_ samples: [Float]) -> Data {
        var result = Data()
        let size = UInt32(samples.count * MemoryLayout<Float>.size)
        result.reserveCapacity(Int(size) + 44)
        func append<T: FixedWidthInteger>(_ value: T) {
            var value = value.littleEndian
            withUnsafeBytes(of: &value) { result.append(contentsOf: $0) }
        }
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
        #if _endian(little)
            samples.withUnsafeBytes { result.append(contentsOf: $0) }
        #else
            for sample in samples { append(sample.bitPattern) }
        #endif
        return result
    }
}
