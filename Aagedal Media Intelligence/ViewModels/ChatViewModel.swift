import Foundation
import Combine

class ChatViewModel: ObservableObject {
    @Published var conversation = ChatConversation()
    @Published var inputText = ""
    @Published var isGenerating = false
    @Published var currentResponse = ""
    @Published var error: Error?

    private let inferenceService: LlamaInferenceService

    init(inferenceService: LlamaInferenceService) {
        self.inferenceService = inferenceService
    }

    func sendMessage(
        file: MediaFile? = nil,
        folderURL: URL? = nil,
        transcript: Transcript? = nil,
        analysisResult: AnalysisResult? = nil,
        notes: String? = nil
    ) async {
        let userText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userText.isEmpty else { return }

        let userMessage = ChatMessage(role: .user, content: userText)
        conversation.addMessage(userMessage)
        inputText = ""
        isGenerating = true
        currentResponse = ""
        error = nil

        let systemPrompt = buildSystemPrompt(
            file: file,
            transcript: transcript,
            analysisResult: analysisResult,
            notes: notes
        )

        // Build history
        var history: [[String: Any]] = []
        for msg in conversation.messages.dropLast() {
            switch msg.role {
            case .user: history.append(["role": "user", "content": msg.content])
            case .assistant: history.append(["role": "assistant", "content": msg.content])
            case .system: break
            }
        }

        do {
            let response = try await inferenceService.generateText(
                systemPrompt: systemPrompt,
                userMessage: userText,
                conversationHistory: history
            )

            let assistantMessage = ChatMessage(role: .assistant, content: response)
            conversation.addMessage(assistantMessage)

            // Save chat history
            if let folderURL, let fileName = file?.name {
                try? SidecarStorageService.saveChatHistory(conversation, fileName: fileName, folderURL: folderURL)
            }
        } catch {
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
    }

    func clearConversation() {
        conversation = ChatConversation(fileName: conversation.fileName)
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
