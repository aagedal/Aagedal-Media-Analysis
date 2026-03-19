import Foundation

struct WorkFolder: Identifiable, Hashable {
    let id: UUID
    let url: URL
    var name: String
    var files: [MediaFile]
    var bookmarkData: Data?

    var sidecarPath: URL {
        url.appendingPathComponent(".media_intelligence", isDirectory: true)
    }

    init(url: URL) {
        self.id = UUID()
        self.url = url
        self.name = url.lastPathComponent
        self.files = []
    }

    nonisolated static func == (lhs: WorkFolder, rhs: WorkFolder) -> Bool {
        lhs.id == rhs.id
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
