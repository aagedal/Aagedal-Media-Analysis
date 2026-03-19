import Foundation

struct AnalysisResult: Codable, Identifiable {
    let id: UUID
    let fileName: String
    let timestamp: Date
    var prompt: String
    var response: String
    var frameURLs: [String]?
    var analysisType: AnalysisType

    enum AnalysisType: String, Codable {
        case videoFrameAnalysis
        case imageAnalysis
        case audioSummarization
        case highlightDetection
        case episodeIdentification
        case faceDetection
    }

    init(fileName: String, prompt: String, response: String, type: AnalysisType) {
        self.id = UUID()
        self.fileName = fileName
        self.timestamp = Date()
        self.prompt = prompt
        self.response = response
        self.analysisType = type
    }
}
