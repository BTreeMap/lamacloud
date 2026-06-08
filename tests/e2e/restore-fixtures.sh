#!/usr/bin/env bash
# Restore the real sayo.json / lamacloud.json files that install-fixtures.sh
# swapped out. Safe to run even if no backup exists (no-op in that case).

set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

restore_one() {
  local relative="$1"
  local target="$REPO_ROOT/$relative"
  local backup="${target}.real-backup"

  if [[ -f "$backup" ]]; then
    mv "$backup" "$target"
    lc_ok "restore-fixtures/$relative"
  else
    lc_skip "restore-fixtures/$relative: no backup found"
  fi
}

lc_banner "Restoring real configuration files"
restore_one "sayo.json"
restore_one "lamacloud.json"
lc_banner "Restoration complete"
