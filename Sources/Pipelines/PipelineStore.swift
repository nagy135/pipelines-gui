import AppKit
import SwiftUI

@MainActor
final class PipelineStore: ObservableObject {
    @Published var repo: String
    @Published var localRepositoryPath: String
    @Published var provider: String
    @Published var resolvedProvider = ""
    @Published var filter = "active"
    @Published var limit: Int
    @Published var refreshInterval: Int
    @Published var logInterval: Int
    @Published var pipelines: [Pipeline] = []
    @Published var selectedPipelineID: Int?
    @Published var pipeline: Pipeline?
    @Published var jobs: [JobRow] = []
    @Published var selectedJobID: Int64?
    @Published var viewerMode = "logs"
    @Published var viewerText = ""
    @Published var viewerError: String?
    @Published var error: String?
    @Published var listLoading = false
    @Published var detailLoading = false
    @Published var viewerLoading = false
    @Published var lastUpdated: Date?
    @Published var snippets: [Int64: String] = [:]
    @Published var showInlineLogs = true
    @Published var now = Date()
    @Published var isDemo: Bool
    private var listToken = UUID()
    private var detailToken = UUID()
    private var viewerToken = UUID()
    private var snippetToken = UUID()
    private var lastListFetch = Date.distantPast
    private var lastDetailFetch = Date.distantPast
    private var lastLogFetch = Date.distantPast
    private var lastSnippetFetch = Date.distantPast
    private var snippetsLoading = false

    init(demo: Bool = ProcessInfo.processInfo.arguments.contains("--demo")) {
        isDemo = demo
        let defaults = UserDefaults.standard
        repo = defaults.string(forKey: "repository") ?? ""
        localRepositoryPath = defaults.string(forKey: "localRepositoryPath") ?? ""
        provider = defaults.string(forKey: "provider") ?? "auto"
        let configuredLimit = defaults.object(forKey: "limit") as? Int ?? Self.envInt("CI_TUI_LIMIT", legacy: "GLAB_TUI_LIMIT", fallback: 10)
        limit = min(100, max(1, configuredLimit))
        refreshInterval = defaults.object(forKey: "refresh") as? Int ?? Self.envInt("CI_TUI_REFRESH", legacy: "GLAB_TUI_REFRESH", fallback: 20)
        logInterval = Self.envInt("CI_TUI_LOG_REFRESH", legacy: "GLAB_TUI_LOG_REFRESH", fallback: 3)
        if demo { loadDemo() }
    }

    static func envInt(_ key: String, legacy: String, fallback: Int) -> Int {
        let env = ProcessInfo.processInfo.environment
        guard let value = Int(env[key] ?? env[legacy] ?? ""), value > 0 else { return fallback }
        return value
    }

    var selectedJob: JobRow? { jobs.first { $0.id == selectedJobID } }
    var stages: [String] { jobs.reduce(into: []) { if !$0.contains($1.current.stage) { $0.append($1.current.stage) } } }
    var displayProvider: String { (resolvedProvider.isEmpty ? provider : resolvedProvider) == "github" ? "GitHub Actions" : "GitLab CI" }

    func request(_ operation: String) -> BridgeRequest {
        BridgeRequest(operation: operation, provider: resolvedProvider.isEmpty ? provider : resolvedProvider,
                      repo: repo, status: filter, limit: limit, pipeline: pipeline, job: selectedJob?.logTarget)
    }

    func connect(repo value: String, provider chosenProvider: String, localPath: String = "") async {
        localRepositoryPath = localPath
        UserDefaults.standard.set(localPath, forKey: "localRepositoryPath")
        repo = value.trimmingCharacters(in: .whitespacesAndNewlines)
        provider = chosenProvider
        resolvedProvider = ""
        isDemo = false
        UserDefaults.standard.set(repo, forKey: "repository")
        UserDefaults.standard.set(provider, forKey: "provider")
        invalidate()
        pipelines = []
        selectedPipelineID = nil
        clearDetail()
        await loadList()
    }

    func connect(repository: LocalRepository) async {
        await connect(repo: repository.remote, provider: repository.provider, localPath: repository.path)
    }

    func invalidate() {
        listToken = UUID(); detailToken = UUID(); viewerToken = UUID(); snippetToken = UUID()
        listLoading = false; detailLoading = false; viewerLoading = false; snippetsLoading = false
    }

