import XCTest
@testable import ClawdexHost

final class ClawdexHostTests: XCTestCase {
    func testCloudflaredConfigRendersExpectedIngress() {
        let file = CloudflaredConfigFile(
            tunnelUuid: "uuid-123",
            credentialsFile: "/tmp/cred.json",
            hostname: "clawdex.example.com",
            bridgePort: 8787
        )

        let rendered = file.render()

        XCTAssertTrue(rendered.contains("tunnel: uuid-123"))
        XCTAssertTrue(rendered.contains("credentials-file: \"/tmp/cred.json\""))
        XCTAssertTrue(rendered.contains("hostname: clawdex.example.com"))
        XCTAssertTrue(rendered.contains("service: \"http://127.0.0.1:8787\""))
        XCTAssertTrue(rendered.contains("service: http_status:404"))
    }

    func testBridgeEnvironmentDisablesQueryTokenAndOutsideRoot() {
        let spec = BridgeLaunchSpec(
            bridgeBinaryPath: "/tmp/codex-rust-bridge",
            codexPath: "/opt/homebrew/bin/codex",
            repoRoot: "/tmp/repo",
            token: "secret",
            bridgePort: 8787
        )

        XCTAssertEqual(spec.environment["BRIDGE_ALLOW_QUERY_TOKEN_AUTH"], "false")
        XCTAssertEqual(spec.environment["BRIDGE_ALLOW_OUTSIDE_ROOT_CWD"], "false")
        XCTAssertEqual(spec.environment["BRIDGE_AUTH_TOKEN"], "secret")
        XCTAssertEqual(spec.environment["CODEX_CLI_BIN"], "/opt/homebrew/bin/codex")
    }

    func testHostConfigDefaultsToExpectedPublicHostname() {
        XCTAssertEqual(HostConfig.empty.hostname, "clawdex.example.com")
        XCTAssertEqual(HostConfig.empty.publicURLString, "https://clawdex.example.com")
    }

    func testHostConfigUsesConfiguredHostnameAndTunnelName() {
        var config = HostConfig.empty
        config.hostname = "bridge.example.com"
        config.tunnelName = "operator-tunnel"

        XCTAssertEqual(config.publicURLString, "https://bridge.example.com")
        XCTAssertEqual(config.tunnelName, "operator-tunnel")
    }

    func testScreenModeUsesCompactSetupWhenConfigIsIncompleteAndServicesAreInactive() {
        let mode = HostScreenMode.resolve(
            config: .empty,
            bridgeState: .stopped,
            tunnelState: .stopped
        )

        XCTAssertEqual(mode, .compactSetup)
    }

    func testScreenModeUsesRuntimeWhenConfigIsComplete() {
        let mode = HostScreenMode.resolve(
            config: HostConfig(
                repoRoot: "/tmp/repo",
                codexCliPath: "/opt/homebrew/bin/codex",
                hostname: "bridge.example.com",
                tunnelName: "bridge-tunnel",
                tunnelUuid: "uuid-123",
                credentialsFile: "/tmp/bridge.json",
                bridgePort: 8787
            ),
            bridgeState: .stopped,
            tunnelState: .stopped
        )

        XCTAssertEqual(mode, .runtime)
    }

    func testScreenModeUsesRuntimeWhenServicesAreAlreadyActive() {
        let mode = HostScreenMode.resolve(
            config: .empty,
            bridgeState: .running,
            tunnelState: .stopped
        )

        XCTAssertEqual(mode, .runtime)
    }

    func testCredentialPathUsesConfiguredTunnelName() {
        let paths = AppPaths(
            appSupportDirectory: URL(fileURLWithPath: "/tmp/ClawdexHost"),
            configFile: URL(fileURLWithPath: "/tmp/ClawdexHost/config.json"),
            runtimeFile: URL(fileURLWithPath: "/tmp/ClawdexHost/runtime.json"),
            cloudflaredConfigFile: URL(fileURLWithPath: "/tmp/ClawdexHost/tunnel/config.yml"),
            tunnelDirectory: URL(fileURLWithPath: "/tmp/ClawdexHost/tunnel"),
            bridgeLogFile: URL(fileURLWithPath: "/tmp/ClawdexHost/logs/bridge.log"),
            tunnelLogFile: URL(fileURLWithPath: "/tmp/ClawdexHost/logs/cloudflared.log")
        )

        XCTAssertEqual(
            paths.tunnelCredentialsFile(for: "custom-prod-tunnel").path,
            "/tmp/ClawdexHost/tunnel/custom-prod-tunnel.json"
        )
        XCTAssertEqual(
            paths.tunnelCredentialsFile(for: "team tunnel/edge").path,
            "/tmp/ClawdexHost/tunnel/team-tunnel-edge.json"
        )
    }

    func testPreflightPassesWhenAllChecksAreReady() {
        let preflight = HostPreflight.assess(
            HostPreflightInput(
                bundledBridge: .ready("/tmp/codex-rust-bridge"),
                repoRoot: .ready("/tmp/repo"),
                codexCli: .ready("/opt/homebrew/bin/codex"),
                cloudflaredCli: .ready("/opt/homebrew/bin/cloudflared"),
                cloudflaredAccess: .ready
            )
        )

        XCTAssertTrue(preflight.canRunSetup)
        XCTAssertTrue(preflight.canStartServices)
        XCTAssertNil(preflight.blockingMessage)
    }

    func testPreflightBlocksMissingBridgeAndCliDependencies() {
        let preflight = HostPreflight.assess(
            HostPreflightInput(
                bundledBridge: .missing("Build the bundled Rust bridge first."),
                repoRoot: .ready("/tmp/repo"),
                codexCli: .missing("Install Codex CLI."),
                cloudflaredCli: .missing("Install cloudflared."),
                cloudflaredAccess: .blocked("Run `cloudflared login` first.")
            )
        )

        XCTAssertFalse(preflight.canRunSetup)
        XCTAssertEqual(preflight.checks.first(where: { $0.key == .bundledBridge })?.status, .blocked("Build the bundled Rust bridge first."))
        XCTAssertEqual(preflight.checks.first(where: { $0.key == .codexCli })?.status, .blocked("Install Codex CLI."))
        XCTAssertEqual(preflight.checks.first(where: { $0.key == .cloudflaredCli })?.status, .blocked("Install cloudflared."))
        XCTAssertEqual(
            preflight.checks.first(where: { $0.key == .cloudflaredAccess })?.status,
            .blocked("Install cloudflared before verifying tunnel access.")
        )
    }

    func testPreflightBlocksUnauthenticatedCloudflaredAccess() {
        let preflight = HostPreflight.assess(
            HostPreflightInput(
                bundledBridge: .ready("/tmp/codex-rust-bridge"),
                repoRoot: .ready("/tmp/repo"),
                codexCli: .ready("/opt/homebrew/bin/codex"),
                cloudflaredCli: .ready("/opt/homebrew/bin/cloudflared"),
                cloudflaredAccess: .blocked("cloudflared is installed but not authenticated. Run `cloudflared login` on this Mac first.")
            )
        )

        XCTAssertFalse(preflight.canRunSetup)
        XCTAssertEqual(
            preflight.checks.first(where: { $0.key == .cloudflaredAccess })?.status,
            .blocked("cloudflared is installed but not authenticated. Run `cloudflared login` on this Mac first.")
        )
    }
}
