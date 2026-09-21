#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

DO_SKILL=1
DO_PASEO=1
for arg in "$@"; do
  case "$arg" in
    --skill-only) DO_PASEO=0 ;;
    --paseo-only) DO_SKILL=0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

if [ "$DO_SKILL" = 0 ] && [ "$DO_PASEO" = 0 ]; then
  echo "--skill-only and --paseo-only are mutually exclusive; pass at most one." >&2
  exit 1
fi

if [ "$DO_SKILL" = 1 ]; then
  mkdir -p "$HOME/.claude/skills"
  rm -rf "$HOME/.claude/skills/orchestrate"
  cp -R "$SCRIPT_DIR/skills/orchestrate" "$HOME/.claude/skills/orchestrate"
  echo "Installed skill: $HOME/.claude/skills/orchestrate"
fi

if [ "$DO_PASEO" = 1 ]; then
  command -v jq >/dev/null 2>&1 || { echo "jq is required but not installed. Install jq and re-run." >&2; exit 1; }

  PASEO_DIR="$HOME/.paseo"
  CONFIG="$PASEO_DIR/config.json"
  SNIPPET="$SCRIPT_DIR/paseo/config.snippet.json"

  mkdir -p "$PASEO_DIR"
  if [ ! -f "$CONFIG" ]; then
    echo '{"version":1}' > "$CONFIG"
  fi

  cp "$CONFIG" "$CONFIG.bak-$(date +%Y%m%d%H%M%S)"

  MERGED="$(jq --slurpfile snip "$SNIPPET" '
    (.daemon.agentProfiles // []) as $existing
    | ($snip[0].daemon.agentProfiles) as $newProfiles
    | ($existing | map(.name)) as $existingNames
    | ($newProfiles | map(select((.name as $n | $existingNames | index($n)) | not))) as $toAdd
    | .daemon.agentProfiles = ($existing + $toAdd)
    | (.agents.providers // {}) as $existingProviders
    | ($snip[0].agents.providers) as $newProviders
    | .agents.providers = ($existingProviders + ($newProviders | with_entries(select((.key as $k | $existingProviders | has($k)) | not))))
  ' "$CONFIG")"

  TMP="$(mktemp "$CONFIG.XXXXXX")"
  printf '%s\n' "$MERGED" > "$TMP"
  mv "$TMP" "$CONFIG"
  echo "Merged Paseo config: $CONFIG (backup saved alongside it)"

  INJECT_INTO_AGENTS="$(jq -r '.daemon.mcp.injectIntoAgents // false' "$CONFIG")"
  if [ "$INJECT_INTO_AGENTS" != "true" ]; then
    echo "WARNING: daemon.mcp.injectIntoAgents is not enabled in $CONFIG" >&2
    echo "The Lead agent will not have the create_agent tool without it." >&2
    echo "Enable it by setting daemon.mcp.enabled: true and daemon.mcp.injectIntoAgents: true" >&2
  fi

  echo "Run 'paseo daemon reload' to load the new profiles and provider."
fi
