import Foundation
import Combine

/// Detects interesting moments in video by scoring frames + transcript segments
class HighlightDetectionService: ObservableObject {

    @Published var isDetecting = false
    @Published var progress: Double = 0
    @Published var highlights: [Highlight] = []
    @Published var error: Error?

    private let ffmpegService = FFmpegService()
    private let inferenceService: LlamaInferenceService

    init(inferenceService: LlamaInferenceService) {
        self.inferenceService = inferenceService
    }

    struct Highlight: Identifiable {
        let id = UUID()
        let timestamp: TimeInterval
        let score: Double
        let description: String
        let frameURL: URL?
    }

    func detectHighlights(
        file: MediaFile,
        intervalSeconds: Double = 30,
        folderURL: URL
    ) async throws -> [Highlight] {
        isDetecting = true
        progress = 0
        error = nil
        defer { isDetecting = false }

        guard let duration = await ffmpegService.getDuration(url: file.url), duration > 0 else {
            throw FFmpegError.extractionFailed("Could not determine duration")
        }

        let frameCount = Int(duration / intervalSeconds)
        guard frameCount > 0 else { return [] }

        let framesDir = SidecarStorageService.framesDirectory(fileName: file.name, folderURL: folderURL)
        let frames = try await ffmpegService.extractFrames(url: file.url, count: min(frameCount, 30), outputDir: framesDir)
        progress = 0.4

        var detectedHighlights: [Highlight] = []
        let interval = duration / Double(frames.count + 1)

        for (index, frameURL) in frames.enumerated() {
            let timestamp = interval * Double(index + 1)
            guard let imageData = try? Data(contentsOf: frameURL) else { continue }

            let response = try await inferenceService.analyzeImage(
                imageData: imageData,
                prompt: "Rate the visual interest/excitement of this scene on a scale of 1-10. Respond with just the number and a one-sentence description.",
                temperature: 0.2,
                maxTokens: 100
            )

            // Parse score from response
            let score = parseScore(from: response)
            if score >= 6 {
                detectedHighlights.append(Highlight(
                    timestamp: timestamp,
                    score: score,
                    description: response,
                    frameURL: frameURL
                ))
            }

            progress = 0.4 + 0.6 * Double(index + 1) / Double(frames.count)
        }

        highlights = detectedHighlights.sorted { $0.score > $1.score }
        return highlights
    }

    private func parseScore(from text: String) -> Double {
        let digits = text.prefix(2).filter(\.isNumber)
        return Double(digits) ?? 5.0
    }

    func cancel() async {
        await ffmpegService.cancel()
        inferenceService.cancelGeneration()
        isDetecting = false
    }
}
