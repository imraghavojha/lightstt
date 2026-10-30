import Foundation
import AVFoundation

public enum AudioFileReader {
    public static func read(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let input = file.processingFormat
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false), let converter = AVAudioConverter(from: input, to: target), let source = AVAudioPCMBuffer(pcmFormat: input, frameCapacity: AVAudioFrameCount(file.length)) else { throw SpeechError.audio("Unsupported audio file") }
        try file.read(into: source)
        let capacity = AVAudioFrameCount(ceil(Double(source.frameLength) * 16000 / input.sampleRate)) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { throw SpeechError.audio("Cannot allocate audio buffer") }
        var supplied = false; var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied { status.pointee = .endOfStream; return nil }
            supplied = true; status.pointee = .haveData; return source
        }
        if let error { throw error }
        guard let data = output.floatChannelData?[0] else { throw SpeechError.audio("Cannot read audio samples") }
        return Array(UnsafeBufferPointer(start: data, count: Int(output.frameLength)))
    }
}
