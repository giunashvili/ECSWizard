import Foundation

struct ECSCluster: Identifiable, Hashable {
    let id: String
    let arn: String
    let name: String
}

struct ECSService: Identifiable, Hashable {
    let id: String
    let arn: String
    let name: String
}

struct ECSTask: Identifiable, Hashable {
    let id: String
    let taskArn: String
    let taskId: String
    let taskDefinitionArn: String
    let containers: [ECSContainer]
}

struct LogEntry: Identifiable, Equatable {
    let id: String
    let timestamp: Date
    let message: String
    let containerName: String
}

struct ECSContainer: Identifiable, Hashable {
    let id: String
    let name: String
    let runtimeId: String
}

struct RDSInstance: Identifiable, Hashable {
    var id: String { identifier }
    let identifier: String
    let host: String
    let port: Int
}

