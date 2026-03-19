import SwiftUI

struct VideoAnalysisView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @EnvironmentObject var workFolderManager: WorkFolderManager
    @StateObject private var viewModel: VideoAnalysisViewModel

    init() {
        // Will be initialized with proper service in .onAppear
        _viewModel = StateObject(wrappedValue: VideoAnalysisViewModel(videoAnalysisService: VideoAnalysisService(inferenceService: LlamaInferenceService(serverManager: LlamaServerManager()))))
    }

    var body: some View {
        VStack(spacing: 0) {
            if let file = appViewModel.selectedFile, file.type == .video {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        fileHeader(file)
                        frameExtractionSection(file)
                        if !viewModel.extractedFrames.isEmpty {
                            frameGrid
                            analysisSection(file)
                        }
                        if let result = viewModel.analysisResult {
                            resultSection(result)
                        }
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView("Select a Video", systemImage: "film", description: Text("Select a video file from the file grid to analyze."))
            }
        }
        .onChange(of: appViewModel.selectedFile?.id) { _, _ in
            if let file = appViewModel.selectedFile, let folder = workFolderManager.selectedFolder {
                viewModel.loadExistingAnalysis(fileName: file.name, folderURL: folder.url)
            }
        }
    }

    private func fileHeader(_ file: MediaFile) -> some View {
        HStack {
            Image(systemName: "film")
                .font(.title2)
            VStack(alignment: .leading) {
                Text(file.name).font(.headline)
                if let dur = file.metadata?.duration {
                    Text("Duration: \(dur.formattedDuration)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private func frameExtractionSection(_ file: MediaFile) -> some View {
        HStack {
            Stepper("Frames: \(viewModel.frameCount)", value: $viewModel.frameCount, in: 1...30)
            Spacer()
            Button("Extract Frames") {
                Task {
                    if let folder = workFolderManager.selectedFolder {
                        await viewModel.extractFrames(from: file, folderURL: folder.url)
                    }
                }
            }
            .disabled(viewModel.isExtracting)
            if viewModel.isExtracting {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var frameGrid: some View {
        VStack(alignment: .leading) {
            Text("Extracted Frames").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(viewModel.extractedFrames.enumerated()), id: \.offset) { index, url in
                        if let image = NSImage(contentsOf: url) {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 160, height: 100)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6)
                                    .stroke(viewModel.selectedFrameIndices.contains(index) ? Color.accentColor : Color.clear, lineWidth: 3))
                                .onTapGesture {
                                    if viewModel.selectedFrameIndices.contains(index) {
                                        viewModel.selectedFrameIndices.remove(index)
                                    } else {
                                        viewModel.selectedFrameIndices.insert(index)
                                    }
                                }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func analysisSection(_ file: MediaFile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Analysis Prompt").font(.headline)
            TextEditor(text: $viewModel.prompt)
                .frame(height: 60)
                .border(Color.secondary.opacity(0.3))

            Button("Analyze Selected Frames") {
                Task {
                    if let folder = workFolderManager.selectedFolder {
                        await viewModel.analyzeSelectedFrames(fileName: file.name, folderURL: folder.url)
                    }
                }
            }
            .disabled(viewModel.isAnalyzing || viewModel.selectedFrameIndices.isEmpty || !appViewModel.llamaServerManager.isRunning)

            if viewModel.isAnalyzing {
                ProgressView("Analyzing...")
            }
        }
    }

    private func resultSection(_ result: AnalysisResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Analysis Result").font(.headline)
            Text(result.response)
                .padding()
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .textSelection(.enabled)
        }
    }
}
