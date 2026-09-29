import AppKit
import Foundation
import Testing
@testable import Pipelines

@Test func shortcutHelpAcceptsQuestionMarkWithoutInterruptingTyping() {
    #expect(ProjectSearchShortcut.matchesHelp(characters: "?", modifiers: [], isEditing: false))
    #expect(ProjectSearchShortcut.matchesHelp(characters: "?", modifiers: .shift, isEditing: false))
    #expect(ProjectSearchShortcut.matchesHelp(characters: "?", modifiers: [.shift, .capsLock], isEditing: false))
    #expect(!ProjectSearchShortcut.matchesHelp(characters: "?", modifiers: .shift, isEditing: true))
    #expect(!ProjectSearchShortcut.matchesHelp(characters: "?", modifiers: [.command, .shift], isEditing: false))
    #expect(!ProjectSearchShortcut.matchesHelp(characters: "?", modifiers: .control, isEditing: false))
    #expect(!ProjectSearchShortcut.matchesHelp(characters: "?", modifiers: .option, isEditing: false))
    #expect(!ProjectSearchShortcut.matchesHelp(characters: "/", modifiers: .shift, isEditing: false))
    #expect(!ProjectSearchShortcut.matchesHelp(characters: nil, modifiers: [], isEditing: false))
}

@Test func projectSearchShortcutsRequireCommand() {
    for key in ["f", "k"] {
        #expect(ProjectSearchShortcut.matches(characters: key, modifiers: .command))
        #expect(!ProjectSearchShortcut.matches(characters: key, modifiers: []))
        #expect(!ProjectSearchShortcut.matches(characters: key, modifiers: [.command, .shift]))
        #expect(!ProjectSearchShortcut.matches(characters: key, modifiers: [.command, .option]))
        #expect(!ProjectSearchShortcut.matches(characters: key, modifiers: .control))
    }
    #expect(!ProjectSearchShortcut.matches(characters: "r", modifiers: .command))
}

@Test func fuzzySearchMatchesSubsequencesAndRanksContiguousNames() {
    #expect(FuzzySearch.score("pgui", in: "tools/pipelines-gui") != nil)
    #expect(FuzzySearch.score("PL GUI", in: "tools/pipelines-gui") != nil)
    #expect(FuzzySearch.score("zz", in: "pipelines") == nil)
    #expect(FuzzySearch.score("aaa", in: "ab") == nil)
    #expect(FuzzySearch.score("x", in: "") == nil)
    #expect(FuzzySearch.score("", in: "anything") == 0)
    let repos = [LocalRepository(path: "1", name: "p-i-p-e", remote: ""), LocalRepository(path: "2", name: "pipe", remote: "")]
    #expect(FuzzySearch.filter(repos, query: "pipe").map(\.path) == ["2", "1"])
}

@Test func scannerFindsNestedRepositoriesAndWorktrees() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let ordinary = root.appendingPathComponent("team/project with spaces")
    let nested = ordinary.appendingPathComponent("nested")
    let worktree = root.appendingPathComponent("worktree")
    let ignored = root.appendingPathComponent("node_modules/dependency/.git")
    for folder in [ordinary.appendingPathComponent(".git"), nested.appendingPathComponent(".git"), worktree, ignored] {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    try Data("gitdir: /does/not/exist\n".utf8).write(to: worktree.appendingPathComponent(".git"))
    let discovered = try RepositoryScanner.scan(root: root.path)
    #expect(discovered.map(\.name) == ["team/project with spaces", "team/project with spaces/nested", "worktree"])
    #expect(discovered.allSatisfy { $0.remote.isEmpty })
    // The selected parent may itself be a repository.
    let sameRoot = try RepositoryScanner.scan(root: ordinary.path)
    #expect(sameRoot.map(\.name).contains("project with spaces"))
}

@Test func scannerReadsOriginsAndDoesNotFollowSymlinks() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = root.appendingPathComponent("actual")
    try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
    for arguments in [["-C", repository.path, "init", "--quiet"], ["-C", repository.path, "remote", "add", "origin", "git@github.com:owner/repo.git"]] {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/git"); process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit(); #expect(process.terminationStatus == 0)
    }
    try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("alias"), withDestinationURL: repository)
    let found = try RepositoryScanner.scan(root: root.path)
    #expect(found.count == 1)
    #expect(found.first?.remote == "git@github.com:owner/repo.git")
    #expect(found.first?.provider == "github")
}

@Test func unicodeLogSearchUsesUTF16Ranges() {
    let ranges = LogTextView.ranges(in: "🚀 build\nBUILD finished", query: "build")
    #expect(ranges == [NSRange(location: 3, length: 5), NSRange(location: 9, length: 5)])
    #expect(LogTextView.ranges(in: "aaa", query: "").isEmpty)
}

@Test func decodeBackendResponsePreservesSnakeCaseAndPreviousRuns() throws {
    let payload = #"{"provider":"gitlab","pipeline":{"id":42,"iid":3,"status":"running","ref":"main","sha":"abcdef12","source":"push","updated_at":"","created_at":"","started_at":"","web_url":"https://gitlab.com/a/b/-/pipelines/42","commit":{"title":"Build","author_name":"Ada"}},"jobs":[{"current":{"id":7,"name":"test","status":"manual","stage":"test","ref":"main","web_url":"","created_at":"","started_at":"","finished_at":"","allow_failure":true,"retried":false,"pipeline":{"id":42,"iid":0,"status":"","ref":"","sha":"","source":"","updated_at":"","created_at":"","started_at":"","web_url":"","commit":{"title":"","author_name":""}}},"log_target":{"id":6,"name":"test","status":"failed","stage":"test","ref":"main","web_url":"","created_at":"","started_at":"","finished_at":"","duration":20,"allow_failure":true,"retried":true,"pipeline":{"id":42,"iid":0,"status":"","ref":"","sha":"","source":"","updated_at":"","created_at":"","started_at":"","web_url":"","commit":{"title":"","author_name":""}}},"status":"failed + manual","typical_duration":20}]}"#
    let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
    let response = try decoder.decode(BridgeResponse.self, from: Data(payload.utf8))
    #expect(response.pipeline?.commit.authorName == "Ada")
    #expect(response.pipeline?.webUrl == "https://gitlab.com/a/b/-/pipelines/42")
    #expect(response.jobs?.first?.logTarget.id == 6)
    #expect(response.jobs?.first?.current.allowFailure == true)
    #expect(response.jobs?.first?.typicalDuration == 20)
}

@Test func durationsAndRunningElapsedAreAccurate() {
    #expect(Display.duration(3661) == "1h 1m 1s")
    #expect(Display.duration(nil) == "—")
    #expect(Display.duration(-1) == "—")
    let now = Display.date("2026-09-29T20:00:30Z")!
    #expect(Display.elapsed("2026-09-29T20:00:00Z", duration: nil, status: "running", now: now) == 30)
    #expect(Display.elapsed("2026-09-29T20:00:00Z", duration: 12, status: "success", now: now) == 12)
}
