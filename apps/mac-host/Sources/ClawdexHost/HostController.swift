import AppKit
import Foundation

@MainActor
final class HostController: ObservableObject {
    @Published var config: HostConfig
    @Published var bridgeToken = ""
    @Published var bridgeState: ServiceState = .stopped
    @Published var tunnelState: ServiceState = .stopped
    @Published var setupState = "Not configured"
    @Published var statusMessage = "Pick a repo and run setup."
    @Published var logs = ""
    @Published var cloudflaredPath = ""
    @Published var preflight = HostPreflight.empty
    @Published var isBusy = false
    @Published var bridgeLogPath = ""
    @Published var tunnelLogPath = ""

    private let paths: AppPaths
    private let configStore: JSONFileStore<HostConfig>
    private let runtimeStore: JSONFileStore<RuntimeState>
    private var bridgeProcess: ManagedProcess?
    private var tunnelProcess: ManagedProcess?
    private var healthMonitorTask: Task<Void, Never>?
    private var isStoppingServices = false

    var screenMode: HostScreenMode {
        HostScreenMode.resolve(
            config: config,
            bridgeState: bridgeState,
            tunnelState: tunnelState
        )
    }

    var didSetupFail: Bool {
        setupState == "Setup failed"
    }

    init() {
        do {
            let loadedPaths = try AppPaths.load()
            self.paths = loadedPaths
        } catch {
            fatalError("Unable to create application support directory: \(error.localizedDescription)")
        }

        self.configStore = JSONFileStore(url: paths.configFile)
        self.runtimeStore = JSONFileStore(url: paths.runtimeFile)
        self.config = configStore.load(defaultValue: .empty)
        self.bridgeLogPath = paths.bridgeLogFile.path
        self.tunnelLogPath = paths.tunnelLogFile.path

        Task { await bootstrap() }
    }

    func bootstrap() async {
        await appendLog(HostLogger.render(prefix: "host", "Loading host state"))
        do {
            if let savedToken = try KeychainStore.loadToken() {
                bridgeToken = savedToken
            }
        } catch {
            statusMessage = error.localizedDescription
        }

        cleanupOrphans()
        refreshToolingPaths()
    }

