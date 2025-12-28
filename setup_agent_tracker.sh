#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[agent-tracker] %s\n' "$*" >&2
}

die() {
  log "Error: $*"
  exit 1
}

if [[ "$(uname -s)" != "Darwin" ]]; then
  die "This script only supports macOS."
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$REPO_ROOT/.config/agent-tracker"
[[ -d "$SRC_DIR" ]] || die "Expected agent-tracker source at: $SRC_DIR"

BREW_BIN="$(command -v brew || true)"
if [[ -z "$BREW_BIN" ]]; then
  if [[ -x "/opt/homebrew/bin/brew" ]]; then
    BREW_BIN="/opt/homebrew/bin/brew"
  elif [[ -x "/usr/local/bin/brew" ]]; then
    BREW_BIN="/usr/local/bin/brew"
  fi
fi

if [[ -z "$BREW_BIN" ]]; then
  log "Homebrew not found; installing..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  BREW_BIN="$(command -v brew || true)"
  if [[ -z "$BREW_BIN" ]]; then
    if [[ -x "/opt/homebrew/bin/brew" ]]; then
      BREW_BIN="/opt/homebrew/bin/brew"
    elif [[ -x "/usr/local/bin/brew" ]]; then
      BREW_BIN="/usr/local/bin/brew"
    fi
  fi
fi

[[ -n "$BREW_BIN" ]] || die "Homebrew install failed or brew is not on PATH."
eval "$("$BREW_BIN" shellenv)"

if ! brew services list >/dev/null 2>&1; then
  log "Enabling brew services (homebrew/services tap)..."
  brew tap homebrew/services >/dev/null
fi
brew services list >/dev/null 2>&1 || die "brew services is unavailable."

if ! command -v go >/dev/null 2>&1; then
  log "Installing Go..."
  brew install go
fi

DEST_DIR="$HOME/.config/agent-tracker"
mkdir -p "$HOME/.config"

if [[ -L "$DEST_DIR" ]]; then
  :
elif [[ -e "$DEST_DIR" ]]; then
  [[ -x "$DEST_DIR/install.sh" ]] || die "$DEST_DIR exists but does not look like agent-tracker (missing install.sh)."
else
  log "Linking $DEST_DIR -> $SRC_DIR"
  ln -s "$SRC_DIR" "$DEST_DIR"
fi

[[ -x "$DEST_DIR/install.sh" ]] || die "Missing $DEST_DIR/install.sh"
[[ -x "$DEST_DIR/deploy" ]] || die "Missing $DEST_DIR/deploy"

log "Building agent-tracker binaries..."
(cd "$DEST_DIR" && ./install.sh)

log "Installing/updating agent-tracker server brew service..."
(cd "$DEST_DIR" && ./deploy)

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
CODEX_CFG="$CODEX_HOME/config.toml"
if [[ -f "$CODEX_CFG" ]] && ! grep -Fq '[mcp_servers.tracker]' "$CODEX_CFG"; then
  log "Adding tracker MCP server to $CODEX_CFG"
  cat >>"$CODEX_CFG" <<EOF

[mcp_servers.tracker]
command = "$DEST_DIR/bin/tracker-mcp"
startup_timeout_ms = 20000
EOF
  log "Restart codex to pick up tracker MCP changes."
fi

log "Done. Service status:"
brew services list | awk '$1=="agent-tracker-server"{print}'
