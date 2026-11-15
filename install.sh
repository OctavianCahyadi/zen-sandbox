#!/usr/bin/env bash
# Puts `sbx` on PATH (symlink into ~/.local/bin) and optionally adds the CLAUDE.md block.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
mkdir -p "$BIN_DIR"
ln -sf "$ROOT/bin/sbx" "$BIN_DIR/sbx"
echo "linked $BIN_DIR/sbx -> $ROOT/bin/sbx"
case ":$PATH:" in *":$BIN_DIR:"*) ;; *) echo "add to your shell rc:  export PATH=\"$BIN_DIR:\$PATH\"" ;; esac
"$ROOT/bin/sbx" list >/dev/null
echo "config: ~/.sandbox/.env"
if [ "${1:-}" = "--claude-md" ]; then "$ROOT/bin/sbx" claude install; fi
echo "next: sbx up postgres redis"
