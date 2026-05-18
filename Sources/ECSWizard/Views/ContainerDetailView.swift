import SwiftUI

private struct DBContext: Identifiable {
    let id = UUID()
    let task: ECSTask
    let container: ECSContainer
}

private enum ActiveSheet: Identifiable {
    case db(DBContext)
    case logs(LogsContext)

    var id: UUID {
        switch self {
        case .db(let ctx): return ctx.id
        case .logs(let ctx): return ctx.id
        }
    }
}

struct ContainerDetailView: View {
    @EnvironmentObject private var appState: AppState
    @State private var activeSheet: ActiveSheet?

    var body: some View {
        Group {
            if appState.selectedService == nil {
                placeholder("Select a service")
            } else if appState.isLoadingTasks {
                ProgressView("Loading tasks…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if appState.tasks.isEmpty {
                placeholder("No running tasks")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        ForEach(appState.tasks) { task in
                            TaskSection(
                                task: task,
                                onDB: { container in
                                    activeSheet = .db(DBContext(task: task, container: container))
                                },
                                onLogs: { containers in
                                    activeSheet = .logs(LogsContext(task: task, containers: containers))
                                }
                            )
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .navigationTitle(appState.selectedService?.name ?? "")
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .db(let ctx):
                DBConnectSheet(task: ctx.task, container: ctx.container)
                    .environmentObject(appState)
            case .logs(let ctx):
                LogsSheet(context: ctx)
                    .environmentObject(appState)
            }
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TaskSection: View {
    @EnvironmentObject private var appState: AppState
    let task: ECSTask
    let onDB: (ECSContainer) -> Void
    let onLogs: ([ECSContainer]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TASK")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(task.taskId)
                        .font(.system(.body, design: .monospaced))
                }
                Spacer()
                Button { onLogs(task.containers) } label: {
                    Label("All Logs", systemImage: "doc.text.magnifyingglass")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            ForEach(task.containers) { container in
                ContainerCard(
                    container: container,
                    onShell: { appState.launchShell(task: task, container: container) },
                    onDB: { onDB(container) },
                    onLogs: { onLogs([container]) }
                )
            }
        }
    }
}

struct ContainerCard: View {
    let container: ECSContainer
    let onShell: () -> Void
    let onDB: () -> Void
    let onLogs: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "shippingbox")
                    .foregroundColor(.accentColor)
                Text(container.name)
                    .fontWeight(.medium)
                Spacer()
            }

            HStack(spacing: 10) {
                Button(action: onShell) {
                    Label("Open Shell", systemImage: "terminal")
                }
                .buttonStyle(.borderedProminent)

                Button(action: onDB) {
                    Label("Port Forward (DB)", systemImage: "cylinder.split.1x2")
                }
                .buttonStyle(.bordered)

                Button(action: onLogs) {
                    Label("Logs", systemImage: "doc.text.magnifyingglass")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}
