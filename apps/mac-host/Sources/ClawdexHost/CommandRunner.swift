import Foundation

enum CommandRunner {
    static func run(
        executable: String,
        arguments: [String],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil
    ) throws -> ManagedCommandResult {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr
        if let currentDirectory {
            process.currentDirectoryURL = currentDirectory
        }
        if let environment {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }

        do {
            try process.run()
        } catch {
            throw HostError.command("Failed to launch \(executable): \(error.localizedDescription)")
        }

        process.waitUntilExit()

        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
        let stdoutString = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderrString = String(data: stderrData, encoding: .utf8) ?? ""

        return ManagedCommandResult(status: process.terminationStatus, stdout: stdoutString, stderr: stderrString)
    }

    static func resolveExecutable(named name: String, additionalCandidates: [String] = []) -> String? {
        let fileManager = FileManager.default
        let pathEntries = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)

        let candidates = additionalCandidates + pathEntries.map { NSString(string: $0).appendingPathComponent(name) }
        for candidate in candidates {
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }

    static func resolveCodexBinary(preferredPath: String?) -> String? {
        let candidates = [
            preferredPath,
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ].compactMap { $0 }
        return resolveExecutable(named: "codex", additionalCandidates: candidates)
    }

    static func resolveCloudflaredBinary() -> String? {
        resolveExecutable(
            named: "cloudflared",
            additionalCandidates: [
                "/opt/homebrew/bin/cloudflared",
                "/usr/local/bin/cloudflared"
            ]
        )
    }

    static func processCommandLine(for pid: Int32) -> String? {
        guard pid > 0 else {
            return nil
        }

        guard let ps = resolveExecutable(named: "ps", additionalCandidates: ["/bin/ps", "/usr/bin/ps"]) else {
            return nil
        }

        let result = try? run(executable: ps, arguments: ["-p", String(pid), "-o", "command="])
        guard let result, result.status == 0 else {
            return nil
        }

        let command = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return command.isEmpty ? nil : command
    }

    static func digCNAME(hostname: String) -> String? {
        guard let dig = resolveExecutable(named: "dig", additionalCandidates: ["/usr/bin/dig"]) else {
            return nil
        }

        let result = try? run(executable: dig, arguments: ["+short", "CNAME", hostname])
        guard let result, result.status == 0 else {
            return nil
        }

        let cname = result.stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return cname.isEmpty ? nil : cname.lowercased()
    }
}

final class JSONFileStore<Value: Codable> {
    private let url: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(url: URL) {
        self.url = url
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load(defaultValue: Value) -> Value {
        guard let data = try? Data(contentsOf: url) else {
            return defaultValue
        }

        return (try? decoder.decode(Value.self, from: data)) ?? defaultValue
    }

    func save(_ value: Value) throws {
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }
}

