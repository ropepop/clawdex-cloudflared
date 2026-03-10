# Troubleshooting

## macOS host build fails because `cargo` is missing

The macOS host build bundles the Rust bridge, so Rust is required.

Install Rust, then retry:

```bash
curl https://sh.rustup.rs -sSf | sh -s -- -y --profile minimal
. "$HOME/.cargo/env"
npm run build -w @codex/mac-host
```

If the shell still cannot find `cargo`, restart the shell or source `"$HOME/.cargo/env"` before rerunning npm commands.

## `cloudflared` is missing or not authenticated

Symptoms:

- macOS host app cannot complete setup
- `cloudflared tunnel list` fails

Recovery:

```bash
cloudflared tunnel list
cloudflared login
cloudflared tunnel list
```

Then relaunch `npm run mac:host` or rerun setup in the app.

## DNS for the configured hostname already points elsewhere

The macOS host app expects the hostname shown in its setup form to point at the configured tunnel.

If setup reports a DNS conflict:

- inspect the existing DNS record in Cloudflare
- remove or change the conflicting record
- confirm the hostname/tunnel name you entered in the app are the intended values
- rerun setup in the macOS host app

## Tunnel exists but the credentials file is missing

The app copies tunnel credentials into:

- `~/Library/Application Support/ClawdexHost/tunnel/<tunnel-name>.json`

If the tunnel already exists but that file is missing:

- ensure the original credentials file still exists under `~/.cloudflared/`
- rerun setup in the macOS host app
- if the original file is gone, recreate the tunnel and rerun setup

## Public URL works but `/rpc` returns `401`

This usually means the tunnel is healthy but the bridge token in the mobile app is wrong.

Recovery:

- confirm `https://<configured-hostname>/health` returns `"status":"ok"` and `"ready":true`
- copy the token again from the macOS host app
- paste it into iOS onboarding/settings
- retry connection

## `/health` returns `ready: false` or `appServerStatus` is not `running`

This means the Rust bridge is reachable, but its inner `codex app-server` is unavailable.

Recovery:

- inspect the bridge log path shown in the macOS host app
- confirm `codex --version` still works on this Mac
- stop and restart services from the macOS host app
- if the issue persists, relaunch `npm run mac:host` and retry setup/start

If `degradedReason` is present in `/health`, use that message as the primary debugging lead.

## Remote access stops when you close the macOS host app

This is expected in v1.

- closing the macOS host window quits the app
- quitting the app stops both the bridge and `cloudflared`

To restore access, relaunch:

```bash
npm run mac:host
```

## Bridge auth errors (`401`, invalid token)

For the macOS host app path:

- ensure the token entered in mobile exactly matches the value shown in the macOS app
- if the token has drifted, rotate it in the macOS app and re-enter it in mobile

For the LAN/Tailscale path:

- ensure `BRIDGE_AUTH_TOKEN` in `.env.secure` matches `EXPO_PUBLIC_HOST_BRIDGE_TOKEN` in `apps/mobile/.env`
- restart bridge + Expo after token changes

## Onboarding looks stuck before Expo logs appear

- Expo startup can be slow on first launch.
- You should see: `Waiting for Expo output ...`
- Increase timeout if needed:

```bash
EXPO_OUTPUT_WAIT_SECS=180 npm run setup:wizard
```

- If Expo never emits logs:

```bash
tail -n 120 .expo.log
```

## Expo starts but QR/network is wrong

- re-run `npm run secure:setup`
- confirm `.env.secure` has the correct `BRIDGE_HOST`
- restart `npm run mobile`

## Stop all running services quickly

```bash
npm run stop:services
```

## Tailscale issues

- Verify host and phone are on the same Tailscale network
- Check host IP (`tailscale ip -4`) and mobile `.env` URL

## `codex` not found

- Ensure `codex` is in `PATH`
- Or set `CODEX_CLI_BIN` explicitly

## Bridge build fails with `linker 'cc' not found`

Install C build tools:

```bash
sudo apt-get update && sudo apt-get install -y build-essential
```

Then retry `npm run secure:bridge`.

## iOS bundling error: `Unable to resolve "./BoundingDimensions"`

Manual recovery:

```bash
npm install --include=dev --force
npm install --include=dev --force -w apps/mobile
npm run -w apps/mobile start -- --clear
```

## Runtime errors: `[runtime not ready]` / `property is not writable`

Manual recovery:

```bash
rm -rf node_modules apps/mobile/node_modules
npm install --include=dev --force
npm install --include=dev --force -w apps/mobile
npm run -w apps/mobile start -- --clear
```

Also update Expo Go on your phone.

## Git operations fail

- Verify chat workspace is a valid git repo
- Verify remote auth/access for push

## Attachment upload issues

- Ensure mobile app has file/photo permissions
- File limit is `20 MB` per upload
- Uploads persist under `BRIDGE_WORKDIR/.clawdex-mobile-attachments`
- Ensure `BRIDGE_WORKDIR` is writable

## Worklets/Reanimated mismatch

```bash
cd apps/mobile
npx expo install --fix
npm run start -- --clear
```

## Plan mode errors (`RPC-32600` invalid `collaborationMode`)

- Restart Expo and reload app bundle
- Ensure bridge/mobile revisions match
- Run API test if needed:

```bash
npm run -w apps/mobile test -- --runInBand src/api/__tests__/client.test.ts
```

## Stop button does not interrupt a run

- Ensure revision supports `turn/interrupt`
- If run already finished, stop button disappears by design
- Pull latest, restart bridge, reload Expo bundle
