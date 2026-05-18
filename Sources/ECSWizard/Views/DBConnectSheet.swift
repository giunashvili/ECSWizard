import SwiftUI

struct DBConnectSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let task: ECSTask
    let container: ECSContainer

    @State private var dbHost = ""
    @State private var remotePort = ""
    @State private var localPort = "33066"
    @State private var instances: [RDSInstance] = []
    @State private var selectedIdentifier = ""
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Port Forward to Database")
                .font(.title2)
                .fontWeight(.semibold)

            if isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Looking up RDS instances…")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    if !instances.isEmpty {
                        GridRow {
                            Text("Instance").frame(width: 90, alignment: .leading)
                            Picker("", selection: $selectedIdentifier) {
                                ForEach(instances) { inst in
                                    Text(inst.identifier).tag(inst.identifier)
                                }
                            }
                            .onChange(of: selectedIdentifier) { id in
                                if let inst = instances.first(where: { $0.identifier == id }) {
                                    dbHost = inst.host
                                    remotePort = String(inst.port)
                                }
                            }
                        }
                    }
                    GridRow {
                        Text("DB Host").frame(width: 90, alignment: .leading)
                        TextField("e.g. mydb.cluster.us-east-1.rds.amazonaws.com", text: $dbHost)
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("Remote Port").frame(width: 90, alignment: .leading)
                        TextField("5432", text: $remotePort)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                    GridRow {
                        Text("Local Port").frame(width: 90, alignment: .leading)
                        TextField("33066", text: $localPort)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                }
            }

            Spacer()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                Spacer()
                Button("Connect") { connect() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading
                              || dbHost.trimmingCharacters(in: .whitespaces).isEmpty
                              || Int(remotePort) == nil
                              || Int(localPort) == nil)
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(24)
        .frame(width: 520, height: 260)
        .task {
            let found = await appState.findDBInstances()
            instances = found
            if let first = found.first {
                selectedIdentifier = first.identifier
                dbHost = first.host
                remotePort = String(first.port)
            }
            isLoading = false
        }
    }

    private func connect() {
        guard let remote = Int(remotePort), let local = Int(localPort) else { return }
        appState.launchDBTunnel(
            task: task,
            container: container,
            dbHost: dbHost.trimmingCharacters(in: .whitespaces),
            dbPort: remote,
            localPort: local
        )
        dismiss()
    }
}
