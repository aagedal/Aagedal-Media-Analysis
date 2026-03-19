import Foundation
import Combine
import AppKit
import zlib

/// Manages a bundled llama-server process for GGUF model inference
class LlamaServerManager: ObservableObject {

    @Published var isRunning = false
    @Published var isLoading = false
    @Published var loadedModelPath: URL?
    @Published var error: Error?
    @Published var isDownloadingBinary = false
    @Published var binaryDownloadProgress: DownloadProgress?

    static let llamaCppVersion = "b8391"
    private static let downloadURL = URL(string: "https://github.com/ggml-org/llama.cpp/releases/download/\(llamaCppVersion)/llama-\(llamaCppVersion)-bin-macos-arm64.tar.gz")!
    private static let downloadSizeBytes: Int64 = 38_000_000

    private var serverProcess: Process?
    private var serverPort: Int = 8081
    private let portRange = 8081...8089
    private var downloadTask: URLSessionDownloadTask?

    init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.stopServer() }
        }
    }

    private var llamaServerDirectory: URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return appSupport.appendingPathComponent("LlamaServer")
    }

    var isBinaryAvailable: Bool { findLlamaServerBinary() != nil }

    func ensureBinaryAvailable() async throws {
        if findLlamaServerBinary() != nil { return }
        try await downloadLlamaServer()
    }

    private static let maxDownloadRetries = 3

    func downloadLlamaServer() async throws {
        guard let installDir = llamaServerDirectory else {
            throw LlamaServerError.downloadFailed("Cannot determine Application Support directory")
        }

        isDownloadingBinary = true
        error = nil
        binaryDownloadProgress = DownloadProgress(fractionCompleted: 0, totalBytesWritten: 0, totalBytesExpected: Self.downloadSizeBytes, bytesPerSecond: 0)

        var lastError: Error?
        for attempt in 1...Self.maxDownloadRetries {
            if attempt > 1 {
                binaryDownloadProgress = DownloadProgress(fractionCompleted: 0, totalBytesWritten: 0, totalBytesExpected: Self.downloadSizeBytes, bytesPerSecond: 0)
            }
            do {
                let tarballURL = try await attemptBinaryDownload()
                try await extractLlamaServer(tarball: tarballURL, to: installDir)
                try? FileManager.default.removeItem(at: tarballURL)
                isDownloadingBinary = false
                binaryDownloadProgress = nil
                downloadTask = nil
                return
            } catch {
                lastError = error
                let nsError = error as NSError
                if nsError.code == NSURLErrorCancelled { isDownloadingBinary = false; binaryDownloadProgress = nil; downloadTask = nil; throw error }
                if nsError.code == NSURLErrorTimedOut { continue }
                isDownloadingBinary = false; binaryDownloadProgress = nil; downloadTask = nil; self.error = error; throw error
            }
        }
        isDownloadingBinary = false; binaryDownloadProgress = nil; downloadTask = nil; self.error = lastError
        throw LlamaServerError.downloadFailed("Download failed after \(Self.maxDownloadRetries) attempts.")
    }

    private func attemptBinaryDownload() async throws -> URL {
        let delegate = DownloadDelegate(expectedBytes: Self.downloadSizeBytes) { [weak self] progress in
            Task { @MainActor [weak self] in self?.binaryDownloadProgress = progress }
        }
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 600
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)

        return try await withCheckedThrowingContinuation { continuation in
            delegate.onComplete = { result in
                switch result {
                case .success(let tempURL):
                    let stableURL = FileManager.default.temporaryDirectory.appendingPathComponent("llama-server-\(UUID().uuidString).tar.gz")
                    do {
                        try FileManager.default.moveItem(at: tempURL, to: stableURL)
                        continuation.resume(returning: stableURL)
                    } catch {
                        try? FileManager.default.removeItem(at: tempURL)
                        continuation.resume(throwing: error)
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            let task = session.downloadTask(with: Self.downloadURL)
            self.downloadTask = task
            task.resume()
        }
    }

    private func extractLlamaServer(tarball: URL, to directory: URL) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let prefix = "llama-\(Self.llamaCppVersion)/"
        let compressedData = try Data(contentsOf: tarball)
        let tarData = try Self.decompressGzip(compressedData)
        var extractedCount = 0
        var offset = 0

        while offset + 512 <= tarData.count {
            let headerData = tarData[offset..<(offset + 512)]
            if headerData.allSatisfy({ $0 == 0 }) { break }
            let nameBytes = headerData[offset..<(offset + 100)]
            let name = String(bytes: nameBytes.prefix(while: { $0 != 0 }), encoding: .utf8) ?? ""
            let sizeBytes = headerData[(offset + 124)..<(offset + 136)]
            let sizeString = String(bytes: sizeBytes.prefix(while: { $0 != 0 && $0 != 0x20 }), encoding: .utf8) ?? "0"
            let fileSize = Int(sizeString, radix: 8) ?? 0
            let typeFlag = headerData[offset + 156]
            let linkBytes = headerData[(offset + 157)..<(offset + 257)]
            let linkTarget = String(bytes: linkBytes.prefix(while: { $0 != 0 }), encoding: .utf8) ?? ""
            let prefixBytes = headerData[(offset + 345)..<(offset + 500)]
            let namePrefix = String(bytes: prefixBytes.prefix(while: { $0 != 0 }), encoding: .utf8) ?? ""
            let fullName = namePrefix.isEmpty ? name : "\(namePrefix)/\(name)"

            offset += 512

            guard fullName.hasPrefix(prefix) else { offset += ((fileSize + 511) / 512) * 512; continue }
            let localName = String(fullName.dropFirst(prefix.count))
            guard !localName.isEmpty else { offset += ((fileSize + 511) / 512) * 512; continue }
            let isServerBinary = localName == "llama-server"
            let isDylib = localName.hasSuffix(".dylib")
            guard isServerBinary || isDylib else { offset += ((fileSize + 511) / 512) * 512; continue }

            let destPath = directory.appendingPathComponent(localName)

            if typeFlag == UInt8(ascii: "2") {
                try? FileManager.default.removeItem(at: destPath)
                try FileManager.default.createSymbolicLink(atPath: destPath.path, withDestinationPath: linkTarget)
                extractedCount += 1
            } else if typeFlag == UInt8(ascii: "0") || typeFlag == 0 {
                guard offset + fileSize <= tarData.count else { throw LlamaServerError.downloadFailed("Tar truncated") }
                let fileData = tarData[offset..<(offset + fileSize)]
                try? FileManager.default.removeItem(at: destPath)
                try fileData.write(to: destPath)
                if isServerBinary { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destPath.path) }
                extractedCount += 1
            }
            offset += ((fileSize + 511) / 512) * 512
        }

        let serverPath = directory.appendingPathComponent("llama-server").path
        guard FileManager.default.fileExists(atPath: serverPath) else {
            throw LlamaServerError.downloadFailed("llama-server not found after extraction")
        }
        if let contents = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            for file in contents { removexattr(file.path, "com.apple.quarantine", 0) }
        }
    }

    private static func decompressGzip(_ data: Data) throws -> Data {
        guard data.count > 2, data[data.startIndex] == 0x1f, data[data.startIndex + 1] == 0x8b else {
            throw LlamaServerError.downloadFailed("Not a valid gzip file")
        }
        var result = Data()
        result.reserveCapacity(data.count * 4)
        let inputBytes = [UInt8](data)
        let bufferSize = 65536
        var outputBuffer = [UInt8](repeating: 0, count: bufferSize)
        var stream = z_stream()
        stream.next_in = UnsafeMutablePointer(mutating: inputBytes)
        stream.avail_in = UInt32(inputBytes.count)
        guard inflateInit2_(&stream, 15 + 32, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw LlamaServerError.downloadFailed("zlib init failed")
        }
        defer { inflateEnd(&stream) }
        var status: Int32 = Z_OK
        while status != Z_STREAM_END {
            status = outputBuffer.withUnsafeMutableBufferPointer { buf in
                stream.next_out = buf.baseAddress
                stream.avail_out = UInt32(bufferSize)
                return inflate(&stream, Z_NO_FLUSH)
            }
            let produced = bufferSize - Int(stream.avail_out)
            if produced > 0 { result.append(outputBuffer, count: produced) }
            if status != Z_OK && status != Z_STREAM_END { throw LlamaServerError.downloadFailed("zlib inflate failed: \(status)") }
        }
        return result
    }

    func cancelBinaryDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloadingBinary = false
        binaryDownloadProgress = nil
    }

    // MARK: - Server Lifecycle

    func startServer(modelPath: URL, mmProjPath: URL? = nil) async throws {
        if isRunning && loadedModelPath == modelPath { return }
        if isRunning { stopServer() }

        isLoading = true
        error = nil

        if findLlamaServerBinary() == nil { try await downloadLlamaServer() }
        guard let binaryPath = findLlamaServerBinary() else { isLoading = false; throw LlamaServerError.binaryNotFound }
        guard let port = await findAvailablePort() else { isLoading = false; throw LlamaServerError.portConflict }
        serverPort = port

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        var args = [
            "--model", modelPath.path,
            "--port", String(port),
            "--host", "127.0.0.1",
            "--ctx-size", "4096",
            "--n-gpu-layers", "99"
        ]
        if let mmProjPath {
            args += ["--mmproj", mmProjPath.path]
        }
        process.arguments = args
        let binaryDir = (binaryPath as NSString).deletingLastPathComponent
        process.environment = ProcessInfo.processInfo.environment
        process.currentDirectoryURL = URL(fileURLWithPath: binaryDir)
        process.standardError = Pipe()
        process.standardOutput = Pipe()

        do {
            try process.run()
            serverProcess = process
            loadedModelPath = modelPath

            // Monitor process lifecycle — reset state if server crashes
            process.terminationHandler = { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.serverProcess === process else { return }
                    self.isRunning = false
                    self.loadedModelPath = nil
                    self.serverProcess = nil
                }
            }

            let ready = await pollHealthEndpoint(port: port, maxAttempts: 60, interval: 0.5)
            if ready {
                isRunning = true; isLoading = false
            } else {
                stopServer(); isLoading = false; throw LlamaServerError.startupTimeout
            }
        } catch let err as LlamaServerError {
            isLoading = false; throw err
        } catch {
            self.error = error; isLoading = false; throw error
        }
    }

    func stopServer() {
        guard let process = serverProcess, process.isRunning else {
            isRunning = false; loadedModelPath = nil; serverProcess = nil; return
        }
        process.terminate()
        DispatchQueue.global().async { process.waitUntilExit() }
        serverProcess = nil; isRunning = false; loadedModelPath = nil
    }

    // MARK: - Chat Completion API

    func sendChatCompletion(
        messages: [[String: Any]],
        temperature: Double = 0.7,
        maxTokens: Int = 2000
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let url = URL(string: "http://127.0.0.1:\(self.serverPort)/v1/chat/completions")!
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    let body: [String: Any] = ["messages": messages, "temperature": temperature, "max_tokens": maxTokens, "stream": true]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        continuation.finish(throwing: LlamaServerError.requestFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)"))
                        return
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let data = String(line.dropFirst(6))
                        if data == "[DONE]" { break }
                        guard let jsonData = data.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any],
                              let content = delta["content"] as? String else { continue }
                        continuation.yield(content)
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
        }
    }

    // MARK: - Private Helpers

    private func findLlamaServerBinary() -> String? {
        if let p = Bundle.main.path(forResource: "llama-server", ofType: nil) { return p }
        if let dir = llamaServerDirectory {
            let p = dir.appendingPathComponent("llama-server").path
            if FileManager.default.fileExists(atPath: p) { removexattr(p, "com.apple.quarantine", 0); return p }
        }
        for path in ["/opt/homebrew/bin/llama-server", "/usr/local/bin/llama-server"] {
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    private func findAvailablePort() async -> Int? {
        for port in portRange {
            let url = URL(string: "http://127.0.0.1:\(port)/health")!
            var req = URLRequest(url: url); req.timeoutInterval = 0.5
            do { let _ = try await URLSession.shared.data(for: req); continue } catch { return port }
        }
        return nil
    }

    private func pollHealthEndpoint(port: Int, maxAttempts: Int, interval: TimeInterval) async -> Bool {
        let url = URL(string: "http://127.0.0.1:\(port)/health")!
        for _ in 0..<maxAttempts {
            do {
                let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url))
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let status = json["status"] as? String, status == "ok" { return true }
                    return true
                }
            } catch {}
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
        return false
    }

    nonisolated deinit {}
}

enum LlamaServerError: LocalizedError {
    case binaryNotFound, portConflict, startupTimeout, requestFailed(String), serverNotRunning, downloadFailed(String)
    var errorDescription: String? {
        switch self {
        case .binaryNotFound: return "llama-server binary not found."
        case .portConflict: return "No available port (8081-8089)."
        case .startupTimeout: return "llama-server failed to start within 30 seconds."
        case .requestFailed(let r): return "Request failed: \(r)"
        case .serverNotRunning: return "llama-server is not running."
        case .downloadFailed(let r): return "Download failed: \(r)"
        }
    }
}
