#!/bin/bash
# logging.sh - Structured logging framework for deployment scripts
# Part of Home CI/CD Server deployment automation

set -euo pipefail

# ============================================================================
# Logging Configuration
# ============================================================================

# Only set if not already set (avoid readonly variable conflicts)
if [[ -z "${LOG_DIR:-}" ]]; then
    LOG_DIR="/opt/core-setup/logs"
fi

if [[ -z "${DEPLOYMENT_LOG:-}" ]]; then
    DEPLOYMENT_LOG="${LOG_DIR}/deployment-$(date +%Y-%m-%d).log"
fi

if [[ -z "${CHANGE_HISTORY_LOG:-}" ]]; then
    CHANGE_HISTORY_LOG="${LOG_DIR}/change-history.log"
fi

# Log levels
if [[ -z "${LOG_LEVEL_DEBUG:-}" ]]; then
    LOG_LEVEL_DEBUG=0
    LOG_LEVEL_INFO=1
    LOG_LEVEL_WARN=2
    LOG_LEVEL_ERROR=3
    LOG_LEVEL_SUCCESS=4
fi

# Current log level (INFO by default)
LOG_LEVEL="${LOG_LEVEL:-$LOG_LEVEL_INFO}"

# Colors for console output - always ensure they're set
if [[ -t 1 ]]; then
    COLOR_RESET=${COLOR_RESET:-'\033[0m'}
    COLOR_DEBUG=${COLOR_DEBUG:-'\033[0;36m'}     # Cyan
    COLOR_INFO=${COLOR_INFO:-'\033[0;34m'}       # Blue
    COLOR_WARN=${COLOR_WARN:-'\033[0;33m'}       # Yellow
    COLOR_ERROR=${COLOR_ERROR:-'\033[0;31m'}     # Red
    COLOR_SUCCESS=${COLOR_SUCCESS:-'\033[0;32m'} # Green
else
    COLOR_RESET=${COLOR_RESET:-''}
    COLOR_DEBUG=${COLOR_DEBUG:-''}
    COLOR_INFO=${COLOR_INFO:-''}
    COLOR_WARN=${COLOR_WARN:-''}
    COLOR_ERROR=${COLOR_ERROR:-''}
    COLOR_SUCCESS=${COLOR_SUCCESS:-''}
fi

# ============================================================================
# Core Logging Functions
# ============================================================================

# Initialize logging
function init_logging() {
    # Ensure log directory exists
    if [[ ! -d "$LOG_DIR" ]]; then
        mkdir -p "$LOG_DIR"
        chmod 755 "$LOG_DIR"
    fi

    # Create log files if they don't exist
    touch "$DEPLOYMENT_LOG" "$CHANGE_HISTORY_LOG"
    chmod 644 "$DEPLOYMENT_LOG" "$CHANGE_HISTORY_LOG"

    log_info "Logging initialized"
    log_info "Deployment log: $DEPLOYMENT_LOG"
    log_info "Change history: $CHANGE_HISTORY_LOG"
}

# Generic log function
function _log() {
    local level="$1"
    local level_num="$2"
    local color="$3"
    shift 3
    local message="$*"

    # Check if message should be logged based on level
    if [[ $level_num -lt $LOG_LEVEL ]]; then
        return 0
    fi

    # Get timestamp
    local timestamp
    timestamp="$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")"

    # Get caller information
    local caller_file="${BASH_SOURCE[2]##*/}"
    local caller_line="${BASH_LINENO[1]}"
    local caller_func="${FUNCNAME[2]:-main}"

    # Format log entry (structured JSON-like)
    local log_entry="[$timestamp] [$level] [$caller_file:$caller_line:$caller_func] $message"

    # Write to log file (ensure directory exists first)
    if [[ ! -d "$LOG_DIR" ]]; then
        mkdir -p "$LOG_DIR" 2>/dev/null || true
    fi
    echo "$log_entry" >> "$DEPLOYMENT_LOG" 2>/dev/null || true

    # Write to console with color
    echo -e "${color}[$level]${COLOR_RESET} $message"
}

