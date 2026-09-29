import AppKit
import SwiftUI

/// Route project search and shortcut help to the active main window, including from its sheets or Settings.
struct ProjectSearchShortcut: NSViewRepresentable {
    var open: () -> Void
    var showHelp: () -> Void

    nonisolated static func matches(characters: String?, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard characters == "f" || characters == "k" else { return false }
        let modifiers = modifiers.intersection([.command, .control, .option, .shift])
        return modifiers == .command
    }

    nonisolated static func matchesHelp(characters: String?, modifiers: NSEvent.ModifierFlags, isEditing: Bool) -> Bool {
        guard characters == "?", !isEditing else { return false }
        // Use the produced character so layouts that require Shift for ? also work.
        return modifiers.intersection([.command, .control, .option]).isEmpty
    }

    static func openProjectSearch() { ShortcutView.target(for: NSApp.keyWindow)?.activate() }

    func makeNSView(context: Context) -> ShortcutView { ShortcutView() }

    func updateNSView(_ view: ShortcutView, context: Context) {
        view.open = open
        view.showHelp = showHelp
    }

    static func dismantleNSView(_ view: ShortcutView, coordinator: ()) { view.stopMonitoring() }

    final class ShortcutView: NSView {
        private static let hosts = NSHashTable<ShortcutView>.weakObjects()
        var open: (() -> Void)?
        var showHelp: (() -> Void)?
        private var monitor: Any?

        static func target(for window: NSWindow?) -> ShortcutView? {
            let hosts = hosts.allObjects
            var parent = window
            while let window = parent {
                if let host = hosts.first(where: { $0.window === window }) { return host }
                parent = window.sheetParent
            }
            // Settings is a separate window; return to the frontmost project window.
            for window in NSApp.orderedWindows {
                if let host = hosts.first(where: { $0.window === window }) { return host }
            }
            return nil
        }

        func activate() {
            if let sheet = window?.attachedSheet { sheet.makeKeyAndOrderFront(nil) }
            else { window?.makeKeyAndOrderFront(nil) }
            open?()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard window != nil else { return }
            Self.hosts.add(self)
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let handled = MainActor.assumeIsolated {
                    guard let self, Self.target(for: event.window) === self,
                          NSApp.modalWindow == nil, !event.isARepeat else { return false }
                    let isEditing = (event.window?.firstResponder as? NSTextView)?.isEditable == true
                    if ProjectSearchShortcut.matchesHelp(characters: event.characters,
                                                         modifiers: event.modifierFlags, isEditing: isEditing) {
                        if let sheet = self.window?.attachedSheet { sheet.makeKeyAndOrderFront(nil) }
                        else { self.window?.makeKeyAndOrderFront(nil) }
                        self.showHelp?()
                        return true
                    }
                    guard ProjectSearchShortcut.matches(characters: event.charactersIgnoringModifiers,
                                                        modifiers: event.modifierFlags) else { return false }
                    self.activate()
                    return true
                }
                return handled ? nil : event
            }
        }

        func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            Self.hosts.remove(self)
        }
    }
}
