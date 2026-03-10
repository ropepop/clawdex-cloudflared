# Clawdex Host

Native macOS launcher for running the Rust bridge behind Cloudflare Tunnel.

This is the canonical host-app path for publishing the bridge through a Cloudflare Tunnel while keeping the local bridge bound to `127.0.0.1:8787`.

The mobile app source is unchanged for this flow. Pair manually by entering:

- bridge URL: the public URL shown by the macOS host app
- bridge token: the value shown in the macOS host app

There is no QR pairing in this path.

Defaults:

- hostname: `clawdex.example.com`
- tunnel name: `clawdex-host`

Both values are editable in-app before setup.

## Prerequisites

- macOS
- Rust toolchain with `cargo`
- `cloudflared` installed and already authenticated on this Mac
- `codex` available in `PATH` or one of the standard Homebrew locations
- a local repository/worktree selected as the bridge root

Verify Cloudflare auth before launching the app:

```bash
cargo --version
cloudflared tunnel list
codex --version
```

## Build and Run

Run the test/build path first so the bundled `codex-rust-bridge` binary is copied into the app resources.

## Test

```bash
npm run test -w @codex/mac-host
```

## Build

```bash
npm run build -w @codex/mac-host
```

`npm run build -w @codex/mac-host` requires `cargo`. If Rust is missing, the build fails before app launch.

## Launch

```bash
npm run mac:host
```

## In-App Setup Flow

1. Choose the repo/worktree root.
2. Confirm preflight passes for:
   - bundled bridge
   - repo root
   - `codex`
   - `cloudflared`
   - Cloudflare login
3. Keep the default hostname/tunnel name or replace them with your own values.
4. Run setup.
5. The app creates or reuses the configured tunnel and configures DNS for the configured hostname.
6. Start services.
7. Copy the public URL and bridge token into the iOS app.

## Runtime Behavior

- The Rust bridge binds to `127.0.0.1:8787`.
- `cloudflared` publishes the bridge at the configured public URL.
- The bridge token is stored in macOS Keychain.
- Tunnel config, credentials copy, runtime state, and logs live under `~/Library/Application Support/ClawdexHost/`.
- Closing the host window quits the app and terminates both child processes.
- The app only treats the bridge as running when `/health` reports `ready: true`.
- If the bridge health becomes degraded, the app marks failure, stops the tunnel, preserves logs, and requires a manual restart.

## Notes

- This is a single-operator self-hosted flow. It does not add Cloudflare Access.
- The app does not use `.env.secure` and does not print pairing QR codes.
- If you lose the device or want to re-pair, rotate the token in the macOS app and update it in the mobile app.
- If `/health` shows `ready: false`, inspect the bridge log path shown in the app and restart services after fixing the underlying `codex app-server` issue.
