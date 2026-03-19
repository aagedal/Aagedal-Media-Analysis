import Foundation
import Combine
import AppKit

/// Manages working folders: opening, enumerating media files, persisting recent folders
class WorkFolderManager: ObservableObject {

    @Published var folders: [WorkFolder] = []
    @Published var selectedFolder: WorkFolder?
    @Published var error: Error?

    private let bookmarkManager = SecurityBookmarkManager(bookmarkKey: "workFolderBookmarks")
    private let recentFoldersKey = "recentWorkFolders"

    private let mediaExtensions: Set<String> = [
        // Video
        "mp4", "mkv", "mov", "avi", "m4v", "webm", "ts", "mxf",
        // Audio
        "wav", "mp3", "m4a", "aac", "flac", "ogg", "wma",
        // Image
        "jpg", "jpeg", "png", "heif", "heic", "tiff", "tif", "bmp", "webp", "gif"
    ]

    init() {
        restoreRecentFolders()
    }

    // MARK: - Open Folder

    func openFolderDialog() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder containing media files"
        panel.prompt = "Open"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        addFolder(url: url)
    }

    func addFolder(url: URL) {
        // Save bookmark for persistent access
        let _ = bookmarkManager.saveBookmark(for: url)

        var folder = WorkFolder(url: url)
        folder.bookmarkData = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        // Enumerate media files
        folder.files = enumerateMediaFiles(in: url)

        // Ensure sidecar structure
        do {
            try SidecarStorageService.ensureSidecarStructure(for: url)
        } catch {
            Logger.error("Failed to create sidecar structure", error: error, category: Logger.general)
        }

        // Add or replace existing
        if let idx = folders.firstIndex(where: { $0.url == url }) {
            folders[idx] = folder
        } else {
            folders.append(folder)
        }

        selectedFolder = folder
        saveRecentFolders()
    }

    func removeFolder(_ folder: WorkFolder) {
        folders.removeAll { $0.id == folder.id }
        if selectedFolder?.id == folder.id {
            selectedFolder = folders.first
        }
        bookmarkManager.removeBookmark(for: folder.url)
        saveRecentFolders()
    }

    func refreshFolder(_ folder: WorkFolder) {
        guard let idx = folders.firstIndex(where: { $0.id == folder.id }) else { return }

        let accessing = folder.url.startAccessingSecurityScopedResource()
        defer { if accessing { folder.url.stopAccessingSecurityScopedResource() } }

        folders[idx].files = enumerateMediaFiles(in: folder.url)
        if selectedFolder?.id == folder.id {
            selectedFolder = folders[idx]
        }
    }

    // MARK: - Media File Enumeration

    private func enumerateMediaFiles(in folderURL: URL) -> [MediaFile] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return [] }

        var files: [MediaFile] = []
        for case let fileURL as URL in enumerator {
            let ext = fileURL.pathExtension.lowercased()
            guard mediaExtensions.contains(ext),
                  let mediaType = MediaType.from(url: fileURL) else { continue }

            var mediaFile = MediaFile(url: fileURL, type: mediaType)

            // Get file size
            if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let size = values.fileSize {
                mediaFile.metadata = MediaMetadata(fileSize: Int64(size))
            }

            files.append(mediaFile)
        }

        return files.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: - Persistence

    private func saveRecentFolders() {
        let paths = folders.map(\.url.path)
        UserDefaults.standard.set(paths, forKey: recentFoldersKey)
    }

    private func restoreRecentFolders() {
        let resolvedURLs = bookmarkManager.resolveAllBookmarks()
        for url in resolvedURLs {
            let accessing = url.startAccessingSecurityScopedResource()
            guard FileManager.default.fileExists(atPath: url.path) else {
                if accessing { url.stopAccessingSecurityScopedResource() }
                continue
            }

            var folder = WorkFolder(url: url)
            folder.files = enumerateMediaFiles(in: url)
            folders.append(folder)

            if accessing {
                // Keep access for now; will be released when app terminates
            }
        }

        selectedFolder = folders.first
    }
}
