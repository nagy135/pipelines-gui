import AppKit
import Foundation
import Darwin
import SwiftUI

struct LocalRepository: Identifiable, Sendable, Equatable {
    var path: String
    var name: String
    var remote: String
    var id: String { path }
    var provider: String {
        let host: String
        if let url = URL(string: remote), let hostname = url.host { host = hostname }
        else {
            let afterUser = remote.split(separator: "@").last.map(String.init) ?? remote
            host = afterUser.split(whereSeparator: { $0 == ":" || $0 == "/" }).first.map(String.init) ?? ""
        }
        return host.lowercased().contains("github") ? "github" : "gitlab"
    }
}

enum RepositoryScanner {
    static func scan(root: String) throws -> [LocalRepository] {
        let base: URL
        if let resolved = realpath(root, nil) {
            base = URL(fileURLWithPath: String(cString: resolved))
            free(resolved)
        } else { base = URL(fileURLWithPath: root).standardizedFileURL }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: base.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw BridgeError.message("The repository parent folder is unavailable. Choose an existing folder in Settings.")
        }
        let ignored: Set<String> = ["node_modules", ".build", ".next", ".cache", ".uv-cache", "Pods", ".venv", "venv", "DerivedData"]
        var folders = Set<URL>()
        if FileManager.default.fileExists(atPath: base.appendingPathComponent(".git").path) { folders.insert(base) }
        var unreadable = false
        guard let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [], errorHandler: { _, _ in unreadable = true; return true }) else {
            throw BridgeError.message("Could not read the repository parent folder.")
        }
        for case let url as URL in walker {
            if url.lastPathComponent == ".git" {
                folders.insert(url.deletingLastPathComponent())
                walker.skipDescendants()
            } else if ignored.contains(url.lastPathComponent) {
                walker.skipDescendants()
            } else if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                walker.skipDescendants()
            } else if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                      FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path) {
                folders.insert(url)
            }
        }
        if folders.isEmpty && unreadable { throw BridgeError.message("The parent folder could not be read. Check its permissions in Settings.") }
        return folders.map { folder in
            let relative = folder.path == base.path ? folder.lastPathComponent : String(folder.path.dropFirst(base.path.count + 1))
            return LocalRepository(path: folder.path, name: relative, remote: origin(at: folder))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func origin(at folder: URL) -> String {
        let process = Process(); let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", folder.path, "remote", "get-url", "origin"]
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
            guard process.terminationStatus == 0 else { return "" }
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } catch { return "" }
    }
}

enum FuzzySearch {
    /// Case-insensitive subsequence matching, rewarding adjacent letters and word boundaries.
    static func score(_ query: String, in candidate: String) -> Int? {
        let needle = Array(query.lowercased().filter { !$0.isWhitespace })
        guard !needle.isEmpty else { return 0 }
        let haystack = Array(candidate.lowercased())
        var index = 0, previous = -2, score = 0
        for letter in needle {
            guard let match = haystack[index...].firstIndex(of: letter) else { return nil }
            score += 10
            if match == previous + 1 { score += 16 }
            if match == 0 || "/-_ .".contains(haystack[match - 1]) { score += 12 }
            score -= match - index
            previous = match; index = match + 1
        }
        return score - max(0, haystack.count - needle.count) / 4
    }

    static func filter(_ repositories: [LocalRepository], query: String) -> [LocalRepository] {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return repositories }
        return repositories.compactMap { repo -> (LocalRepository, Int)? in
            guard let score = score(query, in: repo.name) else { return nil }
            return (repo, score)
        }.sorted { lhs, rhs in
            lhs.1 == rhs.1 ? lhs.0.name.localizedStandardCompare(rhs.0.name) == .orderedAscending : lhs.1 > rhs.1
        }.map(\.0)
    }

}

@MainActor
final class AppSettings: ObservableObject {
    @Published var parentRoot: String {
        didSet { UserDefaults.standard.set(parentRoot, forKey: "parentRoot") }
    }
    @Published var repositories: [LocalRepository] = []
    @Published var scanning = false
    @Published var scanError: String?
    private var scanToken = UUID()

    init() { parentRoot = UserDefaults.standard.string(forKey: "parentRoot") ?? "" }

    func chooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false; panel.prompt = "Use Parent Folder"
        panel.message = "Pipelines finds all Git repositories inside this folder and its subfolders."
        if !parentRoot.isEmpty { panel.directoryURL = URL(fileURLWithPath: parentRoot) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        parentRoot = url.path
        Task { await scan() }
    }

    func scan() async {
        let token = UUID(); scanToken = token
        guard !parentRoot.isEmpty else { repositories = []; scanning = false; return }
        scanning = true; scanError = nil
        let root = parentRoot
        do {
            let discovered = try await Task.detached(priority: .userInitiated) { try RepositoryScanner.scan(root: root) }.value
            guard scanToken == token else { return }
            repositories = discovered
        } catch {
            guard scanToken == token else { return }
            repositories = []; scanError = error.localizedDescription
        }
        if scanToken == token { scanning = false }
    }
}
