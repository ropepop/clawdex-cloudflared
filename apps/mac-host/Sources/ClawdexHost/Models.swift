import Foundation

enum HostDefaults {
    static let appName = "ClawdexHost"
    static let appSupportDirectoryName = "ClawdexHost"
    static let keychainService = "ClawdexHost"
    static let keychainAccount = "bridge-token"
    static let hostname = "clawdex.example.com"
    static let publicURL = "https://clawdex.example.com"
    static let tunnelName = "clawdex-host"
    static let bridgePort = 8787
    static let localhostBridgeURL = "http://127.0.0.1:\(bridgePort)"
    static let bridgeBinaryName = "codex-rust-bridge"
}

enum ServiceState: String {
    case stopped
    case starting
    case running
    case stopping
    case failed

    var isActive: Bool {
        switch self {
        case .starting, .running:
            return true
        case .stopped, .stopping, .failed:
            return false
        }
    }
}

enum HostScreenMode: Equatable {
    case compactSetup
    case runtime

    static func resolve(
        config: HostConfig,
        bridgeState: ServiceState,
        tunnelState: ServiceState
    ) -> HostScreenMode {
        if config.isComplete || bridgeState.isActive || tunnelState.isActive {
            return .runtime
        }

        return .compactSetup
    }
}

struct HostConfig: Codable, Equatable {
    var repoRoot: String
    var codexCliPath: String
    var hostname: String
    var tunnelName: String
    var tunnelUuid: String
    var credentialsFile: String
    var bridgePort: Int

    static let empty = HostConfig(
        repoRoot: "",
        codexCliPath: "",
        hostname: HostDefaults.hostname,
        tunnelName: HostDefaults.tunnelName,
        tunnelUuid: "",
        credentialsFile: "",
        bridgePort: HostDefaults.bridgePort
    )

    var publicURLString: String {
        "https://\(hostname)"
    }

    var isComplete: Bool {
        !repoRoot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !codexCliPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !hostname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !tunnelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !tunnelUuid.isEmpty &&
            !credentialsFile.isEmpty &&
            bridgePort > 0
    }
}

struct RuntimeState: Codable, Equatable {
    struct ProcessRecord: Codable, Equatable {
        var pid: Int32
        var command: String
    }

    var bridge: ProcessRecord?
    var tunnel: ProcessRecord?

    static let empty = RuntimeState(bridge: nil, tunnel: nil)
}

struct TunnelRecord: Decodable, Equatable {
    let id: String
    let name: String
}

struct ManagedCommandResult {
    let status: Int32
    let stdout: String
    let stderr: String

    var combinedOutput: String {
        [stdout, stderr]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

struct ToolResolution {
    let cloudflaredPath: String
    let codexPath: String
}

struct BridgeHealthSnapshot: Decodable, Equatable {
    let status: String
    let ready: Bool?
    let appServerStatus: String?
    let degradedReason: String?
    let at: String?
    let uptimeSec: UInt64?

    var isReady: Bool {
        ready ?? (status == "ok")
    }

    var effectiveAppServerStatus: String {
        appServerStatus ?? "running"
    }

    var failureDescription: String {
        if let degradedReason, !degradedReason.isEmpty {
            return degradedReason
        }

        if isReady {
            return "Bridge is healthy."
        }

        return "Bridge health degraded (\(effectiveAppServerStatus))."
    }
}

enum HostRepoRootStatus: Equatable {
    case missing
    case invalid(String)
    case ready(String)
}

enum HostBinaryStatus: Equatable {
    case missing(String)
    case ready(String)
}

enum HostTunnelAccessStatus: Equatable {
    case ready
    case blocked(String)
}

struct HostPreflightInput: Equatable {
    let bundledBridge: HostBinaryStatus
    let repoRoot: HostRepoRootStatus
    let codexCli: HostBinaryStatus
    let cloudflaredCli: HostBinaryStatus
    let cloudflaredAccess: HostTunnelAccessStatus
}

enum HostPreflightCheckKey: String, CaseIterable, Identifiable {
    case bundledBridge
    case repoRoot
    case codexCli
    case cloudflaredCli
    case cloudflaredAccess

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bundledBridge:
            return "Bundled bridge"
        case .repoRoot:
            return "Repo root"
        case .codexCli:
            return "Codex CLI"
        case .cloudflaredCli:
            return "cloudflared"
        case .cloudflaredAccess:
            return "Cloudflare login"
        }
    }
}

enum HostPreflightCheckStatus: Equatable {
    case ready(String)
    case blocked(String)

    var detail: String {
        switch self {
        case .ready(let detail), .blocked(let detail):
            return detail
        }
    }

    var isReady: Bool {
        if case .ready = self {
            return true
        }
        return false
    }
}

struct HostPreflightCheck: Equatable, Identifiable {
    let key: HostPreflightCheckKey
    let status: HostPreflightCheckStatus

    var id: String { key.id }
    var title: String { key.title }
}

struct HostPreflight: Equatable {
    let checks: [HostPreflightCheck]

    static let empty = HostPreflight(checks: [])

    var canRunSetup: Bool {
        checks.allSatisfy { $0.status.isReady }
    }

    var canStartServices: Bool {
        canRunSetup
    }

    var blockingMessage: String? {
        checks.first(where: { !$0.status.isReady })?.status.detail
    }

