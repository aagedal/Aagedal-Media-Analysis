import SwiftUI

struct FolderSidebarView: View {
    @EnvironmentObject var workFolderManager: WorkFolderManager
    @EnvironmentObject var appViewModel: AppViewModel

    var body: some View {
        List(selection: Binding(
            get: { workFolderManager.selectedFolder?.id },
            set: { id in
                workFolderManager.selectedFolder = workFolderManager.folders.first { $0.id == id }
            }
        )) {
            Section("Working Folders") {
                ForEach(workFolderManager.folders) { folder in
                    folderRow(folder)
                        .tag(folder.id)
                        .contextMenu {
                            Button("Refresh") { workFolderManager.refreshFolder(folder) }
                            Button("Reveal in Finder") {
                                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.url.path)
                            }
                            Divider()
                            Button("Remove from List", role: .destructive) {
                                workFolderManager.removeFolder(folder)
                            }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Button {
                    workFolderManager.openFolderDialog()
                } label: {
                    Label("Open Folder", systemImage: "folder.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .navigationTitle("Media Intelligence")
    }

    private func folderRow(_ folder: WorkFolder) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(folder.name)
                .font(.body)
                .lineLimit(1)

            HStack(spacing: 8) {
                let videos = folder.files.filter { $0.type == .video }.count
                let images = folder.files.filter { $0.type == .image }.count
                let audios = folder.files.filter { $0.type == .audio }.count

                if videos > 0 {
                    Label("\(videos)", systemImage: "film")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if images > 0 {
                    Label("\(images)", systemImage: "photo")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if audios > 0 {
                    Label("\(audios)", systemImage: "waveform")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
