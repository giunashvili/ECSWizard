import SwiftUI

// MARK: - Connections list

struct ConnectionsView: View {
    @EnvironmentObject private var appState: AppState
    var onConnected: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil

    // Identifiable wrapper so .sheet(item:) always creates a fresh form
    private struct FormTarget: Identifiable {
        let id = UUID()
        let connection: Connection?
    }
    @State private var formTarget: FormTarget? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("ECS Wizard").font(.title).fontWeight(.bold)

            if appState.connections.isEmpty {
                VStack(spacing: 16) {
                    Text("No connections yet.").foregroundColor(.secondary)
                    Button {
                        formTarget = FormTarget(connection: nil)
                    } label: {
                        Label("Add Connection", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 6) {
                    ForEach(appState.connections) { conn in
                        ConnectionRow(
                            connection: conn,
                            isCurrent: conn.id == appState.currentConnection?.id,
                            onConnect: {
                                appState.connect(conn)
                                onConnected?()
                            },
                            onEdit: { formTarget = FormTarget(connection: conn) },
                            onDelete: { appState.deleteConnection(conn) }
                        )
                    }
                }

                if let error = appState.errorMessage {
                    Text(error).foregroundColor(.red).font(.caption)
                }

                HStack(spacing: 8) {
                    Button {
                        formTarget = FormTarget(connection: nil)
                    } label: {
                        Label("New Connection", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)

                    if let dismiss = onDismiss {
                        Button("Close", action: dismiss)
                            .buttonStyle(.bordered)
                            .keyboardShortcut(.escape, modifiers: [])
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(28)
        .sheet(item: $formTarget) { target in
            ConnectionFormView(
                connection: target.connection,
                onSave: { conn in
                    appState.saveConnection(conn)
                    formTarget = nil
                },
                onCancel: { formTarget = nil }
            )
        }
    }
}

// MARK: - Connection row

private struct ConnectionRow: View {
    let connection: Connection
    let isCurrent: Bool
    let onConnect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    private enum TestStatus { case idle, testing, success, failed }
    @State private var testStatus: TestStatus = .idle

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isCurrent ? "bolt.fill" : "bolt")
                .foregroundColor(isCurrent ? .accentColor : .secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(connection.name).fontWeight(.medium)
                Text(connection.region).font(.caption).foregroundColor(.secondary)
            }

            Spacer()

            // Test button
            Button { runTest() } label: {
                switch testStatus {
                case .idle:
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundColor(.secondary)
                case .testing:
                    ProgressView().controlSize(.small)
                case .success:
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                case .failed:
                    Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                }
            }
            .buttonStyle(.borderless)
            .help("Test connection")

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("Edit")

            Button(action: onDelete) {
                Image(systemName: "trash").foregroundColor(.red)
            }
            .buttonStyle(.borderless)
            .help("Delete")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { onConnect() }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isCurrent ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isCurrent ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    private func runTest() {
        guard testStatus != .testing else { return }
        testStatus = .testing
        Task {
            guard let svc = try? AWSService.make(credentials: connection.credentials, region: connection.region),
                  (try? await svc.listClusters()) != nil
            else {
                testStatus = .failed
                return
            }
            testStatus = .success
        }
    }
}

// MARK: - Add / edit form

struct ConnectionFormView: View {
    let connection: Connection?
    let onSave: (Connection) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var credentialsText: String
    @State private var region: String
    @State private var parseError = false

    init(connection: Connection?, onSave: @escaping (Connection) -> Void, onCancel: @escaping () -> Void) {
        self.connection = connection
        self.onSave = onSave
        self.onCancel = onCancel

        if let c = connection {
            _name = State(initialValue: c.name)
            var lines = [
                "export AWS_ACCESS_KEY_ID=\(c.credentials.accessKeyId)",
                "export AWS_SECRET_ACCESS_KEY=\(c.credentials.secretAccessKey)",
            ]
            if let token = c.credentials.sessionToken {
                lines.append("export AWS_SESSION_TOKEN=\(token)")
            }
            _credentialsText = State(initialValue: lines.joined(separator: "\n"))
            _region = State(initialValue: c.region)
        } else {
            _name = State(initialValue: "")
            _credentialsText = State(initialValue: "")
            _region = State(initialValue: "us-east-1")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(connection == nil ? "New Connection" : "Edit Connection")
                .font(.title2).fontWeight(.semibold)

            field(label: "Name") {
                TextField("Production", text: $name)
            }

            TextEditor(text: $credentialsText)
                .font(.system(size: 13, design: .monospaced))
                .frame(height: 110)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color(NSColor.textBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3), lineWidth: 1))

            field(label: "Region") {
                TextField("us-east-1", text: $region).frame(width: 160)
            }

            if parseError {
                Text("Could not parse credentials — paste the full export block.")
                    .foregroundColor(.red).font(.caption)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.escape, modifiers: [])
                Button("Save") { handleSave() }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty ||
                              credentialsText.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(28)
        .frame(width: 500)
    }

    @ViewBuilder
    private func field<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(label).frame(width: 65, alignment: .leading)
            content()
                .textFieldStyle(.plain)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
        }
    }

    private func handleSave() {
        guard let creds = AWSCredentials.parse(from: credentialsText) else {
            parseError = true
            return
        }
        parseError = false
        onSave(Connection(
            id: connection?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            credentials: creds,
            region: region.trimmingCharacters(in: .whitespaces)
        ))
    }
}
