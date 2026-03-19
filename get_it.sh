#!/bin/bash

# --- CONFIG ---
GITHUB_API_USER="https://api.github.com/user"
# --------------

log() { echo "[$(date '+%F %T')] $*"; }

# Read a token with * masking — supports typing, paste, and backspace.
# Usage: read_masked_token "Prompt: " VAR_NAME
read_masked_token() {
    local prompt="${1:-Enter token: }"
    local __var="${2:-GITHUB_TOKEN}"
    local token="" char
    local old_stty
    old_stty=$(stty -g 2>/dev/null)
    [ -t 0 ] && stty -echo -icanon min 1 time 0 2>/dev/null
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
                [ -t 0 ] && stty "$old_stty" 2>/dev/null
                printf '\n' >&2; exit 130 ;;
            *)
                token+="$char"
                printf '*' >&2 ;;
        esac
    done
    [ -t 0 ] && stty "$old_stty" 2>/dev/null
    printf '\n' >&2
    printf -v "$__var" '%s' "$token"
}

github_token_validate_pull_user() {
    log "Validating GitHub token and fetching user info..."

    if [ -z "${GITHUB_TOKEN:-}" ]; then
        log "ERROR: GITHUB_TOKEN not set. Aborting."
        exit 1
    fi

    # Hit the /user endpoint
    BODY_FILE="$(mktemp)"
    USER_JSON=$(curl -sS -w "\n%{http_code}" -o $BODY_FILE \
    -H "Authorization: Bearer $GITHUB_TOKEN" $GITHUB_API_USER)

    # Split out HTTP status and response body
    HTTP_CODE=$(tail -n1 <<<"$USER_JSON")
    BODY=$(head -n -1 <<<"$USER_JSON")

    if [ "$HTTP_CODE" != "200" ]; then
        log "ERROR: GitHub token validation failed (HTTP $HTTP_CODE)."
        cat $BODY_FILE
        exit 1
    fi

    # Extract username from JSON safely (using grep + cut for portability)
    GITHUB_USER=$(grep -oE '"login": ?"[^"]+' $BODY_FILE | cut -d'"' -f4)
    if [ -z "$GITHUB_USER" ]; then
        log "ERROR: Could not extract username from GitHub response."
        exit 1
    fi
    rm -f "$BODY_FILE"

    log "Token is valid for user: $GITHUB_USER"
}

sudo apt update -y && sudo apt upgrade -y
sudo apt install -y curl git

#--- main ---
GITHUB_REPO_URL="https://raw.githubusercontent.com/gocloudwave/BuildStep/refs/heads/main/clone_repo.sh"
read_masked_token "Enter GitHub Token (ghp_...): " GITHUB_TOKEN

if [[ -z "$GITHUB_TOKEN" ]]; then
    log "No github token entered."
    exit 1
fi

github_token_validate_pull_user

# --- helper ---
if [ "$(id -u)" -ne 0 ]; then
    SUDO="sudo"
else
    SUDO=""
fi

$SUDO curl -sS -f -o clone_repo.sh \
    -H "Authorization: token $GITHUB_TOKEN" \
    "$GITHUB_REPO_URL" || { log "Error curl-ing clone_repo.sh."; exit 1; }
$SUDO chown "$(id -u):$(id -g)" clone_repo.sh
$SUDO chmod +x clone_repo.sh
mv clone_repo.sh /opt/clone_repo.sh
$SUDO env GITHUB_USER="${GITHUB_USER}" GITHUB_TOKEN="${GITHUB_TOKEN}" bash /opt/clone_repo.sh

log "Removing get_it.sh script for security."
sudo rm -f get_it.sh