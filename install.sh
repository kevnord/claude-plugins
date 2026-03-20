#!/usr/bin/env bash
#
# Install a plugin from the claude-plugins marketplace into the current project.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/kevnord/claude-plugins/main/install.sh | bash -s -- <plugin-name>
#   ./install.sh <plugin-name>
#   ./install.sh --list
#
# Examples:
#   ./install.sh scorecard
#   ./install.sh --list

set -euo pipefail

REPO="kevnord/claude-plugins"
BRANCH="main"
RAW_BASE="https://raw.githubusercontent.com/${REPO}/${BRANCH}"

usage() {
  cat <<EOF
Usage: $(basename "$0") <plugin-name> [--dest <path>]
       $(basename "$0") --list

Options:
  <plugin-name>     Name of the plugin to install (e.g., scorecard)
  --dest <path>     Destination directory (default: .claude/plugins/<plugin-name>)
  --list            List all available plugins
  -h, --help        Show this help message
EOF
}

list_plugins() {
  echo "Fetching plugin catalog..."
  echo ""

  local marketplace
  marketplace=$(curl -fsSL "${RAW_BASE}/.claude-plugin/marketplace.json")

  echo "Available plugins:"
  echo "──────────────────"
  echo ""

  echo "$marketplace" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for p in data.get('plugins', []):
    name = p.get('name', 'unknown')
    desc = p.get('description', '')
    ver = p.get('version', '')
    tags = ', '.join(p.get('tags', []))
    print(f'  {name} (v{ver})')
    print(f'    {desc}')
    if tags:
        print(f'    Tags: {tags}')
    print()
" 2>/dev/null || echo "$marketplace" | jq -r '.plugins[] | "  \(.name) (v\(.version))\n    \(.description)\n"' 2>/dev/null || {
    echo "  (install python3 or jq to display the plugin list)"
    echo "  Marketplace URL: https://github.com/${REPO}"
  }
}

install_plugin() {
  local plugin_name="$1"
  local dest="${2:-.claude/plugins/${plugin_name}}"

  echo "Installing plugin: ${plugin_name}"
  echo ""

  # Verify plugin exists in marketplace
  local marketplace
  marketplace=$(curl -fsSL "${RAW_BASE}/.claude-plugin/marketplace.json")

  local plugin_source
  plugin_source=$(echo "$marketplace" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for p in data.get('plugins', []):
    if p['name'] == '${plugin_name}':
        print(p['source'])
        sys.exit(0)
sys.exit(1)
" 2>/dev/null || echo "$marketplace" | jq -r ".plugins[] | select(.name==\"${plugin_name}\") | .source" 2>/dev/null)

  if [ -z "$plugin_source" ]; then
    echo "Error: plugin '${plugin_name}' not found in marketplace."
    echo "Run '$(basename "$0") --list' to see available plugins."
    exit 1
  fi

  # Clean the source path (remove leading ./)
  plugin_source="${plugin_source#./}"

  if [ -d "$dest" ]; then
    echo "Warning: ${dest} already exists. Updating..."
    rm -rf "$dest"
  fi

  # Clone sparse checkout of just the plugin
  local tmpdir
  tmpdir=$(mktemp -d)
  trap 'rm -rf "$tmpdir"' EXIT

  echo "Downloading ${plugin_name}..."
  git clone --depth 1 --filter=blob:none --sparse \
    "https://github.com/${REPO}.git" "$tmpdir" 2>/dev/null

  cd "$tmpdir"
  git sparse-checkout set "${plugin_source}" 2>/dev/null
  cd - > /dev/null

  # Copy plugin to destination
  mkdir -p "$(dirname "$dest")"
  cp -r "${tmpdir}/${plugin_source}" "$dest"

  echo ""
  echo "Installed ${plugin_name} to ${dest}"
  echo ""

  # Show available commands
  if [ -f "${dest}/.claude-plugin/plugin.json" ]; then
    echo "Available commands:"
    python3 -c "
import json
with open('${dest}/.claude-plugin/plugin.json') as f:
    data = json.load(f)
for cmd in data.get('commands', []):
    name = cmd.rsplit('/', 1)[-1].replace('.md', '')
    print(f'  /{name}')
" 2>/dev/null || echo "  (see ${dest}/.claude-plugin/plugin.json)"
  fi

  echo ""
  echo "Add to your project's .claude/settings.json:"
  echo ""
  echo "  { \"plugins\": [\"${dest}\"] }"
}

# Parse arguments
if [ $# -eq 0 ]; then
  usage
  exit 1
fi

case "$1" in
  -h|--help)
    usage
    exit 0
    ;;
  --list)
    list_plugins
    exit 0
    ;;
  *)
    plugin_name="$1"
    dest=""
    shift
    while [ $# -gt 0 ]; do
      case "$1" in
        --dest)
          dest="$2"
          shift 2
          ;;
        *)
          echo "Unknown option: $1"
          usage
          exit 1
          ;;
      esac
    done
    if [ -n "$dest" ]; then
      install_plugin "$plugin_name" "$dest"
    else
      install_plugin "$plugin_name"
    fi
    ;;
esac
