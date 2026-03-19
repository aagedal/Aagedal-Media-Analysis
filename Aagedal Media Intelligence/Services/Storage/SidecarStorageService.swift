import Foundation

/// Manages reading and writing to the .media_intelligence/ sidecar directory
enum SidecarStorageService {
    private static let sidecarDirName = ".media_intelligence"
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Directory Setup

    nonisolated static func sidecarURL(for folderURL: URL) -> URL {
        folderURL.appendingPathComponent(sidecarDirName, isDirectory: true)
    }

    nonisolated static func ensureSidecarStructure(for folderURL: URL) throws {
        let base = sidecarURL(for: folderURL)
        let fm = FileManager.default
        let dirs = ["notes", "analysis", "chat", "thumbnails", "frames"]
        for dir in dirs {
            let dirURL = base.appendingPathComponent(dir, isDirectory: true)
            if !fm.fileExists(atPath: dirURL.path) {
                try fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
            }
        }
    }

    // MARK: - Analysis Results

    nonisolated static func saveAnalysis(_ result: AnalysisResult, folderURL: URL) throws {
        let base = sidecarURL(for: folderURL)
        let path = base.appendingPathComponent("analysis/\(result.fileName).analysis.json")
        let data = try encoder.encode(result)
        try data.write(to: path, options: .atomic)
    }

    nonisolated static func loadAnalysis(fileName: String, folderURL: URL) -> AnalysisResult? {
        let base = sidecarURL(for: folderURL)
        let path = base.appendingPathComponent("analysis/\(fileName).analysis.json")
        guard let data = try? Data(contentsOf: path) else { return nil }
        return try? decoder.decode(AnalysisResult.self, from: data)
    }

    // MARK: - Transcripts

    nonisolated static func saveTranscript(_ transcript: Transcript, fileName: String, folderURL: URL) throws {
        let base = sidecarURL(for: folderURL)
        let path = base.appendingPathComponent("analysis/\(fileName).transcript.json")
        let data = try encoder.encode(transcript)
        try data.write(to: path, options: .atomic)
    }

    nonisolated static func loadTranscript(fileName: String, folderURL: URL) -> Transcript? {
        let base = sidecarURL(for: folderURL)
        let path = base.appendingPathComponent("analysis/\(fileName).transcript.json")
        guard let data = try? Data(contentsOf: path) else { return nil }
        return try? decoder.decode(Transcript.self, from: data)
    }

    // MARK: - Face Data

    nonisolated static func saveFaceData(_ faceData: FileFaceData, folderURL: URL) throws {
        let base = sidecarURL(for: folderURL)
        let path = base.appendingPathComponent("analysis/\(faceData.fileName).faces.json")
        let data = try encoder.encode(faceData)
        try data.write(to: path, options: .atomic)
    }

    nonisolated static func loadFaceData(fileName: String, folderURL: URL) -> FileFaceData? {
        let base = sidecarURL(for: folderURL)
        let path = base.appendingPathComponent("analysis/\(fileName).faces.json")
        guard let data = try? Data(contentsOf: path) else { return nil }
        return try? decoder.decode(FileFaceData.self, from: data)
    }

    // MARK: - Chat History

    nonisolated static func saveChatHistory(_ conversation: ChatConversation, fileName: String, folderURL: URL) throws {
        let base = sidecarURL(for: folderURL)
        let path = base.appendingPathComponent("chat/\(fileName).chat.json")
        let data = try encoder.encode(conversation)
        try data.write(to: path, options: .atomic)
    }

    nonisolated static func loadChatHistory(fileName: String, folderURL: URL) -> ChatConversation? {
        let base = sidecarURL(for: folderURL)
        let path = base.appendingPathComponent("chat/\(fileName).chat.json")
        guard let data = try? Data(contentsOf: path) else { return nil }
        return try? decoder.decode(ChatConversation.self, from: data)
    }

    // MARK: - Notes

    nonisolated static func saveNotes(_ text: String, fileName: String?, folderURL: URL) throws {
        let base = sidecarURL(for: folderURL)
        let noteName = fileName ?? "general"
        let path = base.appendingPathComponent("notes/\(noteName).md")
        try text.write(to: path, atomically: true, encoding: .utf8)
    }

    nonisolated static func loadNotes(fileName: String?, folderURL: URL) -> String {
        let base = sidecarURL(for: folderURL)
        let noteName = fileName ?? "general"
        let path = base.appendingPathComponent("notes/\(noteName).md")
        return (try? String(contentsOf: path, encoding: .utf8)) ?? ""
    }

    // MARK: - Thumbnails

    nonisolated static func thumbnailURL(fileName: String, folderURL: URL) -> URL {
        let base = sidecarURL(for: folderURL)
        return base.appendingPathComponent("thumbnails/\(fileName)_thumb.jpg")
    }

    nonisolated static func framesDirectory(fileName: String, folderURL: URL) -> URL {
        let base = sidecarURL(for: folderURL)
        return base.appendingPathComponent("frames/\(fileName)", isDirectory: true)
    }
}
