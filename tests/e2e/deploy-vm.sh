#!/usr/bin/env bash
# Full e2e deploy test.
#
# 1. Build the bootstrap NixOS VM (`packages.x86_64-linux.ci-target-vm`).
# 2. Boot it in the background with SSH port-forwarded to 127.0.0.1:2222.
# 3. Wait for the readiness marker `===LC_CI_VM_SSH_READY===` on the VM
#    serial console (emitted by the `lc-ci-ready` systemd unit declared
#    in tests/fixtures/vm-target.nix). This is the AUTHORITATIVE signal
#    that sshd is accepting connections.
# 4. Probe SSH with the fixture sayo key as a secondary confirmation.
# 5. Build the lc-ci-fixture closure via Colmena and apply `switch` to
#    the running VM (over ssh, using the fixture lamacloud.json mapping).
# 6. SSH back in and assert /etc/lamacloud-ci-marker == "deployed-via-colmena".
# 7. Tear the VM down whether the test passed or failed.
#
# Designed to be invoked by `.github/workflows/e2e-deploy.yml`.
# Requires: nix, colmena, qemu-system-x86_64, ssh, nc.

set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

SSH_KEY="$REPO_ROOT/tests/fixtures/sayo.key"
SSH_CONFIG="$REPO_ROOT/tests/e2e/.generated-ssh_config"
VM_LOG="$REPO_ROOT/tests/e2e/.vm.log"
VM_STATE="$REPO_ROOT/tests/e2e/.vm-state"
VM_PID=""

# Tunable timeouts (CI runners with cold nix caches are slow).
VM_BOOT_TIMEOUT="${LC_VM_BOOT_TIMEOUT:-420}"   # secs to wait for readiness marker
VM_SSH_TIMEOUT="${LC_VM_SSH_TIMEOUT:-60}"      # secs to wait for ssh after marker

