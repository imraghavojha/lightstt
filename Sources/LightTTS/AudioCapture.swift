import AVFoundation
import Foundation
import LightTTSCore
final class AudioCapture {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private var active = false
    private var usesTestFile = false
    private let onLevel: (Float) -> Void
    init(onLevel: @escaping (Float) -> Void) { self.onLevel = onLevel }
    func start() throws {
        if let path = ProcessInfo.processInfo.environment["LIGHTTTS_TEST_AUDIO"], !path.isEmpty {
            let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
            let format = file.processingFormat
            guard format.sampleRate == 16000, format.channelCount == 1, format.commonFormat == .pcmFormatFloat32 else {
                throw SpeechError.audio("Test audio must be a 16 kHz mono WAV file.")
            }
            usesTestFile = true
            lock.lock(); active = true; lock.unlock()
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                while let self {
                    self.lock.lock(); let running = self.active; self.lock.unlock()
                    guard running, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024) else { return }
                    do { try file.read(into: buffer, frameCount: 1024) } catch { return }
                    guard buffer.frameLength > 0, let data = buffer.floatChannelData?[0] else { return }
                    self.append(Array(UnsafeBufferPointer(start: data, count: Int(buffer.frameLength))))
                    Thread.sleep(forTimeInterval: Double(buffer.frameLength) / 16000)
                }
            }
            return
        }
        try InputDevice.applySelection(to: engine)
        let node = engine.inputNode; let format = node.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0, let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false), let converter = AVAudioConverter(from: format, to: target) else { throw SpeechError.audio("No microphone input available") }
        lock.lock(); active = true; lock.unlock()
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self, let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: AVAudioFrameCount(ceil(Double(buffer.frameLength) * 16000 / format.sampleRate)) + 32) else { return }
            var supplied = false; var error: NSError?
            converter.convert(to: output, error: &error) { _, status in if supplied { status.pointee = .noDataNow; return nil }; supplied = true; status.pointee = .haveData; return buffer }
            guard error == nil, let data = output.floatChannelData?[0] else { return }
            let chunk = Array(UnsafeBufferPointer(start: data, count: Int(output.frameLength)))
            self.append(chunk)
        }
        try engine.start()
    }
    private func append(_ chunk: [Float]) {
        lock.lock()
        guard active else { lock.unlock(); return }
        samples.append(contentsOf: chunk)
        lock.unlock()
        let rms = sqrt(chunk.reduce(Float(0)) { $0 + $1 * $1 } / Float(max(chunk.count, 1)))
        onLevel(min(1, rms * 8))
    }
    var isActive: Bool { lock.lock(); defer { lock.unlock() }; return active }
    func stop() -> [Float] {
        LaunchTrace.mark("capture-stop-start")
        lock.lock(); active = false; let result = samples; lock.unlock()
        if !usesTestFile { engine.inputNode.removeTap(onBus: 0); engine.stop() }
        LaunchTrace.mark("capture-stop-end")
        return result
    }
}