    func clearDetail() {
        detailToken = UUID(); viewerToken = UUID(); snippetToken = UUID()
        detailLoading = false; viewerLoading = false; snippetsLoading = false
        pipeline = nil; jobs = []; selectedJobID = nil; viewerText = ""; snippets = [:]
        viewerError = nil
    }

    func loadList() async {
        guard !repo.isEmpty, !isDemo, !listLoading else { return }
        let token = UUID(); listToken = token
        listLoading = true; lastListFetch = Date(); error = nil
        let input = request("list")
        do {
            let result = try await Bridge.send(input)
            guard listToken == token else { return }
            pipelines = result.pipelines ?? []
            resolvedProvider = result.provider
            lastUpdated = Date()
            // Keep an open pipeline visible in the detail pane if it leaves the active filter.
            if selectedPipelineID == nil, let first = pipelines.first { selectedPipelineID = first.id }
        } catch {
            guard listToken == token else { return }
            self.error = error.localizedDescription
        }
        if listToken == token { listLoading = false }
    }

    func changeFilter() async {
        listToken = UUID(); listLoading = false
        selectedPipelineID = nil; clearDetail()
        await loadList()
    }

    func selectPipeline(_ id: Int?) async {
        guard let id, let selected = pipelines.first(where: { $0.id == id }) else { return }
        if pipeline?.id != id { clearDetail(); pipeline = selected }
        await loadDetail()
    }

    func loadDetail() async {
        guard pipeline != nil, !isDemo, !detailLoading else { return }
        let token = UUID(); detailToken = token
        detailLoading = true; lastDetailFetch = Date()
        let input = request("detail")
        do {
            let result = try await Bridge.send(input)
            guard detailToken == token else { return }
            let oldStatus = selectedJob?.logTarget.status
            pipeline = result.pipeline; jobs = result.jobs ?? []; lastUpdated = Date(); error = nil
            if let updated = pipeline, let i = pipelines.firstIndex(where: { $0.id == updated.id }) { pipelines[i] = updated }
            if !jobs.contains(where: { $0.id == selectedJobID }) {
                selectedJobID = jobs.first(where: { $0.current.status == "failed" || $0.current.status == "running" })?.id ?? jobs.first?.id
            }
            if oldStatus == "running", selectedJob?.logTarget.status != "running", viewerMode == "logs" { Task { await loadViewer() } }
            Task { await loadSnippets() }
        } catch {
            guard detailToken == token else { return }
            self.error = error.localizedDescription
        }
        if detailToken == token { detailLoading = false }
    }

    func selectJob() async {
        viewerToken = UUID(); viewerLoading = false
        viewerText = ""; viewerError = nil
        if isDemo { viewerText = viewerMode == "logs" ? Self.demoLogs : Self.demoCode; return }
        await loadViewer()
    }

    func loadViewer() async {
        guard selectedJob != nil, !isDemo, !viewerLoading else { return }
        let token = UUID(); viewerToken = token
        viewerLoading = true; lastLogFetch = Date()
        let input = request(viewerMode)
        do {
            let result = try await Bridge.send(input)
            guard viewerToken == token else { return }
            viewerText = result.text ?? ""; viewerError = nil
        } catch {
            guard viewerToken == token else { return }
            viewerError = error.localizedDescription
        }
        if viewerToken == token { viewerLoading = false }
    }

    func loadSnippets() async {
        guard showInlineLogs, !snippetsLoading, !isDemo else { return }
        let targets = jobs.filter { $0.current.status == "running" || $0.current.status == "failed" }
        guard !targets.isEmpty else { return }
        let token = UUID(); snippetToken = token; snippetsLoading = true; lastSnippetFetch = Date()
        let base = request("tail")
        // Bound concurrent CLI processes to four even for pipelines with many jobs.
        for start in stride(from: 0, to: targets.count, by: 4) {
            let batch = Array(targets[start..<min(start + 4, targets.count)])
            let results = await withTaskGroup(of: (Int64, String?).self) { group in
                for row in batch {
                    var input = base; input.job = row.logTarget
                    group.addTask { (row.id, try? await Bridge.send(input).text) }
                }
                var values: [(Int64, String?)] = []
                for await value in group { values.append(value) }
                return values
            }
            guard snippetToken == token else { return }
            for (id, text) in results { if let text { snippets[id] = text } }
        }
        if snippetToken == token { snippetsLoading = false }
    }

