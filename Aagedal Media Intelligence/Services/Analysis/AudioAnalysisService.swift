import Foundation
import Combine

/// Coordinates audio analysis: transcription + summarization
class AudioAnalysisService: ObservableObject {

    @Published var isTranscribing = false
    @Published var isSummarizing = false
    @Published var transcriptionProgress: Double = 0
    @Published var transcript: Transcript?
    @Published var summary: String?
    @Published var error: Error?

    private let ffmpegService = FFmpegService()
    private let whisperService = WhisperService()
    private let inferenceService: LlamaInferenceService
    private let modelManager: ModelManager

    init(inferenceService: LlamaInferenceService, modelManager: ModelManager) {
        self.inferenceService = inferenceService
        self.modelManager = modelManager
    }

    /// Transcribe a media file (audio or video) using FFmpeg's whisper filter
    func transcribe(file: MediaFile, language: String = "auto", whisperModelId: String, folderURL: URL) async throws -> Transcript {
        isTranscribing = true
        transcriptionProgress = 0
        error = nil
        defer { isTranscribing = false }

        guard let modelPath = modelManager.getModelPath(for: whisperModelId) else {
            throw ModelManagerError.modelNotFound(whisperModelId)
        }

        // FFmpeg whisper filter handles both video and audio directly - no extraction needed
        let segments = try await whisperService.transcribe(
            inputURL: file.url,
            modelPath: modelPath,
            language: language
        ) { [weak self] progress in
            Task { @MainActor [weak self] in
                self?.transcriptionProgress = progress
            }
        }

        let result = Transcript(segments: segments, language: language, modelUsed: whisperModelId)
        try SidecarStorageService.saveTranscript(result, fileName: file.name, folderURL: folderURL)
        transcript = result
        transcriptionProgress = 1.0
        return result
    }

    /// Summarize a transcript using AI
    func summarize(transcript: Transcript, mode: SummarizationMode = .general) async throws -> String {
        isSummarizing = true
        error = nil
        defer { isSummarizing = false }

        let systemPrompt = mode.systemPrompt
        let fullText = transcript.fullText

        // Chunk if necessary (rough 4 chars per token estimate)
        let maxChars = 12000
        let textToSummarize: String
        if fullText.count > maxChars {
            textToSummarize = String(fullText.prefix(maxChars)) + "\n[...truncated]"
        } else {
            textToSummarize = fullText
        }

        let response = try await inferenceService.generateText(
            systemPrompt: systemPrompt,
            userMessage: "Please summarize the following transcript:\n\n\(textToSummarize)"
        )

        summary = response
        return response
    }

    func cancel() async {
        await ffmpegService.cancel()
        await whisperService.cancel()
        inferenceService.cancelGeneration()
        isTranscribing = false
        isSummarizing = false
    }
}

enum SummarizationMode: String, CaseIterable {
    case general
    case meeting
    case lecture

    var displayName: String {
        switch self {
        case .general: return "General"
        case .meeting: return "Meeting (Decisions + Actions)"
        case .lecture: return "Lecture (Key Themes)"
        }
    }

    var systemPrompt: String {
        switch self {
        case .general:
            return "You are a helpful assistant. Provide a clear, concise summary of the transcript."
        case .meeting:
            return "You are a meeting assistant. Extract key decisions, action items, and participants. Format with bullet points."
        case .lecture:
            return "You are an academic assistant. Identify main themes, key concepts, and important details from this lecture."
        }
    }
}
