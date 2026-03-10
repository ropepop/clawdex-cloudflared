#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -L)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd -L)"
ROOT_DIR="$(cd "$APP_DIR/../.." && pwd -L)"
BRIDGE_MANIFEST="$ROOT_DIR/services/rust-bridge/Cargo.toml"
BRIDGE_BINARY="$ROOT_DIR/services/rust-bridge/target/release/codex-rust-bridge"
DEST_DIR="$APP_DIR/Sources/ClawdexHost/Resources/Bundled"
DEST_BINARY="$DEST_DIR/codex-rust-bridge"

mkdir -p "$DEST_DIR"

if [[ -f "$HOME/.cargo/env" ]]; then
  # shellcheck disable=SC1090
  source "$HOME/.cargo/env"
fi

if ! command -v cargo >/dev/null 2>&1; then
  echo "error: cargo is required to bundle codex-rust-bridge. Install Rust/cargo, then rerun 'npm run mac:host' or 'npm run build -w @codex/mac-host'." >&2
  exit 1
fi

cargo build --release --manifest-path "$BRIDGE_MANIFEST"
if [[ ! -x "$BRIDGE_BINARY" ]]; then
  echo "error: expected bundled bridge binary was not produced at $BRIDGE_BINARY" >&2
  exit 1
fi
cp "$BRIDGE_BINARY" "$DEST_BINARY"
chmod +x "$DEST_BINARY"

echo "Bundled bridge binary updated at $DEST_BINARY"
