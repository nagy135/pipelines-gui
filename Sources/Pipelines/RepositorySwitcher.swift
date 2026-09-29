import SwiftUI

struct RepositorySwitcher: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject var store: PipelineStore
    var searchRequest = UUID()
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selectedID: String?
    @FocusState private var focused: Bool
    var matches: [LocalRepository] { FuzzySearch.filter(settings.repositories, query: query) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Find project…", text: $query).textFieldStyle(.plain).font(.title3)
                    .focused($focused).onSubmit { activate() }
                    .accessibilityLabel("Fuzzy search projects")
                if settings.scanning { ProgressView().controlSize(.small) }
                Button { Task { await settings.scan() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).help("Rescan parent folder").disabled(settings.scanning)
            }.padding(20)
            Divider()
            if settings.parentRoot.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.plus").font(.largeTitle).foregroundStyle(.secondary)
                    Text("Choose your projects folder").font(.headline)
                    Text("All Git repositories under this folder will appear here.").foregroundStyle(.secondary)
                    Button("Choose Parent Folder…") { settings.chooseRoot() }.buttonStyle(.borderedProminent)
                }.frame(maxWidth: .infinity, minHeight: 260)
            } else if matches.isEmpty {
                VStack(spacing: 10) {
                    Text(settings.scanning ? "Finding repositories…" : query.isEmpty ? "No Git repositories found" : "No matching repositories").font(.headline)
                    if let error = settings.scanError { Text(error).font(.caption).foregroundStyle(.red) }
                    else { Text(query.isEmpty ? "Choose a parent folder that contains your cloned projects." : "Try a few letters from the project or folder name.").font(.caption).foregroundStyle(.secondary) }
                    if query.isEmpty { Button("Change Parent Folder…") { settings.chooseRoot() } }
                }.padding(24).frame(maxWidth: .infinity, minHeight: 260)
            } else {
                List(selection: $selectedID) {
                    ForEach(matches) { repository in
                        HStack(spacing: 12) {
                            Image(systemName: "folder").foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(repository.name).font(.system(size: 13, weight: .medium))
                                Text(repository.remote.isEmpty ? "No origin remote" : repository.remote).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            if repository.path == store.localRepositoryPath { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            if !repository.remote.isEmpty { Text(repository.provider == "github" ? "GitHub" : "GitLab").font(.caption2).foregroundStyle(.secondary) }
                        }.padding(.vertical, 6).tag(repository.id)
                            .contentShape(Rectangle()).onTapGesture(count: 2) { selectedID = repository.id; activate() }
                    }
                }.listStyle(.inset).frame(height: 330)
            }
            Divider()
            HStack {
                Text(settings.parentRoot.isEmpty ? "Set a parent folder to get started" : "\(matches.count) repositories · ↑↓ to select · ↵ to open")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Open") { activate() }.keyboardShortcut(.defaultAction).disabled(selected?.remote.isEmpty != false)
            }.padding(14)
        }.frame(width: 620)
        .onAppear { focused = true; selectedID = matches.first(where: { $0.path == store.localRepositoryPath })?.id ?? matches.first?.id }
        .task { if settings.repositories.isEmpty { await settings.scan() } }
        .onChange(of: query) { _, _ in selectedID = matches.first?.id }
        .onChange(of: searchRequest) { _, _ in focused = true }
        .onChange(of: settings.repositories) { _, _ in if !matches.contains(where: { $0.id == selectedID }) { selectedID = matches.first?.id } }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
    }

    private var selected: LocalRepository? { matches.first { $0.id == selectedID } }
    private func move(_ offset: Int) {
        guard !matches.isEmpty else { return }
        let index = matches.firstIndex { $0.id == selectedID } ?? 0
        selectedID = matches[min(matches.count - 1, max(0, index + offset))].id
    }
    private func activate() {
        guard let selected, !selected.remote.isEmpty else { return }
        dismiss()
        Task { await store.connect(repository: selected) }
    }
}
