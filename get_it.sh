#!/bin/bash
#
# get_it.sh
#
# Environment passthrough (all optional — prompts interactively when unset):
#   GITHUB_TOKEN   GitHub PAT (ghp_...). Prompted with * masking when unset.
#   BUILD_OPTION   The menu choice, by number — skips the menu.
#   GIT_BRANCH     Branch for clone_repo.sh to check out (default: main).
#   RUN_BUILD      y = clone_repo.sh starts the build after the clone without asking.
#
set -euo pipefail

# --- CONFIG ---
GITHUB_API_USER="https://api.github.com/user"
GITHUB_REPO_URL="${CLONE_REPO_URL:-https://raw.githubusercontent.com/gocloudwave/BuildStep/refs/heads/main/clone_repo.sh}"
CLONE_REPO_DEST="/opt/clone_repo.sh"
# --------------

log() { echo "[$(date '+%F %T')] $*"; }

TOKEN_FILE=""
drop_token_file() { [ -n "$TOKEN_FILE" ] && rm -f -- "$TOKEN_FILE"; TOKEN_FILE=""; return 0; }
trap 'rc=$?; drop_token_file; [ $rc -ne 0 ] && log "ABORTED (exit $rc) at line $LINENO — nothing further was run."; exit $rc' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

case "$GITHUB_REPO_URL" in
    https://raw.githubusercontent.com/gocloudwave/*) ;;
    *)
        log "ERROR: CLONE_REPO_URL must start with https://raw.githubusercontent.com/gocloudwave/ (host given: $(printf '%s' "$GITHUB_REPO_URL" | sed -E 's#^([A-Za-z]+://)?([^@/]*@)?([^/?#]*).*#\3#')). The token was not sent."
        exit 1 ;;
esac

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

# --- the token ---
TOKEN_CHECKED=""
if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    read_masked_token "Enter GitHub Token (ghp_...): " GITHUB_TOKEN
    if [[ -z "${GITHUB_TOKEN:-}" ]]; then
        log "No github token entered."
        exit 1
    fi
    if command -v curl >/dev/null 2>&1; then
        github_token_validate_pull_user
        TOKEN_CHECKED=1
    fi
    # Out of this shell's variables and into the file for the length of the apt run.
    TOKEN_FILE=$(umask 077; mktemp -p /dev/shm .get_it.XXXXXXXX 2>/dev/null || mktemp)
    printf '%s' "$GITHUB_TOKEN" > "$TOKEN_FILE"
    unset GITHUB_TOKEN
fi

# --- prerequisites ---
APT_ENV=(env DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1)
APT_OPTS=(-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)
log "Installing prerequisites (curl, git)..."
$SUDO "${APT_ENV[@]}" apt-get update -y || log "WARN: apt-get update returned non-zero; continuing."
$SUDO "${APT_ENV[@]}" apt-get "${APT_OPTS[@]}" upgrade -y || log "WARN: apt-get upgrade returned non-zero; continuing."
$SUDO "${APT_ENV[@]}" apt-get "${APT_OPTS[@]}" install -y curl git || log "WARN: apt-get install returned non-zero; verifying anyway."
if [ -e /var/run/reboot-required ]; then
    log "NOTE: the upgrade needs a reboot to take full effect; reboot once the build is done."
fi

missing=""
for bin in curl git; do
    command -v "$bin" >/dev/null 2>&1 || missing="$missing $bin"
done
if [ -n "$missing" ]; then
    log "ERROR: required tool(s) still missing after install:$missing"
    exit 1
fi

# --- main ---
if [ -n "$TOKEN_FILE" ]; then
    GITHUB_TOKEN=$(<"$TOKEN_FILE")
    drop_token_file
fi

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    log "No github token entered."
    exit 1
fi

[ -n "$TOKEN_CHECKED" ] || github_token_validate_pull_user

# Download straight to /opt as root.
log "Downloading clone_repo.sh to ${CLONE_REPO_DEST} ..."
$SUDO curl -sS -f -o "$CLONE_REPO_DEST" \
    -H "Authorization: token $GITHUB_TOKEN" \
    "$GITHUB_REPO_URL" || { log "ERROR: failed to download clone_repo.sh."; exit 1; }
$SUDO chmod 0700 "$CLONE_REPO_DEST"

[ -s "$CLONE_REPO_DEST" ] || { log "ERROR: ${CLONE_REPO_DEST} is empty."; exit 1; }

export GITHUB_USER GITHUB_TOKEN
export BUILD_OPTION="${BUILD_OPTION:-}"
export GIT_BRANCH="${GIT_BRANCH:-}"
export RUN_BUILD="${RUN_BUILD:-}"

# --preserve-env rather than `sudo env VAR=VALUE ...`
log "Running clone_repo.sh ..."
if [ -n "$SUDO" ]; then
    $SUDO --preserve-env=GITHUB_USER,GITHUB_TOKEN,BUILD_OPTION,GIT_BRANCH,RUN_BUILD \
        bash "$CLONE_REPO_DEST"
else
    bash "$CLONE_REPO_DEST"
fi

# Remove this script by its own path.
log "Removing get_it.sh for security."
_self="$(readlink -f -- "${BASH_SOURCE[0]}" 2>/dev/null || true)"
[ -n "$_self" ] && [ -f "$_self" ] && $SUDO rm -f -- "$_self" || true

log "Bootstrap complete."
