#!/usr/bin/env bash
# Shared logging helpers for the lamacloud e2e scripts.
# Source me, do not execute me.
#
# Logging contract (matched by the GitHub Actions workflows):
#   ==> <stage>                 - banner for a new stage
#   [INFO]  <stage>: <msg>      - informational
#   [OK]    <stage>             - stage succeeded
#   [FAIL]  <stage>: <reason>   - stage failed; script exits non-zero
#   [SKIP]  <stage>: <reason>   - stage intentionally skipped
#
# The "[FAIL]" prefix is grep-able and is what the workflow UI surfaces.

set -uo pipefail

LC_E2E_LIB_LOADED=1

lc_banner() {
  printf '\n==> %s\n' "$*"
}

lc_info() {
  printf '[INFO]  %s\n' "$*"
}

lc_ok() {
  printf '[OK]    %s\n' "$*"
}

lc_skip() {
  printf '[SKIP]  %s\n' "$*"
}

# lc_fail <stage> <reason...>
# Prints the standard single-line failure marker and exits.
lc_fail() {
  local stage="$1"; shift
  printf '[FAIL]  %s: %s\n' "$stage" "$*" >&2
  exit 1
}

# lc_run <stage> -- <cmd ...>
# Runs a command, fails the stage with the exit code on non-zero.
lc_run() {
  local stage="$1"; shift
  [[ "${1:-}" == "--" ]] && shift

  lc_info "$stage: running: $*"

  if ! "$@"; then
    lc_fail "$stage" "command '$*' exited non-zero"
  fi
}

# lc_assert_eq <stage> <expected> <actual>
lc_assert_eq() {
  local stage="$1"
  local expected="$2"
  local actual="$3"

  if [[ "$expected" != "$actual" ]]; then
    lc_fail "$stage" "expected '$expected' but got '$actual'"
  fi
}

# lc_assert_contains <stage> <needle> <haystack>
lc_assert_contains() {
  local stage="$1"
  local needle="$2"
  local haystack="$3"

  if [[ "$haystack" != *"$needle"* ]]; then
    lc_fail "$stage" "expected output to contain '$needle' but got: $haystack"
  fi
}

# lc_assert_file <stage> <path>
lc_assert_file() {
  local stage="$1"
  local path="$2"

  if [[ ! -f "$path" ]]; then
    lc_fail "$stage" "expected file '$path' to exist"
  fi
}

# Resolve the repository root from the script's location.
lc_repo_root() {
  local script_dir="${1:-$(dirname -- "${BASH_SOURCE[1]}")}"
  ( cd "$script_dir" && cd "$(git rev-parse --show-toplevel 2>/dev/null || (cd ../.. && pwd))" && pwd )
}
