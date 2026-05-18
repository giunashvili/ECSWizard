import SwiftUI

struct MainView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showConnections = false

    private var activeColor: Color {
        appState.currentConnection?.color.color ?? .accentColor
    }

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 260)
        } detail: {
            ContainerDetailView()
        }
        .tint(activeColor)
        .overlay(alignment: .top) {
            activeColor
                .frame(height: 3)
                .ignoresSafeArea(edges: .top)
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showConnections = true
                } label: {
                    HStack(spacing: 5) {
                        Text(appState.currentConnection?.emoji ?? "")
                        Text(appState.currentConnection?.name ?? "")
                    }
                }
                .help("Switch connection (⌘⇧K)")
            }
        }
        .sheet(isPresented: $showConnections) {
            ConnectionsView(
                onConnected: { showConnections = false },
                onDismiss: { showConnections = false }
            )
            .frame(width: 500, height: 380)
            .environmentObject(appState)
        }
        .onChange(of: appState.showingConnectionPicker) { show in
            if show {
                showConnections = true
                appState.showingConnectionPicker = false
            }
        }
        .overlay(alignment: .bottom) {
            if let error = appState.errorMessage {
                Text(error)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.85))
                    .cornerRadius(6)
                    .padding(.bottom, 12)
                    .onTapGesture { appState.errorMessage = nil }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.easeInOut, value: appState.errorMessage)
            }
        }
    }
}
