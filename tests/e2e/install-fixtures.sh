#!/usr/bin/env bash
# Swap the repo-root sayo.json and lamacloud.json with the test fixtures.
# Original files are backed up to <name>.real-backup so restore-fixtures.sh
# can put them back. Guarded by LAMACLOUD_CI=1 to prevent accidental local
# clobber.
#
# Usage:
#   LAMACLOUD_CI=1 tests/e2e/install-fixtures.sh

set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FIXTURES="$REPO_ROOT/tests/fixtures"

if [[ "${LAMACLOUD_CI:-}" != "1" ]]; then
  lc_fail "install-fixtures" "refusing to run without LAMACLOUD_CI=1 (would clobber real creds)"
fi

lc_banner "Installing CI fixtures into $REPO_ROOT"

install_one() {
  local relative="$1"
  local source="$FIXTURES/$(basename "$relative")"
  local target="$REPO_ROOT/$relative"
  local backup="${target}.real-backup"

  if [[ ! -f "$source" ]]; then
    lc_fail "install-fixtures/$relative" "fixture source missing: $source"
  fi

  if [[ -f "$target" && ! -f "$backup" ]]; then
    cp "$target" "$backup"
    lc_info "install-fixtures/$relative: backed up real file -> $(basename "$backup")"
  fi

  cp "$source" "$target"
  lc_ok "install-fixtures/$relative"
}

install_one "sayo.json"
install_one "lamacloud.json"

# Make sure the sayo private key is usable by ssh.
chmod 600 "$FIXTURES/sayo.key"
chmod 600 "$FIXTURES/elaina.key"
lc_ok "install-fixtures/keymode"

lc_banner "Fixtures installed"
