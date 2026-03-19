import Foundation

enum ModelType: String, Codable {
    case gguf
    case whisper
}

struct ModelMetadata: Identifiable {
    let id: String
    let name: String
    let type: ModelType
    let filename: String
    let downloadURL: URL
    let sizeBytes: Int64
    let description: String

    var sizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    static let allModels: [ModelMetadata] = [
        // GGUF chat/vision models (Qwen 3.5)
        ModelMetadata(
            id: "qwen3.5-7b-q4",
            name: "Qwen 3.5 7B (Q4_K_M)",
            type: .gguf,
            filename: "Qwen3.5-7B-Q4_K_M.gguf",
            downloadURL: URL(string: "https://huggingface.co/unsloth/Qwen3.5-7B-GGUF/resolve/main/Qwen3.5-7B-Q4_K_M.gguf")!,
            sizeBytes: 4_900_000_000,
            description: "Good balance of quality and speed for Apple Silicon"
        ),
        ModelMetadata(
            id: "qwen3.5-14b-q4",
            name: "Qwen 3.5 14B (Q4_K_M)",
            type: .gguf,
            filename: "Qwen3.5-14B-Q4_K_M.gguf",
            downloadURL: URL(string: "https://huggingface.co/unsloth/Qwen3.5-14B-GGUF/resolve/main/Qwen3.5-14B-Q4_K_M.gguf")!,
            sizeBytes: 9_100_000_000,
            description: "Higher quality, requires 16GB+ RAM"
        ),
        // Whisper models for transcription
        ModelMetadata(
            id: "whisper-base",
            name: "Whisper Base",
            type: .whisper,
            filename: "ggml-base.bin",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin")!,
            sizeBytes: 148_000_000,
            description: "Fast, lower accuracy"
        ),
        ModelMetadata(
            id: "whisper-medium",
            name: "Whisper Medium",
            type: .whisper,
            filename: "ggml-medium.bin",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin")!,
            sizeBytes: 1_533_000_000,
            description: "Good balance of speed and accuracy"
        ),
        ModelMetadata(
            id: "whisper-large-v3-turbo",
            name: "Whisper Large V3 Turbo",
            type: .whisper,
            filename: "ggml-large-v3-turbo.bin",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin")!,
            sizeBytes: 1_640_000_000,
            description: "Best accuracy, optimized speed"
        ),
    ]
}
