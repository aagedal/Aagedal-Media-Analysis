import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @EnvironmentObject var modelManager: ModelManager
    @EnvironmentObject var llamaServerManager: LlamaServerManager

    var body: some View {
        TabView {
            modelsTab
                .tabItem { Label("Models", systemImage: "cpu") }

            generalTab
                .tabItem { Label("General", systemImage: "gear") }
        }
        .frame(width: 600, height: 500)
    }

    // MARK: - Models Tab

    private var modelsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // GGUF Models
                Text("Chat & Vision Models (GGUF)").font(.headline)
                ForEach(modelManager.availableModels.filter({ $0.type == .gguf }), id: \.id) { model in
                    modelRow(model)
                }

                Divider()

                // Whisper Models
                Text("Transcription Models (Whisper)").font(.headline)
                ForEach(modelManager.availableModels.filter({ $0.type == .whisper }), id: \.id) { model in
                    modelRow(model)
                }

                Divider()

                // llama-server status
                VStack(alignment: .leading, spacing: 8) {
                    Text("llama-server").font(.headline)
                    HStack {
                        Circle()
                            .fill(llamaServerManager.isRunning ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)
                        Text(llamaServerManager.isRunning ? "Running" : "Stopped")
                        if let path = llamaServerManager.loadedModelPath {
                            Text("(\(path.lastPathComponent))")
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Text("Binary: \(llamaServerManager.isBinaryAvailable ? "Available" : "Not downloaded")")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if !llamaServerManager.isBinaryAvailable {
                            Button("Download") {
                                Task { try? await llamaServerManager.downloadLlamaServer() }
                            }
                            .controlSize(.small)
                        }
                    }

                    if llamaServerManager.isDownloadingBinary, let progress = llamaServerManager.binaryDownloadProgress {
                        ProgressView(value: progress.fractionCompleted) {
                            Text("Downloading llama-server... \(progress.percentComplete)%")
                                .font(.caption)
                        }
                    }
                }
            }
            .padding()
        }
    }

    private func modelRow(_ model: ModelMetadata) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(model.name).font(.body)
                Text("\(model.description) (\(model.sizeFormatted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if modelManager.isModelInstalled(model.id) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Button("Delete", role: .destructive) {
                        try? modelManager.deleteModel(model)
                    }
                    .controlSize(.small)
                }
            } else if let progress = modelManager.downloadProgress[model.id] {
                VStack(alignment: .trailing) {
                    ProgressView(value: progress.fractionCompleted)
                        .frame(width: 100)
                    Text("\(progress.percentComplete)% \(progress.speedFormatted)")
                        .font(.caption2)
                    Button("Cancel") {
                        modelManager.cancelDownload(for: model.id)
                    }
                    .controlSize(.mini)
                }
            } else {
                Button("Download") {
                    Task { try? await modelManager.downloadModel(model) }
                }
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section("FFmpeg") {
                if let path = Bundle.main.path(forResource: "ffmpeg", ofType: nil) {
                    LabeledContent("FFmpeg", value: path)
                } else {
                    LabeledContent("FFmpeg", value: "Not bundled - add ffmpeg to app resources")
                }
            }

            Section("Storage") {
                if let dir = modelManager.ggufModelDirectory {
                    LabeledContent("GGUF Models", value: dir.path)
                }
                if let dir = modelManager.whisperModelDirectory {
                    LabeledContent("Whisper Models", value: dir.path)
                }
            }
        }
        .padding()
    }
}
