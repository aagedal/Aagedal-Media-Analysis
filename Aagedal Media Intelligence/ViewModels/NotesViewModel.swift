import Foundation
import Combine

class NotesViewModel: ObservableObject {
    @Published var text = ""
    @Published var currentFileName: String?
    @Published var isDirty = false

    private var folderURL: URL?
    private var debounceWorkItem: DispatchWorkItem?

    func load(fileName: String?, folderURL: URL) {
        self.currentFileName = fileName
        self.folderURL = folderURL
        text = SidecarStorageService.loadNotes(fileName: fileName, folderURL: folderURL)
        isDirty = false
    }

    func textDidChange() {
        isDirty = true
        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.save()
        }
        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    func save() {
        guard let folderURL, isDirty else { return }
        try? SidecarStorageService.saveNotes(text, fileName: currentFileName, folderURL: folderURL)
        isDirty = false
    }
}
