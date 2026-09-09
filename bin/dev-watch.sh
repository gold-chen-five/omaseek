#!/usr/bin/env bash
# Restore plugin hot-reload for a repo that lives outside ~/.config/omarchy/plugins.
#
# Omarchy watches its plugins dir with `inotifywait -r`, which does not follow
# symlinks — so edits to this repo never reach the shell on their own. This
# watches the real directory and asks the shell to rescan.
#
# Usage: ./bin/dev-watch.sh   (Ctrl-C to stop)

set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

command -v inotifywait >/dev/null || { echo "need inotify-tools" >&2; exit 1; }

echo "watching $repo — saving a .qml or manifest.json reloads the plugin"
while inotifywait -q -r -e close_write,create,delete,move \
  --exclude '(\.git/|~$|\.swp$)' "$repo" >/dev/null; do
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  echo "reloaded $(date +%H:%M:%S)"
done