    func chooseRepoRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose the repository root that the bridge should control."
        if panel.runModal() == .OK, let url = panel.url {
            config.repoRoot = url.path
            persistConfig()
            refreshPreflight()
        }
    }

    func chooseCodexBinary() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose the Codex CLI executable."
        if panel.runModal() == .OK, let url = panel.url {
            config.codexCliPath = url.path
            refreshToolingPaths()
        }
    }

    func updateHostname(_ hostname: String) {
        let previous = config.hostname.trimmingCharacters(in: .whitespacesAndNewlines)
        config.hostname = hostname
        if previous != hostname.trimmingCharacters(in: .whitespacesAndNewlines) {
            invalidateTunnelSetup()
        }
        persistConfig()
        refreshPreflight()
    }

    func updateTunnelName(_ tunnelName: String) {
        let previous = config.tunnelName.trimmingCharacters(in: .whitespacesAndNewlines)
        config.tunnelName = tunnelName
        if previous != tunnelName.trimmingCharacters(in: .whitespacesAndNewlines) {
            invalidateTunnelSetup()
        }
        persistConfig()
        refreshPreflight()
    }

    func refreshToolingPaths() {
        config.codexCliPath =
            CommandRunner.resolveCodexBinary(preferredPath: config.codexCliPath) ?? config.codexCliPath
        cloudflaredPath = CommandRunner.resolveCloudflaredBinary() ?? ""
        persistConfig()
        refreshPreflight()
    }

    func rotateToken() async {
        bridgeToken = Self.generateBridgeToken()
        do {
            try KeychainStore.saveToken(bridgeToken)
            await appendLog(HostLogger.render(prefix: "host", "Generated a new bridge token"))
            statusMessage = "Bridge token rotated."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func copyPublicURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(config.publicURLString, forType: .string)
        statusMessage = "Copied public URL."
    }

    func copyToken() {
        guard !bridgeToken.isEmpty else {
            statusMessage = "Generate or load a bridge token first."
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(bridgeToken, forType: .string)
        statusMessage = "Copied bridge token."
    }

    func runSetup() async {
        guard !isBusy else {
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            refreshToolingPaths()
            try validateConfigInputs()
            guard preflight.canRunSetup else {
                throw HostError.validation(
                    preflight.blockingMessage ?? "Resolve the setup blockers before running setup."
                )
            }

            if bridgeToken.isEmpty {
                bridgeToken = Self.generateBridgeToken()
            }
            try KeychainStore.saveToken(bridgeToken)

            let tunnelRecord = try ensureTunnel()
            config.tunnelUuid = tunnelRecord.id
            try writeCloudflaredConfig()
            persistConfig()
            refreshPreflight()

            setupState = "Configured"
            statusMessage = "Tunnel setup complete. You can now start services."
            await appendLog(HostLogger.render(prefix: "host", "Setup complete for \(config.publicURLString)"))
        } catch {
            setupState = "Setup failed"
            statusMessage = error.localizedDescription
            await appendLog(HostLogger.render(prefix: "host", "Setup failed: \(error.localizedDescription)"))
        }
    }

    func startServices() async {
        guard !isBusy else {
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            refreshToolingPaths()
            try validateReadyToStart()
            try stopServicesSync()

            bridgeState = .starting
            tunnelState = .starting
            await appendLog(HostLogger.render(prefix: "host", "Starting bridge and tunnel"))

            let bridgePath = try resolveBridgeBinary()
            let bridgeSpec = BridgeLaunchSpec(
                bridgeBinaryPath: bridgePath,
                codexPath: config.codexCliPath,
                repoRoot: config.repoRoot,
                token: bridgeToken,
                bridgePort: config.bridgePort
            )

            let bridge = ManagedProcess(label: "bridge", logURL: paths.bridgeLogFile) { [weak self] message in
                Task { @MainActor in
                    await self?.appendLog(message)
                }
            }
            try bridge.start(
                executable: bridgeSpec.bridgeBinaryPath,
                arguments: [],
                environment: bridgeSpec.environment,
                currentDirectory: URL(fileURLWithPath: config.repoRoot)
            ) { [weak self] status in
                Task { @MainActor in
                    await self?.handleProcessExit(service: .bridge, status: status)
                }
            }
            bridgeProcess = bridge
            persistRuntime()

            _ = try await waitForBridgeHealth()
            bridgeState = .running

            let tunnel = ManagedProcess(label: "cloudflared", logURL: paths.tunnelLogFile) { [weak self] message in
                Task { @MainActor in
                    await self?.appendLog(message)
                }
            }
            try tunnel.start(
                executable: cloudflaredPath,
                arguments: [
                    "tunnel",
                    "--config",
                    paths.cloudflaredConfigFile.path,
                    "run",
                    config.tunnelName
                ]
            ) { [weak self] status in
                Task { @MainActor in
                    await self?.handleProcessExit(service: .tunnel, status: status)
                }
            }
            tunnelProcess = tunnel
            tunnelState = .running
            persistRuntime()
            startHealthMonitor()

            statusMessage = "Bridge and tunnel are running. Use \(config.publicURLString) in the iOS app."
        } catch {
            await appendLog(HostLogger.render(prefix: "host", "Start failed: \(error.localizedDescription)"))
            statusMessage = error.localizedDescription
            try? stopServicesSync(finalBridgeState: .failed, finalTunnelState: .failed)
        }
    }

    func stopServices() async {
        do {
            try stopServicesSync()
            statusMessage = "Bridge and tunnel stopped."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func prepareForTermination() {
        try? stopServicesSync()
    }

    private func stopServicesSync(
        finalBridgeState: ServiceState = .stopped,
        finalTunnelState: ServiceState = .stopped
    ) throws {
        cancelHealthMonitor()
        isStoppingServices = true
        defer { isStoppingServices = false }

        if tunnelProcess != nil {
            tunnelState = .stopping
        }
        if bridgeProcess != nil {
            bridgeState = .stopping
        }

        tunnelProcess?.stop()
        bridgeProcess?.stop()
        tunnelProcess = nil
        bridgeProcess = nil
        tunnelState = finalTunnelState
        bridgeState = finalBridgeState
        persistRuntime(empty: true)
    }

    private func validateConfigInputs() throws {
        let hostname = config.hostname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hostname.isEmpty else {
            throw HostError.validation("Enter the public hostname that should point at this tunnel.")
        }

        let tunnelName = config.tunnelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tunnelName.isEmpty else {
            throw HostError.validation("Enter a Cloudflare tunnel name before running setup.")
        }

        guard !config.repoRoot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw HostError.validation("Choose a repo root before running setup.")
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: config.repoRoot, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw HostError.validation("The selected repo root does not exist.")
        }

        guard let codexPath = CommandRunner.resolveCodexBinary(preferredPath: config.codexCliPath) else {
            throw HostError.validation("Install Codex CLI first or choose the binary manually.")
        }

        _ = try resolveBridgeBinary()

        config.hostname = hostname
        config.tunnelName = tunnelName
        config.codexCliPath = codexPath
    }

    private func validateReadyToStart() throws {
        try validateConfigInputs()
        guard preflight.canStartServices else {
            throw HostError.validation(
                preflight.blockingMessage ?? "Resolve the setup blockers before starting services."
            )
        }
        guard config.isComplete else {
            throw HostError.validation("Run setup before starting services.")
        }
        guard !bridgeToken.isEmpty else {
            throw HostError.validation("Bridge token is missing. Run setup again.")
        }
        guard !cloudflaredPath.isEmpty else {
            throw HostError.validation("cloudflared is not available.")
        }
    }

    private func ensureTunnel() throws -> TunnelRecord {
        guard !cloudflaredPath.isEmpty else {
            throw HostError.validation("cloudflared is not available.")
        }

        let credentialsFile = paths.tunnelCredentialsFile(for: config.tunnelName)
        let tunnels = try loadTunnels()
        if let existing = tunnels.first(where: { $0.name == config.tunnelName }) {
            try prepareCredentialsFile(for: existing.id, destination: credentialsFile)
            try ensureDNSRoute(for: existing.id)
            return existing
        }

        let create = try CommandRunner.run(
            executable: cloudflaredPath,
            arguments: [
                "tunnel",
                "create",
                "--output",
                "json",
                "--credentials-file",
                credentialsFile.path,
                config.tunnelName
            ]
        )
        guard create.status == 0 else {
            throw HostError.command("Failed to create tunnel: \(create.combinedOutput)")
        }

        let refreshed = try loadTunnels()
        guard let created = refreshed.first(where: { $0.name == config.tunnelName }) else {
            throw HostError.parsing("Tunnel was created but could not be found afterwards.")
        }

        config.credentialsFile = credentialsFile.path
        try ensureDNSRoute(for: created.id)
        return created
    }

    private func prepareCredentialsFile(for tunnelUUID: String, destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            config.credentialsFile = destination.path
            return
        }

        let legacyPath = NSString(string: NSHomeDirectory())
            .appendingPathComponent(".cloudflared/\(tunnelUUID).json")
        if FileManager.default.fileExists(atPath: legacyPath) {
            try FileManager.default.copyItem(atPath: legacyPath, toPath: destination.path)
            config.credentialsFile = destination.path
            return
        }

        throw HostError.validation(
            "Tunnel credentials for \(config.tunnelName) are missing. Recreate the tunnel or restore the credential file."
        )
    }

    private func ensureDNSRoute(for tunnelUUID: String) throws {
        let expected = "\(tunnelUUID).cfargotunnel.com"
        if let cname = CommandRunner.digCNAME(hostname: config.hostname) {
            if cname == expected {
                return
            }
            throw HostError.validation(
                "DNS for \(config.hostname) already points to \(cname), not \(expected). Resolve that conflict before continuing."
            )
        }

        let route = try CommandRunner.run(
            executable: cloudflaredPath,
            arguments: ["tunnel", "route", "dns", config.tunnelName, config.hostname]
        )
        guard route.status == 0 else {
            throw HostError.command("Failed to create DNS route: \(route.combinedOutput)")
        }
    }

    private func loadTunnels() throws -> [TunnelRecord] {
        let result = try CommandRunner.run(
            executable: cloudflaredPath,
            arguments: ["tunnel", "list", "--output", "json"]
        )
        guard result.status == 0 else {
            throw HostError.validation("cloudflared is installed but not authenticated. Run `cloudflared login` on this Mac first.")
        }

        let data = Data(result.stdout.utf8)
        do {
            return try JSONDecoder().decode([TunnelRecord].self, from: data)
        } catch {
            throw HostError.parsing("Unable to parse `cloudflared tunnel list` output: \(error.localizedDescription)")
        }
    }

    private func writeCloudflaredConfig() throws {
        let file = CloudflaredConfigFile(
            tunnelUuid: config.tunnelUuid,
            credentialsFile: config.credentialsFile,
            hostname: config.hostname,
            bridgePort: config.bridgePort
        )
        try file.render().write(to: paths.cloudflaredConfigFile, atomically: true, encoding: .utf8)
    }

    private func waitForBridgeHealth() async throws -> BridgeHealthSnapshot {
        var lastFailure = "Bridge failed to become healthy on \(HostDefaults.localhostBridgeURL)."

        for _ in 0..<20 {
            do {
                let snapshot = try await fetchBridgeHealth()
                if snapshot.isReady {
                    return snapshot
                }
                lastFailure = snapshot.failureDescription
            } catch {
                lastFailure = error.localizedDescription
            }
            try await Task.sleep(for: .milliseconds(250))
        }

        throw HostError.command(lastFailure)
    }

    private func fetchBridgeHealth() async throws -> BridgeHealthSnapshot {
        guard let url = URL(string: "\(HostDefaults.localhostBridgeURL)/health") else {
            throw HostError.validation("Local bridge health URL is invalid.")
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw HostError.command("Bridge health endpoint returned an unexpected response.")
        }

        do {
            return try JSONDecoder().decode(BridgeHealthSnapshot.self, from: data)
        } catch {
            throw HostError.parsing("Bridge health response could not be parsed: \(error.localizedDescription)")
        }
    }

    private func resolveBridgeBinary() throws -> String {
        if let bundled = Bundle.module.url(
            forResource: HostDefaults.bridgeBinaryName,
            withExtension: nil,
            subdirectory: "Bundled"
        ) {
            let path = bundled.path
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        let devPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("services/rust-bridge/target/release/\(HostDefaults.bridgeBinaryName)")
            .path
        if FileManager.default.isExecutableFile(atPath: devPath) {
            return devPath
        }

        throw HostError.validation(
            "Bundled Rust bridge binary is missing. Run `npm run mac:host` or `npm run build -w @codex/mac-host` after installing Rust/cargo."
        )
    }

    private func refreshPreflight() {
        preflight = HostPreflight.assess(
            HostPreflightInput(
                bundledBridge: bundledBridgeStatus(),
                repoRoot: repoRootStatus(),
                codexCli: codexCliStatus(),
                cloudflaredCli: cloudflaredCliStatus(),
                cloudflaredAccess: cloudflaredAccessStatus()
            )
        )
        updateSetupState()
    }

    private func bundledBridgeStatus() -> HostBinaryStatus {
        do {
            return .ready(try resolveBridgeBinary())
        } catch {
            return .missing(error.localizedDescription)
        }
    }

    private func repoRootStatus() -> HostRepoRootStatus {
        let repoRoot = config.repoRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repoRoot.isEmpty else {
            return .missing
        }

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: repoRoot, isDirectory: &isDirectory)
        guard exists, isDirectory.boolValue else {
            return .invalid(repoRoot)
        }

        return .ready(repoRoot)
    }

    private func codexCliStatus() -> HostBinaryStatus {
        guard let path = CommandRunner.resolveCodexBinary(preferredPath: config.codexCliPath) else {
            return .missing("Install Codex CLI first or choose the binary manually.")
        }
        return .ready(path)
    }

    private func cloudflaredCliStatus() -> HostBinaryStatus {
        guard !cloudflaredPath.isEmpty else {
            return .missing("Install cloudflared first. The app could not resolve it in PATH or Homebrew defaults.")
        }
        return .ready(cloudflaredPath)
    }

    private func cloudflaredAccessStatus() -> HostTunnelAccessStatus {
        guard !cloudflaredPath.isEmpty else {
            return .blocked("Install cloudflared before verifying tunnel access.")
        }

        do {
            _ = try loadTunnels()
            return .ready
        } catch {
            return .blocked(error.localizedDescription)
        }
    }

    private func startHealthMonitor() {
        cancelHealthMonitor()
        healthMonitorTask = Task { [weak self] in
            while let self {
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    return
                }

                guard !Task.isCancelled else {
                    return
                }

                guard self.bridgeState == .running else {
                    return
                }

                do {
                    let health = try await self.fetchBridgeHealth()
                    if !health.isReady {
                        await self.handleRuntimeFailure(reason: health.failureDescription)
                        return
                    }
                } catch {
                    await self.handleRuntimeFailure(reason: error.localizedDescription)
                    return
                }
            }
        }
    }

    private func cancelHealthMonitor() {
        healthMonitorTask?.cancel()
        healthMonitorTask = nil
    }

    private func handleProcessExit(service: ManagedService, status: Int32) async {
        persistRuntime()

        if isStoppingServices {
            return
        }

        switch service {
        case .bridge:
            guard bridgeState == .starting || bridgeState == .running else {
                bridgeState = status == 0 ? .stopped : .failed
                return
            }
            await handleRuntimeFailure(reason: "Bridge process exited with status \(status). Restart services after fixing the issue.")
        case .tunnel:
            guard tunnelState == .starting || tunnelState == .running else {
                tunnelState = status == 0 ? .stopped : .failed
                return
            }
            await handleRuntimeFailure(reason: "cloudflared exited with status \(status). Restart services after fixing the issue.")
        }
    }

    private func handleRuntimeFailure(reason: String) async {
        guard !isStoppingServices else {
            return
        }

        cancelHealthMonitor()
        await appendLog(HostLogger.render(prefix: "host", "Runtime degraded: \(reason)"))
        statusMessage = reason
        try? stopServicesSync(finalBridgeState: .failed, finalTunnelState: .failed)
    }

    private func updateSetupState() {
        if servicesAreActive {
            return
        }

        if let blockingMessage = preflight.blockingMessage {
            setupState = "Action required"
            statusMessage = blockingMessage
            return
        }

        if config.isComplete {
            setupState = "Configured"
            if bridgeState == .failed || tunnelState == .failed {
                statusMessage = "Setup is valid. Restart services when you are ready."
            } else {
                statusMessage = "Ready to start bridge and tunnel."
            }
            return
        }

        if config.hostname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            setupState = "Needs setup"
            statusMessage = "Enter the public hostname that should point at this Mac."
            return
        }

        if config.tunnelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            setupState = "Needs setup"
            statusMessage = "Enter the Cloudflare tunnel name to create or reuse."
            return
        }

        if !config.repoRoot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            setupState = "Needs setup"
            statusMessage = "Ready to run setup."
            return
        }

        setupState = "Not configured"
        statusMessage = "Pick a repo root, review the hostname/tunnel settings, and run setup."
    }

    private func invalidateTunnelSetup() {
        config.tunnelUuid = ""
        config.credentialsFile = ""
    }

    private var servicesAreActive: Bool {
        bridgeState == .starting ||
            bridgeState == .running ||
            tunnelState == .starting ||
            tunnelState == .running
    }

    private func persistConfig() {
        try? configStore.save(config)
    }

    private func persistRuntime(empty: Bool = false) {
        if empty {
            try? runtimeStore.save(.empty)
            return
        }

        let runtime = RuntimeState(
            bridge: bridgeProcess?.pid.map {
                RuntimeState.ProcessRecord(pid: $0, command: HostDefaults.bridgeBinaryName)
            },
            tunnel: tunnelProcess?.pid.map {
                RuntimeState.ProcessRecord(pid: $0, command: "cloudflared")
            }
        )
        try? runtimeStore.save(runtime)
    }

    private func cleanupOrphans() {
        let runtime = runtimeStore.load(defaultValue: .empty)
        cleanup(record: runtime.bridge)
        cleanup(record: runtime.tunnel)
        persistRuntime(empty: true)
    }

    private func cleanup(record: RuntimeState.ProcessRecord?) {
        guard let record else {
            return
        }

        guard let commandLine = CommandRunner.processCommandLine(for: record.pid), commandLine.contains(record.command) else {
            return
        }

        kill(record.pid, SIGTERM)
        Thread.sleep(forTimeInterval: 0.5)
        if CommandRunner.processCommandLine(for: record.pid) != nil {
            kill(record.pid, SIGKILL)
        }
    }

    private func appendLog(_ line: String) async {
        let cleaned = line.trimmingCharacters(in: .newlines)
        guard !cleaned.isEmpty else {
            return
        }

        let next = logs.isEmpty ? cleaned : "\(logs)\n\(cleaned)"
        let segments = next.split(separator: "\n", omittingEmptySubsequences: false)
        if segments.count > 400 {
            logs = segments.suffix(400).joined(separator: "\n")
        } else {
            logs = next
        }
    }

    private static func generateBridgeToken() -> String {
        let bytes = (0..<24).map { _ in UInt8.random(in: 0...255) }
        return Data(bytes).map { String(format: "%02x", $0) }.joined()
    }
}

private enum ManagedService {
    case bridge
    case tunnel
}
