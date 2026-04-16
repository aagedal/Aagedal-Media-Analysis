import Foundation
import Combine
import AppKit

@MainActor
class ChatViewModel: ObservableObject {
    @Published var conversation = ChatConversation()
    @Published var inputText = ""
    @Published var isGenerating = false
    @Published var currentResponse = ""
    @Published var error: Error?
    /// User-facing error message shown inline in the chat UI, not persisted to history
    @Published var lastErrorMessage: String?

    private let inferenceService: LlamaInferenceService
    /// Cache for resized image data to avoid re-processing on every message
    private var imageCache: (url: URL, data: Data)?

    init(inferenceService: LlamaInferenceService) {
        self.inferenceService = inferenceService

        // Forward streaming tokens from inference service to chat view
        inferenceService.$currentResponse
            .receive(on: RunLoop.main)
            .assign(to: &$currentResponse)
    }

    func sendMessage(
        file: MediaFile? = nil,
        folderURL: URL? = nil,
        transcript: Transcript? = nil,
        analysisResult: AnalysisResult? = nil,
        notes: String? = nil,
        supportsVision: Bool = false
    ) async {
        let userText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userText.isEmpty else { return }

        let userMessage = ChatMessage(role: .user, content: userText)
        conversation.addMessage(userMessage)
        inputText = ""
        isGenerating = true
        currentResponse = ""
        error = nil
        lastErrorMessage = nil

        let systemPrompt = buildSystemPrompt(
            file: file,
            transcript: transcript,
            analysisResult: analysisResult,
            notes: notes
        )

        // Build history — only include real user/assistant messages (not error placeholders)
        var history: [[String: Any]] = []
        for msg in conversation.messages.dropLast() {
            switch msg.role {
            case .user: history.append(["role": "user", "content": msg.content])
            case .assistant: history.append(["role": "assistant", "content": msg.content])
            case .system: break
            }
        }

        do {
            let response: String

            // Include image data when model supports vision and file is an image
            if supportsVision, let file, file.type == .image,
               let imageData = prepareImageData(from: file.url) {
                response = try await inferenceService.analyzeImage(
                    imageData: imageData,
                    prompt: userText,
                    systemPrompt: systemPrompt
                )
            } else {
                response = try await inferenceService.generateText(
                    systemPrompt: systemPrompt,
                    userMessage: userText,
                    conversationHistory: history
                )
            }

            let assistantMessage = ChatMessage(role: .assistant, content: response)
            conversation.addMessage(assistantMessage)

            // Save chat history
            if let folderURL, let fileName = file?.name {
                do {
                    try SidecarStorageService.saveChatHistory(conversation, fileName: fileName, folderURL: folderURL)
                } catch {
                    Logger.error("Failed to save chat history for \(fileName)", error: error, category: Logger.processing)
                }
            }
        } catch {
            // Don't pollute conversation history with error messages.
            // Show the error transiently in the UI instead.
            Logger.error("Chat generation failed", error: error, category: Logger.processing)
            lastErrorMessage = error.localizedDescription
            self.error = error
        }

        isGenerating = false
        currentResponse = ""
    }

    func loadChatHistory(fileName: String, folderURL: URL) {
        if let saved = SidecarStorageService.loadChatHistory(fileName: fileName, folderURL: folderURL) {
            conversation = saved
        } else {
            conversation = ChatConversation(fileName: fileName)
        }
        // Invalidate image cache when switching files
        imageCache = nil
        lastErrorMessage = nil
    }

    func clearConversation() {
        conversation = ChatConversation(fileName: conversation.fileName)
        lastErrorMessage = nil
    }

    private func prepareImageData(from url: URL) -> Data? {
        // Return cached data if the same image was already processed
        if let cached = imageCache, cached.url == url {
            return cached.data
        }

        guard let imageData = try? Data(contentsOf: url),
              let image = NSImage(data: imageData) else {
            Logger.warning("Could not read image at: \(url.lastPathComponent)", category: Logger.processing)
            return nil
        }

        let maxDim: CGFloat = 1024
        let resized: NSImage
        if image.size.width > maxDim || image.size.height > maxDim {
            let scale = min(maxDim / image.size.width, maxDim / image.size.height)
            resized = image.resized(to: NSSize(width: image.size.width * scale, height: image.size.height * scale))
        } else {
            resized = image
        }

        guard let jpegData = resized.jpegData(compressionQuality: 0.85) else {
            Logger.error("Failed to encode image as JPEG: \(url.lastPathComponent)", category: Logger.processing)
            return nil
        }

        // Cache for subsequent messages about the same image
        imageCache = (url: url, data: jpegData)
        return jpegData
    }

    private func buildSystemPrompt(
        file: MediaFile?,
        transcript: Transcript?,
        analysisResult: AnalysisResult?,
        notes: String?
    ) -> String {
        var prompt = "You are a helpful media analysis assistant. Answer questions about the media file and its content."

        if let file {
            prompt += "\n\nCurrent file: \(file.name) (type: \(file.type.rawValue))"
            if let meta = file.metadata {
                if let dur = meta.duration { prompt += "\nDuration: \(dur.formattedDuration)" }
                if let w = meta.width, let h = meta.height { prompt += "\nResolution: \(w)x\(h)" }
            }
        }

        if let transcript {
            let text = transcript.fullText
            let maxChars = 8000
            let truncated = text.count > maxChars ? String(text.prefix(maxChars)) + "\n[...truncated]" : text
            prompt += "\n\n--- Transcript ---\n\(truncated)\n--- End Transcript ---"
        }

        if let analysisResult {
            prompt += "\n\n--- Analysis ---\n\(analysisResult.response)\n--- End Analysis ---"
        }

        if let notes, !notes.isEmpty {
            prompt += "\n\n--- Notes ---\n\(notes)\n--- End Notes ---"
        }

        return prompt
    }
}
