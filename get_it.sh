#!/bin/bash
#
# get_it.sh — bootstrap a fresh appliance host.
#
# Installs prerequisites, validates a GitHub PAT, downloads clone_repo.sh from the
# BuildStep repo, and runs it. clone_repo.sh does the actual repo clone into /opt.
#
# Environment passthrough (all optional — prompts interactively when unset):
#   GITHUB_TOKEN   GitHub PAT (ghp_...). Prompted with * masking when unset.
#   BUILD_OPTION   1=Sentinel 2=Honeypot 3=VScan 4=Orchestrator — skips the menu.
#   GIT_BRANCH     Branch for clone_repo.sh to check out (default: main).
#                  main = the LEGACY build line. The BindPlane honeypot line needs
#                  BindPlane_Implementation.

set -euo pipefail

# --- CONFIG ---
GITHUB_API_USER="https://api.github.com/user"
# Overridable ONLY so a candidate clone_repo.sh can be validated end-to-end before it
# is merged to BuildStep main (field boxes fetch main, so it must never be the guinea
# pig). Unset = the production URL, i.e. unchanged behaviour.
GITHUB_REPO_URL="${CLONE_REPO_URL:-https://raw.githubusercontent.com/gocloudwave/BuildStep/refs/heads/main/clone_repo.sh}"
CLONE_REPO_DEST="/opt/clone_repo.sh"
# --------------

log() { echo "[$(date '+%F %T')] $*"; }

# Any unhandled failure lands here. Without this the script used to sail past a
# failed step and still print its success line — see the mv/permission bug below.
trap 'rc=$?; [ $rc -ne 0 ] && log "ABORTED (exit $rc) at line $LINENO — nothing further was run."; exit $rc' EXIT

# Read a token with * masking — supports typing, paste, and backspace.
# Usage: read_masked_token "Prompt: " VAR_NAME
read_masked_token() {
    local prompt="${1:-Enter token: }"
    local __var="${2:-GITHUB_TOKEN}"
    local token="" char
    local old_stty
    old_stty=$(stty -g 2>/dev/null || true)
    [ -t 0 ] && stty -echo -icanon min 1 time 0 2>/dev/null || true
    printf '%s' "$prompt" >&2
    while IFS= read -r -d '' -n1 char 2>/dev/null; do
        case "$char" in
            $'\n'|$'\r')            break ;;
            $'\x7f'|$'\x08')        # backspace / DEL
                if [ ${#token} -gt 0 ]; then
                    token="${token%?}"
                    printf '\b \b' >&2
                fi ;;
            $'\x03')                # Ctrl-C
                [ -t 0 ] && stty "$old_stty" 2>/dev/null || true
                printf '\n' >&2; exit 130 ;;
            *)
                token+="$char"
                printf '*' >&2 ;;
        esac
    done
    [ -t 0 ] && stty "$old_stty" 2>/dev/null || true
    printf '\n' >&2
    printf -v "$__var" '%s' "$token"
}

github_token_validate_pull_user() {
    log "Validating GitHub token and fetching user info..."

    if [ -z "${GITHUB_TOKEN:-}" ]; then
        log "ERROR: GITHUB_TOKEN not set. Aborting."
        exit 1
    fi

    local body_file http_code
    body_file="$(mktemp)"
    http_code=$(curl -sS -o "$body_file" -w '%{http_code}' \
        -H "Authorization: Bearer $GITHUB_TOKEN" "$GITHUB_API_USER" || echo "000")

    if [ "$http_code" != "200" ]; then
        log "ERROR: GitHub token validation failed (HTTP $http_code)."
        # 401 = expired/revoked PAT. This is the single most common field failure,
        # so name it explicitly rather than dumping a raw API body.
        [ "$http_code" = "401" ] && log "       The token is expired or revoked — generate a new PAT."
        [ "$http_code" = "000" ] && log "       Could not reach api.github.com — check network/DNS/proxy."
        rm -f "$body_file"
        exit 1
    fi

    GITHUB_USER=$(grep -oE '"login": ?"[^"]+' "$body_file" | cut -d'"' -f4)
    rm -f "$body_file"
    if [ -z "${GITHUB_USER:-}" ]; then
        log "ERROR: Could not extract username from GitHub response."
        exit 1
    fi

    log "Token is valid for user: $GITHUB_USER"
}

# --- privilege helper (must be resolved before any privileged step) ---
if [ "$(id -u)" -ne 0 ]; then
    SUDO="sudo"
else
    SUDO=""
fi

# --- prerequisites ---
# apt update/upgrade is best-effort: a warning-level repo hiccup must not abort the
# bootstrap under `set -e`. What actually matters is that curl and git exist, so
# verify that explicitly instead of trusting apt's exit code.
log "Installing prerequisites (curl, git)..."
$SUDO apt-get update -y  || log "WARN: apt-get update returned non-zero; continuing."
$SUDO apt-get upgrade -y || log "WARN: apt-get upgrade returned non-zero; continuing."
$SUDO apt-get install -y curl git || log "WARN: apt-get install returned non-zero; verifying anyway."

missing=""
for bin in curl git; do
    command -v "$bin" >/dev/null 2>&1 || missing="$missing $bin"
done
if [ -n "$missing" ]; then
    log "ERROR: required tool(s) still missing after install:$missing"
    exit 1
fi

# --- main ---
if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    read_masked_token "Enter GitHub Token (ghp_...): " GITHUB_TOKEN
fi

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    log "No github token entered."
    exit 1
fi

github_token_validate_pull_user

# Download straight to /opt as root. The previous version curl'd into the CWD and
# then ran a bare `mv clone_repo.sh /opt/` with NO sudo — /opt is root-owned, so the
# documented non-root invocation (`bash get_it.sh`, per the README) always failed
# there with "Permission denied". Worse, with no `set -e` the script carried on to
# run the file it had failed to place, then reported success.
log "Downloading clone_repo.sh to ${CLONE_REPO_DEST} ..."
$SUDO curl -sS -f -o "$CLONE_REPO_DEST" \
    -H "Authorization: token $GITHUB_TOKEN" \
    "$GITHUB_REPO_URL" || { log "ERROR: failed to download clone_repo.sh."; exit 1; }
$SUDO chmod 0700 "$CLONE_REPO_DEST"

[ -s "$CLONE_REPO_DEST" ] || { log "ERROR: ${CLONE_REPO_DEST} is empty."; exit 1; }

export GITHUB_USER GITHUB_TOKEN
export BUILD_OPTION="${BUILD_OPTION:-}"
export GIT_BRANCH="${GIT_BRANCH:-}"

# --preserve-env rather than `sudo env VAR=VALUE ...`: the latter puts the PAT in
# argv, where any user on the box can read it out of `ps`.
log "Running clone_repo.sh ..."
if [ -n "$SUDO" ]; then
    $SUDO --preserve-env=GITHUB_USER,GITHUB_TOKEN,BUILD_OPTION,GIT_BRANCH \
        bash "$CLONE_REPO_DEST"
else
    bash "$CLONE_REPO_DEST"
fi

# Remove THIS script by its own path — the old `rm -f get_it.sh` was relative and
# silently missed whenever the caller's CWD wasn't where the file lived.
log "Removing get_it.sh for security."
_self="$(readlink -f -- "${BASH_SOURCE[0]}" 2>/dev/null || true)"
[ -n "$_self" ] && [ -f "$_self" ] && $SUDO rm -f -- "$_self" || true

log "Bootstrap complete."
