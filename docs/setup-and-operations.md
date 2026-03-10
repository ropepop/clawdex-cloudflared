# Setup and Operations

This guide is the detailed companion to the top-level `README.md`.

## macOS Host App + Cloudflare Tunnel

This is the primary host flow for the public fork. It does not use `.env.secure`, does not print a pairing QR, and does not expose a LAN/Tailscale bridge URL to the phone.

### 1) Install dependencies

```bash
npm install
```

### 2) Verify host prerequisites

```bash
cargo --version
cloudflared tunnel list
codex --version
```

Requirements for this path:

- `cargo` is required because the macOS host build bundles `codex-rust-bridge`
- `cloudflared tunnel list` must succeed on this Mac before the host app can configure or run the tunnel
- `codex --version` should succeed unless you plan to select a custom binary manually in-app

### 3) Build and test the macOS host app

```bash
npm run test -w @codex/mac-host
npm run build -w @codex/mac-host
```

### 4) Launch the host app

```bash
npm run mac:host
```

### 5) In-app setup

In the macOS app:

1. choose the repo root
2. confirm the preflight checks are green for:
   - bundled bridge
   - repo root
   - `codex`
   - `cloudflared`
   - Cloudflare login
3. review or change the public hostname and tunnel name
4. run setup to create or reuse the configured tunnel
5. verify the app shows a tunnel UUID and credential file path
6. start services and wait for Bridge + Tunnel to report running

### 6) Manual mobile onboarding

In the iOS app, enter:

- bridge URL: the public URL shown in the macOS host app
- bridge token: the token shown in the macOS host app

This flow is manual. There is no QR pairing.

## Manual Secure Setup (LAN / Tailscale)

This is the secondary host flow. It uses `.env.secure`, LAN/Tailscale reachability, and QR/manual pairing inside the mobile app.

### 1) Install dependencies

```bash
npm install
```

### 2) Generate secure runtime config

```bash
npm run secure:setup
```

Creates/updates:

- `.env.secure` (bridge runtime config + token)
- `apps/mobile/.env` (mobile token + optional runtime knobs)

### 3) Start bridge

```bash
npm run secure:bridge
```

### 4) Start Expo

```bash
npm run mobile
```

`npm run mobile` uses `scripts/start-expo.sh`, which sets `REACT_NATIVE_PACKAGER_HOSTNAME` from your secure config so QR resolution is predictable.

On first app launch, onboarding will ask for your bridge URL (for example `http://100.x.y.z:8787` or `http://192.168.x.y:8787`). This URL is stored on-device and can be changed later in Settings.

## Guided Setup Wizard

Use this when you want the repo-managed LAN/Tailscale onboarding path:

```bash
npm run setup:wizard
```

Expected output cues:

1. Bridge health passes.
2. Expo starts in the background.
3. A short spinner may appear while Expo warms up.
4. Expo prints its QR block and connection URL.
5. You can detach while Expo + bridge keep running.

## Advanced Knobs

Optional environment variables:

- `CLAWDEX_SETUP_VERBOSE=true` — show full installer output
- `BRIDGE_HEALTH_WAIT_SECS=300` — max wait for bridge `/health`
- `EXPO_OUTPUT_WAIT_SECS=90` — spinner timeout before streaming Expo logs
- `EXPO_AUTO_REPAIR=true` — auto-repair React Native runtime on `npm run mobile`
- `EXPO_CLEAR_CACHE=true` — force `expo start --clear` via `npm run mobile`

## Teardown / Cleanup

```bash
npm run teardown
```

Can:

- stop Expo + bridge
- remove generated artifacts (`.env.secure`, `.bridge.log`, `.expo.log`, pid files)
- optionally reset `apps/mobile/.env` from `.env.example`
- optionally run `tailscale down`

Non-interactive mode:

```bash
npm run teardown -- --yes
```

## Environment Reference

### Bridge runtime (`.env.secure`, generated)

| Variable | Purpose |
|---|---|
| `BRIDGE_HOST` | bind host for rust bridge |
| `BRIDGE_PORT` | bridge port (default `8787`) |
| `BRIDGE_AUTH_TOKEN` | required auth token |
| `BRIDGE_ALLOW_QUERY_TOKEN_AUTH` | query-token auth fallback |
| `CODEX_CLI_BIN` | codex executable |
| `BRIDGE_WORKDIR` | absolute working directory for terminal/git |
| `BRIDGE_ALLOW_OUTSIDE_ROOT_CWD` | allow terminal/git `cwd` outside `BRIDGE_WORKDIR` |

