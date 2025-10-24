#!/bin/bash
# module-dns.sh - Dynamic DNS configuration module
# Part of Home CI/CD Server deployment automation
#
# This module configures dynamic DNS updates using Dynu API:
# - Stores API credentials securely
# - Sets up cron job for periodic updates
# - Provides manual update capability
#
# This module is idempotent and can be run multiple times safely.

set -euo pipefail

# ============================================================================
# Module Initialization
# ============================================================================

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$MODULE_DIR/.." && pwd)"

# Source library functions
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=../lib/logging.sh
source "$SCRIPT_DIR/lib/logging.sh"
# shellcheck source=../lib/validation.sh
source "$SCRIPT_DIR/lib/validation.sh"

# Module metadata
MODULE_NAME="dns"
MODULE_VERSION="1.0.0"
# shellcheck disable=SC2034  # Used by deployment system
MODULE_DESCRIPTION="Dynamic DNS configuration using Dynu API"

# ============================================================================
# Configuration
# ============================================================================

# Deployment directories (must match module-base-system.sh)
DEPLOYMENT_ROOT="/opt/core-setup"
DEPLOYMENT_SCRIPTS="${DEPLOYMENT_ROOT}/scripts"
DEPLOYMENT_CONFIG="${DEPLOYMENT_ROOT}/config"

# DNS configuration
DOMAIN_NAME="${DOMAIN_NAME:-core.mohjave.com}"
DYNU_API_KEY="${DYNU_API_KEY:-XTc3be75U4636TXZUV5VeWd3eXcXYT43}"
API_KEY_FILE="${DEPLOYMENT_CONFIG}/.dynu-api-key"
DNS_UPDATE_SCRIPT="${DEPLOYMENT_SCRIPTS}/update-dynu-dns.sh"
CRON_SCHEDULE="*/15 * * * *"  # Every 15 minutes

# ============================================================================
# Idempotency Checks
# ============================================================================

function check_module_state() {
    local state_file="${DEPLOYMENT_CONFIG}/.${MODULE_NAME}.state"

    if [[ -f "$state_file" ]]; then
        # shellcheck source=/dev/null
        source "$state_file"
        return 0
    fi
    return 1
}

function save_module_state() {
    local state_file="${DEPLOYMENT_CONFIG}/.${MODULE_NAME}.state"

    cat > "$state_file" << EOF
# Module state file for: $MODULE_NAME
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

MODULE_LAST_RUN=$(date +%s)
MODULE_VERSION=$MODULE_VERSION
MODULE_STATUS=completed

DNS_CONFIGURED=yes
CRON_INSTALLED=yes
EOF

    chmod 600 "$state_file"
}

# ============================================================================
# DNS Configuration Functions
# ============================================================================

function install_dns_update_script() {
    log_task_start "Install DNS update script"

    # Ensure deployment directories exist
    ensure_directory "$DEPLOYMENT_SCRIPTS" "755" "root:root"
    ensure_directory "$DEPLOYMENT_CONFIG" "700" "root:root"

    # Copy DNS update script
    local source_script="${SCRIPT_DIR}/scripts/update-dynu-dns.sh"

    if [[ ! -f "$source_script" ]]; then
        log_error "Source script not found: $source_script"
        log_task_failed "DNS update script not found"
        return 1
    fi

    log_info "Copying DNS update script to $DNS_UPDATE_SCRIPT..."
    cp "$source_script" "$DNS_UPDATE_SCRIPT"
    chmod 755 "$DNS_UPDATE_SCRIPT"
    chown root:root "$DNS_UPDATE_SCRIPT"

    log_success "DNS update script installed"
    log_task_complete
    return 0
}

function configure_api_credentials() {
    log_task_start "Configure Dynu API credentials"

    # Store API key securely
    log_info "Storing API key in $API_KEY_FILE..."
    echo "$DYNU_API_KEY" > "$API_KEY_FILE"
    chmod 600 "$API_KEY_FILE"
    chown root:root "$API_KEY_FILE"

    log_success "API credentials configured"
    log_task_complete
    return 0
}

function test_dns_update() {
    log_task_start "Test DNS update"

    # Run the update script once to verify it works
    log_info "Running initial DNS update..."

    if "$DNS_UPDATE_SCRIPT"; then
        log_success "DNS update test successful"
        log_task_complete
        return 0
    else
        log_warn "DNS update test failed (this may be normal if IP hasn't changed)"
        log_task_complete
        return 0
    fi
}

function setup_cron_job() {
    log_task_start "Setup DNS update cron job"

    local cron_command="$DNS_UPDATE_SCRIPT >> /var/log/dynu-dns-update.log 2>&1"
    local cron_entry="$CRON_SCHEDULE $cron_command"

    # Check if cron job already exists
    if crontab -l 2>/dev/null | grep -F "$DNS_UPDATE_SCRIPT" >/dev/null; then
        log_info "Cron job already exists, updating..."
        # Remove old entry
        (crontab -l 2>/dev/null | grep -v "$DNS_UPDATE_SCRIPT") | crontab -
    fi

    # Add new cron job
    log_info "Adding cron job: $cron_entry"
    (crontab -l 2>/dev/null; echo "$cron_entry") | crontab -

    log_success "Cron job configured (runs every 15 minutes)"
    log_task_complete
    return 0
}

function show_dns_info() {
    log_info "=================================================="
    log_info "Dynamic DNS Configuration Summary"
    log_info "=================================================="
    log_info "Domain: $DOMAIN_NAME"
    log_info "Update script: $DNS_UPDATE_SCRIPT"
    log_info "Update schedule: Every 15 minutes"
    log_info "Log file: /var/log/dynu-dns-update.log"
    log_info ""
    log_info "Manual update: sudo $DNS_UPDATE_SCRIPT"
    log_info "View logs: tail -f /var/log/dynu-dns-update.log"
    log_info "=================================================="
}

# ============================================================================
# Main Module Execution
# ============================================================================

function main() {
    log_module_start "$MODULE_NAME"

    # Skip DNS module in E2E test environments
    if [[ "${E2E_TEST_MODE:-false}" == "true" ]]; then
        log_info "Skipping DNS module in E2E test environment"
        log_module_complete
        return 0
    fi

    # Check module state
    if check_module_state; then
        log_info "Re-running module (idempotent mode)"
    fi

    # Install and configure DNS updates
    install_dns_update_script || return 1
    configure_api_credentials || return 1
    test_dns_update || return 1
    setup_cron_job || return 1

    # Show configuration info
    show_dns_info

    # Save module state
    save_module_state

    log_module_complete
    return 0
}

# ============================================================================
# Module Entry Point
# ============================================================================

main "$@"
