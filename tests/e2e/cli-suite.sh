#!/usr/bin/env bash
# Exercise every lamacloud CLI subcommand against the test fixtures.
# This script is the FIRST thing CI runs - it does NOT require nix and
# therefore catches regressions in the JS code path quickly.
#
# Subcommands exercised:
#   - lamacloud --help              (commander wiring)
#   - lamacloud check               (repo integrity)
#   - lamacloud diverge             (templated host creation)  [scripted]
#   - lamacloud build <host>        (skipped here - nix required, runs in colmena-build.sh)
#   - lamacloud creds public <host> (read-only key inspection)
#   - lamacloud deploy --help       (deploy wiring without invoking colmena)
#
# Stages that need a TTY (interactive prompts) are driven through the
# subcommand options that bypass prompts (`creds new --sayo`, etc.).

set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

LAMACLOUD="$REPO_ROOT/foundation/scripts/lamacloud"
PATH="$REPO_ROOT/foundation/scripts/node_modules/.bin:$PATH"
export PATH

if ! command -v zx >/dev/null 2>&1; then
  lc_fail "cli-suite/prereq" "zx not found in PATH (run 'pnpm -C foundation/scripts install' first)"
fi

lc_banner "cli-suite: help & version"
help_output="$($LAMACLOUD --help 2>&1)"
lc_assert_contains "cli-suite/help" "lamacloud" "$help_output"
lc_assert_contains "cli-suite/help" "deploy" "$help_output"
lc_assert_contains "cli-suite/help" "check" "$help_output"
lc_assert_contains "cli-suite/help" "diverge" "$help_output"
lc_ok "cli-suite/help"

lc_banner "cli-suite: lamacloud check"
check_output="$($LAMACLOUD check 2>&1)" || lc_fail "cli-suite/check" "non-zero exit; output: $check_output"
lc_assert_contains "cli-suite/check" "[check] OK" "$check_output"
lc_ok "cli-suite/check"

lc_banner "cli-suite: lamacloud creds public lc-ci-fixture"
pub_output="$($LAMACLOUD creds public lc-ci-fixture 2>&1)" || lc_fail "cli-suite/creds-public" "non-zero exit; output: $pub_output"
lc_assert_contains "cli-suite/creds-public" "ssh-ed25519" "$pub_output"
lc_assert_contains "cli-suite/creds-public" "elaina@lc-ci-fixture" "$pub_output"
lc_ok "cli-suite/creds-public"

lc_banner "cli-suite: lamacloud deploy --help"
deploy_help="$($LAMACLOUD deploy --help 2>&1)" || lc_fail "cli-suite/deploy-help" "non-zero exit; output: $deploy_help"
lc_assert_contains "cli-suite/deploy-help" "Colmena" "$deploy_help"
lc_assert_contains "cli-suite/deploy-help" "--goal" "$deploy_help"
lc_ok "cli-suite/deploy-help"

lc_banner "cli-suite: lamacloud hive-build --help"
hb_help="$($LAMACLOUD hive-build --help 2>&1)" || lc_fail "cli-suite/hive-build-help" "non-zero exit; output: $hb_help"
lc_assert_contains "cli-suite/hive-build-help" "Colmena" "$hb_help"
lc_ok "cli-suite/hive-build-help"

# `diverge` is interactive (uses `prompts`); we exercise the template
# rendering directly via a node one-liner. This guards against template
# regressions without depending on TTY emulation in CI.
lc_banner "cli-suite: diverge template rendering"
template_render=$(node --input-type=module -e '
import fs from "node:fs"
const tmpl = fs.readFileSync("foundation/scripts/template.nix", "utf8")
const out = tmpl.replaceAll("TEMPLATE_ARCH", "x86_64-linux").replaceAll("TEMPLATE_HOSTNAME", "lc-diverge-probe")
if (!out.includes("hostName = \"lc-diverge-probe\"")) {
  console.error("missing hostName substitution")
  process.exit(1)
}
if (!out.includes("target-arch = \"x86_64-linux\"")) {
  console.error("missing target-arch substitution")
  process.exit(1)
}
console.log("diverge template OK")
') || lc_fail "cli-suite/diverge-template" "$template_render"
lc_info "cli-suite/diverge-template: $template_render"
lc_ok "cli-suite/diverge-template"

lc_banner "cli-suite: all stages passed"
