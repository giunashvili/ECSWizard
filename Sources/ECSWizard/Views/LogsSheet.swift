import SwiftUI

// MARK: - Supporting types

struct LogsContext: Identifiable {
    let id = UUID()
    let task: ECSTask
    let containers: [ECSContainer]
    var title: String { containers.count == 1 ? containers[0].name : "All Containers" }
}

enum TimeFilter: String, CaseIterable {
    case all = "All", last5 = "5m", last10 = "10m", last15 = "15m"
    var interval: TimeInterval? {
        switch self {
        case .all:    return nil
        case .last5:  return 5  * 60
        case .last10: return 10 * 60
        case .last15: return 15 * 60
        }
    }
}

// MARK: - ViewModel

@MainActor
class LogsViewModel: ObservableObject {
    @Published var entries: [LogEntry] = []
    @Published var isLoading = true
    @Published var isLoadingNewer = false
    @Published var isLoadingOlder = false
    @Published var isLoadingAll = false
    @Published var error: String?
    @Published private(set) var isTailing = false
    @Published var timeFilter: TimeFilter = .all

    private var task: ECSTask?
    private var streamMap: [(container: ECSContainer, config: ContainerLogConfig)] = []
    private var forwardTokens:  [String: String] = [:]
    private var backwardTokens: [String: String] = [:]
    private var tailTask: Task<Void, Never>?
    private var getEventsFn: ((String, String, String, String?, Bool, Int?) async throws -> ([LogEntry], String?, String?))?

    var displayedEntries: [LogEntry] {
        guard let interval = timeFilter.interval else { return entries }
        let cutoff = Date().addingTimeInterval(-interval)
        return entries.filter { $0.timestamp >= cutoff }
    }

    func start(
        task: ECSTask,
        targetContainers: [ECSContainer],
        getConfig: @escaping (String, String) async throws -> ContainerLogConfig?,
        getEvents: @escaping (String, String, String, String?, Bool, Int?) async throws -> ([LogEntry], String?, String?)
    ) {
        self.task = task
        self.getEventsFn = getEvents
        isLoading = true
        error = nil

        Task { [weak self] in
            guard let self else { return }

            var map: [(container: ECSContainer, config: ContainerLogConfig)] = []
            for container in targetContainers {
                if let config = try? await getConfig(task.taskDefinitionArn, container.name) {
                    map.append((container: container, config: config))
                }
            }
            self.streamMap = map

            guard !map.isEmpty else {
                self.error = "No CloudWatch log configuration found"
                self.isLoading = false
                return
            }

            // Initial load: most recent events (startFromHead: false)
            var initial: [LogEntry] = []
            for item in map {
                let stream = streamName(item.container, item.config, task)
                if let (events, fwd, bwd) = try? await getEvents(item.config.logGroup, stream, item.container.name, nil, false, 20) {
                    initial.append(contentsOf: events)
                    if let t = fwd { self.forwardTokens[stream] = t }
                    if let t = bwd { self.backwardTokens[stream] = t }
                }
            }
            self.entries = initial.sorted { $0.timestamp > $1.timestamp }
            self.isLoading = false
        }
    }

    // Top button — fetch events newer than current window
    func loadNewer() {
        guard let task, let getEvents = getEventsFn, !isLoadingNewer else { return }
        isLoadingNewer = true
        Task { [weak self] in
            guard let self else { return }
            var fresh: [LogEntry] = []
            for item in streamMap {
                let stream = streamName(item.container, item.config, task)
                if let (events, fwd, _) = try? await getEvents(item.config.logGroup, stream, item.container.name, forwardTokens[stream], true, nil) {
                    fresh.append(contentsOf: events)
                    if let t = fwd { forwardTokens[stream] = t }
                }
            }
            if !fresh.isEmpty {
                entries.append(contentsOf: fresh)
                entries.sort { $0.timestamp > $1.timestamp }
            }
            isLoadingNewer = false
        }
    }

