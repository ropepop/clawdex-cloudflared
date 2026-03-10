# Project Status

> Last reviewed: 2026-03-10

## Snapshot

`clawdex-cloudflared` is a source-first public fork focused on the Cloudflare Tunnel + macOS host workflow. The current architecture centers on the Rust bridge and the native macOS host app, with the Expo mobile app as the operator client and the TypeScript bridge retained as legacy reference code.

## Current Architecture

```
Mobile App (Expo/RN)
        │
        ├── manual URL + token pairing
        ▼
Rust Bridge (`services/rust-bridge`)
        │
        ├── localhost binding on the Mac
        ├── `/health` + `/rpc`
        ▼
Codex `app-server`

macOS Host App (`apps/mac-host`)
        │
        ├── launches the Rust bridge
        ├── manages tunnel config and token storage
        ▼
Cloudflare Tunnel (`cloudflared`)
```

## What Is Implemented

- Mobile chat, approvals, Git actions, terminal execution, and file/image attachments
- Rust bridge auth with bridge-token enforcement for HTTP and WebSocket access
- Health reporting that includes `ready`, `appServerStatus`, and `degradedReason`
- Native macOS host app for Cloudflare Tunnel setup and runtime supervision
- Legacy TypeScript bridge retained for protocol reference and historical comparison

## Public-Fork Posture

- Repo metadata, legal/support URLs, and mobile defaults now point at `ropepop/clawdex-cloudflared`
- Owner-bound Expo/App Store identifiers have been removed from the tracked config
- The old npm publish automation has been retired; this fork is not configured for package publishing by default
- The Cloudflare path is documented as primary; LAN/Tailscale remains supported as a secondary operator flow

## Known Gaps

- Mobile reconnect and longer-running resilience behavior still need hardening
- Dynamic tool calls and some newer Codex surfaces remain incomplete in the mobile UX
- Standalone mobile release configuration now requires a new owner to supply their own Expo/App Store identifiers
- Mac host validation is still primarily manual/macOS-local rather than enforced in CI

## Compliance Reminder

- Keep the root `LICENSE` file in place
- Follow [docs/open-source-license-requirements.md](docs/open-source-license-requirements.md) before shipping builds
- Generate `THIRD_PARTY_NOTICES` for any distributed release artifacts
