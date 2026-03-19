import Foundation
import Combine

class VideoAnalysisViewModel: ObservableObject {
    @Published var prompt: String = "Describe what's happening in these video frames."
    @Published var frameCount: Int = 10
    @Published var extractedFrames: [URL] = []
    @Published var selectedFrameIndices: Set<Int> = []
    @Published var analysisResult: AnalysisResult?
    @Published var isExtracting = false
    @Published var isAnalyzing = false
    @Published var error: Error?

    private let videoAnalysisService: VideoAnalysisService

    init(videoAnalysisService: VideoAnalysisService) {
        self.videoAnalysisService = videoAnalysisService
    }

    func extractFrames(from file: MediaFile, folderURL: URL) async {
        isExtracting = true
        error = nil
        defer { isExtracting = false }

        do {
            extractedFrames = try await videoAnalysisService.extractFrames(from: file, count: frameCount, folderURL: folderURL)
            selectedFrameIndices = Set(extractedFrames.indices)
        } catch {
            self.error = error
        }
    }

    func analyzeSelectedFrames(fileName: String, folderURL: URL) async {
        isAnalyzing = true
        error = nil
        defer { isAnalyzing = false }

        let selectedURLs = selectedFrameIndices.sorted().compactMap { index in
            index < extractedFrames.count ? extractedFrames[index] : nil
        }

        guard !selectedURLs.isEmpty else { return }

        do {
            analysisResult = try await videoAnalysisService.analyzeFrames(
                frameURLs: selectedURLs,
                prompt: prompt,
                fileName: fileName,
                folderURL: folderURL
            )
        } catch {
            self.error = error
        }
    }

    func loadExistingAnalysis(fileName: String, folderURL: URL) {
        analysisResult = SidecarStorageService.loadAnalysis(fileName: fileName, folderURL: folderURL)
    }
}
