#!/bin/bash
# module-netdata.sh - Netdata monitoring configuration module
# Part of Home CI/CD Server deployment automation
#
# This module configures Netdata including:
# - Installation of Netdata monitoring agent
# - Basic security configuration
# - Integration with Nginx reverse proxy
# - System monitoring setup
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
MODULE_NAME="netdata"
MODULE_VERSION="1.0.0"
# shellcheck disable=SC2034  # Used by deployment system
MODULE_DESCRIPTION="Netdata monitoring agent configuration"

# ============================================================================
# Configuration
# ============================================================================

# Netdata configuration
NETDATA_PORT="${NETDATA_PORT:-19999}"
NETDATA_CONFIG_DIR="/etc/netdata"
# shellcheck disable=SC2034  # Reserved for future use
NETDATA_DATA_DIR="/var/lib/netdata"
# shellcheck disable=SC2034  # Reserved for future use
NETDATA_CACHE_DIR="/var/cache/netdata"
# shellcheck disable=SC2034  # Reserved for future use
NETDATA_LOG_DIR="/var/log/netdata"

# Domain configuration
DOMAIN_NAME="${DOMAIN_NAME:-core.mohjave.com}"

# ============================================================================
# Idempotency Checks
# ============================================================================

function check_module_state() {
    local state_file="${DEPLOYMENT_CONFIG:-/opt/core-setup/config}/.${MODULE_NAME}.state"

    if [[ -f "$state_file" ]]; then
        # shellcheck source=/dev/null
        source "$state_file"
        return 0
    fi
    return 1
}

function save_module_state() {
    local state_file="${DEPLOYMENT_CONFIG:-/opt/core-setup/config}/.${MODULE_NAME}.state"

    cat > "$state_file" << EOF
# Module state file for: $MODULE_NAME
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

MODULE_LAST_RUN=$(date +%s)
MODULE_VERSION=$MODULE_VERSION
MODULE_STATUS=completed

NETDATA_INSTALLED=yes
NETDATA_CONFIGURED=yes
EOF

    chmod 600 "$state_file"
}

# ============================================================================
# Netdata Installation
# ============================================================================

function install_netdata() {
    log_task_start "Install Netdata"

    # Check if Netdata is already installed
    if check_command netdata; then
        log_info "Netdata already installed"
        log_task_complete
        return 0
    fi

    # Install using official kickstart script (most reliable method)
    log_info "Installing Netdata using official kickstart script..."
    log_info "This may take a few minutes to compile and install..."

    # Download and run kickstart script with non-interactive options
    local install_script="/tmp/netdata-kickstart.sh"

    log_info "Downloading Netdata kickstart script..."
    if ! wget -O "$install_script" "https://get.netdata.cloud/kickstart.sh"; then
        log_task_failed "Failed to download Netdata installation script"
        return 1
    fi

    chmod +x "$install_script"

    # Run installation with options:
    # --non-interactive: No prompts
    # --stable-channel: Use stable releases
    # --disable-telemetry: Disable anonymous statistics
    log_info "Running Netdata installation (this may take 2-3 minutes)..."
    if bash "$install_script" --non-interactive --stable-channel --disable-telemetry; then
        log_success "Netdata installed successfully"
        rm -f "$install_script"
        log_task_complete
        return 0
    else
        log_error "Netdata installation failed"
        rm -f "$install_script"
        log_task_failed "Failed to install Netdata"
        return 1
    fi
}

# ============================================================================
# Netdata Configuration
# ============================================================================

function setup_netdata_directories() {
    log_task_start "Setup Netdata directories"

    # Create required directories with proper ownership
    local dirs=(
        "/var/log/netdata"
        "/var/lib/netdata"
        "/var/cache/netdata"
        "/var/lib/netdata/registry"
    )

    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            log_info "Creating directory: $dir"
            mkdir -p "$dir"
        fi

        # Set ownership to netdata user
        if id -u netdata >/dev/null 2>&1; then
            chown -R netdata:netdata "$dir"
            chmod 755 "$dir"
            log_info "Set ownership of $dir to netdata:netdata"
        else
            log_warn "netdata user not found, will be created during installation"
        fi
    done

    log_task_complete
    return 0
}

