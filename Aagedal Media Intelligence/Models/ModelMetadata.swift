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
        // GGUF chat/vision models (Qwen 3.5 — all sizes support vision)
        ModelMetadata(
            id: "qwen3.5-0.8b-q4",
            name: "Qwen 3.5 0.8B (Q4_K_M)",
            type: .gguf,
            filename: "Qwen3.5-0.8B-Q4_K_M.gguf",
            downloadURL: URL(string: "https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF/resolve/main/Qwen3.5-0.8B-Q4_K_M.gguf")!,
            sizeBytes: 533_000_000,
            description: "Tiny, very fast. Good for quick tests and simple tasks"
        ),
        ModelMetadata(
            id: "qwen3.5-2b-q4",
            name: "Qwen 3.5 2B (Q4_K_M)",
            type: .gguf,
            filename: "Qwen3.5-2B-Q4_K_M.gguf",
            downloadURL: URL(string: "https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/main/Qwen3.5-2B-Q4_K_M.gguf")!,
            sizeBytes: 1_280_000_000,
            description: "Small and fast with decent quality. Runs on any Mac"
        ),
        ModelMetadata(
            id: "qwen3.5-4b-q4",
            name: "Qwen 3.5 4B (Q4_K_M)",
            type: .gguf,
            filename: "Qwen3.5-4B-Q4_K_M.gguf",
            downloadURL: URL(string: "https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/main/Qwen3.5-4B-Q4_K_M.gguf")!,
            sizeBytes: 2_740_000_000,
            description: "Good balance of speed and quality for 8GB Macs"
        ),
        ModelMetadata(
            id: "qwen3.5-9b-q4",
            name: "Qwen 3.5 9B (Q4_K_M)",
            type: .gguf,
            filename: "Qwen3.5-9B-Q4_K_M.gguf",
            downloadURL: URL(string: "https://huggingface.co/unsloth/Qwen3.5-9B-GGUF/resolve/main/Qwen3.5-9B-Q4_K_M.gguf")!,
            sizeBytes: 5_680_000_000,
            description: "Strong quality for 16GB+ Macs. Recommended"
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
