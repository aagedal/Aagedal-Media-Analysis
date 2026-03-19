import Foundation
import Combine

class AppViewModel: ObservableObject {

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

    @Published var selectedTab: CenterTab = .files
    @Published var selectedFile: MediaFile?
    @Published var isModelLoaded = false
    @Published var showSettings = false

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
        let inference = LlamaInferenceService(serverManager: llamaServerManager)
        self.inferenceService = inference
        self.videoAnalysisService = VideoAnalysisService(inferenceService: inference)
        self.imageAnalysisService = ImageAnalysisService(inferenceService: inference)
        self.audioAnalysisService = AudioAnalysisService(inferenceService: inference, modelManager: modelManager)
        self.highlightDetectionService = HighlightDetectionService(inferenceService: inference)
    }

    func ensureModelLoaded(ggufModelId: String) async {
        guard let modelPath = modelManager.getModelPath(for: ggufModelId) else { return }
        if llamaServerManager.isRunning && llamaServerManager.loadedModelPath == modelPath {
            isModelLoaded = true; return
        }
        do {
            try await llamaServerManager.startServer(modelPath: modelPath)
            isModelLoaded = true
        } catch {
            Logger.error("Failed to start llama-server", error: error, category: Logger.processing)
            isModelLoaded = false
        }
    }

    func selectFile(_ file: MediaFile) {
        selectedFile = file
        switch file.type {
        case .video: selectedTab = .video
        case .image: selectedTab = .image
        case .audio: selectedTab = .audio
        }
    }
}
