import SwiftUI

struct FileGridView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @EnvironmentObject var workFolderManager: WorkFolderManager
    @StateObject private var viewModel = FileGridViewModel()

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                TextField("Search files...", text: $viewModel.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)

                Spacer()

                Picker("Sort", selection: $viewModel.sortOrder) {
                    ForEach(FileSortOrder.allCases, id: \.self) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            if let folder = workFolderManager.selectedFolder {
                let files = viewModel.sortFiles(folder.files)
                if files.isEmpty {
                    ContentUnavailableView("No Media Files", systemImage: "photo.on.rectangle.angled", description: Text("Open a folder containing video, audio, or image files."))
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(files) { file in
                                FileGridCell(file: file, isSelected: viewModel.selectedFiles.contains(file.id), folderURL: folder.url)
                                    .onTapGesture {
                                        appViewModel.selectFile(file)
                                    }
                                    .onTapGesture(count: 1) {
                                        viewModel.toggleSelection(file)
                                    }
                            }
                        }
                        .padding()
                    }
                }
            } else {
                ContentUnavailableView("No Folder Selected", systemImage: "folder", description: Text("Select or open a working folder from the sidebar."))
            }
        }
        .task(id: workFolderManager.selectedFolder?.id) {
            if let folder = workFolderManager.selectedFolder {
                await viewModel.generateThumbnails(for: folder)
            }
        }
    }
}

struct FileGridCell: View {
    let file: MediaFile
    let isSelected: Bool
    let folderURL: URL

    var body: some View {
        VStack(spacing: 4) {
            // Thumbnail
            ZStack {
                let thumbURL = SidecarStorageService.thumbnailURL(fileName: file.name, folderURL: folderURL)
                if FileManager.default.fileExists(atPath: thumbURL.path),
                   let image = NSImage(contentsOf: thumbURL) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 160, height: 100)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 160, height: 100)
                        .overlay {
                            Image(systemName: file.type.icon)
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                        }
                }

                // Type badge
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: file.type.icon)
                            .font(.caption2)
                            .padding(4)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    Spacer()
                    if let duration = file.metadata?.duration {
                        HStack {
                            Spacer()
                            Text(duration.formattedDuration)
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(.black.opacity(0.7))
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }
                }
                .padding(4)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // File name
            Text(file.name)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 160)
        }
        .padding(4)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
