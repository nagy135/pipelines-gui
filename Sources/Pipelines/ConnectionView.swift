import SwiftUI

struct ConnectionView: View {
    @ObservedObject var store: PipelineStore
    @Environment(\.dismiss) private var dismiss
    @State private var repo = ""
    @State private var provider = "auto"
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.branch").font(.system(size: 28)).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Connect a Repository").font(.title2.weight(.semibold))
                    Text("Uses your existing gh or glab authentication.").font(.callout).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("Repository").font(.headline)
                TextField("owner/repository or a full remote URL", text: $repo).textFieldStyle(.roundedBorder).focused($focused)
                    .onSubmit { connect() }
                Text("For self-hosted GitLab, include the hostname: gitlab.example.com/group/project.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Picker("Provider", selection: $provider) {
                Text("Automatic (from URL)").tag("auto")
                Text("GitLab CI").tag("gitlab")
                Text("GitHub Actions").tag("github")
            }
            Text("For an owner/repository path, select its provider. Automatic uses GitLab when the hostname is absent.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("First-time authentication").font(.caption.weight(.semibold))
                Text("GitLab: glab auth login\nGitHub: gh auth login").font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Choose Local Folder…") { dismiss(); Task { await store.chooseRepositoryFolder() } }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Connect") { connect() }.keyboardShortcut(.defaultAction)
                    .disabled(repo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(28).frame(width: 520)
        .onAppear { repo = store.isDemo ? "" : store.repo; provider = store.isDemo ? "auto" : store.provider; focused = true }
    }

    private func connect() {
        guard !repo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let value = repo, selected = provider
        dismiss()
        Task { await store.connect(repo: value, provider: selected) }
    }
}
