// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ECSWizard",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(
            url: "https://github.com/awslabs/aws-sdk-swift",
            from: "1.0.0"
        ),
        .package(
            url: "https://github.com/smithy-lang/smithy-swift",
            exact: "0.203.0"
        ),
    ],
    targets: [
        .executableTarget(
            name: "ECSWizard",
            dependencies: [
                .product(name: "AWSECS", package: "aws-sdk-swift"),
                .product(name: "AWSRDS", package: "aws-sdk-swift"),
                .product(name: "AWSCloudWatchLogs", package: "aws-sdk-swift"),
                .product(name: "SmithyIdentity", package: "smithy-swift"),
            ],
            path: "Sources/ECSWizard"
        ),
    ]
)
