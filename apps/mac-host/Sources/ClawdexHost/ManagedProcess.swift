import Darwin
import Foundation

final class ManagedProcess: @unchecked Sendable {
    private let process = Process()
    private let stdout = Pipe()
    private let stderr = Pipe()
    private let logURL: URL
    private let logger: @Sendable (String) -> Void
    private let label: String
    private var fileHandle: FileHandle?

    init(label: String, logURL: URL, logger: @escaping @Sendable (String) -> Void) {
        self.label = label
        self.logURL = logURL
        self.logger = logger
    }

    var pid: Int32? {
        process.isRunning ? process.processIdentifier : nil
    }

    func start(
        executable: String,
        arguments: [String],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil,
        onExit: @escaping @Sendable (Int32) -> Void
    ) throws {
        if process.isRunning {
            return
        }

        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        fileHandle = try FileHandle(forWritingTo: logURL)
        try fileHandle?.seekToEnd()

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

        let pipeHandler: @Sendable (FileHandle) -> Void = { [weak self] handle in
            let data = handle.availableData
            guard let self, !data.isEmpty else {
                return
            }
            let text = String(decoding: data, as: UTF8.self)
            self.appendLog(text)
        }

        stdout.fileHandleForReading.readabilityHandler = pipeHandler
        stderr.fileHandleForReading.readabilityHandler = pipeHandler

        process.terminationHandler = { [weak self] process in
            self?.stdout.fileHandleForReading.readabilityHandler = nil
            self?.stderr.fileHandleForReading.readabilityHandler = nil
            self?.appendLog("\(self?.label ?? "process") exited with status \(process.terminationStatus)\n")
            onExit(process.terminationStatus)
        }

        do {
            try process.run()
            appendLog("\(label) started: \(executable) \(arguments.joined(separator: " "))\n")
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            throw HostError.command("Failed to start \(label): \(error.localizedDescription)")
        }
    }

    func stop(gracePeriod: TimeInterval = 1.5) {
        guard process.isRunning else {
            cleanup()
            return
        }

        process.terminate()
        let deadline = Date().addingTimeInterval(gracePeriod)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }

        if process.isRunning, let pid = pid {
            kill(pid, SIGKILL)
        }

        cleanup()
    }

    private func cleanup() {
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        try? fileHandle?.close()
        fileHandle = nil
    }

    private func appendLog(_ text: String) {
        let prefixed = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { HostLogger.render(prefix: label, String($0)) }
            .joined(separator: "\n")

        if let data = (prefixed + "\n").data(using: .utf8) {
            try? fileHandle?.write(contentsOf: data)
        }

        logger(prefixed)
    }
}
