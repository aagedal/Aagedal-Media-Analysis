import Foundation
import Combine

@MainActor
class ImageAnalysisViewModel: ObservableObject {
    @Published var prompt: String = "Describe this image in detail."
    @Published var analysisResult: AnalysisResult?
    @Published var metadata: [String: Any]?
    @Published var isAnalyzing = false
    @Published var error: Error?

    private let imageAnalysisService: ImageAnalysisService

    init(imageAnalysisService: ImageAnalysisService) {
        self.imageAnalysisService = imageAnalysisService
    }

    func analyzeImage(file: MediaFile, folderURL: URL?) async {
        isAnalyzing = true
        error = nil
        defer { isAnalyzing = false }

        do {
            analysisResult = try await imageAnalysisService.analyzeImage(
                file: file,
                prompt: prompt,
                folderURL: folderURL
            )
        } catch {
            self.error = error
        }
    }

    func loadMetadata(from file: MediaFile) {
        metadata = imageAnalysisService.extractMetadata(from: file.url)
    }

    func loadExistingAnalysis(fileName: String, folderURL: URL) {
        analysisResult = SidecarStorageService.loadAnalysis(fileName: fileName, folderURL: folderURL)
    }
}
