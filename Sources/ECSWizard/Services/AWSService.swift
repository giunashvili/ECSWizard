import Foundation
import AWSECS
import AWSRDS
import AWSCloudWatchLogs
import SmithyIdentity

struct ContainerLogConfig {
    let logGroup: String
    let streamPrefix: String
}

class AWSService {
    private let ecsClient: ECSClient
    private let rdsClient: RDSClient
    private let cwlClient: CloudWatchLogsClient

    static func make(credentials: AWSCredentials, region: String) throws -> AWSService {
        let identity = AWSCredentialIdentity(
            accessKey: credentials.accessKeyId,
            secret: credentials.secretAccessKey,
            sessionToken: credentials.sessionToken
        )
        let resolver = StaticAWSCredentialIdentityResolver(identity)
        let ecsConfig = try ECSClient.ECSClientConfig(
            awsCredentialIdentityResolver: resolver,
            region: region
        )
        let rdsConfig = try RDSClient.RDSClientConfig(
            awsCredentialIdentityResolver: resolver,
            region: region
        )
        let cwlConfig = try CloudWatchLogsClient.CloudWatchLogsClientConfig(
            awsCredentialIdentityResolver: resolver,
            region: region
        )
        return AWSService(
            ecsClient: ECSClient(config: ecsConfig),
            rdsClient: RDSClient(config: rdsConfig),
            cwlClient: CloudWatchLogsClient(config: cwlConfig)
        )
    }

    private init(ecsClient: ECSClient, rdsClient: RDSClient, cwlClient: CloudWatchLogsClient) {
        self.ecsClient = ecsClient
        self.rdsClient = rdsClient
        self.cwlClient = cwlClient
    }

    func listClusters() async throws -> [ECSCluster] {
        let list = try await ecsClient.listClusters(input: ListClustersInput())
        let arns = list.clusterArns ?? []
        guard !arns.isEmpty else { return [] }

        let desc = try await ecsClient.describeClusters(
            input: DescribeClustersInput(clusters: arns)
        )
        return (desc.clusters ?? []).compactMap { c in
            guard let arn = c.clusterArn, let name = c.clusterName else { return nil }
            return ECSCluster(id: arn, arn: arn, name: name)
        }
    }

    func listServices(clusterArn: String) async throws -> [ECSService] {
        var all: [ECSService] = []
        var nextToken: String?

        repeat {
            let response = try await ecsClient.listServices(
                input: ListServicesInput(cluster: clusterArn, nextToken: nextToken)
            )
            let arns = response.serviceArns ?? []
            if !arns.isEmpty {
                let desc = try await ecsClient.describeServices(
                    input: DescribeServicesInput(cluster: clusterArn, services: arns)
                )
                let batch = (desc.services ?? []).compactMap { s -> ECSService? in
                    guard let arn = s.serviceArn, let name = s.serviceName else { return nil }
                    return ECSService(id: arn, arn: arn, name: name)
                }
                all.append(contentsOf: batch)
            }
            nextToken = response.nextToken
        } while nextToken != nil

        return all
    }

    func listTasks(clusterArn: String, serviceArn: String) async throws -> [ECSTask] {
        let serviceName = serviceArn.components(separatedBy: "/").last ?? serviceArn

        let list = try await ecsClient.listTasks(
            input: ListTasksInput(
                cluster: clusterArn,
                desiredStatus: .running,
                serviceName: serviceName
            )
        )
        let arns = list.taskArns ?? []
        guard !arns.isEmpty else { return [] }

        let desc = try await ecsClient.describeTasks(
            input: DescribeTasksInput(cluster: clusterArn, tasks: arns)
        )
        return (desc.tasks ?? []).compactMap { t -> ECSTask? in
            guard let arn = t.taskArn, let taskDefArn = t.taskDefinitionArn else { return nil }
            let taskId = arn.components(separatedBy: "/").last ?? arn
            let containers = (t.containers ?? []).compactMap { c -> ECSContainer? in
                guard let name = c.name, let runtimeId = c.runtimeId else { return nil }
                return ECSContainer(id: runtimeId, name: name, runtimeId: runtimeId)
            }
            return ECSTask(id: arn, taskArn: arn, taskId: taskId, taskDefinitionArn: taskDefArn, containers: containers)
        }
    }

    func getLogConfig(taskDefinitionArn: String, containerName: String) async throws -> ContainerLogConfig? {
        let response = try await ecsClient.describeTaskDefinition(
            input: DescribeTaskDefinitionInput(taskDefinition: taskDefinitionArn)
        )
        guard let containerDef = response.taskDefinition?.containerDefinitions?
                .first(where: { $0.name == containerName }),
              let logConfig = containerDef.logConfiguration,
              logConfig.logDriver?.rawValue == "awslogs",
              let options = logConfig.options,
              let logGroup = options["awslogs-group"],
              let streamPrefix = options["awslogs-stream-prefix"]
        else { return nil }
        return ContainerLogConfig(logGroup: logGroup, streamPrefix: streamPrefix)
    }

    // startFromHead is only meaningful on the first call (no token).
    // Pass forwardToken to tail new events; backwardToken to load older events.
    func fetchLogEvents(
        logGroup: String,
        logStream: String,
        containerName: String,
        nextToken: String?,
        startFromHead: Bool = false,
        limit: Int? = nil
    ) async throws -> (events: [LogEntry], forwardToken: String?, backwardToken: String?) {
        let input = GetLogEventsInput(
            limit: limit,
            logGroupName: logGroup,
            logStreamName: logStream,
            nextToken: nextToken,
            startFromHead: startFromHead
        )
        let response = try await cwlClient.getLogEvents(input: input)
        let entries: [LogEntry] = (response.events ?? []).compactMap { event -> LogEntry? in
            guard let message = event.message else { return nil }
            let ts = event.timestamp.map { Date(timeIntervalSince1970: Double($0) / 1000.0) } ?? Date()
            let id = "\(logStream)_\(ts.timeIntervalSince1970)_\(message.hashValue)"
            return LogEntry(id: id, timestamp: ts, message: message, containerName: containerName)
        }
        return (entries, response.nextForwardToken, response.nextBackwardToken)
    }

    // Strips the last segment of the cluster name (e.g. "falcon-dev-cluster" → "falcon-dev")
    // and returns RDS instances whose identifier contains that prefix.
    func findDBInstances(forCluster clusterName: String) async throws -> [RDSInstance] {
        let prefix = clusterName.components(separatedBy: "-").dropLast().joined(separator: "-")
        guard !prefix.isEmpty else { return [] }

        let response = try await rdsClient.describeDBInstances(input: DescribeDBInstancesInput())
        return (response.dbInstances ?? []).compactMap { inst in
            guard let identifier = inst.dbInstanceIdentifier,
                  identifier.contains(prefix),
                  let host = inst.endpoint?.address,
                  let port = inst.endpoint?.port
            else { return nil }
            return RDSInstance(identifier: identifier, host: host, port: port)
        }
    }
}
