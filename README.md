# Clawdex Cloudflared

<p align="center">
  <img src="apps/mobile/assets/brand/app-icon.png" alt="Clawdex Cloudflared app icon" width="112" />
</p>

Clawdex Cloudflared is a self-hosted mobile + macOS control surface for Codex. It pairs an Expo React Native client with a Rust bridge and a native macOS host app that can publish the bridge through Cloudflare Tunnel without exposing your local machine directly.

This public fork is a sanitized derivative of the original [clawdex-mobile](https://github.com/Mohit-Patil/clawdex-mobile). The code is flattened into a clean public history, but the original upstream remains linked here for attribution.

## Repository Layout

- `apps/mac-host`: native SwiftUI macOS launcher for the Rust bridge + Cloudflare Tunnel
- `apps/mobile`: Expo mobile client for chat, approvals, Git, terminal, and settings
- `services/rust-bridge`: primary backend bridge (`/health` + `/rpc`, `codex app-server` adapter)
- `services/mac-bridge`: legacy TypeScript bridge kept for reference
- `docs/`: setup, troubleshooting, release, and compliance notes

## Primary Quickstart: Cloudflare Tunnel + macOS Host App

This is the primary path for this fork. It keeps the bridge bound to `127.0.0.1:8787` and publishes it through a hostname you control.

### 1. Install dependencies

```bash
npm install
```

### 2. Verify host prerequisites

```bash
cargo --version
cloudflared tunnel list
codex --version
```

You need:

- macOS
- Node.js 20+
- npm 10+
- Rust toolchain with `cargo`
- `codex` in `PATH`
- `cloudflared` installed and authenticated on this Mac

### 3. Build and launch the host app

```bash
npm run test -w @codex/mac-host
npm run build -w @codex/mac-host
npm run mac:host
```

### 4. Configure the tunnel in the macOS app

In `apps/mac-host`:

1. Select the repo root.
2. Confirm preflight is green for bundled bridge, repo root, `codex`, `cloudflared`, and Cloudflare login.
3. Replace the default example hostname if needed.
4. Run setup to create or reuse the tunnel and DNS route.
5. Start services and wait for Bridge + Tunnel to show running.
6. Copy the public URL and bridge token shown in the app.

### 5. Pair the mobile app manually

Use the public URL and bridge token from the macOS host app in the mobile app onboarding/settings flow.

- There is no QR pairing in the Cloudflare path.
- Closing the macOS host app stops both the bridge and `cloudflared`.
- The host app stores the bridge token in Keychain and runtime files under `~/Library/Application Support/ClawdexHost/`.

## Secondary Host Flow: LAN or Tailscale

This repo still supports the original private-network bridge flow when you do not want Cloudflare Tunnel.

```bash
npm run secure:setup
npm run secure:bridge
npm run mobile
```

Use `npm run setup:wizard` if you want the guided path. This flow uses `.env.secure`, private-network reachability, and QR/manual pairing inside the mobile app.

## Day-to-Day Commands

From repo root:

- `npm run mac:host`
- `npm run mobile`
- `npm run ios`
- `npm run android`
- `npm run setup:wizard`
- `npm run secure:setup`
- `npm run secure:bridge`
- `npm run secure:bridge:dev`
- `npm run stop:services`
- `npm run teardown`
- `npm run lint`
- `npm run typecheck`
- `npm run build`

## Mobile App and Release Notes

- The mobile app source is included in `apps/mobile`.
- This fork intentionally removes owner-bound Expo/App Store identifiers.
- Before using EAS or store submission, configure your own bundle IDs, Expo project linkage, and submission settings.
- See [docs/eas-builds.md](docs/eas-builds.md) for the owner-supplied build checklist.

## Security Notes

- Treat the bridge as trusted-network or owner-operated infrastructure.
- Do not expose the Rust bridge directly to the public internet.
- Keep bridge tokens private and rotate them on device loss or suspected exposure.
- Review terminal, Git, and approval actions carefully before allowing them.

## Docs

- [Setup and Operations](docs/setup-and-operations.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Privacy Policy](docs/privacy-policy.md)
- [Terms of Service](docs/terms-of-service.md)
- [EAS Builds](docs/eas-builds.md)
- [Open Source License Requirements](docs/open-source-license-requirements.md)

```bash
# Android emulator or connected Android device
npx expo run:android
```

Optional local EAS build:

```bash
# Requires local Android SDK / Xcode setup
eas build --platform android --profile preview --local
```

## Documentation Map

- Setup + operations: [`docs/setup-and-operations.md`](docs/setup-and-operations.md)
- Troubleshooting: [`docs/troubleshooting.md`](docs/troubleshooting.md)
- Realtime sync limits/mitigations: [`docs/realtime-streaming-limitations.md`](docs/realtime-streaming-limitations.md)
- Voice transcription internals: [`docs/voice-transcription.md`](docs/voice-transcription.md)
- Open-source license obligations: [`docs/open-source-license-requirements.md`](docs/open-source-license-requirements.md)
- App review template: [`docs/app-review-notes.md`](docs/app-review-notes.md)
- App-server/CLI gap tracking: [`docs/codex-app-server-cli-gap-tracker.md`](docs/codex-app-server-cli-gap-tracker.md)

## Open Source License Requirements

Follow project requirements in:

- `LICENSE`
- `docs/open-source-license-requirements.md`

## Development Checks

From repo root:

```bash
npm run lint
npm run typecheck
npm run build
npm run test
```
