import Foundation

struct TranscriptSegment: Codable, Identifiable {
    let id: UUID
    var startTime: TimeInterval
    var endTime: TimeInterval
    var text: String

    init(startTime: TimeInterval, endTime: TimeInterval, text: String) {
        self.id = UUID()
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
    }

    var formattedStartTime: String {
        Self.formatTime(startTime)
    }

    var formattedEndTime: String {
        Self.formatTime(endTime)
    }

    var formattedRange: String {
        "\(formattedStartTime) --> \(formattedEndTime)"
    }

    static func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        let milliseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, milliseconds)
    }

    /// Parse SRT format text into transcript segments
    static func parseSRT(_ srtText: String) -> [TranscriptSegment] {
        var segments: [TranscriptSegment] = []
        let blocks = srtText.components(separatedBy: "\n\n")

        for block in blocks {
            let lines = block.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: "\n")
            guard lines.count >= 3 else { continue }

            // Line 1 is sequence number, line 2 is timecode, rest is text
            let timecodeStr = lines[1]
            let text = lines[2...].joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)

            let timeParts = timecodeStr.components(separatedBy: " --> ")
            guard timeParts.count == 2 else { continue }

            if let start = parseSRTTime(timeParts[0].trimmingCharacters(in: .whitespaces)),
               let end = parseSRTTime(timeParts[1].trimmingCharacters(in: .whitespaces)) {
                segments.append(TranscriptSegment(startTime: start, endTime: end, text: text))
            }
        }

        return segments
    }

    private static func parseSRTTime(_ str: String) -> TimeInterval? {
        // Format: HH:MM:SS,mmm
        let cleaned = str.replacingOccurrences(of: ",", with: ".")
        let parts = cleaned.components(separatedBy: ":")
        guard parts.count == 3,
              let hours = Double(parts[0]),
              let minutes = Double(parts[1]),
              let seconds = Double(parts[2]) else {
            return nil
        }
        return hours * 3600 + minutes * 60 + seconds
    }
}

struct Transcript: Codable {
    var segments: [TranscriptSegment]
    var language: String?
    var modelUsed: String?
    var createdAt: Date

    var fullText: String {
        segments.map(\.text).joined(separator: " ")
    }

    init(segments: [TranscriptSegment], language: String? = nil, modelUsed: String? = nil) {
        self.segments = segments
        self.language = language
        self.modelUsed = modelUsed
        self.createdAt = Date()
    }
}
