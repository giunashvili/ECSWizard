import Foundation

@MainActor
class AppState: ObservableObject {
    @Published var connections: [Connection] = []
    @Published var currentConnection: Connection?

    @Published var clusters: [ECSCluster] = []
    @Published var services: [String: [ECSService]] = [:]
    @Published var tasks: [ECSTask] = []

    @Published var selectedCluster: ECSCluster?
    @Published var selectedService: ECSService?

    @Published var isLoadingClusters = false
    @Published var isLoadingServices: Set<String> = []
    @Published var isLoadingTasks = false

    @Published var errorMessage: String?
    @Published var showingConnectionPicker = false

    private var awsService: AWSService?

    var isAuthenticated: Bool { currentConnection != nil }

    init() {
        connections = ConnectionsStore.load()
    }

    func connect(_ connection: Connection) {
        do {
            awsService = try AWSService.make(credentials: connection.credentials, region: connection.region)
            currentConnection = connection
            clusters = []
            services = [:]
            tasks = []
            selectedCluster = nil
            selectedService = nil
            errorMessage = nil
            Task { await loadClusters() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func disconnect() {
        currentConnection = nil
        awsService = nil
        clusters = []
        services = [:]
        tasks = []
        selectedCluster = nil
        selectedService = nil
        errorMessage = nil
    }

    func saveConnection(_ connection: Connection) {
        if let idx = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[idx] = connection
        } else {
            connections.append(connection)
        }
        ConnectionsStore.save(connections)
        if currentConnection?.id == connection.id {
            connect(connection)
        }
    }

    func deleteConnection(_ connection: Connection) {
        connections.removeAll { $0.id == connection.id }
        ConnectionsStore.save(connections)
        if currentConnection?.id == connection.id {
            disconnect()
        }
    }

    func loadClusters() async {
        guard let svc = awsService else { return }
        isLoadingClusters = true
        errorMessage = nil
        do {
            clusters = try await svc.listClusters()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingClusters = false
    }

    func loadServices(for cluster: ECSCluster) async {
        guard let svc = awsService else { return }
        guard services[cluster.arn] == nil else { return }
        isLoadingServices.insert(cluster.arn)
        do {
            services[cluster.arn] = try await svc.listServices(clusterArn: cluster.arn)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingServices.remove(cluster.arn)
    }

    func selectService(_ service: ECSService, in cluster: ECSCluster) {
        selectedCluster = cluster
        selectedService = service
        tasks = []
        Task { await loadTasks(clusterArn: cluster.arn, serviceArn: service.arn) }
    }

    private func loadTasks(clusterArn: String, serviceArn: String) async {
        guard let svc = awsService else { return }
        isLoadingTasks = true
        errorMessage = nil
        do {
            tasks = try await svc.listTasks(clusterArn: clusterArn, serviceArn: serviceArn)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingTasks = false
    }

    func launchShell(task: ECSTask, container: ECSContainer) {
        guard let cluster = selectedCluster, let conn = currentConnection else { return }
        ConnectionService.launchShell(
            cluster: cluster.name,
            taskArn: task.taskArn,
            containerName: container.name,
            region: conn.region,
            credentials: conn.credentials
        )
    }

    func getLogConfig(taskDefinitionArn: String, containerName: String) async throws -> ContainerLogConfig? {
        try await awsService?.getLogConfig(taskDefinitionArn: taskDefinitionArn, containerName: containerName)
    }

    func fetchLogEvents(logGroup: String, logStream: String, containerName: String, nextToken: String?, startFromHead: Bool, limit: Int? = nil) async throws -> ([LogEntry], String?, String?) {
        guard let svc = awsService else { return ([], nil, nil) }
        return try await svc.fetchLogEvents(logGroup: logGroup, logStream: logStream, containerName: containerName, nextToken: nextToken, startFromHead: startFromHead, limit: limit)
    }

    func findDBInstances() async -> [RDSInstance] {
        guard let svc = awsService, let cluster = selectedCluster else { return [] }
        return (try? await svc.findDBInstances(forCluster: cluster.name)) ?? []
    }

    func launchDBTunnel(task: ECSTask, container: ECSContainer, dbHost: String, dbPort: Int, localPort: Int) {
        guard let cluster = selectedCluster, let conn = currentConnection else { return }
        ConnectionService.launchDBTunnel(
            cluster: cluster.name,
            taskId: task.taskId,
            runtimeId: container.runtimeId,
            dbHost: dbHost,
            dbPort: dbPort,
            localPort: localPort,
            region: conn.region,
            credentials: conn.credentials
        )
    }
}