function configure_netdata() {
    log_task_start "Configure Netdata"

    local netdata_conf="${NETDATA_CONFIG_DIR}/netdata.conf"

    # Ensure configuration directory exists
    if [[ ! -d "$NETDATA_CONFIG_DIR" ]]; then
        log_warn "Netdata configuration directory not found, creating..."
        mkdir -p "$NETDATA_CONFIG_DIR"
    fi

    # Backup existing configuration
    backup_file "$netdata_conf" 2>/dev/null || true

    # Generate default configuration if it doesn't exist
    if [[ ! -f "$netdata_conf" ]]; then
        log_info "Generating default Netdata configuration..."
        if check_command netdata; then
            netdata -W set 2>&1 | grep -v "LISTENING" > "$netdata_conf" || true
        fi
    fi

    # Configure Netdata to bind to localhost only (proxied via Nginx)
    log_info "Configuring Netdata to listen on localhost only..."

    # Create or update configuration
    cat > "$netdata_conf" << EOF
# Home CI/CD Server - Netdata Configuration
# Generated: $(date)

[global]
    # Bind to localhost only (proxied via Nginx)
    bind to = 127.0.0.1

    # Data retention (1 day for RAM, longer for disk)
    history = 3600

    # Update frequency
    update every = 1

    # Memory mode (save to disk)
    memory mode = dbengine

[web]
    # Web server configuration
    web files owner = root
    web files group = netdata

    # Disable direct access from outside (use Nginx proxy)
    bind to = 127.0.0.1:${NETDATA_PORT}

    # Allow dashboard from Nginx proxy
    allow connections from = localhost 127.0.0.1

[plugins]
    # Enable/disable plugin groups
    proc = yes
    tc = no
    idlejitter = yes
    cgroups = yes
    checks = no
    apps = yes
    python.d = yes
    charts.d = no
    node.d = no
    go.d = yes

[health]
    enabled = yes
    default repeat warning = never
    default repeat critical = never
EOF

    chown root:netdata "$netdata_conf"
    chmod 644 "$netdata_conf"

    log_task_complete
    return 0
}

function configure_netdata_health() {
    log_task_start "Configure Netdata health monitoring"

    local health_dir="${NETDATA_CONFIG_DIR}/health.d"

    ensure_directory "$health_dir" "755" "root:netdata"

    # Create custom health alarm for disk space
    cat > "${health_dir}/disk_space.conf" << 'EOF'
# Disk space monitoring
alarm: disk_space_usage
    on: disk.space
lookup: average -1m percentage of used
 every: 1m
  warn: $this > 80
  crit: $this > 90
  info: disk space usage is high
EOF

    # Create custom health alarm for memory
    cat > "${health_dir}/memory.conf" << 'EOF'
# Memory monitoring
alarm: memory_usage
    on: system.ram
lookup: average -1m percentage of used
 every: 1m
  warn: $this > 80
  crit: $this > 95
  info: memory usage is high
EOF

    log_task_complete
    return 0
}

# ============================================================================
# Netdata Service Management
# ============================================================================

function start_netdata() {
    log_task_start "Start Netdata service"

    # Enable Netdata to start on boot
    systemctl enable netdata

    # Start Netdata
    log_info "Starting Netdata service..."
    if systemctl restart netdata; then
        log_success "Netdata started successfully"
    else
        log_warn "Failed to start Netdata on first attempt, checking status..."
        systemctl status netdata --no-pager || true

        # Try again after a brief delay
        log_info "Waiting 5 seconds and retrying..."
        sleep 5
        if systemctl restart netdata; then
            log_success "Netdata started successfully on retry"
        else
            log_task_failed "Failed to start Netdata"
            return 1
        fi
    fi

    # Wait for Netdata to be ready
    log_info "Waiting for Netdata to be ready..."
    local max_wait=30
    local counter=0
    while [[ $counter -lt $max_wait ]]; do
        if curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${NETDATA_PORT}/api/v1/info" | grep -q "200"; then
            log_success "Netdata is responding"
            log_task_complete
            return 0
        fi
        sleep 1
        ((counter++))
    done

    log_warn "Netdata may not be fully ready yet (continuing)"
    log_task_complete
    return 0
}

function verify_netdata_installation() {
    log_task_start "Verify Netdata installation"

    # Check if service is running
    if ! systemctl is-active --quiet netdata; then
        log_task_failed "Netdata service is not running"
        return 1
    fi

    # Check if API is responding
    if ! curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${NETDATA_PORT}/api/v1/info" | grep -q "200"; then
        log_task_failed "Netdata API is not responding"
        return 1
    fi

    log_success "Netdata is running and responding correctly"
    log_info "Netdata dashboard accessible at: http://monitoring.${DOMAIN_NAME}"
    log_info "Local access: http://127.0.0.1:${NETDATA_PORT}"

    log_task_complete
    return 0
}

# ============================================================================
# Main Module Execution
# ============================================================================

function main() {
    log_module_start "$MODULE_NAME"

    # Check module state
    if check_module_state; then
        log_info "Re-running module (idempotent mode)"
    fi

    # Install Netdata
    install_netdata || return 1

    # Setup directories (after installation, so netdata user exists)
    setup_netdata_directories || return 1

    # Configure Netdata
    configure_netdata || return 1
    configure_netdata_health || return 1

    # Start Netdata
    start_netdata || return 1

    # Verify installation
    verify_netdata_installation || return 1

    # Save module state
    save_module_state

    log_module_complete
    return 0
}

# ============================================================================
# Module Entry Point
# ============================================================================

main "$@"
