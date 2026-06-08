#!/usr/bin/env bash
# Build every host declared in hosts/ via Colmena. Optionally restricted
# to a single host via $LC_BUILD_TARGET (defaults to "lc-ci-fixture" to
# keep the x86-only path fast; pass `*` to build the entire hive).
#
# Requires `nix` and `colmena` available in PATH.

set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

TARGET="${LC_BUILD_TARGET:-lc-ci-fixture}"

if ! command -v colmena >/dev/null 2>&1; then
  lc_fail "colmena-build/prereq" "colmena not found in PATH"
fi

if ! command -v nix >/dev/null 2>&1; then
  lc_fail "colmena-build/prereq" "nix not found in PATH"
fi

lc_banner "colmena-build: nix flake check"
if ! nix flake check --no-build --show-trace 2>&1; then
  lc_fail "colmena-build/flake-check" "nix flake check failed"
fi
lc_ok "colmena-build/flake-check"

lc_banner "colmena-build: building '$TARGET'"
if ! colmena build --on "$TARGET" --show-trace 2>&1; then
  lc_fail "colmena-build/build" "colmena build failed for selector '$TARGET'"
fi
lc_ok "colmena-build/build"

lc_banner "colmena-build: complete"
