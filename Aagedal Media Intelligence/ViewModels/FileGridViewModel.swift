import Foundation
import Combine
import AppKit

enum FileSortOrder: String, CaseIterable {
    case name = "Name"
    case date = "Date"
    case type = "Type"
    case duration = "Duration"
}

class FileGridViewModel: ObservableObject {
    @Published var sortOrder: FileSortOrder = .name
    @Published var selectedFiles: Set<UUID> = []
    @Published var searchText = ""
    @Published var isGeneratingThumbnails = false

    private let ffmpegService = FFmpegService()

    var sortedFiles: [MediaFile] {
        get { [] } // Computed from the folder's files
    }

    func sortFiles(_ files: [MediaFile]) -> [MediaFile] {
        let filtered = searchText.isEmpty ? files : files.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }

        switch sortOrder {
        case .name:
            return filtered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .date:
            return filtered.sorted { ($0.metadata?.creationDate ?? .distantPast) > ($1.metadata?.creationDate ?? .distantPast) }
        case .type:
            return filtered.sorted { $0.type.rawValue < $1.type.rawValue }
        case .duration:
            return filtered.sorted { ($0.metadata?.duration ?? 0) > ($1.metadata?.duration ?? 0) }
        }
    }

    func toggleSelection(_ file: MediaFile) {
        if selectedFiles.contains(file.id) {
            selectedFiles.remove(file.id)
        } else {
            selectedFiles.insert(file.id)
        }
    }

    func selectAll(_ files: [MediaFile]) {
        selectedFiles = Set(files.map(\.id))
    }

    func deselectAll() {
        selectedFiles.removeAll()
    }

    /// Generate thumbnails for all media files in a folder
    func generateThumbnails(for folder: WorkFolder) async {
        isGeneratingThumbnails = true
        defer { isGeneratingThumbnails = false }

        for file in folder.files {
            let thumbURL = SidecarStorageService.thumbnailURL(fileName: file.name, folderURL: folder.url)
            guard !FileManager.default.fileExists(atPath: thumbURL.path) else { continue }

            switch file.type {
            case .video:
                try? await ffmpegService.extractThumbnail(url: file.url, at: 1.0, outputURL: thumbURL, width: 320)
            case .image:
                // Copy a resized version as thumbnail
                if let image = NSImage(contentsOf: file.url) {
                    let resized = image.resized(to: NSSize(width: 320, height: 320 * image.size.height / max(image.size.width, 1)))
                    if let data = resized.jpegData(compressionQuality: 0.7) {
                        try? data.write(to: thumbURL)
                    }
                }
            case .audio:
                break // Audio files don't have visual thumbnails
            }
        }
    }
}
