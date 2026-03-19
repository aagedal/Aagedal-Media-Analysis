import SwiftUI

struct NotesView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @EnvironmentObject var workFolderManager: WorkFolderManager
    @StateObject private var viewModel = NotesViewModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Notes", systemImage: "note.text")
                    .font(.headline)
                Spacer()
                if viewModel.isDirty {
                    Text("Unsaved")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            TextEditor(text: $viewModel.text)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(4)
                .onChange(of: viewModel.text) { _, _ in
                    viewModel.textDidChange()
                }
        }
        .onChange(of: appViewModel.selectedFile?.id) { _, _ in
            viewModel.save() // Save previous
            if let folder = workFolderManager.selectedFolder {
                viewModel.load(fileName: appViewModel.selectedFile?.name, folderURL: folder.url)
            }
        }
        .onChange(of: workFolderManager.selectedFolder?.id) { _, _ in
            viewModel.save()
            if let folder = workFolderManager.selectedFolder {
                viewModel.load(fileName: appViewModel.selectedFile?.name, folderURL: folder.url)
            }
        }
    }
}