    func refresh() async {
        guard !isDemo else { return }
        await loadList()
        await loadDetail()
        await loadViewer()
    }

    func tick() async {
        now = Date()
        guard !isDemo, !repo.isEmpty, refreshInterval > 0 else { return }
        if now.timeIntervalSince(lastListFetch) >= Double(refreshInterval) { Task { await loadList() } }
        if pipeline != nil, now.timeIntervalSince(lastDetailFetch) >= Double(refreshInterval) { Task { await loadDetail() } }
        if viewerMode == "logs", selectedJob?.logTarget.status == "running", now.timeIntervalSince(lastLogFetch) >= Double(logInterval) { Task { await loadViewer() } }
        if showInlineLogs, jobs.contains(where: { $0.current.status == "running" }), now.timeIntervalSince(lastSnippetFetch) >= Double(logInterval) { Task { await loadSnippets() } }
    }

    func saveSettings() {
        guard !isDemo else { return }
        UserDefaults.standard.set(limit, forKey: "limit")
        UserDefaults.standard.set(refreshInterval, forKey: "refresh")
    }

    func chooseRepositoryFolder() async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.prompt = "Choose Repository"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let remote: String? = try? await Task.detached {
            let process = Process(); let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", folder.path, "remote", "get-url", "origin"]
            process.standardOutput = output; process.standardError = FileHandle.nullDevice
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw BridgeError.message("No origin remote found.") }
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }.value
        if let remote, !remote.isEmpty { await connect(repo: remote, provider: "auto") }
        else { error = "That folder has no Git origin remote. Choose a cloned repository or enter its owner/project path." }
    }

    func loadDemo() {
        repo = "acme/platform"; provider = "gitlab"; resolvedProvider = "gitlab"
        filter = "all"
        let timestamp = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-94))
        let current = Pipeline(id: 8421, iid: 142, status: "running", ref: "main", sha: "8c12f4a9e1b2", source: "push", createdAt: timestamp, startedAt: timestamp,
                               commit: Commit(title: "Improve deployment health checks", authorName: "Alex Morgan"), commitTitle: "Improve deployment health checks")
        let older = Pipeline(id: 8420, status: "success", ref: "feature/cache", sha: "a21b794ee432", source: "merge_request_event", createdAt: timestamp, startedAt: timestamp, duration: 187,
                             commit: Commit(title: "Cache dependencies across builds", authorName: "Sam Lee"), commitTitle: "Cache dependencies across builds")
        pipelines = [current, older]; pipeline = current; selectedPipelineID = current.id
        let definitions: [(String, String, String, Double?)] = [("install dependencies", "prepare", "success", 24), ("lint", "verify", "success", 12), ("unit tests", "verify", "running", nil), ("build application", "build", "pending", nil), ("deploy production", "deploy", "manual", nil)]
        jobs = definitions.enumerated().map { i, item in
            let j = Job(id: Int64(12001 + i), name: item.0, status: item.2, stage: item.1, startedAt: item.2 == "running" ? timestamp : "", duration: item.3, pipeline: current)
            return JobRow(current: j, logTarget: j, status: j.status, typicalDuration: 145)
        }
        selectedJobID = jobs[2].id; viewerText = Self.demoLogs
        snippets[jobs[2].id] = "✓ Authentication tests (12)\n✓ Pipeline tests (28)\n✓ Deployment tests (9)\nRunning integration tests…"
        lastUpdated = Date()
    }

    static let demoLogs = """
    Running with gitlab-runner 18.3.0
    Preparing the docker executor
    Using Docker executor with image node:22-alpine …
    Getting source from Git repository
    Checking out 8c12f4a9 as detached HEAD (ref is main)…
    Restoring dependency cache
    Successfully extracted cache
    Executing the job script
    $ npm run test

     RUN  v3.2.4 /builds/acme/platform

     ✓ Authentication tests (12)      124ms
     ✓ Pipeline tests (28)            382ms
     ✓ Deployment tests (9)           206ms

    Running integration tests…
    """
    static let demoCode = """
    # job: unit tests
    # stage: verify

    # before_script
    npm ci --cache .npm --prefer-offline

    # script
    npm run test
    npm run test:integration
    """
}
