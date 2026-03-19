import SwiftUI

struct AudioAnalysisView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @EnvironmentObject var workFolderManager: WorkFolderManager
    @StateObject private var viewModel: AudioAnalysisViewModel

    init() {
        _viewModel = StateObject(wrappedValue: AudioAnalysisViewModel(audioAnalysisService: AudioAnalysisService(inferenceService: LlamaInferenceService(serverManager: LlamaServerManager()), modelManager: ModelManager())))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Recording section
                    recordingSection

                    Divider()

                    // Transcription section
                    if let file = appViewModel.selectedFile, file.type == .video || file.type == .audio {
                        transcriptionSection(file)
                    }

                    // Transcript display
                    if let transcript = viewModel.transcript {
                        transcriptDisplay(transcript)

                        // Summarization
                        summarizationSection
                    }

                    if let summary = viewModel.summary {
                        summaryDisplay(summary)
                    }
                }
                .padding()
            }
        }
        .onChange(of: appViewModel.selectedFile?.id) { _, _ in
            if let file = appViewModel.selectedFile, let folder = workFolderManager.selectedFolder {
                viewModel.loadExisting(fileName: file.name, folderURL: folder.url)
            }
        }
    }

    private var recordingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recording").font(.headline)
            HStack(spacing: 12) {
                Button {
                    if appViewModel.audioRecordingManager.isRecording {
                        let _ = appViewModel.audioRecordingManager.stopRecording()
                    } else {
                        appViewModel.audioRecordingManager.startRecording()
                    }
                } label: {
                    Label(
                        appViewModel.audioRecordingManager.isRecording ? "Stop" : "Record",
                        systemImage: appViewModel.audioRecordingManager.isRecording ? "stop.circle.fill" : "record.circle"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(appViewModel.audioRecordingManager.isRecording ? .red : .accentColor)

                if appViewModel.audioRecordingManager.isRecording {
                    AudioVisualizerView(bands: appViewModel.audioRecordingManager.frequencyBands)
                    Text(appViewModel.audioRecordingManager.recordingTime.formattedDuration)
                        .font(.system(.body, design: .monospaced))
                }
            }
        }
    }

    private func transcriptionSection(_ file: MediaFile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Transcription").font(.headline)

            HStack {
                Picker("Model", selection: $viewModel.selectedWhisperModel) {
                    ForEach(ModelMetadata.allModels.filter({ $0.type == .whisper }), id: \.id) { model in
                        Text(model.name).tag(model.id)
                    }
                }
                .frame(maxWidth: 200)

                Picker("Language", selection: $viewModel.language) {
                    ForEach(AudioAnalysisViewModel.languageOptions, id: \.self) { lang in
                        Text(lang).tag(lang)
                    }
                }
                .frame(maxWidth: 120)

                Button("Transcribe") {
                    Task {
                        if let folder = workFolderManager.selectedFolder {
                            await viewModel.transcribe(file: file, folderURL: folder.url)
                        }
                    }
                }
                .disabled(viewModel.isTranscribing || !appViewModel.modelManager.isModelInstalled(viewModel.selectedWhisperModel))
            }

            if viewModel.isTranscribing {
                ProgressView(value: viewModel.transcriptionProgress) {
                    Text("Transcribing...")
                }
            }

            if let error = viewModel.error {
                Text(error.localizedDescription)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
    }

    private func transcriptDisplay(_ transcript: Transcript) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Transcript").font(.headline)
                Spacer()
                Text("\(transcript.segments.count) segments")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(transcript.segments) { segment in
                        HStack(alignment: .top, spacing: 8) {
                            Text(segment.formattedStartTime)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 80, alignment: .trailing)
                                .monospacedDigit()
                            Text(segment.text)
                                .font(.body)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding()
            }
            .frame(maxHeight: 300)
            .background(Color.secondary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var summarizationSection: some View {
        HStack {
            Picker("Mode", selection: $viewModel.summarizationMode) {
                ForEach(SummarizationMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .frame(maxWidth: 250)

            Button("Summarize") {
                Task { await viewModel.summarize() }
            }
            .disabled(viewModel.isSummarizing || !appViewModel.llamaServerManager.isRunning)

            if viewModel.isSummarizing {
                ProgressView().controlSize(.small)
            }
        }
    }

    private func summaryDisplay(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Summary").font(.headline)
            Text(summary)
                .padding()
                .background(Color.secondary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .textSelection(.enabled)
        }
    }
}

struct AudioVisualizerView: View {
    let bands: [Float]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<9, id: \.self) { index in
                let value = index < bands.count ? CGFloat(bands[index]) : 0
                let height = 2 + value * 14
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.accentColor)
                    .frame(width: 3, height: height)
                    .animation(.easeOut(duration: 0.08), value: value)
            }
        }
        .frame(height: 16)
    }
}
