import Foundation
import Combine

/// Download progress information for UI display
struct DownloadProgress {
    let fractionCompleted: Double
    let totalBytesWritten: Int64
    let totalBytesExpected: Int64
    let bytesPerSecond: Double

    var downloadedFormatted: String { ByteCountFormatter.string(fromByteCount: totalBytesWritten, countStyle: .file) }
    var totalFormatted: String { ByteCountFormatter.string(fromByteCount: totalBytesExpected, countStyle: .file) }
    var speedFormatted: String {
        if bytesPerSecond >= 1_000_000 { return String(format: "%.1f MB/s", bytesPerSecond / 1_000_000) }
        else if bytesPerSecond > 0 { return String(format: "%.0f KB/s", bytesPerSecond / 1_000) }
        return ""
    }
    var percentComplete: Int { Int(fractionCompleted * 100) }
}

/// Central model management for GGUF and Whisper model downloads
class ModelManager: ObservableObject {

    @Published var ggufModelDirectory: URL?
    @Published var whisperModelDirectory: URL?
    @Published var installedModels: Set<String> = []
    @Published var downloadProgress: [String: DownloadProgress] = [:]
    @Published var error: Error?

    let availableModels = ModelMetadata.allModels
    private let fileManager = FileManager.default
    private var downloadTasks: [String: URLSessionDownloadTask] = [:]

    init() {
        resolveDirectories()
        scanInstalledModels()
    }

    private func resolveDirectories() {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }

        let ggufDir = appSupport.appendingPathComponent("GGUFModels")
        try? fileManager.createDirectory(at: ggufDir, withIntermediateDirectories: true)
        ggufModelDirectory = ggufDir

        let whisperDir = appSupport.appendingPathComponent("WhisperModels")
        try? fileManager.createDirectory(at: whisperDir, withIntermediateDirectories: true)
        whisperModelDirectory = whisperDir
    }

    func scanInstalledModels() {
        var found = Set<String>()
        for model in availableModels {
            let dir = model.type == .gguf ? ggufModelDirectory : whisperModelDirectory
            guard let dir else { continue }
            if fileManager.fileExists(atPath: dir.appendingPathComponent(model.filename).path) {
                found.insert(model.id)
            }
        }
        installedModels = found
    }

    func getModelPath(for modelId: String) -> URL? {
        guard let model = availableModels.first(where: { $0.id == modelId }) else { return nil }
        let dir = model.type == .gguf ? ggufModelDirectory : whisperModelDirectory
        guard let dir else { return nil }
        let path = dir.appendingPathComponent(model.filename)
        return fileManager.fileExists(atPath: path.path) ? path : nil
    }

    func getMMProjPath(for modelId: String) -> URL? {
        guard let model = availableModels.first(where: { $0.id == modelId }),
              let mmProjFilename = model.mmProjFilename,
              let dir = ggufModelDirectory else { return nil }
        let path = dir.appendingPathComponent(mmProjFilename)
        return fileManager.fileExists(atPath: path.path) ? path : nil
    }

    func isModelInstalled(_ modelId: String) -> Bool { installedModels.contains(modelId) }

    func modelSupportsVision(_ modelId: String) -> Bool {
        availableModels.first(where: { $0.id == modelId })?.supportsVision ?? false
    }

    func isMMProjInstalled(for modelId: String) -> Bool {
        getMMProjPath(for: modelId) != nil
    }

    func downloadModel(_ metadata: ModelMetadata) async throws {
        let directory = metadata.type == .gguf ? ggufModelDirectory : whisperModelDirectory
        guard let directory else { throw ModelManagerError.directoryAccessFailed }
        let destination = directory.appendingPathComponent(metadata.filename)

        if !fileManager.fileExists(atPath: destination.path) {
            try await downloadFile(
                url: metadata.downloadURL,
                destination: destination,
                progressKey: metadata.id,
                expectedBytes: metadata.sizeBytes
            )
        }
        installedModels.insert(metadata.id)

        // Also download mmproj file for vision support
        if let mmProjFilename = metadata.mmProjFilename,
           let mmProjURL = metadata.mmProjDownloadURL {
            let mmProjDest = directory.appendingPathComponent(mmProjFilename)
            if !fileManager.fileExists(atPath: mmProjDest.path) {
                let mmKey = metadata.id + "-mmproj"
                try await downloadFile(
                    url: mmProjURL,
                    destination: mmProjDest,
                    progressKey: mmKey,
                    expectedBytes: metadata.mmProjSizeBytes
                )
            }
        }
    }

    private func downloadFile(url: URL, destination: URL, progressKey: String, expectedBytes: Int64) async throws {
        downloadProgress[progressKey] = DownloadProgress(fractionCompleted: 0, totalBytesWritten: 0, totalBytesExpected: expectedBytes, bytesPerSecond: 0)

        do {
            let delegate = DownloadDelegate(expectedBytes: expectedBytes) { progress in
                Task { @MainActor [weak self] in self?.downloadProgress[progressKey] = progress }
            }
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30
            config.timeoutIntervalForResource = 3600
            let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                delegate.onComplete = { [weak self] result in
                    switch result {
                    case .success(let tempURL):
                        do {
                            try FileManager.default.moveItem(at: tempURL, to: destination)
                            Task { @MainActor in
                                self?.downloadProgress.removeValue(forKey: progressKey)
                                self?.downloadTasks.removeValue(forKey: progressKey)
                            }
                            continuation.resume()
                        } catch {
                            try? FileManager.default.removeItem(at: tempURL)
                            continuation.resume(throwing: error)
                        }
                    case .failure(let error):
                        Task { @MainActor in self?.downloadTasks.removeValue(forKey: progressKey) }
                        continuation.resume(throwing: error)
                    }
                }
                let task = session.downloadTask(with: url)
                self.downloadTasks[progressKey] = task
                task.resume()
            }
        } catch {
            downloadProgress.removeValue(forKey: progressKey)
            throw error
        }
    }

    func cancelDownload(for modelId: String) {
        downloadTasks[modelId]?.cancel()
        downloadTasks.removeValue(forKey: modelId)
        downloadProgress.removeValue(forKey: modelId)
    }

    func deleteModel(_ metadata: ModelMetadata) throws {
        let dir = metadata.type == .gguf ? ggufModelDirectory : whisperModelDirectory
        guard let dir else { throw ModelManagerError.directoryAccessFailed }
        let path = dir.appendingPathComponent(metadata.filename)
        if fileManager.fileExists(atPath: path.path) {
            try fileManager.removeItem(at: path)
            installedModels.remove(metadata.id)
        }
        // Also remove mmproj file
        if let mmProjFilename = metadata.mmProjFilename {
            let mmProjPath = dir.appendingPathComponent(mmProjFilename)
            try? fileManager.removeItem(at: mmProjPath)
        }
    }

    nonisolated deinit {}
}