# Log debug message
function log_debug() {
    _log "DEBUG" "$LOG_LEVEL_DEBUG" "$COLOR_DEBUG" "$@"
}

# Log info message
function log_info() {
    _log "INFO" "$LOG_LEVEL_INFO" "$COLOR_INFO" "$@"
}

# Log warning message
function log_warn() {
    _log "WARN" "$LOG_LEVEL_WARN" "$COLOR_WARN" "$@"
}

# Log error message
function log_error() {
    _log "ERROR" "$LOG_LEVEL_ERROR" "$COLOR_ERROR" "$@"
}

# Log success message
function log_success() {
    _log "SUCCESS" "$LOG_LEVEL_SUCCESS" "$COLOR_SUCCESS" "$@"
}

# ============================================================================
# Change History Logging
# ============================================================================

# Log change to change history (audit trail)
function log_change() {
    local action="$1"
    shift
    local details="$*"

    local timestamp
    timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    local user="${SUDO_USER:-${USER:-$(whoami)}}"
    local hostname
    hostname="$(hostname)"

    # Format: [TIMESTAMP] [HOSTNAME] [USER] ACTION: Details
    local change_entry="[$timestamp] [$hostname] [$user] $action: $details"

    # Ensure log directory exists before writing
    if [[ ! -d "$LOG_DIR" ]]; then
        mkdir -p "$LOG_DIR" 2>/dev/null || true
    fi
    echo "$change_entry" >> "$CHANGE_HISTORY_LOG" 2>/dev/null || true
    log_info "CHANGE: $action - $details"
}

# ============================================================================
# Structured Event Logging
# ============================================================================

# Log structured event (for parsing/monitoring)
function log_event() {
    local event_type="$1"
    local event_data="$2"

    local timestamp
    timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    # JSON-like structure for easy parsing
    local event_json="{\"timestamp\":\"$timestamp\",\"type\":\"$event_type\",\"data\":\"$event_data\"}"

    # Ensure log directory exists before writing
    if [[ ! -d "$LOG_DIR" ]]; then
        mkdir -p "$LOG_DIR" 2>/dev/null || true
    fi
    echo "$event_json" >> "${LOG_DIR}/events-$(date +%Y-%m-%d).log" 2>/dev/null || true
}

# Log security event
function log_security_event() {
    local event_type="$1"
    local severity="$2"
    local source_ip="${3:-unknown}"
    local details="$4"

    local timestamp
    timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    local security_log
    security_log="/var/log/central/security/$(date +%Y-%m-%d).log"
    mkdir -p "$(dirname "$security_log")"

    # Security event format
    local event="{\"timestamp\":\"$timestamp\",\"event_type\":\"$event_type\",\"severity\":\"$severity\",\"source_ip\":\"$source_ip\",\"details\":\"$details\"}"

    echo "$event" >> "$security_log"
    log_warn "SECURITY EVENT: $event_type (severity: $severity) from $source_ip"
}

# ============================================================================
# Progress Tracking
# ============================================================================

# Log task start
function log_task_start() {
    local task_name="$1"
    log_info "=========================================="
    log_info "Starting task: $task_name"
    log_info "=========================================="

    # Store start time for duration calculation
    TASK_START_TIME=$(date +%s)
    export TASK_START_TIME
    export CURRENT_TASK="$task_name"
}

# Log task completion
function log_task_complete() {
    local task_name="${CURRENT_TASK:-unknown}"
    local end_time
    end_time=$(date +%s)
    local start_time="${TASK_START_TIME:-$end_time}"
    local duration=$((end_time - start_time))

    log_success "Task completed: $task_name (${duration}s)"
    log_change "TASK_COMPLETED" "$task_name in ${duration}s"

    unset TASK_START_TIME
    unset CURRENT_TASK
}

# Log task failure
function log_task_failed() {
    local task_name="${CURRENT_TASK:-unknown}"
    local error_message="$1"

    log_error "Task failed: $task_name"
    log_error "Error: $error_message"
    log_change "TASK_FAILED" "$task_name - $error_message"

    unset TASK_START_TIME
    unset CURRENT_TASK
}

