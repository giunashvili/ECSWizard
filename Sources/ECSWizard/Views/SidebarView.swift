import SwiftUI

private let knownEnvironments = ["development", "staging", "prerelease", "production"]

private func envIcon(_ env: String) -> String {
    switch env {
    case "development":  return "hammer"
    case "staging":      return "tag"
    case "prerelease":   return "checkmark.seal"
    case "production":   return "shield.fill"
    default:             return "folder"
    }
}

private func shortName(_ name: String, env: String) -> String {
    name.replacingOccurrences(of: "-\(env)-", with: "-")
        .replacingOccurrences(of: "-\(env)", with: "")
        .replacingOccurrences(of: "\(env)-", with: "")
}

struct SidebarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        List {
            if appState.isLoadingClusters {
                ProgressView("Loading clusters…")
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(Array(appState.clusters.enumerated()), id: \.element.id) { index, cluster in
                    ClusterRow(cluster: cluster, isFirst: index == 0)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("ECS Wizard")
    }
}

struct ClusterRow: View {
    @EnvironmentObject private var appState: AppState
    let cluster: ECSCluster
    let isFirst: Bool
    @State private var isExpanded: Bool
    @State private var expandedEnvs: Set<String> = []

    init(cluster: ECSCluster, isFirst: Bool) {
        self.cluster = cluster
        self.isFirst = isFirst
        _isExpanded = State(initialValue: isFirst)
    }

    private var grouped: [(env: String, services: [ECSService])] {
        let all = appState.services[cluster.arn] ?? []
        var result: [(String, [ECSService])] = []
        for env in knownEnvironments {
            let matching = all.filter { $0.name.contains(env) }.sorted { $0.name < $1.name }
            if !matching.isEmpty { result.append((env, matching)) }
        }
        let ungrouped = all
            .filter { svc in !knownEnvironments.contains(where: { svc.name.contains($0) }) }
            .sorted { $0.name < $1.name }
        if !ungrouped.isEmpty { result.append(("other", ungrouped)) }
        return result
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if appState.isLoadingServices.contains(cluster.arn) {
                ProgressView().padding(.leading, 8)
            } else {
                ForEach(grouped, id: \.env) { group in
                    EnvironmentGroup(
                        env: group.env,
                        services: group.services,
                        cluster: cluster,
                        isExpanded: Binding(
                            get: { expandedEnvs.contains(group.env) },
                            set: { if $0 { expandedEnvs.insert(group.env) } else { expandedEnvs.remove(group.env) } }
                        )
                    )
                }
            }
        } label: {
            Label(cluster.name, systemImage: "server.rack").fontWeight(.medium)
        }
        .onAppear {
            if isFirst { Task { await appState.loadServices(for: cluster) } }
        }
        .onChange(of: isExpanded) { expanded in
            if expanded { Task { await appState.loadServices(for: cluster) } }
        }
        .onChange(of: appState.services[cluster.arn]) { _ in
            if isFirst, expandedEnvs.isEmpty, let firstEnv = grouped.first?.env {
                expandedEnvs.insert(firstEnv)
            }
        }
    }
}

struct EnvironmentGroup: View {
    let env: String
    let services: [ECSService]
    let cluster: ECSCluster
    @Binding var isExpanded: Bool

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(services) { service in
                ServiceRow(service: service, cluster: cluster, displayName: shortName(service.name, env: env))
            }
        } label: {
            Label(env.capitalized, systemImage: envIcon(env))
                .foregroundColor(.secondary)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { isExpanded.toggle() }
        }
        .padding(.leading, 4)
    }
}

struct ServiceRow: View {
    @EnvironmentObject private var appState: AppState
    let service: ECSService
    let cluster: ECSCluster
    let displayName: String

    var isSelected: Bool { appState.selectedService?.id == service.id }

    var body: some View {
        Button {
            appState.selectService(service, in: cluster)
        } label: {
            Label(displayName, systemImage: "square.stack.3d.up")
                .foregroundColor(isSelected ? .accentColor : .primary)
        }
        .buttonStyle(.plain)
        .padding(.leading, 8)
    }
}
