import AppKit

enum ConnectionService {
    static func launchShell(
        cluster: String,
        taskArn: String,
        containerName: String,
        region: String,
        credentials: AWSCredentials?
    ) {
        let command = [
            "aws ecs execute-command",
            "--cluster '\(cluster)'",
            "--task '\(taskArn)'",
            "--container '\(containerName)'",
            "--command '/bin/sh -c \"su - \(containerName) || exec /bin/sh\"'",
            "--interactive",
            "--region '\(region)'"
        ].joined(separator: " ")

        launchViaScript(credentials: credentials, command: command)
    }

    static func launchDBTunnel(
        cluster: String,
        taskId: String,
        runtimeId: String,
        dbHost: String,
        dbPort: Int,
        localPort: Int,
        region: String,
        credentials: AWSCredentials?
    ) {
        let target = "ecs:\(cluster)_\(taskId)_\(runtimeId)"
        let command = [
            "aws ssm start-session",
            "--target '\(target)'",
            "--document-name AWS-StartPortForwardingSessionToRemoteHost",
            "--parameters 'host=\(dbHost),portNumber=\(dbPort),localPortNumber=\(localPort)'",
            "--region '\(region)'"
        ].joined(separator: " ")

        launchViaScript(credentials: credentials, command: command)
    }

    // Writes a temp script to avoid 'do script' length limits in AppleScript
    private static func launchViaScript(credentials: AWSCredentials?, command: String) {
        var lines = ["#!/bin/bash"]
        if let c = credentials {
            // Single-quoted values are safe: AWS credentials use only Base64 chars
            lines.append("export AWS_ACCESS_KEY_ID='\(c.accessKeyId)'")
            lines.append("export AWS_SECRET_ACCESS_KEY='\(c.secretAccessKey)'")
            if let token = c.sessionToken { lines.append("export AWS_SESSION_TOKEN='\(token)'") }
        }
        lines.append(command)

        let path = "/tmp/ecs-wizard-\(Int.random(in: 100_000...999_999)).sh"
        let content = lines.joined(separator: "\n") + "\n"

        do {
            try content.write(toFile: path, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path)
        } catch {
            return
        }

        let appleScript = """
        set wasRunning to application "Terminal" is running
        tell application "Terminal"
            activate
            if wasRunning then
                do script "bash \(path); rm -f \(path)"
            else
                do script "bash \(path); rm -f \(path)" in window 1
            end if
        end tell
        """

        if let script = NSAppleScript(source: appleScript) {
            var errorInfo: NSDictionary?
            script.executeAndReturnError(&errorInfo)
        }
    }
}
