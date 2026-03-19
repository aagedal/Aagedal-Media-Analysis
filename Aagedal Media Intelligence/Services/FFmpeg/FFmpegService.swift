import Foundation

/// Actor that manages FFmpeg/ffprobe process execution for media operations
actor FFmpegService {
    private var currentProcess: Process?

    // MARK: - Binary Location

    private var ffmpegPath: String? {
        Bundle.main.path(forResource: "ffmpeg", ofType: nil)
    }

    private var ffprobePath: String? {
        Bundle.main.path(forResource: "ffprobe", ofType: nil)
    }

    // MARK: - Probe

    /// Get media duration using ffprobe
    func getDuration(url: URL) async -> TimeInterval? {
        guard let path = ffprobePath else { return nil }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = [
            "-v", "error",
            "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1",
            url.path
        ]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = try await readWithTimeout(from: pipe.fileHandleForReading, process: process, timeout: 10)
            guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return nil
            }
            return Double(output)
        } catch {
            return nil
        }
    }

    /// Get media metadata using ffprobe (JSON output)
    func probe(url: URL) async -> MediaMetadata? {
        guard let path = ffprobePath else { return nil }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = [
            "-v", "error",
            "-show_entries", "format=duration,bit_rate:stream=codec_name,width,height,r_frame_rate,sample_rate,channels",
            "-of", "json",
            url.path
        ]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = try await readWithTimeout(from: pipe.fileHandleForReading, process: process, timeout: 10)

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }

            var metadata = MediaMetadata()

            // Parse format info
            if let format = json["format"] as? [String: Any] {
                if let durStr = format["duration"] as? String { metadata.duration = Double(durStr) }
                if let brStr = format["bit_rate"] as? String { metadata.bitRate = Int(brStr) }
            }

            // Parse stream info
            if let streams = json["streams"] as? [[String: Any]], let stream = streams.first {
                metadata.codecName = stream["codec_name"] as? String
                metadata.width = stream["width"] as? Int
                metadata.height = stream["height"] as? Int
                metadata.sampleRate = (stream["sample_rate"] as? String).flatMap(Int.init)
                metadata.channels = stream["channels"] as? Int

                if let rateStr = stream["r_frame_rate"] as? String {
                    let parts = rateStr.split(separator: "/")
                    if parts.count == 2, let num = Double(parts[0]), let den = Double(parts[1]), den > 0 {
                        metadata.frameRate = num / den
                    }
                }
            }

            // File size
            if let values = try? url.resourceValues(forKeys: [.fileSizeKey]) {
                metadata.fileSize = values.fileSize.map(Int64.init)
            }

            return metadata
        } catch {
            return nil
        }
    }

    // MARK: - Thumbnail Extraction

    /// Extract a single thumbnail frame at the given time
    func extractThumbnail(url: URL, at time: TimeInterval = 1.0, outputURL: URL, width: Int = 640) async throws {
        guard let path = ffmpegPath else {
            throw FFmpegError.binaryNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = [
            "-ss", String(time),
            "-i", url.path,
            "-vframes", "1",
            "-vf", "scale=\(width):-1",
            "-q:v", "3",
            "-y",
            outputURL.path
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw FFmpegError.extractionFailed("Thumbnail extraction exited with status \(process.terminationStatus)")
        }
    }

    // MARK: - Frame Extraction

    /// Extract multiple frames at even intervals
    func extractFrames(url: URL, count: Int = 10, outputDir: URL, width: Int = 640) async throws -> [URL] {
        guard let path = ffmpegPath else {
            throw FFmpegError.binaryNotFound
        }

        let fm = FileManager.default
        try fm.createDirectory(at: outputDir, withIntermediateDirectories: true)

        // Get duration first
        guard let duration = await getDuration(url: url), duration > 0 else {
            throw FFmpegError.extractionFailed("Could not determine video duration")
        }

        var frameURLs: [URL] = []
        let interval = duration / Double(count + 1)

        for i in 1...count {
            let time = interval * Double(i)
            let frameName = String(format: "frame_%04d.jpg", i)
            let frameURL = outputDir.appendingPathComponent(frameName)

            try await extractThumbnail(url: url, at: time, outputURL: frameURL, width: width)
            frameURLs.append(frameURL)
        }

        return frameURLs
    }

    // MARK: - Audio Extraction

    /// Extract audio from a video file as WAV (16kHz mono for Whisper)
    func extractAudio(url: URL, outputURL: URL) async throws {
        guard let path = ffmpegPath else {
            throw FFmpegError.binaryNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = [
            "-i", url.path,
            "-vn",
            "-ar", "16000",
            "-ac", "1",
            "-f", "wav",
            "-y",
            outputURL.path
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw FFmpegError.extractionFailed("Audio extraction exited with status \(process.terminationStatus)")
        }
    }

    // MARK: - Cancel

    func cancel() {
        currentProcess?.terminate()
        currentProcess = nil
    }

    // MARK: - Helpers

    private func readWithTimeout(from handle: FileHandle, process: Process, timeout: TimeInterval) async throws -> Data {
        try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                let data = handle.readDataToEndOfFile()
                if process.isRunning { process.terminate() }
                return data
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if process.isRunning { process.terminate() }
                throw FFmpegError.timeout
            }
            guard let data = try await group.next() else {
                group.cancelAll()
                throw FFmpegError.timeout
            }
            group.cancelAll()
            return data
        }
    }
}

// MARK: - Errors

enum FFmpegError: LocalizedError {
    case binaryNotFound
    case extractionFailed(String)
    case timeout
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "FFmpeg/FFprobe binary not found in app bundle."
        case .extractionFailed(let reason):
            return "Extraction failed: \(reason)"
        case .timeout:
            return "FFmpeg operation timed out."
        case .transcriptionFailed(let reason):
            return "Transcription failed: \(reason)"
        }
    }
}
