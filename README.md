# PreBuildStep

Downloads and runs `clone_repo.sh` from the [BuildStep](https://github.com/gocloudwave/BuildStep) repo onto a target host.

## What it does

1. Installs prerequisites (`curl`, `git`) via `apt`
2. Validates the GitHub token against the GitHub API
3. Downloads `clone_repo.sh` from the BuildStep repo using the token
4. Executes `clone_repo.sh`, which clones a selected build-scripts repo to `/opt/`
5. Self-removes `get_it.sh` for security

## Usage

### Interactive (manual run on host)

```bash
sudo wget -q -O get_it.sh https://tinyurl.com/2m6berax && sudo bash get_it.sh
```

Or without `sudo`:

```bash
wget -q -O get_it.sh https://tinyurl.com/2m6berax && bash get_it.sh
```

Direct link (without tinyurl):

```bash
wget -q -O get_it.sh raw.githubusercontent.com/gocloudwave/PreBuildStep/refs/heads/main/get_it.sh && bash get_it.sh
```

You will be prompted for a GitHub personal access token (`ghp_...`).

### Automated (non-interactive)

Set `GITHUB_TOKEN` and optionally `BUILD_OPTION` as environment variables to run without prompts.

| Variable | Required | Description |
|---|---|---|
| `GITHUB_TOKEN` | Yes | GitHub personal access token (`ghp_...`) |
| `BUILD_OPTION` | No | Clone target: `1` Sentinel, `2` Honeypot, `3` VScan, `4` Orchestrator (`9` exits) |
| `GIT_BRANCH` | No | Branch `clone_repo.sh` checks out (default `main`). Needs a `clone_repo.sh` that reads it (BuildStep `fix/clone-repo-hardening` or later). |
| `CLONE_REPO_URL` | No | A different `clone_repo.sh` to run, for testing a BuildStep commit before it reaches `main`. Must start with `https://raw.githubusercontent.com/gocloudwave/`; anything else is refused, because the token is sent to this URL. |

Prefer the masked prompt to typing the token on a command line: a command line lands in shell history,
and on a `sudo` command line it can be logged.

**Token only** — skips the token prompt, still prompts for clone target:

```bash
GITHUB_TOKEN=ghp_xxxxxxxxxxxx bash get_it.sh
```

**Fully automated** — skips all prompts:

```bash
GITHUB_TOKEN=ghp_xxxxxxxxxxxx BUILD_OPTION=3 bash get_it.sh
```

```bash
wget -q -O get_it.sh https://tinyurl.com/2m6berax
sudo GITHUB_TOKEN=ghp_xxxxxxxxxxxx BUILD_OPTION=3 bash get_it.sh
```

When `BUILD_OPTION` is set, `clone_repo.sh` also runs non-interactively and skips any post-clone follow-up prompts.

### Testing a branch before it merges

Run a candidate `get_it.sh` and `clone_repo.sh` by commit, so nothing on `main` is touched. For example,
to build the `vscan-consolidation` branch of VScanBuildScripts (enter the token at the prompt):

```bash
wget -q -O get_it.sh https://raw.githubusercontent.com/gocloudwave/PreBuildStep/<commit>/get_it.sh
sudo CLONE_REPO_URL=https://raw.githubusercontent.com/gocloudwave/BuildStep/<commit>/clone_repo.sh GIT_BRANCH=vscan-consolidation bash get_it.sh
```
