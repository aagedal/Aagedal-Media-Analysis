import Foundation
import Combine

class AudioAnalysisViewModel: ObservableObject {
    @Published var selectedWhisperModel: String = "whisper-medium"
    @Published var language: String = "auto"
    @Published var summarizationMode: SummarizationMode = .general
    @Published var transcript: Transcript?
    @Published var summary: String?
    @Published var isTranscribing = false
    @Published var isSummarizing = false
    @Published var transcriptionProgress: Double = 0
    @Published var error: Error?

    static let languageOptions = ["auto", "en", "no", "sv", "da", "de", "fr", "es", "it", "ja", "zh"]

    private let audioAnalysisService: AudioAnalysisService

    init(audioAnalysisService: AudioAnalysisService) {
        self.audioAnalysisService = audioAnalysisService
    }

    func transcribe(file: MediaFile, folderURL: URL) async {
        isTranscribing = true
        error = nil
        transcriptionProgress = 0
        defer { isTranscribing = false }

        do {
            transcript = try await audioAnalysisService.transcribe(
                file: file,
                language: language,
                whisperModelId: selectedWhisperModel,
                folderURL: folderURL
            )
        } catch {
            self.error = error
        }
    }

    func summarize() async {
        guard let transcript else { return }
        isSummarizing = true
        error = nil
        defer { isSummarizing = false }

        do {
            summary = try await audioAnalysisService.summarize(
                transcript: transcript,
                mode: summarizationMode
            )
        } catch {
            self.error = error
        }
    }

    func loadExisting(fileName: String, folderURL: URL) {
        transcript = SidecarStorageService.loadTranscript(fileName: fileName, folderURL: folderURL)
    }
}
