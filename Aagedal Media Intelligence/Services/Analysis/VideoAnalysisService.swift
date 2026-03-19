import Foundation
import Combine
import AppKit

/// Coordinates video analysis: frame extraction + AI analysis
class VideoAnalysisService: ObservableObject {

    @Published var isAnalyzing = false
    @Published var progress: Double = 0
    @Published var extractedFrames: [URL] = []
    @Published var analysisResult: AnalysisResult?
    @Published var error: Error?

    private let ffmpegService = FFmpegService()
    private let inferenceService: LlamaInferenceService

    init(inferenceService: LlamaInferenceService) {
        self.inferenceService = inferenceService
    }

    /// Extract frames from a video file
    func extractFrames(from file: MediaFile, count: Int = 10, folderURL: URL) async throws -> [URL] {
        let framesDir = SidecarStorageService.framesDirectory(fileName: file.name, folderURL: folderURL)
        let frames = try await ffmpegService.extractFrames(url: file.url, count: count, outputDir: framesDir)
        extractedFrames = frames
        return frames
    }

    /// Analyze extracted frames with AI
    func analyzeFrames(
        frameURLs: [URL],
        prompt: String,
        fileName: String,
        folderURL: URL
    ) async throws -> AnalysisResult {
        isAnalyzing = true
        progress = 0
        error = nil
        defer { isAnalyzing = false }

        let response = try await inferenceService.analyzeFrames(
            frameURLs: frameURLs,
            prompt: prompt,
            maxTokens: 2000
        )

        let result = AnalysisResult(
            fileName: fileName,
            prompt: prompt,
            response: response,
            type: .videoFrameAnalysis
        )

        try SidecarStorageService.saveAnalysis(result, folderURL: folderURL)
        analysisResult = result
        return result
    }

    /// Full pipeline: extract frames + analyze
    func analyzeVideo(file: MediaFile, prompt: String, frameCount: Int = 10, folderURL: URL) async throws -> AnalysisResult {
        isAnalyzing = true
        progress = 0.1
        error = nil

        let frames = try await extractFrames(from: file, count: frameCount, folderURL: folderURL)
        progress = 0.5

        let result = try await analyzeFrames(
            frameURLs: frames,
            prompt: prompt,
            fileName: file.name,
            folderURL: folderURL
        )
        progress = 1.0
        isAnalyzing = false
        return result
    }

    func cancel() async {
        await ffmpegService.cancel()
        inferenceService.cancelGeneration()
        isAnalyzing = false
    }
}
