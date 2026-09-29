import Foundation

enum BridgeError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}

enum Bridge {
    static func send(_ request: BridgeRequest) async throws -> BridgeResponse {
        try await Task.detached(priority: .userInitiated) {
            let helper = Bundle.main.url(forAuxiliaryExecutable: "pipelines-helper")
                ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("dist/Pipelines.app/Contents/MacOS/pipelines-helper")
            guard FileManager.default.isExecutableFile(atPath: helper.path) else {
                throw BridgeError.message("The pipeline helper is missing. Build the app with make build, then open dist/Pipelines.app.")
            }
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let outputURL = directory.appendingPathComponent("output")
            let errorURL = directory.appendingPathComponent("error")
            FileManager.default.createFile(atPath: outputURL.path, contents: nil)
            FileManager.default.createFile(atPath: errorURL.path, contents: nil)
            let output = try FileHandle(forWritingTo: outputURL)
            let errors = try FileHandle(forWritingTo: errorURL)
            defer { try? output.close(); try? errors.close() }
            let input = Pipe()
            let process = Process()
            process.executableURL = helper
            // Finder starts apps with a minimal PATH. Include Homebrew and the user's Nix profile.
            var env = ProcessInfo.processInfo.environment
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            env["PATH"] = [env["PATH"] ?? "", "/opt/homebrew/bin", "/usr/local/bin", "\(home)/.nix-profile/bin", "/run/current-system/sw/bin", "/nix/var/nix/profiles/default/bin", "/usr/bin", "/bin"].joined(separator: ":")
            env["GH_PROMPT_DISABLED"] = "1"
            env["NO_COLOR"] = "1"
            process.environment = env
            process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
            process.standardInput = input
            process.standardOutput = output
            process.standardError = errors
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            let data = try encoder.encode(request)
            try process.run()
            try input.fileHandleForWriting.write(contentsOf: data)
            try input.fileHandleForWriting.close()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let detail = String(data: (try? Data(contentsOf: errorURL)) ?? Data(), encoding: .utf8) ?? ""
                throw BridgeError.message(detail.isEmpty ? "Pipeline helper exited unexpectedly." : detail)
            }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let result = try decoder.decode(BridgeResponse.self, from: Data(contentsOf: outputURL))
            if let error = result.error, !error.isEmpty { throw BridgeError.message(error) }
            return result
        }.value
    }
}