# ============================================================================
# Module Logging
# ============================================================================

# Log module start
function log_module_start() {
    local module_name="$1"
    log_info "=========================================="
    log_info "Module: $module_name"
    log_info "=========================================="

    MODULE_START_TIME=$(date +%s)
    export MODULE_START_TIME
    export CURRENT_MODULE="$module_name"

    log_change "MODULE_START" "$module_name"
}

# Log module completion
function log_module_complete() {
    local module_name="${CURRENT_MODULE:-unknown}"
    local end_time
    end_time=$(date +%s)
    local start_time="${MODULE_START_TIME:-$end_time}"
    local duration=$((end_time - start_time))

    log_success "Module completed: $module_name (${duration}s)"
    log_change "MODULE_COMPLETED" "$module_name in ${duration}s"

    unset MODULE_START_TIME
    unset CURRENT_MODULE
}

# Log module failure
function log_module_failed() {
    local module_name="${CURRENT_MODULE:-unknown}"
    local error_message="$1"

    log_error "Module failed: $module_name"
    log_error "Error: $error_message"
    log_change "MODULE_FAILED" "$module_name - $error_message"

    unset MODULE_START_TIME
    unset CURRENT_MODULE
}

# ============================================================================
# Deployment Session Logging
# ============================================================================

# Log deployment start
function log_deployment_start() {
    local deployment_type="${1:-full}"
    local current_user="${SUDO_USER:-${USER:-$(whoami)}}"

    log_info "=========================================="
    log_info "DEPLOYMENT START: $deployment_type"
    log_info "=========================================="
    log_info "Timestamp: $(date)"
    log_info "User: $current_user"
    log_info "Hostname: $(hostname)"
    log_info "=========================================="

    DEPLOYMENT_START_TIME=$(date +%s)
    export DEPLOYMENT_START_TIME

    log_change "DEPLOYMENT_START" "Type: $deployment_type, User: $current_user"
}

# Log deployment completion
function log_deployment_complete() {
    local end_time
    end_time=$(date +%s)
    local start_time="${DEPLOYMENT_START_TIME:-$end_time}"
    local duration=$((end_time - start_time))

    log_success "=========================================="
    log_success "DEPLOYMENT COMPLETE"
    log_success "=========================================="
    log_success "Total duration: ${duration}s ($(format_duration "$duration"))"
    log_success "=========================================="

    log_change "DEPLOYMENT_COMPLETED" "Duration: ${duration}s"

    unset DEPLOYMENT_START_TIME
}

# Log deployment failure
function log_deployment_failed() {
    local error_message="$1"
    local end_time
    end_time=$(date +%s)
    local start_time="${DEPLOYMENT_START_TIME:-$end_time}"
    local duration=$((end_time - start_time))

    log_error "=========================================="
    log_error "DEPLOYMENT FAILED"
    log_error "=========================================="
    log_error "Error: $error_message"
    log_error "Duration before failure: ${duration}s"
    log_error "=========================================="

    log_change "DEPLOYMENT_FAILED" "$error_message after ${duration}s"

    unset DEPLOYMENT_START_TIME
}

# ============================================================================
# Helper function for duration formatting
# ============================================================================

function format_duration() {
    local seconds="$1"
    local hours=$((seconds / 3600))
    local minutes=$(((seconds % 3600) / 60))
    local secs=$((seconds % 60))

    if [[ $hours -gt 0 ]]; then
        printf "%dh %dm %ds" "$hours" "$minutes" "$secs"
    elif [[ $minutes -gt 0 ]]; then
        printf "%dm %ds" "$minutes" "$secs"
    else
        printf "%ds" "$secs"
    fi
}

# ============================================================================
# Export Functions
# ============================================================================

export -f init_logging
export -f log_debug
export -f log_info
export -f log_warn
export -f log_error
export -f log_success
export -f log_change
export -f log_event
export -f log_security_event
export -f log_task_start
export -f log_task_complete
export -f log_task_failed
export -f log_module_start
export -f log_module_complete
export -f log_module_failed
export -f log_deployment_start
export -f log_deployment_complete
export -f log_deployment_failed
export -f format_duration
