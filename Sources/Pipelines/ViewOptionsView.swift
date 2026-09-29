import SwiftUI

struct ViewOptionsView: View {
    @Binding var limit: Int
    @Binding var refreshInterval: Int
    @Binding var showInlineLogs: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("View Options").font(.headline)
            VStack(alignment: .leading, spacing: 8) {
                Text("Pipeline limit").font(.subheadline)
                Picker("Pipeline limit", selection: $limit) {
                    ForEach([10, 20, 30, 50, 100], id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Refresh interval").font(.subheadline)
                Picker("Refresh interval", selection: $refreshInterval) {
                    Text("Paused").tag(0)
                    ForEach([5, 10, 20, 30, 60, 120], id: \.self) { Text("\($0)s").tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            Toggle("Inline log previews", isOn: $showInlineLogs)
                .toggleStyle(.checkbox)
            Divider()
            HStack {
                Text("Changes apply immediately.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}
