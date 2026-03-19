import Foundation
import UniformTypeIdentifiers

enum MediaType: String, Codable, CaseIterable {
    case video
    case audio
    case image

    var icon: String {
        switch self {
        case .video: return "film"
        case .audio: return "waveform"
        case .image: return "photo"
        }
    }

    static func from(url: URL) -> MediaType? {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "mp4", "mkv", "mov", "avi", "m4v", "webm", "ts", "mxf":
            return .video
        case "wav", "mp3", "m4a", "aac", "flac", "ogg", "wma":
            return .audio
        case "jpg", "jpeg", "png", "heif", "heic", "tiff", "tif", "bmp", "webp", "gif":
            return .image
        default:
            return nil
        }
    }
}

enum AnalysisState: Codable {
    case none
    case inProgress
    case completed
    case failed(String)
}

struct MediaMetadata: Codable {
    var duration: TimeInterval?
    var width: Int?
    var height: Int?
    var codecName: String?
    var bitRate: Int?
    var frameRate: Double?
    var sampleRate: Int?
    var channels: Int?
    var fileSize: Int64?
    var creationDate: Date?
}

struct MediaFile: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let type: MediaType
    var name: String
    var thumbnailURL: URL?
    var metadata: MediaMetadata?
    var analysisState: AnalysisState

    init(url: URL, type: MediaType) {
        self.id = UUID()
        self.url = url
        self.type = type
        self.name = url.lastPathComponent
        self.analysisState = .none
    }

    nonisolated static func == (lhs: MediaFile, rhs: MediaFile) -> Bool {
        lhs.id == rhs.id
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
