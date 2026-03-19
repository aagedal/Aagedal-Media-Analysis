import Foundation

/// Transcription service using FFmpeg's built-in whisper audio filter
actor WhisperService {
    private var currentProcess: Process?
    private var isCancelled = false

    private var ffmpegPath: String? {
        Bundle.main.path(forResource: "ffmpeg", ofType: nil)
    }

    var isAvailable: Bool {
        ffmpegPath != nil
    }

    /// Transcribe a media file using FFmpeg's whisper filter, producing an SRT file
    /// - Parameters:
    ///   - inputURL: The input video or audio file
    ///   - modelPath: Path to the whisper GGML model file
    ///   - language: Language code (or "auto" for auto-detect)
    ///   - onProgress: Progress callback (0.0 - 1.0)
    /// - Returns: Parsed transcript segments
    func transcribe(
        inputURL: URL,
        modelPath: URL,
        language: String = "auto",
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> [TranscriptSegment] {
        guard let ffmpeg = ffmpegPath else {
            throw FFmpegError.binaryNotFound
        }

        isCancelled = false

        // Write SRT to a temp file
        let srtFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).srt")

        // Build the whisper filter string
        // Paths must be escaped for FFmpeg filter syntax (colons, backslashes, quotes)
        let escapedModelPath = escapeFFmpegFilterPath(modelPath.path)
        let escapedSrtPath = escapeFFmpegFilterPath(srtFile.path)

        let filterComponents = [
            "model=\(escapedModelPath)",
            "language=\(language)",
            "format=srt",
            "destination=\(escapedSrtPath)",
            "use_gpu=true"
        ]
        let whisperFilter = "whisper=" + filterComponents.joined(separator: ":")

        let process = Process()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.arguments = [
            "-i", inputURL.path,
            "-af", whisperFilter,
            "-f", "null",
            "-"
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice

        currentProcess = process

        // Parse stderr for progress (duration + current time)
        final class ProgressState: @unchecked Sendable {
            var durationSeconds: Double = 0
            var lastReportedProgress: Double = 0
        }
        let state = ProgressState()

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }

            // Parse total duration
            if state.durationSeconds == 0,
               let durationMatch = line.range(of: #"Duration:\s*(\d{2}):(\d{2}):(\d{2}\.\d+)"#, options: .regularExpression) {
                let durationStr = String(line[durationMatch])
                if let timeMatch = durationStr.range(of: #"(\d{2}):(\d{2}):(\d{2}\.\d+)"#, options: .regularExpression) {
                    let components = String(durationStr[timeMatch]).components(separatedBy: ":")
                    if components.count == 3,
                       let h = Double(components[0]),
                       let m = Double(components[1]),
                       let s = Double(components[2]) {
                        state.durationSeconds = h * 3600 + m * 60 + s
                    }
                }
            }

            // Parse current processing time for progress
            if state.durationSeconds > 0,
               let timeMatch = line.range(of: #"time=(\d{2}):(\d{2}):(\d{2}\.\d+)"#, options: .regularExpression) {
                let timeStr = String(line[timeMatch])
                if let match = timeStr.range(of: #"(\d{2}):(\d{2}):(\d{2}\.\d+)"#, options: .regularExpression) {
                    let components = String(timeStr[match]).components(separatedBy: ":")
                    if components.count == 3,
                       let h = Double(components[0]),
                       let m = Double(components[1]),
                       let s = Double(components[2]) {
                        let current = h * 3600 + m * 60 + s
                        let progress = min(current / state.durationSeconds, 0.99)
                        if progress - state.lastReportedProgress >= 0.01 {
                            state.lastReportedProgress = progress
                            onProgress?(progress)
                        }
                    }
                }
            }
        }

        try process.run()
        process.waitUntilExit()

        stderrPipe.fileHandleForReading.readabilityHandler = nil
        currentProcess = nil

        guard !isCancelled else {
            try? FileManager.default.removeItem(at: srtFile)
            throw FFmpegError.transcriptionFailed("Transcription cancelled")
        }

        guard process.terminationStatus == 0 else {
            throw FFmpegError.transcriptionFailed("FFmpeg whisper filter exited with code \(process.terminationStatus)")
        }

        guard FileManager.default.fileExists(atPath: srtFile.path) else {
            throw FFmpegError.transcriptionFailed("SRT file was not generated")
        }

        // Read and parse the SRT file
        let srtText = try String(contentsOf: srtFile, encoding: .utf8)
        try? FileManager.default.removeItem(at: srtFile)

        onProgress?(1.0)

        let segments = TranscriptSegment.parseSRT(srtText)
        guard !segments.isEmpty else {
            throw FFmpegError.transcriptionFailed("No transcription segments found")
        }

        return segments
    }

    func cancel() {
        isCancelled = true
        if let process = currentProcess, process.isRunning {
            process.terminate()
        }
        currentProcess = nil
    }

    // MARK: - Helpers

    /// Escapes a file path for use in FFmpeg filter syntax
    /// FFmpeg filter options use : as separator, so paths must escape special characters
    private nonisolated func escapeFFmpegFilterPath(_ path: String) -> String {
        path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ":", with: "\\:")
            .replacingOccurrences(of: "'", with: "\\'")
    }
}
