import AppKit
import SwiftUI

@main
struct PipelinesApp: App {
    @StateObject private var settings = AppSettings()
    var body: some Scene {
        WindowGroup("Pipelines") {
            ContentView()
                .environmentObject(settings)
                .frame(minWidth: 1000, minHeight: 640)
        }
        .defaultSize(width: 1360, height: 900)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Find Project…") { ProjectSearchShortcut.openProjectSearch() }
                    .keyboardShortcut("f")
            }
        }
        Settings { SettingsView().environmentObject(settings) }
    }
}