### Mobile runtime (`apps/mobile/.env`, generated/updated)

| Variable | Purpose |
|---|---|
| `EXPO_PUBLIC_HOST_BRIDGE_TOKEN` | token sent by mobile client |
| `EXPO_PUBLIC_ALLOW_QUERY_TOKEN_AUTH` | query-token behavior for WebSocket auth fallback |
| `EXPO_PUBLIC_ALLOW_INSECURE_REMOTE_BRIDGE` | suppress insecure-HTTP warning |
| `EXPO_PUBLIC_PRIVACY_POLICY_URL` | in-app Privacy link |
| `EXPO_PUBLIC_TERMS_OF_SERVICE_URL` | in-app Terms link |

## Production Readiness Checklist

- Keep bridge network-private only (Tailscale/private LAN/VPN + host firewall)
- Require `BRIDGE_AUTH_TOKEN`
- Keep `BRIDGE_ALLOW_QUERY_TOKEN_AUTH=true` only on private networks (required for Android WS auth fallback)
- Do not set `BRIDGE_ALLOW_INSECURE_NO_AUTH=true` outside local debugging
- Scope `BRIDGE_WORKDIR` to minimal required root
- Use strict default approvals on mobile
- Treat `Session`/`Allow similar` approval actions as privileged
- Run bridge under a supervisor with restart policy
- Rotate bridge tokens periodically and on device loss
- Keep `codex`, Node deps, Expo SDK, and OS patches updated

## Verifying Setup

### macOS host app + Cloudflare Tunnel

1. Run `cloudflared tunnel list` and confirm it succeeds.
2. In the macOS app, confirm both Bridge and Tunnel show running state.
3. Open the public URL shown in the app:

```bash
curl https://<configured-hostname>/health
```

Expected response contains:

- `"status":"ok"`
- `"ready":true`
- `"appServerStatus":"running"`

4. In the iOS app, use `Test Connection` or connect normally and confirm the authenticated RPC check succeeds (`bridge/health/read`).

### LAN/Tailscale bridge health

This is the non-Cloudflare verification path.

```bash
source .env.secure
curl "http://$BRIDGE_HOST:$BRIDGE_PORT/health"
```

Expected response contains `"status":"ok"`. Newer bridge revisions also include `ready`, `appServerStatus`, and optionally `degradedReason` to reflect whether the inner `codex app-server` is actually usable.

### In-app smoke test

1. Open app and verify Settings reports bridge connected
2. Set `Start Directory` from sidebar (optional)
3. Create a chat and send a prompt
4. Switch to Plan mode and send prompt that triggers clarifying options
5. Verify clarification flow can submit
6. Open Git from header and verify status/diff/commit/push behavior
7. Test attachment menu (`+`) with workspace path + phone file/image
8. Run long task and verify stop button interrupts run and transcript logs stop

## Mobile UX Notes

- Start Directory applies to new chats, not existing ones.
- Plan mode is sent through `turn/start` via structured `collaborationMode`.
- Approval decisions are surfaced through `bridge/approval.requested` and `bridge/approval.resolved`.
- Mobile slash commands include `/help`, `/new`, `/model`, `/plan`, `/status`, `/rename`, `/compact`, `/review`, `/fork`, and `/diff`.

## API Summary (Rust Bridge)

### Endpoints

- `GET /health`
- `GET /rpc` (WebSocket JSON-RPC)

### Health fields

Bridge health payloads preserve `status: "ok"` for compatibility and now also include:

- `ready` — whether the inner `codex app-server` is currently usable
- `appServerStatus` — `running`, `stopped`, or `failed`
- `degradedReason` — present when `ready` is `false`

### Forwarded methods

- `thread/*`
- `turn/*` (includes `turn/interrupt`)
- `review/start`
- `model/list`
- `skills/list`
- `app/list`

### Bridge RPC methods

- `bridge/health/read`
- `bridge/terminal/exec`
- `bridge/attachments/upload`
- `bridge/voice/transcribe`
- `bridge/git/status`
- `bridge/git/diff`
- `bridge/git/commit`
- `bridge/git/push`
- `bridge/approvals/list`
- `bridge/approvals/resolve`
- `bridge/userInput/resolve`

### Notifications (examples)

- `turn/*`, `item/*`
- `bridge/approval.*`
- `bridge/userInput.*`
- `bridge/terminal/completed`
- `bridge/git/updated`
- `bridge/connection/state`