    static func assess(_ input: HostPreflightInput) -> HostPreflight {
        HostPreflight(
            checks: [
                HostPreflightCheck(
                    key: .bundledBridge,
                    status: status(from: input.bundledBridge)
                ),
                HostPreflightCheck(
                    key: .repoRoot,
                    status: repoRootStatus(from: input.repoRoot)
                ),
                HostPreflightCheck(
                    key: .codexCli,
                    status: status(from: input.codexCli)
                ),
                HostPreflightCheck(
                    key: .cloudflaredCli,
                    status: status(from: input.cloudflaredCli)
                ),
                HostPreflightCheck(
                    key: .cloudflaredAccess,
                    status: cloudflaredAccessStatus(
                        from: input.cloudflaredAccess,
                        cloudflaredCli: input.cloudflaredCli
                    )
                )
            ]
        )
    }

    private static func status(from binary: HostBinaryStatus) -> HostPreflightCheckStatus {
        switch binary {
        case .ready(let path):
            return .ready(path)
        case .missing(let message):
            return .blocked(message)
        }
    }

    private static func repoRootStatus(from repoRoot: HostRepoRootStatus) -> HostPreflightCheckStatus {
        switch repoRoot {
        case .missing:
            return .blocked("Choose a repository root for the bridge workspace.")
        case .invalid:
            return .blocked("The selected repo root no longer exists.")
        case .ready(let path):
            return .ready(path)
        }
    }

    private static func cloudflaredAccessStatus(
        from access: HostTunnelAccessStatus,
        cloudflaredCli: HostBinaryStatus
    ) -> HostPreflightCheckStatus {
        switch cloudflaredCli {
        case .missing:
            return .blocked("Install cloudflared before verifying tunnel access.")
        case .ready:
            switch access {
            case .ready:
                return .ready("Authenticated for tunnel management.")
            case .blocked(let message):
                return .blocked(message)
            }
        }
    }
}

struct CloudflaredConfigFile {
    let tunnelUuid: String
    let credentialsFile: String
    let hostname: String
    let bridgePort: Int

    func render() -> String {
        """
        tunnel: \(tunnelUuid)
        credentials-file: "\(credentialsFile)"
        ingress:
          - hostname: \(hostname)
            service: "http://127.0.0.1:\(bridgePort)"
          - service: http_status:404
        """
    }
}

struct BridgeLaunchSpec {
    let bridgeBinaryPath: String
    let codexPath: String
    let repoRoot: String
    let token: String
    let bridgePort: Int

    var environment: [String: String] {
        [
            "BRIDGE_HOST": "127.0.0.1",
            "BRIDGE_PORT": String(bridgePort),
            "BRIDGE_AUTH_TOKEN": token,
            "BRIDGE_ALLOW_QUERY_TOKEN_AUTH": "false",
            "BRIDGE_ALLOW_INSECURE_NO_AUTH": "false",
            "BRIDGE_WORKDIR": repoRoot,
            "BRIDGE_ALLOW_OUTSIDE_ROOT_CWD": "false",
            "BRIDGE_SHOW_PAIRING_QR": "false",
            "CODEX_CLI_BIN": codexPath
        ]
    }
}

struct AppPaths {
    let appSupportDirectory: URL
    let configFile: URL
    let runtimeFile: URL
    let cloudflaredConfigFile: URL
    let tunnelDirectory: URL
    let bridgeLogFile: URL
    let tunnelLogFile: URL

    static func load(fileManager: FileManager = .default) throws -> AppPaths {
        let appSupportBase = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = appSupportBase.appendingPathComponent(HostDefaults.appSupportDirectoryName, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let logs = directory.appendingPathComponent("logs", isDirectory: true)
        try fileManager.createDirectory(at: logs, withIntermediateDirectories: true)
        let tunnel = directory.appendingPathComponent("tunnel", isDirectory: true)
        try fileManager.createDirectory(at: tunnel, withIntermediateDirectories: true)

        return AppPaths(
            appSupportDirectory: directory,
            configFile: directory.appendingPathComponent("config.json"),
            runtimeFile: directory.appendingPathComponent("runtime.json"),
            cloudflaredConfigFile: tunnel.appendingPathComponent("config.yml"),
            tunnelDirectory: tunnel,
            bridgeLogFile: logs.appendingPathComponent("bridge.log"),
            tunnelLogFile: logs.appendingPathComponent("cloudflared.log")
        )
    }

    func tunnelCredentialsFile(for tunnelName: String) -> URL {
        tunnelDirectory.appendingPathComponent("\(sanitizedTunnelFileStem(from: tunnelName)).json")
    }
}

enum HostError: LocalizedError {
    case validation(String)
    case command(String)
    case parsing(String)
    case keychain(String)

    var errorDescription: String? {
        switch self {
        case .validation(let message), .command(let message), .parsing(let message), .keychain(let message):
            return message
        }
    }
}

enum HostLogger {
    static func render(prefix: String, _ message: String) -> String {
        "[\(prefix)] \(message)"
    }
}

private func sanitizedTunnelFileStem(from tunnelName: String) -> String {
    let trimmed = tunnelName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return HostDefaults.tunnelName
    }

    let scalarView = trimmed.unicodeScalars.map { scalar -> Character in
        if CharacterSet.alphanumerics.contains(scalar)
            || scalar == UnicodeScalar("-")
            || scalar == UnicodeScalar("_")
            || scalar == UnicodeScalar(".")
        {
            return Character(scalar)
        }
        return "-"
    }

    let value = String(scalarView)
        .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

    return value.isEmpty ? HostDefaults.tunnelName : value
}
