# CI Deployment Guide

This document describes how the GitHub Actions workflows interact with
real lamacloud infrastructure, what secrets the production deploy
workflow needs, and the exact format each secret must take.

If a secret is missing, malformed, or contains the wrong content, the
deploy workflow exits early with a `[FAIL]  deploy-prod/<stage>: ...`
line — there is no silent failure path.

---

## Workflows at a glance

| Workflow                              | Trigger                       | Touches real infra? |
| ------------------------------------- | ----------------------------- | ------------------- |
| `.github/workflows/ci.yml`            | push / pull_request           | No                  |
| `.github/workflows/e2e-deploy.yml`    | push / pull_request           | No (QEMU VM only)   |
| `.github/workflows/deploy-prod.yml`   | manual (`workflow_dispatch`)  | **YES**             |

Only `deploy-prod.yml` reads any of the secrets below. The other two
workflows use the committed `tests/fixtures/` material and a throwaway
VM, so they require **zero secret configuration**.

---

## Required GitHub Actions secrets

Configure these in the repository's
**Settings → Environments → `production` → Add secret**. They MUST live
in the `production` environment (not in the repo-wide secrets pane) so
that GitHub's environment protection rules (required reviewers,
deployment branch restrictions) apply automatically.

### 1. `LAMACLOUD_SAYO_PRIVATE_KEY` — *(required)*

The ed25519 **private** key matching the `sayo` public key recorded in
`sayo.json`. Colmena uses this to SSH into every host as user `sayo`.

**Format:** OpenSSH PEM, **including the BEGIN/END lines and a trailing
newline**. The exact bytes you would get from:

```bash
ssh-keygen -t ed25519 -N '' -C 'sayo@lamacloud-ci' -f /tmp/sayo
cat /tmp/sayo                              # <-- this is the secret value
```

**Setting it:**

```bash
gh secret set LAMACLOUD_SAYO_PRIVATE_KEY \
  --env production \
  --body "$(cat /tmp/sayo)"
```

**Validation:** the workflow's "Materialise SSH credentials" step
writes the secret to `~/.ssh/sayo` with mode `0600` and immediately
fails if the variable is empty. A malformed key surfaces as an SSH
error in the next step (e.g. `Load key "/home/runner/.ssh/sayo": invalid format`).

**Public-key counterpart:** the matching public key must already appear
verbatim in `sayo.json` at the repo root, under `publicKey.keys[]`.
Regenerate `sayo.json` with `lamacloud creds new --sayo` after rotating
the keypair, commit it, and rotate this secret in the same PR.

### 2. `LAMACLOUD_SSH_KNOWN_HOSTS` — *(required)*

A `known_hosts` file containing one or more entries for every target
host the workflow will deploy to. The deploy workflow sets
`StrictHostKeyChecking yes`, so an unknown host fingerprint is a hard
failure (this is intentional — it eliminates the MITM-attack window
that `accept-new` opens).

**Format:** one `known_hosts` line per host, concatenated. Example
contents:

```
hk01.lamacloud.onlylama.fans ssh-ed25519 AAAAC3Nz...EXAMPLE
hk01.lamacloud.onlylama.fans ecdsa-sha2-nistp256 AAAAE2Vj...EXAMPLE
[hk01.lamacloud.onlylama.fans]:19312 ssh-ed25519 AAAAC3Nz...EXAMPLE
```

Note the `[host]:port` form is needed for hosts whose
`lamacloud.json` entry specifies a non-default port (e.g. hk01 uses 19312).

**Generating the entries:**

```bash
# Repeat for every (host, port) tuple in lamacloud.json
ssh-keyscan -p 19312 hk01.lamacloud.onlylama.fans >> /tmp/known_hosts
ssh-keyscan        hk01.lamacloud.onlylama.fans >> /tmp/known_hosts
# ... etc

gh secret set LAMACLOUD_SSH_KNOWN_HOSTS \
  --env production \
  --body "$(cat /tmp/known_hosts)"
```

**Rotation:** whenever a target host's SSH host key changes (fresh
install, key rotation), regenerate this secret. Forgetting to do so is
a *safe failure* — the workflow refuses to connect rather than silently
trusting the new key.

---

## Optional GitHub Actions configuration

### Environment protection rules

Open **Settings → Environments → `production`** and enable:

- **Required reviewers:** at least one project owner. This forces a
  human to approve every `deploy-prod.yml` run before it touches real
  infra, even if someone has push access to `main`.
