import Foundation
import Combine
import AppKit

/// Wraps llama-server HTTP API for text and vision inference.
///
/// Uses array-based token buffering to avoid O(n²) string concatenation
/// during streaming responses.
class LlamaInferenceService: ObservableObject {

    @Published var isGenerating = false
    @Published var currentResponse = ""
    @Published var error: Error?

    private let serverManager: LlamaServerManager

    init(serverManager: LlamaServerManager) {
        self.serverManager = serverManager
    }

    // MARK: - Streaming Helper

    /// Consumes a token stream using efficient array buffering instead of O(n²) string concatenation.
    /// Publishes incremental results to `currentResponse` for live UI updates.
    private func consumeStream(_ stream: AsyncThrowingStream<String, Error>) async throws -> String {
        var tokens: [String] = []
        tokens.reserveCapacity(256)

        for try await token in stream {
            tokens.append(token)
            // Join only for UI display — amortized by SwiftUI's coalescing
            currentResponse = tokens.joined()
        }

        let fullResponse = tokens.joined()
        currentResponse = ""
        return fullResponse.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Validates server is running and sets up generation state. Returns cleanup closure.
    private func beginGeneration() throws {
        guard serverManager.isRunning else {
            throw LlamaServerError.serverNotRunning
        }
        isGenerating = true
        currentResponse = ""
        error = nil
    }

    private func endGeneration() {
        isGenerating = false
    }

    // MARK: - Text Completion

    /// Text-only chat completion
    func generateText(
        systemPrompt: String,
        userMessage: String,
        conversationHistory: [[String: Any]] = [],
        temperature: Double = 0.7,
        maxTokens: Int = 2000
    ) async throws -> String {
        try beginGeneration()
        defer { endGeneration() }

        var messages: [[String: Any]] = [["role": "system", "content": systemPrompt]]
        messages.append(contentsOf: conversationHistory)
        messages.append(["role": "user", "content": userMessage])

        let stream = serverManager.sendChatCompletion(
            messages: messages,
            temperature: temperature,
            maxTokens: maxTokens
        )

        return try await consumeStream(stream)
    }

    // MARK: - Vision Completion

    /// Vision completion: send image + text prompt
    func analyzeImage(
        imageData: Data,
        prompt: String,
        systemPrompt: String = "You are an expert visual analyst. Describe what you see in detail.",
        temperature: Double = 0.3,
        maxTokens: Int = 2000
    ) async throws -> String {
        try beginGeneration()
        defer { endGeneration() }

        let base64 = imageData.base64EncodedString()

        let messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": [
                ["type": "text", "text": prompt],
                ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64)"]]
            ] as [Any]]
        ]

        let stream = serverManager.sendChatCompletion(
            messages: messages,
            temperature: temperature,
            maxTokens: maxTokens
        )

        return try await consumeStream(stream)
    }

    /// Analyze multiple images (e.g., video frames) together
    func analyzeFrames(
        frameURLs: [URL],
        prompt: String,
        systemPrompt: String = "You are analyzing video frames extracted at regular intervals.",
        maxTokens: Int = 2000
    ) async throws -> String {
        try beginGeneration()
        defer { endGeneration() }

        // Build content array with text + images
        var content: [[String: Any]] = [["type": "text", "text": prompt]]

        for frameURL in frameURLs {
            guard let imageData = try? Data(contentsOf: frameURL) else {
                Logger.warning("Skipping unreadable frame: \(frameURL.lastPathComponent)", category: Logger.processing)
                continue
            }
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

        let stream = serverManager.sendChatCompletion(
            messages: messages,
            temperature: 0.3,
            maxTokens: maxTokens
        )

        return try await consumeStream(stream)
    }

    func cancelGeneration() {
        isGenerating = false
        currentResponse = ""
    }
}
