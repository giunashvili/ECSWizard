import SwiftUI

@main
struct ECSWizardApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            Group {
                if appState.isAuthenticated {
                    MainView()
                        .frame(minWidth: 800, minHeight: 500)
                } else {
                    ConnectionsView()
                        .frame(width: 500, height: 380)
                }
            }
            .environmentObject(appState)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Connections…") {
                    appState.showingConnectionPicker = true
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            }
        }
    }
}
