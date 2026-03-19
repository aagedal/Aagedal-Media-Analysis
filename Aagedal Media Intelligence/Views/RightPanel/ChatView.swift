import SwiftUI

struct ChatView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @EnvironmentObject var workFolderManager: WorkFolderManager
    @EnvironmentObject var viewModel: ChatViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("AI Chat", systemImage: "bubble.left.and.bubble.right")
                    .font(.headline)
                Spacer()
                Button { viewModel.clearConversation() } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Clear conversation")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.conversation.messages) { message in
                            ChatBubble(message: message)
                                .id(message.id)
                        }

                        if viewModel.isGenerating {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "sparkle")
                                    .foregroundStyle(.purple)
                                Text(viewModel.currentResponse.isEmpty ? "Thinking..." : viewModel.currentResponse)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal)
                            .id("generating")
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.conversation.messages.count) { _, _ in
                    if let last = viewModel.conversation.messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            Divider()

            // Input
            HStack(spacing: 8) {
                TextField("Ask about this file...", text: $viewModel.inputText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { sendMessage() }

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isGenerating || !appViewModel.llamaServerManager.isRunning)
            }
            .padding()

            if !appViewModel.llamaServerManager.isRunning {
                HStack {
                    if appViewModel.llamaServerManager.isLoading {
                        Label("Loading model...", systemImage: "hourglass")
                            .font(.caption).foregroundStyle(.orange)
                    } else {
                        Text("AI offline")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Start") {
                            Task { await appViewModel.startServerIfNeeded() }
                        }
                        .controlSize(.mini)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 4)
            }
        }
        .onChange(of: appViewModel.selectedFile?.id) { _, _ in
            if let file = appViewModel.selectedFile, let folder = workFolderManager.selectedFolder {
                viewModel.loadChatHistory(fileName: file.name, folderURL: folder.url)
            }
        }
    }

    private func sendMessage() {
        Task {
            await viewModel.sendMessage(
                file: appViewModel.selectedFile,
                folderURL: workFolderManager.selectedFolder?.url,
                supportsVision: appViewModel.modelManager.modelSupportsVision(appViewModel.selectedGGUFModel)
            )
        }
    }
}

struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: message.role == .user ? "person.circle" : "sparkle")
                .foregroundStyle(message.role == .user ? .blue : .purple)

            Text(message.content)
                .font(.body)
                .textSelection(.enabled)
        }
        .padding(.horizontal)
    }
}