    // Bottom button — fetch events older than current window
    func loadOlder() {
        guard let task, let getEvents = getEventsFn, !isLoadingOlder else { return }
        isLoadingOlder = true
        Task { [weak self] in
            guard let self else { return }
            var older: [LogEntry] = []
            for item in streamMap {
                let stream = streamName(item.container, item.config, task)
                if let (events, _, bwd) = try? await getEvents(item.config.logGroup, stream, item.container.name, backwardTokens[stream], false, nil) {
                    older.append(contentsOf: events)
                    if let t = bwd { backwardTokens[stream] = t }
                }
            }
            if !older.isEmpty {
                entries = (older + entries).sorted { $0.timestamp > $1.timestamp }
            }
            isLoadingOlder = false
        }
    }

    // Bottom button — reload from the very beginning of the stream
    func loadAll() {
        guard let task, let getEvents = getEventsFn, !isLoadingAll else { return }
        stopTailing()
        entries = []
        forwardTokens = [:]
        backwardTokens = [:]
        isLoadingAll = true
        Task { [weak self] in
            guard let self else { return }
            var all: [LogEntry] = []
            for item in streamMap {
                let stream = streamName(item.container, item.config, task)
                if let (events, fwd, bwd) = try? await getEvents(item.config.logGroup, stream, item.container.name, nil, true, nil) {
                    all.append(contentsOf: events)
                    if let t = fwd { forwardTokens[stream] = t }
                    if let t = bwd { backwardTokens[stream] = t }
                }
            }
            entries = all.sorted { $0.timestamp > $1.timestamp }
            isLoadingAll = false
        }
    }

    func toggleTailing() {
        if isTailing { stopTailing() } else { startTailing() }
    }

    func clear() { entries = [] }

    func stop() {
        tailTask?.cancel()
        tailTask = nil
    }

    private func startTailing() {
        guard let task, let getEvents = getEventsFn else { return }
        isTailing = true
        tailTask?.cancel()
        tailTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }
                guard let self, self.isTailing else { return }
                var fresh: [LogEntry] = []
                for item in self.streamMap {
                    let stream = self.streamName(item.container, item.config, task)
                    if let (events, fwd, _) = try? await getEvents(item.config.logGroup, stream, item.container.name, self.forwardTokens[stream], true, nil) {
                        fresh.append(contentsOf: events)
                        if let t = fwd { self.forwardTokens[stream] = t }
                    }
                }
                if !fresh.isEmpty {
                    self.entries.append(contentsOf: fresh)
                    self.entries.sort { $0.timestamp > $1.timestamp }
                }
            }
        }
    }

    private func stopTailing() {
        isTailing = false
        tailTask?.cancel()
        tailTask = nil
    }

    private func streamName(_ container: ECSContainer, _ config: ContainerLogConfig, _ task: ECSTask) -> String {
        "\(config.streamPrefix)/\(container.name)/\(task.taskId)"
    }
}

// MARK: - View

