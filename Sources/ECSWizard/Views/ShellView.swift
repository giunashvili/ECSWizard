import SwiftUI
import SwiftTerm

struct ShellContext: Identifiable {
    let id = UUID()
    let task: ECSTask
    let container: ECSContainer
    let clusterName: String
    let region: String
    let credentials: AWSCredentials?
}

struct TerminalViewWrapper: NSViewRepresentable {
    let context: ShellContext

    private func findAWS() -> String? {
        ["/usr/local/bin/aws", "/opt/homebrew/bin/aws", "/usr/bin/aws"]
            .first { FileManager.default.fileExists(atPath: $0) }
    }

    func makeNSView(context ctx: NSViewRepresentableContext<TerminalViewWrapper>) -> LocalProcessTerminalView {
        let tv = LocalProcessTerminalView(frame: .zero)
        let coordinator = ctx.coordinator
        coordinator.terminalView = tv
        tv.processDelegate = coordinator

        guard let awsPath = findAWS() else { return tv }

        var env = ProcessInfo.processInfo.environment
        let existing = env["PATH"] ?? ""
        env["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:\(existing)"
        env["AWS_DEFAULT_REGION"] = context.region

        if let creds = context.credentials {
            env["AWS_ACCESS_KEY_ID"]     = creds.accessKeyId
            env["AWS_SECRET_ACCESS_KEY"] = creds.secretAccessKey
            if let token = creds.sessionToken {
                env["AWS_SESSION_TOKEN"] = token
            } else {
                env.removeValue(forKey: "AWS_SESSION_TOKEN")
            }
        }

        let envList = env.map { "\($0.key)=\($0.value)" }
        let args = [
            "ecs", "execute-command",
            "--cluster", context.clusterName,
            "--task",    context.task.taskArn,
            "--container", context.container.name,
            "--interactive",
            "--command", "/bin/sh"
        ]
        tv.startProcess(executable: awsPath, args: args, environment: envList)

        // Wait for the SSM connection to establish, then switch to the container user.
        // su - does a login shell so it also handles cd ~ automatically.
        let containerName = context.container.name
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak coordinator] in
            guard let tv = coordinator?.terminalView, tv.process.running else { return }
            let cmd = Array("su - \(containerName)\n".utf8)
            tv.process.send(data: cmd[...])
        }

        return tv
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: NSViewRepresentableContext<TerminalViewWrapper>) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        weak var terminalView: LocalProcessTerminalView?

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func processTerminated(source: TerminalView, exitCode: Int32?) {}
    }
}

struct FullScreenShellView: View {
    let context: ShellContext
    var body: some View {
        TerminalViewWrapper(context: context)
    }
}

func openShellWindow(context: ShellContext) {
    let controller = NSHostingController(rootView: FullScreenShellView(context: context))
    let window = NSWindow(contentViewController: controller)
    window.title = "\(context.container.name) — Shell"
    window.setContentSize(NSSize(width: 900, height: 600))
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    window.collectionBehavior = [.fullScreenPrimary]
    window.center()
    window.makeKeyAndOrderFront(nil)
}