# ---------------------------------------------------------------------- cleanup
cleanup() {
  local exit_code=$?

  if [[ "$exit_code" -ne 0 && -f "$VM_LOG" ]]; then
    lc_info "cleanup: full VM log (last 200 lines)"
    tail -n 200 "$VM_LOG" | sed 's/^/[vm]    /' || true

    lc_info "cleanup: host networking snapshot"
    ss -tlnp 2>/dev/null | sed 's/^/[ss]    /' || true
  elif [[ -f "$VM_LOG" ]]; then
    lc_info "cleanup: tail of VM log (last 30 lines, success)"
    tail -n 30 "$VM_LOG" | sed 's/^/[vm]    /' || true
  fi

  if [[ -n "$VM_PID" ]] && kill -0 "$VM_PID" 2>/dev/null; then
    lc_info "cleanup: terminating VM pid=$VM_PID"
    # Kill the entire process group so qemu (a grandchild of the subshell)
    # also dies. PGID == PID for the backgrounded subshell.
    kill -TERM -- "-$VM_PID" 2>/dev/null || kill -TERM "$VM_PID" 2>/dev/null || true
    for _ in 1 2 3 4 5; do
      kill -0 "$VM_PID" 2>/dev/null || break
      sleep 1
    done
    kill -KILL -- "-$VM_PID" 2>/dev/null || kill -KILL "$VM_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# ---------------------------------------------------------------------- prereq
lc_banner "deploy-vm: prereq check"
for bin in nix colmena qemu-system-x86_64 ssh nc; do
  command -v "$bin" >/dev/null 2>&1 || lc_fail "deploy-vm/prereq" "'$bin' not in PATH"
done
chmod 600 "$SSH_KEY"
lc_ok "deploy-vm/prereq"

# ---------------------------------------------------------------------- build VM
lc_banner "deploy-vm: building bootstrap VM image"
if ! nix build .#ci-target-vm --out-link "$VM_STATE-link" --show-trace 2>&1; then
  lc_fail "deploy-vm/build-vm" "nix build of ci-target-vm failed"
fi

# qemu-vm.nix exposes `bin/run-<hostname>-vm` as a symlink. `find -L`
# follows it so `-type f` matches the underlying script.
if ! VM_RUNNER="$(find -L "$VM_STATE-link/bin" -maxdepth 1 -type f -name 'run-*-vm' 2>/dev/null | head -n1)" || [[ -z "$VM_RUNNER" ]]; then
  lc_info "deploy-vm/build-vm: contents of $VM_STATE-link/bin"
  ls -la "$VM_STATE-link/bin/" 2>&1 | sed 's/^/  /' || true
  lc_fail "deploy-vm/build-vm" "no run-*-vm script under $VM_STATE-link/bin"
fi
[[ -x "$VM_RUNNER" ]] || lc_fail "deploy-vm/build-vm" "VM runner '$VM_RUNNER' is not executable"

# Echo the qemu command embedded in the runner so we can diagnose any
# port-forward / network misconfiguration directly from the workflow log.
lc_info "deploy-vm/build-vm: runner script (qemu invocation)"
grep -E '(^| )(exec |qemu-system|hostfwd|forwardPorts)' "$VM_RUNNER" 2>/dev/null | sed 's/^/  /' || true
lc_ok "deploy-vm/build-vm"

# ---------------------------------------------------------------------- pre-flight host port
lc_banner "deploy-vm: host TCP/2222 pre-flight"
if ss -tln 'sport = :2222' 2>/dev/null | grep -q ':2222'; then
  lc_info "deploy-vm/preflight: WARNING - something is already listening on :2222"
  ss -tlnp 2>/dev/null | grep ':2222' | sed 's/^/  /' || true
  # Don't fail - QEMU may still be able to bind explicitly to 127.0.0.1.
fi
lc_ok "deploy-vm/preflight"

# ---------------------------------------------------------------------- boot VM
lc_banner "deploy-vm: booting VM (background)"
mkdir -p "$VM_STATE"
rm -f "$VM_STATE/disk.qcow2"

# `setsid` puts the child in a new session/process group so cleanup can
# kill the whole tree (subshell -> bash runner -> qemu).
setsid bash -c "
  NIX_DISK_IMAGE='$VM_STATE/disk.qcow2' \\
  TMPDIR='$VM_STATE' \\
  '$VM_RUNNER' -nographic </dev/null >'$VM_LOG' 2>&1
" &
VM_PID=$!
lc_info "deploy-vm/boot: VM pid=$VM_PID (pgid=$VM_PID), disk=$VM_STATE/disk.qcow2"

# ---------------------------------------------------------------------- wait readiness
lc_banner "deploy-vm: waiting up to ${VM_BOOT_TIMEOUT}s for readiness marker"
READY_DEADLINE=$((SECONDS + VM_BOOT_TIMEOUT))
SAW_MARKER=0

while (( SECONDS < READY_DEADLINE )); do
  if ! kill -0 "$VM_PID" 2>/dev/null; then
    lc_fail "deploy-vm/wait-ready" "VM process died before emitting readiness marker"
  fi

  if [[ -f "$VM_LOG" ]] && grep -q '===LC_CI_VM_SSH_READY===' "$VM_LOG" 2>/dev/null; then
    SAW_MARKER=1
    break
  fi

  if [[ -f "$VM_LOG" ]] && grep -q '===LC_CI_VM_SSH_FAILED===' "$VM_LOG" 2>/dev/null; then
    lc_fail "deploy-vm/wait-ready" "VM emitted ===LC_CI_VM_SSH_FAILED=== (sshd never opened :22 inside guest)"
  fi

  # Periodic diagnostic every ~30s so a hanging boot is debuggable from
  # the workflow log without needing the artifact.
  if (( (SECONDS - (READY_DEADLINE - VM_BOOT_TIMEOUT)) % 30 == 0 )); then
    lc_info "deploy-vm/wait-ready: elapsed=$((SECONDS - (READY_DEADLINE - VM_BOOT_TIMEOUT)))s; last 5 VM log lines:"
    tail -n 5 "$VM_LOG" 2>/dev/null | sed 's/^/  [vm] /' || true
  fi

  sleep 3
done

(( SAW_MARKER == 1 )) || lc_fail "deploy-vm/wait-ready" "did not see ===LC_CI_VM_SSH_READY=== within ${VM_BOOT_TIMEOUT}s"
lc_ok "deploy-vm/wait-ready"

# ---------------------------------------------------------------------- ssh confirm
lc_banner "deploy-vm: confirming SSH from host"
SSH_DEADLINE=$((SECONDS + VM_SSH_TIMEOUT))
SSH_READY=0
LAST_SSH_ERR=""

while (( SECONDS < SSH_DEADLINE )); do
  # Port probe (with explicit short timeout).
  if ! nc -z -w 2 127.0.0.1 2222 2>/dev/null; then
    LAST_SSH_ERR="nc -z 127.0.0.1 2222 failed (port not reachable from host)"
    sleep 2
    continue
  fi

  if LAST_SSH_ERR="$(ssh -i "$SSH_KEY" \
         -o StrictHostKeyChecking=no \
         -o UserKnownHostsFile=/dev/null \
         -o LogLevel=ERROR \
         -o ConnectTimeout=5 \
         -o PreferredAuthentications=publickey \
         -o BatchMode=yes \
         -p 2222 sayo@127.0.0.1 'echo lc-ci-ssh-ok' 2>&1)"; then
    if [[ "$LAST_SSH_ERR" == *"lc-ci-ssh-ok"* ]]; then
      SSH_READY=1
      break
    fi
  fi
  sleep 2
done

if (( SSH_READY != 1 )); then
  lc_info "deploy-vm/ssh-confirm: last error was: $LAST_SSH_ERR"
  lc_info "deploy-vm/ssh-confirm: ssh -vvv attempt for diagnosis"
  ssh -i "$SSH_KEY" \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=5 \
      -o BatchMode=yes \
      -vvv \
      -p 2222 sayo@127.0.0.1 'true' 2>&1 | sed 's/^/  [ssh] /' || true
  lc_fail "deploy-vm/ssh-confirm" "ssh did not succeed within ${VM_SSH_TIMEOUT}s after readiness marker"
fi
lc_ok "deploy-vm/ssh-confirm"

# ---------------------------------------------------------------------- ssh cfg
lc_banner "deploy-vm: generating ssh_config for Colmena"
cat >"$SSH_CONFIG" <<EOF
Host 127.0.0.1 lc-ci-fixture
  HostName 127.0.0.1
  User sayo
  Port 2222
  IdentityFile $SSH_KEY
  IdentitiesOnly yes
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  LogLevel ERROR
EOF
chmod 600 "$SSH_CONFIG"
lc_ok "deploy-vm/ssh-config"

# ---------------------------------------------------------------------- deploy
lc_banner "deploy-vm: colmena apply switch --on lc-ci-fixture"
export SSH_CONFIG_FILE="$SSH_CONFIG"

# Build locally and push (Colmena's default). Tee the output to a file so
# that, on failure, the exact Colmena error is reprinted under an
# unmistakable banner right next to the [FAIL] marker -- otherwise it can
# scroll far above the cleanup VM-log dump and be hard to find.
COLMENA_LOG="$REPO_ROOT/tests/e2e/.colmena-apply.log"
if ! colmena apply switch --on lc-ci-fixture --verbose 2>&1 | tee "$COLMENA_LOG"; then
  lc_info "deploy-vm/colmena-apply: full colmena output follows"
  sed 's/^/  [colmena] /' "$COLMENA_LOG" >&2 || true
  lc_fail "deploy-vm/colmena-apply" "colmena apply switch failed (see [colmena] lines above)"
fi
lc_ok "deploy-vm/colmena-apply"

# ---------------------------------------------------------------------- verify
# Activating the new generation restarts a number of guest units. sshd's
# config is identical to the bootstrap so it is NOT restarted, but other
# services churn briefly. Probe the marker in a short retry loop rather
# than a single shot so a transient connection blip is never mistaken for
# a deploy failure.
lc_banner "deploy-vm: verifying marker file"
VERIFY_DEADLINE=$((SECONDS + 60))
marker=""
verify_err=""
while (( SECONDS < VERIFY_DEADLINE )); do
  if marker="$(ssh -F "$SSH_CONFIG" -o ConnectTimeout=5 lc-ci-fixture \
        'cat /etc/lamacloud-ci-marker' 2>&1)"; then
    break
  fi
  verify_err="$marker"
  marker=""
  sleep 3
done

[[ -n "$marker" ]] || lc_fail "deploy-vm/verify" "could not read marker within 60s: $verify_err"
lc_assert_eq "deploy-vm/verify" "deployed-via-colmena" "${marker%$'\n'}"
lc_ok "deploy-vm/verify"

# ---------------------------------------------------------------------- done
lc_banner "deploy-vm: end-to-end deploy succeeded"
