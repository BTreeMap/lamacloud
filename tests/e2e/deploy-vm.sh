#!/usr/bin/env bash
# Full e2e deploy test.
#
# 1. Build the bootstrap NixOS VM (`packages.x86_64-linux.ci-target-vm`).
# 2. Boot it in the background with SSH port-forwarded to host:2222.
# 3. Wait for sshd to accept the fixture sayo key.
# 4. Build the lc-ci-fixture closure via Colmena and apply `switch` to
#    the running VM (over ssh, using the fixture lamacloud.json mapping).
# 5. SSH back in and assert /etc/lamacloud-ci-marker == "deployed-via-colmena".
# 6. Tear the VM down whether the test passed or failed.
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

cleanup() {
  if [[ -n "$VM_PID" ]] && kill -0 "$VM_PID" 2>/dev/null; then
    lc_info "cleanup: terminating VM pid=$VM_PID"
    kill -TERM "$VM_PID" 2>/dev/null || true
    for _ in 1 2 3 4 5; do
      kill -0 "$VM_PID" 2>/dev/null || break
      sleep 1
    done
    kill -KILL "$VM_PID" 2>/dev/null || true
  fi

  if [[ -f "$VM_LOG" ]]; then
    lc_info "cleanup: tail of VM log"
    tail -n 60 "$VM_LOG" | sed 's/^/[vm]    /' || true
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

VM_RUNNER="$(find "$VM_STATE-link/bin" -maxdepth 1 -type f -name 'run-*-vm' | head -n1)"
[[ -x "$VM_RUNNER" ]] || lc_fail "deploy-vm/build-vm" "no runnable VM script under $VM_STATE-link/bin"
lc_info "deploy-vm/build-vm: runner = $VM_RUNNER"
lc_ok "deploy-vm/build-vm"

# ---------------------------------------------------------------------- boot VM
lc_banner "deploy-vm: booting VM (background)"
# A clean qcow2 every run -- isolates state and prevents stale rootfs.
mkdir -p "$VM_STATE"
rm -f "$VM_STATE/disk.qcow2"

(
  NIX_DISK_IMAGE="$VM_STATE/disk.qcow2" \
  TMPDIR="$VM_STATE" \
  "$VM_RUNNER" -nographic </dev/null >"$VM_LOG" 2>&1
) &
VM_PID=$!
lc_info "deploy-vm/boot: VM pid=$VM_PID, disk=$VM_STATE/disk.qcow2"

# ---------------------------------------------------------------------- wait ssh
lc_banner "deploy-vm: waiting for sshd on 127.0.0.1:2222"
SSH_DEADLINE=$((SECONDS + 240))
SSH_READY=0

while (( SECONDS < SSH_DEADLINE )); do
  if ! kill -0 "$VM_PID" 2>/dev/null; then
    lc_fail "deploy-vm/wait-ssh" "VM process died before sshd became reachable; see VM log above"
  fi

  if nc -z 127.0.0.1 2222 2>/dev/null; then
    # Port is open; try a real SSH connection to confirm sshd is actually ready.
    if ssh -i "$SSH_KEY" \
           -o StrictHostKeyChecking=no \
           -o UserKnownHostsFile=/dev/null \
           -o LogLevel=ERROR \
           -o ConnectTimeout=5 \
           -o PreferredAuthentications=publickey \
           -p 2222 sayo@127.0.0.1 'true' 2>/dev/null; then
      SSH_READY=1
      break
    fi
  fi

  sleep 3
done

(( SSH_READY == 1 )) || lc_fail "deploy-vm/wait-ssh" "ssh did not become ready within timeout"
lc_ok "deploy-vm/wait-ssh"

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

if ! colmena apply switch --on lc-ci-fixture --verbose 2>&1; then
  lc_fail "deploy-vm/colmena-apply" "colmena apply switch failed"
fi
lc_ok "deploy-vm/colmena-apply"

# ---------------------------------------------------------------------- verify
lc_banner "deploy-vm: verifying marker file"
marker="$(ssh -F "$SSH_CONFIG" lc-ci-fixture 'cat /etc/lamacloud-ci-marker' 2>&1)" || \
  lc_fail "deploy-vm/verify" "ssh marker read failed: $marker"

lc_assert_eq "deploy-vm/verify" "deployed-via-colmena" "${marker%$'\n'}"
lc_ok "deploy-vm/verify"

# ---------------------------------------------------------------------- done
lc_banner "deploy-vm: end-to-end deploy succeeded"
