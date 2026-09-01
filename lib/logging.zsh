#!/usr/bin/env zsh
# logging.zsh — Timestamped file logging

set -euo pipefail

LAB_LOG_DIR="${LAB_LOG_DIR:-${LAB_PROJECT_ROOT}/logs}"

# Create a log file and redirect all output to it
# Usage: log_start "stage-name"
# Sets: LAB_CURRENT_LOG
log_start() {
    local stage="$1"
    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    LAB_CURRENT_LOG="${LAB_LOG_DIR}/${stage}-${timestamp}.log"
    mkdir -p "${LAB_LOG_DIR}"
    exec > >(tee -a "${LAB_CURRENT_LOG}") 2>&1
    log_info "Log file: ${LAB_CURRENT_LOG}"
}

# Append to the current log without creating a new file
log_append() {
    local msg="$1"
    echo "${msg}" >> "${LAB_CURRENT_LOG:-/dev/null}"
}

# Show the latest log file
log_show_latest() {
    local latest
    latest=$(ls -t "${LAB_LOG_DIR}"/*.log 2>/dev/null | head -1)
    if [[ -z "${latest}" ]]; then
        log_warn "No log files found in ${LAB_LOG_DIR}"
        return 1
    fi
    log_info "Latest log: ${latest}"
    echo ""
    cat "${latest}"
}

# List all log files
log_list() {
    ls -lt "${LAB_LOG_DIR}"/*.log 2>/dev/null || log_warn "No log files found"
}
