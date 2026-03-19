import Foundation
import Combine
import AppKit

/// Wraps llama-server HTTP API for text and vision inference
class LlamaInferenceService: ObservableObject {

    @Published var isGenerating = false
    @Published var currentResponse = ""
    @Published var error: Error?

    private let serverManager: LlamaServerManager

    init(serverManager: LlamaServerManager) {
        self.serverManager = serverManager
    }

    /// Text-only chat completion
    func generateText(
        systemPrompt: String,
        userMessage: String,
        conversationHistory: [[String: Any]] = [],
        temperature: Double = 0.7,
        maxTokens: Int = 2000
    ) async throws -> String {
        guard serverManager.isRunning else {
            throw LlamaServerError.serverNotRunning
        }

        isGenerating = true
        currentResponse = ""
        error = nil
        defer { isGenerating = false }

        var messages: [[String: Any]] = [["role": "system", "content": systemPrompt]]
        messages.append(contentsOf: conversationHistory)
        messages.append(["role": "user", "content": userMessage])

        var fullResponse = ""
        let stream = serverManager.sendChatCompletion(
            messages: messages,
            temperature: temperature,
            maxTokens: maxTokens
        )

        for try await token in stream {
            fullResponse += token
            currentResponse = fullResponse
        }

        currentResponse = ""
        return fullResponse.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Vision completion: send image + text prompt
    func analyzeImage(
        imageData: Data,
        prompt: String,
        systemPrompt: String = "You are an expert visual analyst. Describe what you see in detail.",
        temperature: Double = 0.3,
        maxTokens: Int = 2000
    ) async throws -> String {
        guard serverManager.isRunning else {
            throw LlamaServerError.serverNotRunning
        }

        isGenerating = true
        currentResponse = ""
        error = nil
        defer { isGenerating = false }

        let base64 = imageData.base64EncodedString()

        let messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": [
                ["type": "text", "text": prompt],
                ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64)"]]
            ] as [Any]]
        ]

        var fullResponse = ""
        let stream = serverManager.sendChatCompletion(
            messages: messages,
            temperature: temperature,
            maxTokens: maxTokens
        )

        for try await token in stream {
            fullResponse += token
            currentResponse = fullResponse
        }

        currentResponse = ""
        return fullResponse.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Analyze multiple images (e.g., video frames) together
    func analyzeFrames(
        frameURLs: [URL],
        prompt: String,
        systemPrompt: String = "You are analyzing video frames extracted at regular intervals.",
        maxTokens: Int = 2000
    ) async throws -> String {
        guard serverManager.isRunning else {
            throw LlamaServerError.serverNotRunning
        }

        isGenerating = true
        currentResponse = ""
        error = nil
        defer { isGenerating = false }

        // Build content array with text + images
        var content: [[String: Any]] = [["type": "text", "text": prompt]]

        for frameURL in frameURLs {
            guard let imageData = try? Data(contentsOf: frameURL) else { continue }
            let base64 = imageData.base64EncodedString()
            content.append([
                "type": "image_url",
                "image_url": ["url": "data:image/jpeg;base64,\(base64)"]
            ])
        }

        let messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": content]
        ]

        var fullResponse = ""
        let stream = serverManager.sendChatCompletion(
            messages: messages,
            temperature: 0.3,
            maxTokens: maxTokens
        )

        for try await token in stream {
            fullResponse += token
            currentResponse = fullResponse
        }

        currentResponse = ""
        return fullResponse.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cancelGeneration() {
        isGenerating = false
        currentResponse = ""
    }
}
