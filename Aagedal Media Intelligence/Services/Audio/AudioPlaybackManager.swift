import Foundation
import Combine
import AVFoundation

/// Manages audio playback using AVAudioPlayer
class AudioPlaybackManager: NSObject, ObservableObject {

    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0.0
    @Published var duration: TimeInterval = 0.0
    @Published var error: Error?
    @Published var playbackRate: Float = 1.0

    static let availableRates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    private var audioPlayer: AVAudioPlayer?
    private var timeUpdateTimer: Timer?

    func loadAudio(url: URL) {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.enableRate = true
            audioPlayer?.rate = playbackRate
            audioPlayer?.prepareToPlay()
            duration = audioPlayer?.duration ?? 0.0
        } catch {
            self.error = error
        }
    }

    func play() {
        guard let player = audioPlayer else { return }
        player.rate = playbackRate
        player.play()
        isPlaying = true
        startTimeUpdateTimer()
    }

    func pause() {
        audioPlayer?.pause()
        isPlaying = false
        stopTimeUpdateTimer()
        currentTime = audioPlayer?.currentTime ?? 0
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        isPlaying = false
        stopTimeUpdateTimer()
        currentTime = 0
    }

    func seek(to time: TimeInterval) {
        guard let player = audioPlayer else { return }
        player.currentTime = max(0, min(time, player.duration))
        currentTime = player.currentTime
    }

    func cycleRate() {
        let rates = Self.availableRates
        if let index = rates.firstIndex(of: playbackRate) {
            playbackRate = rates[(index + 1) % rates.count]
        } else {
            playbackRate = 1.0
        }
        audioPlayer?.rate = playbackRate
    }

    func unload() {
        stop()
        audioPlayer = nil
        duration = 0
    }

    private func startTimeUpdateTimer() {
        stopTimeUpdateTimer()
        timeUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.audioPlayer, self.isPlaying else { return }
                self.currentTime = player.currentTime
            }
        }
    }

    private func stopTimeUpdateTimer() {
        timeUpdateTimer?.invalidate()
        timeUpdateTimer = nil
    }
}

extension AudioPlaybackManager: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in isPlaying = false; stopTimeUpdateTimer(); currentTime = 0 }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in self.error = error; isPlaying = false }
    }
}
