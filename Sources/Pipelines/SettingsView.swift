import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Repository Discovery").font(.title2.weight(.semibold))
            Text("Choose the parent folder containing your projects. Pipelines finds Git repositories recursively, including nested projects and worktrees.")
                .font(.callout).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                Text("Parent folder").font(.headline)
                HStack {
                    Text(settings.parentRoot.isEmpty ? "No folder selected" : settings.parentRoot)
                        .font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Choose…") { settings.chooseRoot() }
                }.padding(12).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            }
            HStack {
                if settings.scanning { ProgressView().controlSize(.small); Text("Finding repositories…") }
                else { Text("\(settings.repositories.count) repositories found") }
                Spacer()
                Button("Rescan") { Task { await settings.scan() } }.disabled(settings.parentRoot.isEmpty || settings.scanning)
            }.font(.caption).foregroundStyle(.secondary)
            if let error = settings.scanError { Text(error).font(.caption).foregroundStyle(.red) }
            Divider()
            Text("Press ⌘F to find projects with fuzzy search (⌘K also works). Authenticate with gh or glab once in Terminal; the app uses those existing accounts.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(28).frame(width: 570)
        .task { if settings.repositories.isEmpty { await settings.scan() } }
    }
}
