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
                Text("All Qwen 3.5 models support both text chat and image/video frame analysis.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(modelManager.availableModels.filter({ $0.type == .gguf }), id: \.id) { model in
                    ggufModelRow(model)
                }

                Divider()

                // Whisper Models
                Text("Transcription Models (Whisper)").font(.headline)
                Text("Used by the FFmpeg whisper filter for audio/video transcription.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(modelManager.availableModels.filter({ $0.type == .whisper }), id: \.id) { model in
                    whisperModelRow(model)
                }

                Divider()

                // llama-server status
                llamaServerSection
            }
            .padding()
        }
    }

    private func ggufModelRow(_ model: ModelMetadata) -> some View {
        HStack {
            // Selection indicator
            Image(systemName: appViewModel.selectedGGUFModel == model.id ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(appViewModel.selectedGGUFModel == model.id ? Color.accentColor : Color.secondary)
                .font(.title3)

            VStack(alignment: .leading) {
                Text(model.name).font(.body)
                Text("\(model.description) (\(model.sizeFormatted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if modelManager.isModelInstalled(model.id) {
                HStack(spacing: 8) {
                    if appViewModel.selectedGGUFModel != model.id {
                        Button("Use") {
                            Task { await appViewModel.switchModel(to: model.id) }
                        }
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                    } else if llamaServerManager.isRunning {
                        Label("Active", systemImage: "bolt.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else if llamaServerManager.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Start") {
                            Task { await appViewModel.startServerIfNeeded() }
                        }
                        .controlSize(.small)
                    }

                    Button(role: .destructive) {
                        if llamaServerManager.isRunning && appViewModel.selectedGGUFModel == model.id {
                            llamaServerManager.stopServer()
                        }
                        try? modelManager.deleteModel(model)
                    } label: {
                        Image(systemName: "trash")
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
                    Task {
                        try? await modelManager.downloadModel(model)
                        // Auto-select and start if this is the first/selected model
                        if appViewModel.selectedGGUFModel == model.id {
                            await appViewModel.startServerIfNeeded()
                        }
                    }
                }
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private func whisperModelRow(_ model: ModelMetadata) -> some View {
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
                    Button(role: .destructive) {
                        try? modelManager.deleteModel(model)
                    } label: {
                        Image(systemName: "trash")
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

    private var llamaServerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("llama-server").font(.headline)
            HStack {
                Circle()
                    .fill(llamaServerManager.isRunning ? Color.green : (llamaServerManager.isLoading ? Color.orange : Color.gray))
                    .frame(width: 8, height: 8)
                Text(llamaServerManager.isRunning ? "Running" : (llamaServerManager.isLoading ? "Starting..." : "Stopped"))
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

            if let error = llamaServerManager.error {
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section("FFmpeg") {
                if Bundle.main.path(forResource: "ffmpeg", ofType: nil) != nil {
                    LabeledContent("FFmpeg", value: "Bundled (with whisper filter)")
                } else {
                    LabeledContent("FFmpeg") {
                        Text("Not bundled — copy from Aagedal Media Converter")
                            .foregroundStyle(.red)
                    }
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
