import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var store = PipelineStore()
    private enum Sheet: String, Identifiable {
        case connection, projects, shortcuts
        var id: String { rawValue }
    }
    @State private var activeSheet: Sheet?
    @State private var projectSearchRequest = UUID()
    @State private var viewerSearch = ""
    @State private var matchIndex = 0
    @State private var wrap = true
    @State private var lineNumbers = true
    @State private var follow = true

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 420)
        } detail: {
            VStack(spacing: 0) {
                if store.isDemo { demoBanner }
                if let error = store.error { errorBanner(error) }
                if let pipeline = store.pipeline {
                    pipelineHeader(pipeline)
                    Divider()
                    VSplitView {
                        jobsPane.frame(minHeight: 180, idealHeight: 340)
                        viewer.frame(minHeight: 200, idealHeight: 340)
                    }
                } else {
                    emptyDetail.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Divider()
                statusBar
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .navigationTitle("Pipelines")
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { activeSheet = .projects } label: { Label("Switch Repository", systemImage: "arrow.left.arrow.right") }
                    .keyboardShortcut("k").help("Find project (⌘F or ⌘K)")
                Button { activeSheet = .connection } label: { Label("Repository", systemImage: "folder.badge.gearshape") }
                    .help("Connect to a repository")
                Menu {
                    Picker("Pipeline limit", selection: $store.limit) {
                        ForEach([10, 20, 30, 50, 100], id: \.self) { Text("\($0) pipelines").tag($0) }
                    }
                    Picker("Refresh", selection: $store.refreshInterval) {
                        Text("Paused").tag(0)
                        ForEach([5, 10, 20, 30, 60, 120], id: \.self) { Text("Every \($0) seconds").tag($0) }
                    }
                    Toggle("Inline log previews", isOn: $store.showInlineLogs)
                } label: { Label("View Options", systemImage: "slider.horizontal.3") }
                Button { Task { await store.refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .keyboardShortcut("r")
                    .disabled(store.repo.isEmpty || store.isDemo)
                Button { activeSheet = .shortcuts } label: { Label("Keyboard Shortcuts", systemImage: "questionmark.circle") }
                    .help("Keyboard shortcuts (?)")
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .connection: ConnectionView(store: store)
            case .projects:
                RepositorySwitcher(store: store, searchRequest: projectSearchRequest).environmentObject(settings)
            case .shortcuts: KeyboardShortcutsView()
            }
        }
        .background {
            ProjectSearchShortcut(open: {
                activeSheet = .projects
                projectSearchRequest = UUID()
            }, showHelp: {
                activeSheet = activeSheet == .shortcuts ? nil : .shortcuts
            })
        }
        .task {
            Task { await settings.scan() }
            if !store.repo.isEmpty && !store.isDemo { await store.loadList() }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                await store.tick()
            }
        }
        .onChange(of: store.selectedPipelineID) { _, id in Task { await store.selectPipeline(id) } }
        .onChange(of: store.selectedJobID) { _, _ in
            viewerSearch = ""; matchIndex = 0
            Task { await store.selectJob() }
        }
        .onChange(of: store.viewerMode) { _, _ in matchIndex = 0; Task { await store.selectJob() } }
        .onChange(of: store.filter) { _, _ in Task { await store.changeFilter() } }
        .onChange(of: store.limit) { _, _ in store.saveSettings(); Task { await store.loadList() } }
        .onChange(of: store.refreshInterval) { _, _ in store.saveSettings() }
        .onChange(of: store.showInlineLogs) { _, enabled in if enabled { Task { await store.loadSnippets() } } }
        .onChange(of: viewerSearch) { _, _ in matchIndex = 0 }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.branch").foregroundStyle(.tint)
                    Button { activeSheet = .projects } label: { VStack(alignment: .leading, spacing: 3) {
                        Text(store.repo.isEmpty ? "No repository" : repositoryName).font(.headline).lineLimit(1).help(store.repo)
                        Text(store.repo.isEmpty ? "Connect to get started" : store.displayProvider).font(.caption).foregroundStyle(.secondary)
                    } }.buttonStyle(.plain).help("Find project (⌘F or ⌘K)")
                    Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    if store.listLoading { ProgressView().controlSize(.small) }
                }
                Picker("Status", selection: $store.filter) {
                    Text("Active").tag("active")
                    Text("All pipelines").tag("all")
                    Divider()
                    ForEach(["running", "pending", "manual", "success", "failed", "canceled", "skipped"], id: \.self) { Text($0.capitalized).tag($0) }
                }
                .labelsHidden()
            }
            .padding(16)
            Divider()
            if store.pipelines.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: store.repo.isEmpty ? "folder" : "tray").font(.system(size: 30)).foregroundStyle(.tertiary)
                    Text(store.listLoading ? "Loading pipelines…" : "No pipelines found").font(.callout).foregroundStyle(.secondary)
                    if !store.repo.isEmpty && store.filter == "active" && !store.listLoading {
                        Button("Show all pipelines") { store.filter = "all" }
                    }
                    if store.repo.isEmpty { Button("Choose Repository") { activeSheet = .projects } }
                }
                .padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $store.selectedPipelineID) {
                    ForEach(store.pipelines) { p in
                        PipelineListRow(pipeline: p, now: store.now).tag(p.id)
                    }
                }
                .listStyle(.sidebar)
            }
            Divider()
            HStack {
                Text("\(store.pipelines.count) pipelines").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { activeSheet = .projects } label: { Image(systemName: "folder.badge.plus") }
                    .buttonStyle(.plain).help("Switch repository")
            }.padding(12)
        }
    }

    private var repositoryName: String {
        if let local = settings.repositories.first(where: { $0.path == store.localRepositoryPath }) { return local.name }
        var value = store.repo
        if let url = URL(string: value), url.host != nil { value = url.path }
        else if value.contains("@"), let colon = value.lastIndex(of: ":") { value = String(value[value.index(after: colon)...]) }
        return value.replacingOccurrences(of: ".git", with: "").split(separator: "/").suffix(2).joined(separator: "/")
    }

    private func pipelineHeader(_ p: Pipeline) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 10) {
                        Text("Pipeline #\(String(p.id))").font(.system(size: 23, weight: .semibold))
                        StatusBadge(status: p.status)
                        if store.detailLoading { ProgressView().controlSize(.small) }
                    }
                    Text(p.title.isEmpty ? "\(p.ref) · \(p.source)" : p.title)
                        .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Spacer()
                if validURL(p.webUrl) != nil {
                    Button { openWeb(p.webUrl) } label: { Label("Open in Browser", systemImage: "arrow.up.right.square") }
                        .controlSize(.small)
                }
            }
            HStack(alignment: .top, spacing: 28) {
                metadata("Branch", value: p.ref, icon: "arrow.triangle.branch")
                metadata("Commit", value: p.shortSHA, icon: "number", monospaced: true)
                metadata("Source", value: p.source, icon: "bolt")
                metadata("Author", value: p.commit.authorName, icon: "person")
                metadata("Started", value: Display.relative(p.startedAt, now: store.now), icon: "clock").help(Display.fullDate(p.startedAt))
                metadata("Duration", value: Display.duration(Display.elapsed(p.startedAt, duration: p.duration, status: p.status, now: store.now)), icon: "timer")
            }
        }.padding(22)
    }

    private func metadata(_ label: String, value: String, icon: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Label(value.isEmpty ? "—" : value, systemImage: icon)
                .font(monospaced ? .system(size: 12, design: .monospaced) : .system(size: 12))
                .lineLimit(1).help(value).textSelection(.enabled)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var jobsPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Jobs").font(.headline)
                Text("\(store.jobs.count)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !store.jobs.isEmpty {
                    let completed = store.jobs.filter { ["success", "failed", "canceled", "skipped", "neutral"].contains($0.current.status) }.count
                    Text("\(completed) of \(store.jobs.count) finished").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 22).padding(.vertical, 12)
            if store.jobs.isEmpty {
                EmptyPane(icon: "square.stack.3d.up", title: store.detailLoading ? "Loading jobs…" : "No jobs in this pipeline", subtitle: "")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(store.stages, id: \.self) { stage in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Text(stage.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
                                    Rectangle().fill(.quaternary).frame(height: 1)
                                }.padding(.bottom, 3)
                                ForEach(store.jobs.filter { $0.current.stage == stage }) { row in
                                    jobRow(row)
                                }
                            }
                        }
                    }.padding(.horizontal, 22).padding(.bottom, 18)
                }
            }
        }
    }

    private func jobRow(_ row: JobRow) -> some View {
        let selected = store.selectedJobID == row.id
        let elapsed = Display.elapsed(row.current.startedAt, duration: row.current.duration, status: row.current.status, now: store.now)
        return Button { store.selectedJobID = row.id } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: statusIcon(row.current.status)).foregroundStyle(statusColor(row.current.status)).frame(width: 16)
                    Text(row.current.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    if row.current.allowFailure { Text("Allowed to fail").font(.caption2).foregroundStyle(.secondary) }
                    Spacer(minLength: 12)
                    Text(Display.duration(elapsed)).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    StatusBadge(status: row.status)
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                }
                if row.current.status == "running", row.typicalDuration > 0, let elapsed {
                    HStack(spacing: 12) {
                        ProgressView(value: min(1, elapsed / row.typicalDuration)).frame(maxWidth: 170)
                        Text("Usually \(Display.duration(row.typicalDuration))").font(.caption2).foregroundStyle(.secondary)
                    }.padding(.leading, 26)
                }
                if let previous = row.previous {
                    Text("Previous: \(previous.status) · \(Display.duration(previous.duration)) · \(Display.relative(previous.finishedAt, now: store.now))")
                        .font(.caption2).foregroundStyle(.secondary).padding(.leading, 26)
                }
                if store.showInlineLogs, let snippet = store.snippets[row.id], !snippet.isEmpty {
                    Text(snippet).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                        .lineLimit(5).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8).background(Color(nsColor: .textBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
                        .padding(.leading, 26)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(selected ? Color.accentColor.opacity(0.09) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(selected ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.07), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(row.current.name), \(row.status)")
        .contextMenu {
            Button("View Logs") { store.selectedJobID = row.id; store.viewerMode = "logs" }
            Button("View Code") { store.selectedJobID = row.id; store.viewerMode = "code" }
            if validURL(row.logTarget.webUrl) != nil { Button("Open in Browser") { openWeb(row.logTarget.webUrl) } }
        }
    }

    private var viewer: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("Viewer", selection: $store.viewerMode) {
                    Text("Logs").tag("logs")
                    Text("Code").tag("code")
                }.pickerStyle(.segmented).labelsHidden().frame(width: 130)
                Text(store.selectedJob?.logTarget.name ?? "Select a job").font(.system(size: 12, weight: .medium)).lineLimit(1)
                if store.viewerLoading { ProgressView().controlSize(.small) }
                Spacer()
                if let row = store.selectedJob, validURL(row.logTarget.webUrl) != nil {
                    Button { openWeb(row.logTarget.webUrl) } label: { Image(systemName: "arrow.up.right.square") }.help("Open job in browser")
                }
                Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(store.viewerText, forType: .string) } label: { Image(systemName: "doc.on.doc") }
                    .help("Copy \(store.viewerMode)").disabled(store.viewerText.isEmpty)
            }.padding(.horizontal, 16).padding(.vertical, 10)
            if let row = store.selectedJob {
                let target = row.logTarget
                HStack(spacing: 14) {
                    Text(row.current.id == target.id ? "Job #\(String(target.id))" : "Previous run #\(String(target.id))")
                    Text(target.status.replacingOccurrences(of: "_", with: " "))
                    if !target.startedAt.isEmpty { Text("Started \(Display.relative(target.startedAt, now: store.now))").help(Display.fullDate(target.startedAt)) }
                    if !target.finishedAt.isEmpty { Text("Finished \(Display.relative(target.finishedAt, now: store.now))").help(Display.fullDate(target.finishedAt)) }
                    Spacer()
                }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.bottom, 8)
            }
            Divider()
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Find in \(store.viewerMode)", text: $viewerSearch).textFieldStyle(.plain)
                    .onSubmit { matchIndex += 1 }
                    .accessibilityLabel("Find in \(store.viewerMode)")
                if !viewerSearch.isEmpty {
                    Text(matchLabel).font(.caption).foregroundStyle(.secondary)
                    Button { matchIndex -= 1 } label: { Image(systemName: "chevron.up") }.help("Previous match")
                    Button { matchIndex += 1 } label: { Image(systemName: "chevron.down") }.help("Next match")
                    Button { viewerSearch = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).help("Clear search")
                }
                Spacer(minLength: 12)
                Toggle("Wrap", isOn: $wrap).toggleStyle(.checkbox)
                Toggle("Lines", isOn: $lineNumbers).toggleStyle(.checkbox)
                if store.viewerMode == "logs" { Toggle("Follow", isOn: $follow).toggleStyle(.checkbox).help("Keep the latest log output visible") }
            }.font(.system(size: 11)).padding(.horizontal, 16).padding(.vertical, 8)
            Divider()
            if let error = store.viewerError {
                VStack(alignment: .leading, spacing: 10) {
                    Label("\(store.viewerMode.capitalized) unavailable", systemImage: "exclamationmark.triangle").font(.headline)
                    Text(error).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    if store.resolvedProvider == "github" && store.selectedJob?.logTarget.status == "running" {
                        Text("GitHub publishes downloadable job logs after the job finishes.").font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Try Again") { Task { await store.loadViewer() } }
                }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if store.selectedJob == nil || (store.viewerText.isEmpty && !store.viewerLoading) {
                EmptyPane(icon: "terminal", title: store.selectedJob == nil ? "Select a job to inspect" : "No output yet", subtitle: store.selectedJob == nil ? "View its logs or resolved CI code here." : "Output will appear when the job produces logs.")
            } else if store.viewerText.isEmpty {
                ProgressView("Loading \(store.viewerMode)…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                LogTextView(text: store.viewerText, wrap: wrap, lineNumbers: lineNumbers, follow: follow && store.viewerMode == "logs", query: viewerSearch, matchIndex: matchIndex,
                            identity: "\(store.selectedJobID ?? 0)-\(store.viewerMode)")
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var matchLabel: String {
        let count = LogTextView.ranges(in: store.viewerText, query: viewerSearch).count
        if count == 0 { return "No matches" }
        let index = ((matchIndex % count) + count) % count
        return "\(index + 1) of \(count)"
    }

    private var statusBar: some View {
        HStack(spacing: 6) {
            Circle().fill(store.refreshInterval == 0 ? Color.secondary : Color.green).frame(width: 5, height: 5)
            Text(store.isDemo ? "Demo data" : store.refreshInterval == 0 ? "Refresh paused" : "Refresh every \(store.refreshInterval)s")
            Spacer()
            if let last = store.lastUpdated { Text("Updated \(last.formatted(date: .omitted, time: .standard))") }
        }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.vertical, 7)
    }

    private var emptyDetail: some View {
        VStack(spacing: 18) {
            Image(systemName: "arrow.triangle.branch").font(.system(size: 50, weight: .light)).foregroundStyle(.tint)
            Text(store.repo.isEmpty ? "Your pipelines, on your Mac" : "Select a pipeline").font(.title2.weight(.semibold))
            Text(store.repo.isEmpty ? "Browse GitLab CI and GitHub Actions.\nInspect jobs, live logs, and code in one window." : "Choose a pipeline in the sidebar to view its jobs.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            if store.repo.isEmpty {
                Button("Choose Repository") { activeSheet = .projects }.buttonStyle(.borderedProminent).controlSize(.large)
                Text("Set your projects folder once, then find projects with ⌘F.").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(40)
    }

    private var demoBanner: some View {
        HStack {
            Label("Demo preview · Sample pipeline data", systemImage: "eye")
            Spacer()
            Button("Connect Repository") { activeSheet = .connection }
        }.font(.caption).padding(.horizontal, 22).padding(.vertical, 8).background(Color.accentColor.opacity(0.08))
    }

    private func errorBanner(_ error: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(error).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }.help("Retry")
            Button { store.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("Dismiss error")
        }.padding(12).background(Color.orange.opacity(0.08))
    }
}

struct PipelineListRow: View {
    let pipeline: Pipeline
    let now: Date
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("#\(String(pipeline.id))").font(.system(size: 12, weight: .semibold, design: .monospaced))
                Spacer()
                StatusBadge(status: pipeline.status)
            }
            Text(pipeline.title.isEmpty ? pipeline.ref : pipeline.title).font(.system(size: 13, weight: .medium)).lineLimit(2)
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.branch")
                Text(pipeline.ref).lineLimit(1)
                Spacer(minLength: 4)
                Text(Display.relative(pipeline.startedAt.isEmpty ? pipeline.createdAt : pipeline.startedAt, now: now))
            }.font(.system(size: 10)).foregroundStyle(.secondary)
            HStack {
                Text(pipeline.shortSHA).font(.system(size: 10, design: .monospaced))
                Text(pipeline.commit.authorName).lineLimit(1)
                Spacer()
                if let duration = pipeline.duration { Text(Display.duration(duration)) }
            }.font(.system(size: 10)).foregroundStyle(.secondary)
        }.padding(.vertical, 8)
    }
}

