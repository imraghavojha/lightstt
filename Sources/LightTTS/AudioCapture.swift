import AVFoundation
import Foundation
import LightTTSCore
final class AudioCapture {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private let onLevel: (Float) -> Void
    init(onLevel: @escaping (Float) -> Void) { self.onLevel = onLevel }
    func start() throws {
        try InputDevice.applySelection(to: engine)
        let node = engine.inputNode; let format = node.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0, let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false), let converter = AVAudioConverter(from: format, to: target) else { throw SpeechError.audio("No microphone input available") }
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self, let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: AVAudioFrameCount(ceil(Double(buffer.frameLength) * 16000 / format.sampleRate)) + 32) else { return }
            var supplied = false; var error: NSError?
            converter.convert(to: output, error: &error) { _, status in if supplied { status.pointee = .noDataNow; return nil }; supplied = true; status.pointee = .haveData; return buffer }
            guard error == nil, let data = output.floatChannelData?[0] else { return }
            let chunk = Array(UnsafeBufferPointer(start: data, count: Int(output.frameLength)))
            self.lock.lock(); self.samples.append(contentsOf: chunk); self.lock.unlock()
            let rms = sqrt(chunk.reduce(Float(0)) { $0 + $1 * $1 } / Float(max(chunk.count, 1))); self.onLevel(min(1, rms * 8))
        }
        try engine.start()
    }
    func stop() -> [Float] { engine.inputNode.removeTap(onBus: 0); engine.stop(); lock.lock(); defer { lock.unlock() }; return samples }
}
