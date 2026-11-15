#!/usr/bin/env bash
# Injects the sandbox summary into every Claude Code session. Never fails the session.
if command -v sbx >/dev/null 2>&1; then
  sbx context 2>/dev/null || true
else
  bash "${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}/bin/sbx" context 2>/dev/null || true
fi
exit 0