struct StatusBadge: View {
    let status: String
    var body: some View {
        Text(status.replacingOccurrences(of: "_", with: " "))
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(statusColor(status))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(statusColor(status).opacity(0.12), in: Capsule())
            .fixedSize()
    }
}

struct EmptyPane: View {
    var icon: String
    var title: String
    var subtitle: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 28, weight: .light)).foregroundStyle(.tertiary)
            Text(title).font(.callout).foregroundStyle(.secondary)
            if !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(.tertiary) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

func statusColor(_ status: String) -> Color {
    switch status {
    case "success": .green
    case "failed": .red
    case "running": .cyan
    case "manual": .purple
    case "pending", "created", "preparing", "scheduled", "waiting_for_resource": .orange
    default: .secondary
    }
}

func statusIcon(_ status: String) -> String {
    switch status {
    case "success": "checkmark.circle.fill"
    case "failed": "xmark.circle.fill"
    case "running": "arrow.triangle.2.circlepath"
    case "manual": "play.circle"
    case "pending", "created", "preparing", "scheduled", "waiting_for_resource": "clock"
    case "canceled": "minus.circle"
    default: "circle.dashed"
    }
}

func validURL(_ value: String) -> URL? {
    guard let url = URL(string: value), ["https", "http"].contains(url.scheme), url.host != nil else { return nil }
    return url
}

func openWeb(_ value: String) {
    if let url = validURL(value) { NSWorkspace.shared.open(url) }
}
