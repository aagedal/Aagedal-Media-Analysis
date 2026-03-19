import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @EnvironmentObject var workFolderManager: WorkFolderManager
    @State private var showRightPanel = true
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            FolderSidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 350)
        } content: {
            centerContent
                .navigationSplitViewColumnWidth(min: 400, ideal: 600)
        } detail: {
            if showRightPanel {
                rightPanel
                    .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 400)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                toolbarItems
            }
        }
    }

    // MARK: - Center Content

    @ViewBuilder
    private var centerContent: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                ForEach(AppViewModel.CenterTab.allCases, id: \.rawValue) { tab in
                    Button {
                        appViewModel.selectedTab = tab
                    } label: {
                        Label(tab.rawValue, systemImage: tab.icon)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(appViewModel.selectedTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .background(.bar)

            Divider()

            // Tab content
            Group {
                switch appViewModel.selectedTab {
                case .files:
                    FileGridView()
                case .video:
                    VideoAnalysisView()
                case .image:
                    ImageAnalysisView()
                case .audio:
                    AudioAnalysisView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Right Panel

    private var rightPanel: some View {
        VSplitView {
            ChatView()
                .frame(minHeight: 200)
            NotesView()
                .frame(minHeight: 150)
        }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var toolbarItems: some View {
        Button {
            showRightPanel.toggle()
        } label: {
            Image(systemName: showRightPanel ? "sidebar.right" : "sidebar.right")
                .symbolVariant(showRightPanel ? .none : .slash)
        }
        .help(showRightPanel ? "Hide side panel" : "Show side panel")

        // Model status indicator
        HStack(spacing: 4) {
            Circle()
                .fill(appViewModel.llamaServerManager.isRunning ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(appViewModel.llamaServerManager.isRunning ? "AI Ready" : "AI Offline")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