enum ModelManagerError: LocalizedError {
    case downloadFailed(String), directoryAccessFailed, modelNotFound(String)
    var errorDescription: String? {
        switch self {
        case .downloadFailed(let r): return "Download failed: \(r)"
        case .directoryAccessFailed: return "Cannot access model directory"
        case .modelNotFound(let id): return "Model '\(id)' not found."
        }
    }
}

// MARK: - Download Delegate

class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let onProgress: @Sendable (DownloadProgress) -> Void
    let expectedBytes: Int64
    var onComplete: ((Result<URL, Error>) -> Void)?
    private var downloadedURL: URL?
    private var fileError: Error?
    private var lastReportedPercent: Int = -1
    private var lastTimestamp: CFAbsoluteTime = 0
    private var lastBytesWritten: Int64 = 0
    private var currentSpeed: Double = 0

    init(expectedBytes: Int64, onProgress: @escaping @Sendable (DownloadProgress) -> Void) {
        self.expectedBytes = expectedBytes
        self.onProgress = onProgress
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
            fileError = ModelManagerError.downloadFailed("HTTP \(http.statusCode)"); return
        }
        let stableURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-download")
        do { try FileManager.default.moveItem(at: location, to: stableURL); downloadedURL = stableURL }
        catch { fileError = error }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        session.finishTasksAndInvalidate()
        if let error { onComplete?(.failure(error)) }
        else if let fileError { onComplete?(.failure(fileError)) }
        else if let url = downloadedURL { onComplete?(.success(url)) }
        else { onComplete?(.failure(ModelManagerError.downloadFailed("Download completed but file not saved"))) }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let totalBytes = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedBytes
        guard totalBytes > 0 else { return }
        let fraction = min(max(Double(totalBytesWritten) / Double(totalBytes), 0.0), 1.0)
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - lastTimestamp
        if elapsed >= 0.5 {
            currentSpeed = Double(totalBytesWritten - lastBytesWritten) / elapsed
            lastTimestamp = now; lastBytesWritten = totalBytesWritten
        }
        let currentPercent = Int(fraction * 100)
        guard currentPercent > lastReportedPercent else { return }
        lastReportedPercent = currentPercent
        onProgress(DownloadProgress(fractionCompleted: fraction, totalBytesWritten: totalBytesWritten, totalBytesExpected: totalBytes, bytesPerSecond: currentSpeed))
    }
}
