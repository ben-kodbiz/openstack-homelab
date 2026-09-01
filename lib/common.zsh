#!/usr/bin/env zsh
# common.zsh — Shared constants and utility functions

set -euo pipefail

# Project root (resolved once)
if [[ -z "${LAB_PROJECT_ROOT:-}" ]]; then
    # When sourced from main script, $0 resolves correctly
    # When sourced from tests or elsewhere, fall back to caller's directory
    LAB_PROJECT_ROOT="${0:A:h}"
fi

# Source configuration if not already loaded
if [[ -z "${LAB_NAME:-}" ]]; then
    source "${LAB_PROJECT_ROOT}/config/lab.conf"
fi

# Derived paths
LAB_LOG_DIR="${LAB_PROJECT_ROOT}/logs"
LAB_STATE_DIR="${LAB_PROJECT_ROOT}/state"

# Colors (disabled if not a terminal)
if [[ -t 1 ]]; then
    COLOR_RED='\033[0;31m'
    COLOR_GREEN='\033[0;32m'
    COLOR_YELLOW='\033[0;33m'
    COLOR_BLUE='\033[0;34m'
    COLOR_RESET='\033[0m'
else
    COLOR_RED=''
    COLOR_GREEN=''
    COLOR_YELLOW=''
    COLOR_BLUE=''
    COLOR_RESET=''
fi

# --- Logging helpers ---

log_info()    { echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET}    $*"; }
log_ok()      { echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}      $*"; }
log_warn()    { echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET}    $*"; }
log_error()   { echo -e "${COLOR_RED}[ERROR]${COLOR_RESET}   $*" >&2; }
log_fatal()   { log_error "$@"; exit 1; }

# --- Error handling ---

# Print a structured error and exit
# Usage: die STAGE COMMAND REASON SUGGESTION [LOG_FILE]
die() {
    local stage="$1" command="$2" reason="$3" suggestion="${4:-}" logfile="${5:-}"
    echo ""
    log_error "Stage:    ${stage}"
    log_error "Command:  ${command}"
    log_error "Reason:   ${reason}"
    [[ -n "${suggestion}" ]] && log_error "Action:   ${suggestion}"
    [[ -n "${logfile}" ]]   && log_error "Log:      ${logfile}"
    echo ""
    exit 1
}

# --- State management ---

state_ok() {
    local stage="$1"
    [[ -f "${LAB_STATE_DIR}/${stage}.ok" ]]
}

state_set() {
    local stage="$1"
    mkdir -p "${LAB_STATE_DIR}"
    touch "${LAB_STATE_DIR}/${stage}.ok"
}

state_clear() {
    local stage="$1"
    rm -f "${LAB_STATE_DIR}/${stage}.ok"
}

# --- Validation ---

require_var() {
    local var_name="$1"
    if [[ -z "${(P)var_name:-}" ]]; then
        log_fatal "Configuration error: ${var_name} is not set"
    fi
}

require_cmd() {
    local cmd="$1"
    if ! command -v "${cmd}" &>/dev/null; then
        log_error "Required command not found: ${cmd}"
        return 1
    fi
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        log_fatal "This operation requires root privileges. Run with sudo."
    fi
}

# --- Disk ---

get_free_gb() {
    df -BG "${1:-.}" | awk 'NR==2 {gsub(/G/,"",$4); print $4}'
}
