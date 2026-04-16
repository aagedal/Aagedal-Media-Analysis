import Foundation
import Combine

class AppViewModel: ObservableObject {

    // MARK: - Services
    let workFolderManager = WorkFolderManager()
    let modelManager = ModelManager()
    let llamaServerManager = LlamaServerManager()
    let inferenceService: LlamaInferenceService
    let videoAnalysisService: VideoAnalysisService
    let imageAnalysisService: ImageAnalysisService
    let audioAnalysisService: AudioAnalysisService
    let audioRecordingManager = AudioRecordingManager()
    let audioPlaybackManager = AudioPlaybackManager()
    let highlightDetectionService: HighlightDetectionService
    let faceDetectionService = FaceDetectionService()

    // MARK: - View Models (owned here, shared via environment)
    let videoAnalysisVM: VideoAnalysisViewModel
    let imageAnalysisVM: ImageAnalysisViewModel
    let audioAnalysisVM: AudioAnalysisViewModel
    let chatVM: ChatViewModel

    // MARK: - Published State
    @Published var selectedTab: CenterTab = .files
    @Published var selectedFile: MediaFile?
    @Published var isModelLoaded = false
    @Published var showSettings = false
    @Published var selectedGGUFModel: String {
        didSet { UserDefaults.standard.set(selectedGGUFModel, forKey: "selectedGGUFModel") }
    }

    private var cancellables = Set<AnyCancellable>()

    enum CenterTab: String, CaseIterable {
        case files = "Files"
        case video = "Video"
        case image = "Image"
        case audio = "Audio"

        var icon: String {
            switch self {
            case .files: return "square.grid.2x2"
            case .video: return "film"
            case .image: return "photo"
            case .audio: return "waveform"
            }
        }
    }

    init() {
        let savedModel = UserDefaults.standard.string(forKey: "selectedGGUFModel") ?? "qwen3.5-4b-q4"
        self.selectedGGUFModel = savedModel

        let inference = LlamaInferenceService(serverManager: llamaServerManager)
        self.inferenceService = inference
        self.videoAnalysisService = VideoAnalysisService(inferenceService: inference)
        self.imageAnalysisService = ImageAnalysisService(inferenceService: inference)
        self.audioAnalysisService = AudioAnalysisService(inferenceService: inference, modelManager: modelManager)
        self.highlightDetectionService = HighlightDetectionService(inferenceService: inference)

        self.videoAnalysisVM = VideoAnalysisViewModel(videoAnalysisService: VideoAnalysisService(inferenceService: inference))
        self.imageAnalysisVM = ImageAnalysisViewModel(imageAnalysisService: ImageAnalysisService(inferenceService: inference))
        self.audioAnalysisVM = AudioAnalysisViewModel(audioAnalysisService: AudioAnalysisService(inferenceService: inference, modelManager: modelManager))
        self.chatVM = ChatViewModel(inferenceService: inference)

        // Auto-start llama-server when a model becomes available
        modelManager.$installedModels
            .receive(on: RunLoop.main)
            .sink { [weak self] installed in
                guard let self, !self.llamaServerManager.isRunning, !self.llamaServerManager.isLoading else { return }
                if installed.contains(self.selectedGGUFModel) {
                    Task { await self.startServerIfNeeded() }
                }
            }
            .store(in: &cancellables)

        // Clear selected file when switching folders
        workFolderManager.$selectedFolder
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.selectedFile = nil
                self?.selectedTab = .files
            }
            .store(in: &cancellables)
    }

    // MARK: - Model Management

    func startServerIfNeeded() async {
        guard !llamaServerManager.isRunning, !llamaServerManager.isLoading else { return }
        guard let modelPath = modelManager.getModelPath(for: selectedGGUFModel) else { return }

        let mmProjPath = modelManager.getMMProjPath(for: selectedGGUFModel)

        do {
            try await llamaServerManager.startServer(modelPath: modelPath, mmProjPath: mmProjPath)
            isModelLoaded = true
        } catch {
            Logger.error("Failed to start llama-server", error: error, category: Logger.processing)
            isModelLoaded = false
        }
    }

    func switchModel(to modelId: String) async {
        selectedGGUFModel = modelId
        guard let modelPath = modelManager.getModelPath(for: modelId) else { return }

        let mmProjPath = modelManager.getMMProjPath(for: modelId)

        do {
            llamaServerManager.stopServer()
            try await llamaServerManager.startServer(modelPath: modelPath, mmProjPath: mmProjPath)
            isModelLoaded = true
        } catch {
            Logger.error("Failed to switch model", error: error, category: Logger.processing)
            isModelLoaded = false
        }
    }

    // MARK: - File Selection

    func selectFile(_ file: MediaFile) {
        selectedFile = file
        switch file.type {
        case .video: selectedTab = .video
        case .image: selectedTab = .image
        case .audio: selectedTab = .audio
        }
    }
}
