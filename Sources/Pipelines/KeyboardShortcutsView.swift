import SwiftUI

struct KeyboardShortcutsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Keyboard Shortcuts", systemImage: "keyboard")
                .font(.title2.weight(.semibold))

            group("Application", shortcuts: [
                ("?", "Show or close this popup"),
                ("⌘F / ⌘K", "Find project"),
                ("⌘R", "Refresh pipelines"),
                ("⌘,", "Open Settings"),
                ("⌘W", "Close window"),
                ("⌘Q", "Quit Pipelines")
            ])
            group("Project picker and dialogs", shortcuts: [
                ("↑ / ↓", "Select previous or next project"),
                ("Return", "Open selected project or connect repository"),
                ("Esc", "Close popup or cancel dialog"),
                ("Tab / ⇧Tab", "Move focus forward or backward")
            ])
            group("Logs and code", shortcuts: [
                ("Return", "Next match in the search field"),
                ("⌘C", "Copy selected text"),
                ("⌘A", "Select all text in the focused viewer or field")
            ])

            Divider()
            HStack(alignment: .center, spacing: 20) {
                Text("The ? shortcut works outside editable text fields.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(28)
        .frame(width: 560)
    }

    private func group(_ title: String, shortcuts: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            ForEach(shortcuts, id: \.0) { keys, action in
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(action).font(.callout)
                    Spacer()
                    Text(keys).font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
