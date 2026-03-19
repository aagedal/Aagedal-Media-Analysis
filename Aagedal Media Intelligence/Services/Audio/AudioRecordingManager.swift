import Foundation
import Combine
import AVFoundation

enum RecordingState {
    case idle, starting, recording, paused
}

/// Manages audio recording using AVAudioEngine
class AudioRecordingManager: NSObject, ObservableObject {

    @Published var recordingState: RecordingState = .idle
    @Published var recordingTime: TimeInterval = 0.0
    @Published var currentFileURL: URL?
    @Published var error: Error?
    @Published var frequencyBands: [Float] = Array(repeating: 0, count: 9)

    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var timer: Timer?
    private var startTime: Date?
    private var accumulatedTime: TimeInterval = 0

    var isRecording: Bool { recordingState == .recording }

    func startRecording() {
        guard recordingState == .idle else { return }
        recordingState = .starting
        error = nil
        accumulatedTime = 0

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            let granted = await self.requestMicrophonePermission()
            guard granted else {
                await MainActor.run {
                    self.error = NSError(domain: "AudioRecording", code: 4, userInfo: [NSLocalizedDescriptionKey: "Microphone permission denied"])
                    self.recordingState = .idle
                }
                return
            }

            do {
                let recordingsDir = try self.getRecordingsDirectory()
                let filename = "recording_\(Self.dateFormatter.string(from: Date())).wav"
                let fileURL = recordingsDir.appendingPathComponent(filename)

                let engine = AVAudioEngine()
                let inputNode = engine.inputNode
                let inputFormat = inputNode.outputFormat(forBus: 0)

                let file = try AVAudioFile(forWriting: fileURL, settings: inputFormat.settings)

                inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
                    try? file.write(from: buffer)
                    let bands = Self.frequencyBands(from: buffer)
                    Task { @MainActor [weak self] in self?.frequencyBands = bands }
                }

                try engine.start()

                await MainActor.run {
                    self.audioEngine = engine
                    self.audioFile = file
                    self.currentFileURL = fileURL
                    self.recordingState = .recording
                    self.startTime = Date()
                    self.startTimer()
                }
            } catch {
                await MainActor.run {
                    self.error = error
                    self.recordingState = .idle
                }
            }
        }
    }

    func stopRecording() -> URL? {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioFile = nil
        stopTimer()
        frequencyBands = Array(repeating: 0, count: 9)
        recordingState = .idle
        accumulatedTime = 0
        return currentFileURL
    }

    func pauseRecording() {
        guard recordingState == .recording else { return }
        audioEngine?.pause()
        stopTimer()
        accumulatedTime = recordingTime
        recordingState = .paused
    }

    func resumeRecording() {
        guard recordingState == .paused else { return }
        try? audioEngine?.start()
        startTime = Date()
        startTimer()
        recordingState = .recording
    }

    // MARK: - Private Helpers

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func getRecordingsDirectory() throws -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Recordings")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return f
    }()

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.startTime else { return }
                self.recordingTime = self.accumulatedTime + Date().timeIntervalSince(start)
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    nonisolated static func frequencyBands(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else { return Array(repeating: 0, count: 9) }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return Array(repeating: 0, count: 9) }

        let bandCount = 9
        let framesPerBand = frameCount / bandCount
        var bands = [Float](repeating: 0, count: bandCount)

        for i in 0..<bandCount {
            var sum: Float = 0
            let start = i * framesPerBand
            let end = min(start + framesPerBand, frameCount)
            for j in start..<end {
                sum += abs(channelData[0][j])
            }
            bands[i] = min(sum / Float(end - start) * 3.0, 1.0)
        }

        return bands
    }
}
