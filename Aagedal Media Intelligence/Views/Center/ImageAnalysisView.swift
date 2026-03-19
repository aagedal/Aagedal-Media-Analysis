import SwiftUI

struct ImageAnalysisView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @EnvironmentObject var workFolderManager: WorkFolderManager
    @StateObject private var viewModel: ImageAnalysisViewModel

    init() {
        _viewModel = StateObject(wrappedValue: ImageAnalysisViewModel(imageAnalysisService: ImageAnalysisService(inferenceService: LlamaInferenceService(serverManager: LlamaServerManager()))))
    }

    var body: some View {
        VStack(spacing: 0) {
            if let file = appViewModel.selectedFile, file.type == .image {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Image preview
                        if let image = NSImage(contentsOf: file.url) {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 400)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        // Metadata
                        if let metadata = viewModel.metadata {
                            metadataSection(metadata)
                        }

                        // Analysis
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Analysis Prompt").font(.headline)
                            TextEditor(text: $viewModel.prompt)
                                .frame(height: 60)
                                .border(Color.secondary.opacity(0.3))

                            Button("Analyze Image") {
                                Task {
                                    if let folder = workFolderManager.selectedFolder {
                                        await viewModel.analyzeImage(file: file, folderURL: folder.url)
                                    }
                                }
                            }
                            .disabled(viewModel.isAnalyzing || !appViewModel.llamaServerManager.isRunning)

                            if viewModel.isAnalyzing {
                                ProgressView("Analyzing...")
                            }
                        }

                        if let result = viewModel.analysisResult {
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
                    .padding()
                }
            } else {
                ContentUnavailableView("Select an Image", systemImage: "photo", description: Text("Select an image file from the file grid to analyze."))
            }
        }
        .onChange(of: appViewModel.selectedFile?.id) { _, _ in
            if let file = appViewModel.selectedFile {
                viewModel.loadMetadata(from: file)
                if let folder = workFolderManager.selectedFolder {
                    viewModel.loadExistingAnalysis(fileName: file.name, folderURL: folder.url)
                }
            }
        }
    }

    private func metadataSection(_ metadata: [String: Any]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Metadata").font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                if let exif = metadata["{Exif}"] as? [String: Any] {
                    if let model = exif["LensModel"] as? String {
                        metadataRow("Lens", model)
                    }
                    if let iso = exif["ISOSpeedRatings"] as? [Int], let first = iso.first {
                        metadataRow("ISO", "\(first)")
                    }
                    if let fNumber = exif["FNumber"] as? Double {
                        metadataRow("Aperture", "f/\(fNumber)")
                    }
                    if let exposure = exif["ExposureTime"] as? Double {
                        metadataRow("Shutter", exposure < 1 ? "1/\(Int(1/exposure))" : "\(exposure)s")
                    }
                }
                if let tiff = metadata["{TIFF}"] as? [String: Any] {
                    if let make = tiff["Make"] as? String {
                        metadataRow("Camera", make)
                    }
                }
                if let width = metadata["PixelWidth"] as? Int, let height = metadata["PixelHeight"] as? Int {
                    metadataRow("Resolution", "\(width) x \(height)")
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func metadataRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption)
        }
    }
}
