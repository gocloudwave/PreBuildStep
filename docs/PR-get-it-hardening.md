# Recommended title and body — `fix/get-it-hardening` → `main`

**This file is not a pull request.** It is the recommended title and body for one.
Opening the PR is the operator's action.

---

## Recommended title

```
fix(get_it): repair the non-root path and stop reporting failures as success
```

## Recommended body

*(paste from here down)*

### Summary

`get_it.sh` is the first thing run on a fresh appliance. Three defects, found while
validating the bootstrap end-to-end on a genuinely fresh Ubuntu 24.04.4 box
(`bs-claude-24-fresh-1`). Pairs with **BuildStep `fix/clone-repo-hardening`** — merge that
one too; this script fetches it.

### 1. The documented non-root invocation always failed

```bash
mv clone_repo.sh /opt/clone_repo.sh     # ← no $SUDO
```

`/opt` is root-owned, so the README's own non-root form (`wget … && bash get_it.sh`) died
here with *Permission denied*. Every other privileged line used `$SUDO`; this one was
missed. Now curls straight to `/opt` as root, dropping the chown/mv dance entirely.

### 2. No `set -euo pipefail` — so that failure was invisible

After the failed `mv`, the script carried on and ran the file it had just failed to place,
then logged its success line. Added `set -euo pipefail` plus an EXIT trap that reports the
failing line.

### 3. apt failures were unverified

`apt update/upgrade/install` are now best-effort — a warning-level repo hiccup must not
abort a bootstrap under `set -e` — followed by an explicit `command -v` check on `curl` and
`git`. Verify the outcome, not apt's exit code.

### Also

- **Token validation names the cause.** HTTP 401 → *"expired or revoked — generate a new
  PAT"* (the most common field failure per the HP runbook); 000 → *"could not reach
  api.github.com"*. Previously it dumped a raw API body.
- **The PAT no longer lands in `argv`.** Handover uses `sudo --preserve-env=…` instead of
  inline `VAR=VALUE` assignments, which any user on the box could read out of `ps`.
- **Self-removal actually removes.** Uses `BASH_SOURCE` rather than a relative
  `rm -f get_it.sh` that missed whenever the caller's CWD differed.
- **`GIT_BRANCH` passthrough** so the BindPlane line can be bootstrapped, not just legacy.
- **`CLONE_REPO_URL` override** so a candidate `clone_repo.sh` can be validated before it
  reaches `BuildStep main` — field boxes fetch `main` live and must never be the guinea pig.
  Unset = the production URL, i.e. unchanged.

### Test plan — live-fired on `bs-claude-24-fresh-1`

| Case | Result |
|---|---|
| Non-root run (`cl0udwave`, passwordless sudo) | ✅ `RC=0` — the exact path that used to fail at `mv` |
| Legacy honeypot (`BUILD_OPTION=2`, `GIT_BRANCH=main`) | ✅ cloned `main @ 8f04719` |
| BindPlane (`GIT_BRANCH=BindPlane_Implementation`) | ✅ cloned `bd22502`, upstream set |
| Orchestrator (`BUILD_OPTION=4`) | ✅ cloned `main @ 87e89ae` |
| Self-destruct | ✅ removed itself; a follow-up run correctly failed 127 until re-staged |
| Token handling | ✅ never written to disk on the target by the script, never echoed |

Not exercised: an expired PAT, and the interactive masked prompt (all runs were
non-interactive via `GITHUB_TOKEN`). The masking code is unchanged from the original.

### Risks

- Failures that previously passed silently now abort — intended, but it is a behaviour change.
- `apt upgrade` still runs on every bootstrap (unchanged); it is slow on a stale box and can
  leave services wanting a restart. Out of scope here, but worth a follow-up decision.
