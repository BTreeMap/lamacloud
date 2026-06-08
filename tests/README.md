# Lamacloud CI fixtures

> **DO NOT use these credentials in production.** They are committed for the
> sole purpose of letting GitHub Actions exercise the full deploy pipeline
> against a throwaway QEMU VM. The private keys here will never have access
> to any real lamacloud host.

This directory provides everything needed to run the E2E suite on a fresh
GitHub Actions runner with **zero secret material**.

Contents:

| File                  | Purpose                                                                |
| --------------------- | ---------------------------------------------------------------------- |
| `sayo.json`           | Fixture global CI creds (replaces repo-root `sayo.json` during tests)  |
| `sayo.key{,.pub}`     | Matching ed25519 keypair; CI uses this to SSH into the throwaway VM    |
| `elaina.key{,.pub}`   | Fixture per-host elaina keypair (used by `lc-ci-fixture` host)         |
| `lamacloud.json`      | Routes `lc-ci-fixture` to `localhost:2222` (matches QEMU port-forward) |
| `vm-target.nix`       | Stand-alone NixOS config for the bootstrap VM that Colmena targets    |

The `hosts/lc-ci-fixture/` directory contains the actual host configuration
under test. Its `creds.json` references the fixture elaina public key.

Layout invariant: the E2E test scripts swap `sayo.json` / `lamacloud.json`
at the repo root with the files here and restore them at the end of the
run. The swap is opt-in (env-var gated) so contributors running tests
locally will not accidentally clobber their real credentials.
