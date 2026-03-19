import Foundation
import Combine
import AppKit

/// Coordinates image analysis: metadata extraction + AI analysis
class ImageAnalysisService: ObservableObject {

    @Published var isAnalyzing = false
    @Published var analysisResult: AnalysisResult?
    @Published var error: Error?

    private let inferenceService: LlamaInferenceService

    init(inferenceService: LlamaInferenceService) {
        self.inferenceService = inferenceService
    }

    /// Analyze a single image with AI
    func analyzeImage(file: MediaFile, prompt: String, folderURL: URL) async throws -> AnalysisResult {
        isAnalyzing = true
        error = nil
        defer { isAnalyzing = false }

        guard let imageData = try? Data(contentsOf: file.url),
              let image = NSImage(data: imageData) else {
            throw NSError(domain: "ImageAnalysis", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not load image"])
        }

        // Resize for inference if too large
        let maxDim: CGFloat = 1024
        let resized: NSImage
        if image.size.width > maxDim || image.size.height > maxDim {
            let scale = min(maxDim / image.size.width, maxDim / image.size.height)
            resized = image.resized(to: NSSize(width: image.size.width * scale, height: image.size.height * scale))
        } else {
            resized = image
        }

        guard let jpegData = resized.jpegData(compressionQuality: 0.85) else {
            throw NSError(domain: "ImageAnalysis", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not encode image as JPEG"])
        }

        let response = try await inferenceService.analyzeImage(
            imageData: jpegData,
            prompt: prompt
        )

        let result = AnalysisResult(
            fileName: file.name,
            prompt: prompt,
            response: response,
            type: .imageAnalysis
        )

        try SidecarStorageService.saveAnalysis(result, folderURL: folderURL)
        analysisResult = result
        return result
    }

    /// Extract image metadata using CGImageSource
    func extractMetadata(from url: URL) -> [String: Any]? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return nil
        }
        return properties
    }

    func cancel() {
        inferenceService.cancelGeneration()
        isAnalyzing = false
    }
}
