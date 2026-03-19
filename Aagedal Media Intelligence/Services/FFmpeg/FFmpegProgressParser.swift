import Foundation

/// Parses FFmpeg stderr output for progress information
struct FFmpegProgressParser {
    var totalDuration: TimeInterval?

    /// Parse a line of FFmpeg stderr output and return progress 0.0-1.0
    mutating func parse(line: String) -> Double? {
        // Parse duration from initial output: "Duration: HH:MM:SS.ff"
        if totalDuration == nil, line.contains("Duration:") {
            if let range = line.range(of: "Duration: ") {
                let timeStr = String(line[range.upperBound...].prefix(11))
                totalDuration = parseFFmpegTime(timeStr)
            }
        }

        // Parse current time from progress output: "time=HH:MM:SS.ff"
        if let totalDuration, totalDuration > 0,
           let range = line.range(of: "time=") {
            let timeStr = String(line[range.upperBound...].prefix(11))
            if let currentTime = parseFFmpegTime(timeStr) {
                return min(currentTime / totalDuration, 1.0)
            }
        }

        return nil
    }

    private func parseFFmpegTime(_ str: String) -> TimeInterval? {
        let parts = str.split(separator: ":")
        guard parts.count == 3,
              let hours = Double(parts[0]),
              let minutes = Double(parts[1]),
              let seconds = Double(parts[2]) else {
            return nil
        }
        return hours * 3600 + minutes * 60 + seconds
    }
}
