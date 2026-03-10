import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var controller: HostController
    @State private var compactLogsExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
                hero

                if controller.screenMode == .compactSetup {
                    compactSetupSection
                    compactLogSection
                } else {
                    runtimeSetupSection
                    runtimeSection
                    logSection
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(metrics.outerPadding)
        }
        .frame(
            minWidth: metrics.windowWidth,
            idealWidth: metrics.windowWidth,
            minHeight: metrics.windowHeight,
            idealHeight: metrics.windowHeight
        )
        .background(backgroundGradient)
        .preferredColorScheme(.dark)
        .onChange(of: controller.screenMode) { _, newMode in
            if newMode == .compactSetup {
                compactLogsExpanded = false
            }
        }
        .onChange(of: controller.didSetupFail) { _, didFail in
            if didFail && controller.screenMode == .compactSetup {
                compactLogsExpanded = true
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: isCompactSetup ? 8 : 10) {
            Text("Clawdex Host")
                .font(.system(size: isCompactSetup ? 24 : 28, weight: .bold, design: .rounded))
            Text("Window-bound launcher for the Rust bridge and Cloudflare Tunnel.")
                .font(.system(size: isCompactSetup ? 13 : 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            HStack(spacing: isCompactSetup ? 8 : 10) {
                statusBadge(title: "Setup", value: controller.setupState, color: .blue)
                statusBadge(
                    title: "Bridge",
                    value: controller.bridgeState.rawValue.capitalized,
                    color: stateColor(controller.bridgeState)
                )
                statusBadge(
                    title: "Tunnel",
                    value: controller.tunnelState.rawValue.capitalized,
                    color: stateColor(controller.tunnelState)
                )
            }
        }
    }

    private var compactSetupSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: metrics.cardSpacing) {
                compactInfoRow(title: "Public URL", value: controller.config.publicURLString) {
                    controller.copyPublicURL()
                }
                compactInfoRow(
                    title: "Bridge token",
                    value: controller.bridgeToken.isEmpty ? "Not generated" : controller.bridgeToken
                ) {
                    controller.copyToken()
                }

                HStack(alignment: .top, spacing: metrics.inlineSpacing) {
                    compactInputField(
                        title: "Public hostname",
                        placeholder: "clawdex.example.com",
                        text: hostnameBinding
                    )
                    compactInputField(
                        title: "Tunnel name",
                        placeholder: "clawdex-host",
                        text: tunnelNameBinding
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    compactDetailRow(
                        title: "Repo root",
                        value: controller.config.repoRoot.isEmpty ? "Not selected" : controller.config.repoRoot,
                        isPlaceholder: controller.config.repoRoot.isEmpty
                    )
                    compactDetailRow(
                        title: "Codex CLI",
                        value: controller.config.codexCliPath.isEmpty ? "Not detected" : controller.config.codexCliPath,
                        isPlaceholder: controller.config.codexCliPath.isEmpty
                    )
                    compactDetailRow(
                        title: "cloudflared",
                        value: controller.cloudflaredPath.isEmpty ? "Not detected" : controller.cloudflaredPath,
                        isPlaceholder: controller.cloudflaredPath.isEmpty
                    )

                    if !controller.config.tunnelUuid.isEmpty {
                        compactDetailRow(
                            title: "Tunnel UUID",
                            value: controller.config.tunnelUuid,
                            isPlaceholder: false
                        )
                    }

                    if !controller.config.credentialsFile.isEmpty {
                        compactDetailRow(
                            title: "Credential file",
                            value: controller.config.credentialsFile,
                            isPlaceholder: false
                        )
                    }
                }

                HStack(spacing: metrics.inlineSpacing) {
                    Button("Choose Repo Root") {
                        controller.chooseRepoRoot()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Choose Codex Binary") {
                        controller.chooseCodexBinary()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Refresh Detection") {
                        controller.refreshToolingPaths()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Preflight")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)

                    ForEach(controller.preflight.checks) { check in
                        preflightRow(
                            title: check.title,
                            detail: check.status.detail,
                            color: preflightStateColor(check.status),
                            compact: true
                        )
                    }
                }

                Button("Run Setup") {
                    Task { await controller.runSetup() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(runSetupDisabled)

                Text(controller.statusMessage)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(metrics.cardPadding)
        } label: {
            Label("Setup", systemImage: "slider.horizontal.3")
        }
    }

    private var runtimeSetupSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                infoRow(title: "Public URL", value: controller.config.publicURLString) {
                    controller.copyPublicURL()
                }
                infoRow(
                    title: "Bridge token",
                    value: controller.bridgeToken.isEmpty ? "Not generated" : controller.bridgeToken
                ) {
                    controller.copyToken()
                }
                HStack(spacing: 10) {
                    Button("Rotate Token") {
                        Task { await controller.rotateToken() }
                    }
                    .buttonStyle(.bordered)

                    Button("Choose Repo Root") {
                        controller.chooseRepoRoot()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Choose Codex Binary") {
                        controller.chooseCodexBinary()
                    }
                    .buttonStyle(.bordered)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Public hostname")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    TextField(
                        "clawdex.example.com",
                        text: hostnameBinding
                    )
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Tunnel name")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    TextField(
                        "clawdex-host",
                        text: tunnelNameBinding
                    )
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
                }

                LabeledContent("Repo root") {
                    Text(controller.config.repoRoot.isEmpty ? "Not selected" : controller.config.repoRoot)
                        .textSelection(.enabled)
                        .foregroundStyle(controller.config.repoRoot.isEmpty ? .secondary : .primary)
                }
                LabeledContent("Codex CLI") {
                    Text(controller.config.codexCliPath.isEmpty ? "Not detected" : controller.config.codexCliPath)
                        .textSelection(.enabled)
                        .foregroundStyle(controller.config.codexCliPath.isEmpty ? .secondary : .primary)
                }
                LabeledContent("cloudflared") {
                    Text(controller.cloudflaredPath.isEmpty ? "Not detected" : controller.cloudflaredPath)
                        .textSelection(.enabled)
                        .foregroundStyle(controller.cloudflaredPath.isEmpty ? .secondary : .primary)
                }
                LabeledContent("Tunnel UUID") {
                    Text(controller.config.tunnelUuid.isEmpty ? "Not created yet" : controller.config.tunnelUuid)
                        .textSelection(.enabled)
                        .foregroundStyle(controller.config.tunnelUuid.isEmpty ? .secondary : .primary)
                }
                LabeledContent("Credential file") {
                    Text(credentialFileDescription)
                        .textSelection(.enabled)
                        .foregroundStyle(controller.config.credentialsFile.isEmpty ? .secondary : .primary)
                }
                Text(controller.statusMessage)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Preflight")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    ForEach(controller.preflight.checks) { check in
                        preflightRow(
                            title: check.title,
                            detail: check.status.detail,
                            color: preflightStateColor(check.status),
                            compact: false
                        )
                    }
                }

                HStack(spacing: 10) {
                    Button("Refresh Detection") {
                        controller.refreshToolingPaths()
                    }
                    .buttonStyle(.bordered)

                    Button("Run Setup") {
                        Task { await controller.runSetup() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(runSetupDisabled)
                }
            }
            .padding(12)
        } label: {
            Label("Setup", systemImage: "slider.horizontal.3")
        }
    }

    private var runtimeSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("Use the same TestFlight app: enter the public URL and bridge token shown above. No QR pairing is required in this version.")
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button("Start Services") {
                        Task { await controller.startServices() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(startServicesDisabled)

                    Button("Stop Services") {
                        Task { await controller.stopServices() }
                    }
                    .buttonStyle(.bordered)
                }
                Divider()
                LabeledContent("Bridge log file") {
                    Text(controller.bridgeLogPath)
                        .textSelection(.enabled)
                }
                LabeledContent("Tunnel log file") {
                    Text(controller.tunnelLogPath)
                        .textSelection(.enabled)
                }
                Text("Closing the window quits the app and stops both child processes by design.")
                    .foregroundStyle(.secondary)
            }
            .padding(12)
        } label: {
            Label("Runtime", systemImage: "bolt.horizontal.circle")
        }
    }

    private var compactLogSection: some View {
        DisclosureGroup(isExpanded: $compactLogsExpanded) {
            logBody(minHeight: 180)
                .padding(.top, 8)
        } label: {
            Label("Recent Logs", systemImage: "text.page")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .padding(metrics.cardPadding)
        .background(cardBackground(cornerRadius: 12))
    }

    private var logSection: some View {
        GroupBox {
            logBody(minHeight: 280)
                .padding(12)
        } label: {
            Label("Recent Logs", systemImage: "text.page")
        }
    }

    private func compactInfoRow(title: String, value: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Text(value)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(cardBackground(cornerRadius: 10))

                Button("Copy", action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    private func compactInputField(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func compactDetailRow(title: String, value: String, isPlaceholder: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .textSelection(.enabled)
                .foregroundStyle(isPlaceholder ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(cardBackground(cornerRadius: 10))
    }

    private func infoRow(title: String, value: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Text(value)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(cardBackground(cornerRadius: 12))
                Button("Copy", action: action)
                    .buttonStyle(.bordered)
            }
        }
    }

    private func statusBadge(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: isCompactSetup ? 12 : 13, weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
        .padding(.horizontal, isCompactSetup ? 10 : 12)
        .padding(.vertical, isCompactSetup ? 7 : 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(color.opacity(0.45), lineWidth: 1)
                )
        )
    }

    private func preflightRow(title: String, detail: String, color: Color, compact: Bool) -> some View {
        HStack(alignment: .top, spacing: compact ? 8 : 10) {
            Circle()
                .fill(color)
                .frame(width: compact ? 8 : 10, height: compact ? 8 : 10)
                .padding(.top, compact ? 3 : 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: compact ? 11 : 12, weight: .semibold, design: .rounded))
                Text(detail)
                    .font(.system(size: compact ? 11 : 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, compact ? 10 : 12)
        .padding(.vertical, compact ? 8 : 10)
        .background(cardBackground(cornerRadius: 12))
    }

    private func logBody(minHeight: CGFloat) -> some View {
        ScrollView {
            Text(controller.logs.isEmpty ? "Logs will appear here once setup or runtime actions begin." : controller.logs)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity, minHeight: minHeight)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.18))
        )
    }

    private var hostnameBinding: Binding<String> {
        Binding(
            get: { controller.config.hostname },
            set: { newValue in
                controller.updateHostname(newValue)
            }
        )
    }

    private var tunnelNameBinding: Binding<String> {
        Binding(
            get: { controller.config.tunnelName },
            set: { newValue in
                controller.updateTunnelName(newValue)
            }
        )
    }

    private var credentialFileDescription: String {
        if !controller.config.credentialsFile.isEmpty {
            return controller.config.credentialsFile
        }

        let tunnelName = controller.config.tunnelName.trimmingCharacters(in: .whitespacesAndNewlines)
        if tunnelName.isEmpty {
            return "Will be created during setup"
        }

        return "Will be created at \(tunnelName).json during setup"
    }

    private var runSetupDisabled: Bool {
        controller.isBusy ||
            !controller.preflight.canRunSetup ||
            controller.config.hostname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            controller.config.tunnelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var startServicesDisabled: Bool {
        controller.isBusy || !controller.preflight.canStartServices || !controller.config.isComplete
    }

    private var isCompactSetup: Bool {
        controller.screenMode == .compactSetup
    }

    private var metrics: LayoutMetrics {
        isCompactSetup ? .compact : .runtime
    }

    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.09, green: 0.11, blue: 0.15),
                Color(red: 0.13, green: 0.16, blue: 0.20)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func cardBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.white.opacity(0.06))
    }

    private func preflightStateColor(_ status: HostPreflightCheckStatus) -> Color {
        switch status {
        case .ready:
            return .green
        case .blocked:
            return .orange
        }
    }

    private func stateColor(_ state: ServiceState) -> Color {
        switch state {
        case .running:
            return .green
        case .starting, .stopping:
            return .orange
        case .failed:
            return .red
        case .stopped:
            return .gray
        }
    }
}

private struct LayoutMetrics {
    let windowWidth: CGFloat
    let windowHeight: CGFloat
    let outerPadding: CGFloat
    let sectionSpacing: CGFloat
    let cardPadding: CGFloat
    let cardSpacing: CGFloat
    let inlineSpacing: CGFloat

    static let compact = LayoutMetrics(
        windowWidth: 720,
        windowHeight: 560,
        outerPadding: 16,
        sectionSpacing: 12,
        cardPadding: 12,
        cardSpacing: 12,
        inlineSpacing: 8
    )

    static let runtime = LayoutMetrics(
        windowWidth: 920,
        windowHeight: 760,
        outerPadding: 20,
        sectionSpacing: 16,
        cardPadding: 12,
        cardSpacing: 12,
        inlineSpacing: 10
    )
}