struct LogsSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = LogsViewModel()

    let context: LogsContext
    @State private var filterText = ""
    @State private var showTimestamps = true

    private var displayedEntries: [LogEntry] {
        let base = vm.displayedEntries
        guard !filterText.isEmpty else { return base }
        return base.filter { $0.message.localizedCaseInsensitiveContains(filterText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            logArea
        }
        .frame(minWidth: 1100, minHeight: 500)
        .task {
            vm.start(
                task: context.task,
                targetContainers: context.containers,
                getConfig: { taskDefArn, name in
                    try await appState.getLogConfig(taskDefinitionArn: taskDefArn, containerName: name)
                },
                getEvents: { logGroup, logStream, containerName, token, startFromHead, limit in
                    try await appState.fetchLogEvents(
                        logGroup: logGroup, logStream: logStream,
                        containerName: containerName, nextToken: token, startFromHead: startFromHead, limit: limit
                    )
                }
            )
        }
        .onDisappear { vm.stop() }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            Text(context.title).fontWeight(.semibold)
            Spacer()
            HStack(spacing: 4) {
                ForEach(TimeFilter.allCases, id: \.self) { filter in
                    Button(filter.rawValue) { vm.timeFilter = filter }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(vm.timeFilter == filter ? .accentColor : nil)
                }
            }
            Divider().frame(height: 16)
            TextField("Filter…", text: $filterText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)
            Toggle("Timestamps", isOn: $showTimestamps)
                .toggleStyle(.checkbox)
                .controlSize(.small)
            TailButton(isTailing: vm.isTailing, action: vm.toggleTailing)
            Button("Clear") { vm.clear() }
                .buttonStyle(.bordered)
                .controlSize(.small)
            Button { dismiss() } label: { Image(systemName: "xmark") }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: Log area

    @ViewBuilder
    private var logArea: some View {
        if vm.isLoading || vm.isLoadingAll {
            ProgressView(vm.isLoadingAll ? "Loading all logs…" : "Loading logs…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.error {
            Text(err).foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {

                        // ── Top: load newer ──────────────────────────────
                        Button(action: vm.loadNewer) {
                            if vm.isLoadingNewer {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Load More", systemImage: "arrow.up.circle")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .disabled(vm.isLoadingNewer)

                        Divider()

                        // ── Log entries ──────────────────────────────────
                        if displayedEntries.isEmpty {
                            Text(vm.timeFilter == .all
                                 ? "No log events found"
                                 : "No events in the last \(vm.timeFilter.rawValue)")
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(20)
                        } else {
                            ForEach(displayedEntries) { entry in
                                LogRow(
                                    entry: entry,
                                    showTimestamp: showTimestamps,
                                    showContainer: context.containers.count > 1
                                )
                                .id(entry.id)
                            }
                        }

                        Divider()

                        // ── Bottom: older / all ──────────────────────────
                        HStack(spacing: 8) {
                            Button(action: vm.loadOlder) {
                                if vm.isLoadingOlder {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Label("Older Logs", systemImage: "arrow.down.circle")
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(vm.isLoadingOlder)

                            Button(action: vm.loadAll) {
                                Label("All Logs", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(vm.isLoadingAll)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: vm.entries.count) { _ in
                    if vm.isTailing, let first = displayedEntries.first {
                        withAnimation { proxy.scrollTo(first.id, anchor: .top) }
                    }
                }
            }
        }
    }
}

// MARK: - Tail button

private struct TailButton: View {
    let isTailing: Bool
    let action: () -> Void
    @State private var ripple = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                ZStack {
                    if isTailing {
                        Circle()
                            .fill(Color.red.opacity(0.25))
                            .frame(width: 16, height: 16)
                            .scaleEffect(ripple ? 2.2 : 1.0)
                            .opacity(ripple ? 0 : 0.8)
                    }
                    Circle()
                        .fill(isTailing ? Color.red : Color.secondary.opacity(0.45))
                        .frame(width: 8, height: 8)
                }
                .frame(width: 16, height: 16)
                Text("Tail")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(isTailing ? .red : nil)
        .onChange(of: isTailing) { active in
            ripple = false
            if active {
                withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) {
                    ripple = true
                }
            }
        }
    }
}

// MARK: - Log row

private let containerColors: [Color] = [.blue, .green, .orange, .purple, .cyan, .pink]

private func containerColor(for name: String) -> Color {
    containerColors[abs(name.hashValue) % containerColors.count]
}

private struct LogRow: View {
    let entry: LogEntry
    let showTimestamp: Bool
    let showContainer: Bool

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if showTimestamp {
                Text(Self.timeFmt.string(from: entry.timestamp))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 96, alignment: .leading)
            }
            if showContainer {
                Text(entry.containerName)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(containerColor(for: entry.containerName))
                    .frame(width: 110, alignment: .leading)
                    .lineLimit(1)
            }
            Text(entry.message)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }
}