- **Deployment branches:** restrict to `main` only so accidental
  feature-branch deploys are impossible.
- **Wait timer:** optional 1–5 minute delay to give reviewers time to
  cancel an erroneous dispatch.

### Audit log

GitHub's audit log records every `workflow_dispatch` event including
the inputs. Combined with the `deploy-prod.yml` "Deployment summary"
step (which prints commit SHA, selector, goal, reboot flag) this gives
a complete who-deployed-what-when trail without extra tooling.

---

## Running a production deploy

1. Go to **Actions → deploy-prod → Run workflow**.
2. Fill in the inputs:
   - `selector` — Colmena `--on` selector. Defaults to `@lamacloud` (every host). Use `lc-entrypoint-hk01` to target one host, `'@infra-lax'` to target a tag, etc.
   - `goal` — `switch` (apply immediately), `boot` (apply on next reboot), `test` (apply without registering as default), or `dry-activate` (no-op).
   - `reboot` — reboot every node after activation.
   - `confirm` — type `I UNDERSTAND` literally. Any other value aborts the run.
3. Click **Run workflow**. The job will block waiting for a reviewer if you configured required reviewers.
4. Approve. Watch the Actions log for `[OK]` / `[FAIL]` lines.

---

## What the workflow does step by step

1. **`deploy-prod/confirm`** — refuse to proceed unless `confirm == "I UNDERSTAND"`.
2. **`deploy-prod/clean-tree`** — `git status --porcelain` must be empty.
3. Install Nix + Colmena (from our pinned flake input — never `nixpkgs#colmena`, so the binary version matches the hive evaluator exactly).
4. **`deploy-prod/secrets`** — materialise `~/.ssh/sayo`, `~/.ssh/known_hosts`, and `~/.ssh/lamacloud_config` with the right modes. Fail with a clear error if either secret is missing.
5. **Repo integrity** — `lamacloud check --strict` validates that every host has `creds.json` and the sayo creds are syntactically intact.
6. **Hive sanity build** — `colmena build --on <selector>` ensures every selected closure builds locally before any push.
7. **`colmena apply <goal>`** — push closures, activate, optionally reboot.
8. **Deployment summary** — always-on summary line printing selector / goal / reboot / commit SHA.

---

## Failure modes & remediation

| Symptom in log                                                                           | Cause                                                       | Fix                                                                            |
| ---------------------------------------------------------------------------------------- | ----------------------------------------------------------- | ------------------------------------------------------------------------------ |
| `[FAIL]  deploy-prod/confirm: operator did not type 'I UNDERSTAND'`                      | Operator typo in dispatch form.                             | Re-dispatch with the exact string `I UNDERSTAND`.                              |
| `[FAIL]  deploy-prod/clean-tree: working tree is dirty after checkout`                   | A workflow earlier in the run wrote files outside `~/...`. | Investigate; clean trees are a deployment invariant.                           |
| `[FAIL]  deploy-prod/secrets: LAMACLOUD_SAYO_PRIVATE_KEY is unset`                       | Secret missing or stored at repo level instead of env.      | Add to `production` environment. See §1 above.                                 |
| `Load key "/home/runner/.ssh/sayo": invalid format`                                      | Secret value is not a PEM key, or lost its newline.         | Re-set with `--body "$(cat key.pem)"` (NOT `--body "$(cat key.pem | base64)"`). |
| `Host key verification failed`                                                           | `LAMACLOUD_SSH_KNOWN_HOSTS` missing the relevant host:port. | `ssh-keyscan -p <port> <host>` then re-set the secret.                         |
| `[FAIL]  deploy-prod/build`                                                              | A host's closure no longer builds on x86_64 / aarch64.     | Reproduce locally with `lamacloud build <host>`.                              |
| `colmena ... activation failed`                                                          | New configuration is invalid on the target.                 | Re-dispatch with `goal = dry-activate` or `test` to diagnose without bricking. |

---

## Why we never use `accept-new` for known_hosts

The first SSH connection to a host with `StrictHostKeyChecking=accept-new`
silently learns whatever key the server presents. If an attacker is
in-path between the runner and the target (e.g. compromised DNS, BGP
hijack on the runner's egress), they can stand up an interception proxy
that the workflow will trust permanently. By requiring a pre-populated
`known_hosts`, we move that trust decision into a human-reviewed PR
that updates `LAMACLOUD_SSH_KNOWN_HOSTS`. The cost is one extra
`ssh-keyscan` when a host's key legitimately rotates; the benefit is
eliminating an entire class of supply-chain attack.
