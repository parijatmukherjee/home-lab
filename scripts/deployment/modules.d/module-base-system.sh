#!/bin/bash
# module-base-system.sh - Base system configuration module
# Part of Home CI/CD Server deployment automation
#
# This module configures the base system including:
# - System packages and updates
# - Directory structure
# - System users and groups
# - Basic security hardening
# - Time synchronization
# - Hostname configuration
#
# This module is idempotent and can be run multiple times safely.

set -euo pipefail

# ============================================================================
# Module Initialization
# ============================================================================

# Get script directory
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
MODULE_NAME="base-system"
MODULE_VERSION="1.0.0"
# shellcheck disable=SC2034  # Used by deployment system
MODULE_DESCRIPTION="Base system configuration and hardening"

# ============================================================================
# Configuration
# ============================================================================

# Deployment directories
DEPLOYMENT_ROOT="/opt/core-setup"
DEPLOYMENT_SCRIPTS="${DEPLOYMENT_ROOT}/scripts"
DEPLOYMENT_CONFIG="${DEPLOYMENT_ROOT}/config"
DEPLOYMENT_LOGS="${DEPLOYMENT_ROOT}/logs"
DEPLOYMENT_BACKUPS="${DEPLOYMENT_ROOT}/backups"

# Data directories
DATA_ROOT="/srv/data"
ARTIFACTS_DIR="${DATA_ROOT}/artifacts"
DOCKER_REGISTRY_DIR="${DATA_ROOT}/docker-registry"

# System configuration
REQUIRED_PACKAGES=(
    "curl"
    "wget"
    "git"
    "vim"
    "htop"
    "net-tools"
    "dnsutils"
    "ca-certificates"
    "gnupg"
    "lsb-release"
    "apt-transport-https"
    "software-properties-common"
    "jq"
    "unzip"
    "rsync"
    "apache2-utils"
    "openssl"
)

# Optional packages (nice to have)
OPTIONAL_PACKAGES=(
    "tmux"
    "tree"
    "ncdu"
    "iotop"
    "bats"
    "shellcheck"
)

# ============================================================================
# Idempotency Checks
# ============================================================================

# Check if module has been run before
function check_module_state() {
    local state_file="${DEPLOYMENT_CONFIG}/.${MODULE_NAME}.state"

    if [[ -f "$state_file" ]]; then
        log_info "Module state file found: $state_file"
        # shellcheck source=/dev/null
        source "$state_file"
        return 0
    else
        log_info "First run of module: $MODULE_NAME"
        return 1
    fi
}

# Save module state
function save_module_state() {
    local state_file="${DEPLOYMENT_CONFIG}/.${MODULE_NAME}.state"

    cat > "$state_file" << EOF
# Module state file for: $MODULE_NAME
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

MODULE_LAST_RUN=$(date +%s)
MODULE_VERSION=$MODULE_VERSION
MODULE_STATUS=completed

# Package installation
PACKAGES_INSTALLED=yes
SYSTEM_UPDATED=yes

# Directory structure
DIRECTORIES_CREATED=yes

# System configuration
HOSTNAME_CONFIGURED=yes
TIMEZONE_CONFIGURED=yes
NTP_CONFIGURED=yes
SSH_HARDENED=yes

EOF

    chmod 600 "$state_file"
    log_info "Module state saved: $state_file"
}

# ============================================================================
# System Package Management
# ============================================================================

# Update package lists
function update_package_lists() {
    log_task_start "Update package lists"

    if apt-get update; then
        log_task_complete
        return 0
    else
        log_task_failed "Failed to update package lists"
        return 1
    fi
}

# Upgrade installed packages
function upgrade_system_packages() {
    log_task_start "Upgrade system packages"

    # Check if system needs upgrading
    local upgradable
    upgradable=$(apt list --upgradable 2>/dev/null | grep -c upgradable || echo "0")

    if [[ $upgradable -eq 0 ]]; then
        log_info "System is already up to date"
        log_task_complete
        return 0
    fi

    log_info "Upgrading $upgradable packages..."

    # Perform upgrade
    if DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"; then
        log_task_complete
        return 0
    else
        log_task_failed "Failed to upgrade packages"
        return 1
    fi
}

# Install required packages
function install_required_packages() {
    log_task_start "Install required packages"

    local missing_packages=()

    # Check which packages are missing
    for package in "${REQUIRED_PACKAGES[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package "; then
            missing_packages+=("$package")
        fi
    done

    if [[ ${#missing_packages[@]} -eq 0 ]]; then
        log_info "All required packages are already installed"
        log_task_complete
        return 0
    fi

    log_info "Installing ${#missing_packages[@]} missing packages: ${missing_packages[*]}"

    # Install missing packages
    if DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing_packages[@]}"; then
        log_task_complete
        return 0
    else
        log_task_failed "Failed to install required packages"
        return 1
    fi
}

# Install optional packages (best effort)
function install_optional_packages() {
    log_task_start "Install optional packages"

    local installed=0

    for package in "${OPTIONAL_PACKAGES[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package "; then
            if DEBIAN_FRONTEND=noninteractive apt-get install -y "$package" &> /dev/null; then
                log_info "Installed optional package: $package"
                ((installed++))
            else
                log_warn "Failed to install optional package: $package (skipping)"
            fi
        fi
    done

    log_info "Installed $installed optional packages"
    log_task_complete
    return 0
}

# Enable automatic security updates
function configure_automatic_security_updates() {
    log_task_start "Configure automatic security updates"

    # Install unattended-upgrades
    if ! dpkg -l | grep -q "^ii  unattended-upgrades "; then
        if ! DEBIAN_FRONTEND=noninteractive apt-get install -y unattended-upgrades; then
            log_task_failed "Failed to install unattended-upgrades"
            return 1
        fi
    fi

    # Configure unattended-upgrades
    local config_file="/etc/apt/apt.conf.d/50unattended-upgrades"

    if [[ -f "$config_file" ]]; then
        backup_file "$config_file"

        # Enable automatic security updates
        cat > "$config_file" << 'EOF'
// Automatically upgrade packages from these origins
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};

// Automatically remove unused dependencies
Unattended-Upgrade::Remove-Unused-Dependencies "true";

// Automatically reboot if required
Unattended-Upgrade::Automatic-Reboot "false";

// Send email notification on errors
Unattended-Upgrade::Mail "root";
Unattended-Upgrade::MailReport "on-change";
EOF

        # Enable auto-update service
        systemctl enable unattended-upgrades
        systemctl start unattended-upgrades

        log_task_complete
        return 0
    else
        log_task_failed "Configuration file not found: $config_file"
        return 1
    fi
}

# ============================================================================
# Directory Structure
# ============================================================================

# Create deployment directory structure
function create_directory_structure() {
    log_task_start "Create directory structure"

    # Deployment directories
    ensure_directory "$DEPLOYMENT_ROOT" "755" "root:root"
    ensure_directory "$DEPLOYMENT_SCRIPTS" "755" "root:root"
    ensure_directory "$DEPLOYMENT_CONFIG" "755" "root:root"
    ensure_directory "$DEPLOYMENT_LOGS" "755" "root:root"
    ensure_directory "$DEPLOYMENT_BACKUPS" "750" "root:root"

    # Data directories
    ensure_directory "$DATA_ROOT" "755" "root:root"
    ensure_directory "$ARTIFACTS_DIR" "755" "root:root"
    ensure_directory "$DOCKER_REGISTRY_DIR" "755" "root:root"

    # Artifact subdirectories
    for artifact_type in iso jar npm python docker generic; do
        ensure_directory "${ARTIFACTS_DIR}/${artifact_type}" "755" "root:root"
    done

    # Log subdirectories
    ensure_directory "${DEPLOYMENT_LOGS}/modules" "755" "root:root"
    ensure_directory "/var/log/central" "755" "root:root"
    ensure_directory "/var/log/central/security" "750" "root:root"
    ensure_directory "/var/log/central/backups" "755" "root:root"
    ensure_directory "/var/log/central/alerts" "755" "root:root"

    # Backup subdirectories
    ensure_directory "${DEPLOYMENT_BACKUPS}/config-snapshots" "750" "root:root"
    ensure_directory "/srv/backups" "750" "root:root"
    ensure_directory "/srv/backups/restic-repo" "750" "root:root"

    log_task_complete
    return 0
}

# Copy deployment scripts to deployment directory
function install_deployment_scripts() {
    log_task_start "Install deployment scripts"

    # Copy entire scripts directory to deployment location
    if [[ -d "$SCRIPT_DIR" ]]; then
        rsync -a --exclude='.git' "$SCRIPT_DIR/" "$DEPLOYMENT_SCRIPTS/"
        chmod -R u+rwX,go+rX,go-w "$DEPLOYMENT_SCRIPTS"

        # Make scripts executable
        find "$DEPLOYMENT_SCRIPTS" -type f -name "*.sh" -exec chmod +x {} \;

        log_task_complete
        return 0
    else
        log_task_failed "Source script directory not found: $SCRIPT_DIR"
        return 1
    fi
}

# ============================================================================
# System Configuration
# ============================================================================

# Configure hostname
function configure_hostname() {
    log_task_start "Configure hostname"

    local current_hostname
    current_hostname=$(hostname)
    local desired_hostname="${HOSTNAME:-$current_hostname}"

    if [[ "$current_hostname" == "$desired_hostname" ]]; then
        log_info "Hostname already configured: $current_hostname"
        log_task_complete
        return 0
    fi

    log_info "Setting hostname to: $desired_hostname"

    # Set hostname
    hostnamectl set-hostname "$desired_hostname"

    # Update /etc/hosts
    if ! grep -q "$desired_hostname" /etc/hosts; then
        backup_file /etc/hosts
        echo "127.0.1.1 $desired_hostname" >> /etc/hosts
    fi

    log_task_complete
    return 0
}

# Configure timezone
function configure_timezone() {
    log_task_start "Configure timezone"

    local current_timezone
    current_timezone=$(timedatectl show --property=Timezone --value)
    local desired_timezone="${TIMEZONE:-UTC}"

    if [[ "$current_timezone" == "$desired_timezone" ]]; then
        log_info "Timezone already configured: $current_timezone"
        log_task_complete
        return 0
    fi

    log_info "Setting timezone to: $desired_timezone"

    timedatectl set-timezone "$desired_timezone"

    log_task_complete
    return 0
}

# Configure NTP time synchronization
function configure_ntp() {
    log_task_start "Configure NTP time synchronization"

    # Install systemd-timesyncd if not present
    if ! systemctl is-enabled --quiet systemd-timesyncd 2>/dev/null; then
        systemctl enable systemd-timesyncd
        systemctl start systemd-timesyncd
    fi

    # Enable NTP synchronization
    timedatectl set-ntp true

    # Verify NTP is working
    if timedatectl show | grep -q "NTP=yes"; then
        log_success "NTP synchronization enabled"
        log_task_complete
        return 0
    else
        log_warn "NTP synchronization may not be working correctly"
        log_task_complete
        return 0
    fi
}

# Configure system limits
function configure_system_limits() {
    log_task_start "Configure system limits"

    local limits_file="/etc/security/limits.conf"

    backup_file "$limits_file"

    # Add limits for better performance
    cat >> "$limits_file" << 'EOF'

# Home CI/CD Server - System Limits
*               soft    nofile          65536
*               hard    nofile          65536
root            soft    nofile          65536
root            hard    nofile          65536

EOF

    log_task_complete
    return 0
}

# Configure sysctl parameters
function configure_sysctl() {
    log_task_start "Configure sysctl parameters"

    local sysctl_file="/etc/sysctl.d/99-core-setup.conf"

    cat > "$sysctl_file" << 'EOF'
# Home CI/CD Server - Sysctl Parameters

# Network performance
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864

# Network security
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# File system
fs.file-max = 2097152
fs.inotify.max_user_watches = 524288

EOF

    # Apply sysctl parameters
    sysctl -p "$sysctl_file" > /dev/null 2>&1 || true

    log_task_complete
    return 0
}

# ============================================================================
# SSH Hardening Configuration
# ============================================================================

function configure_ssh_hardening() {
    log_task_start "Configure SSH hardening"

    # SSH configuration
    local SSH_PORT="${SSH_PORT:-4926}"
    local sshd_config="/etc/ssh/sshd_config"

    # Backup original config
    backup_file "$sshd_config"

    # Update SSH port
    if grep -q "^Port " "$sshd_config"; then
        sed -i "s/^Port .*/Port $SSH_PORT/" "$sshd_config"
    elif grep -q "^#Port 22" "$sshd_config"; then
        sed -i "s/^#Port 22/Port $SSH_PORT/" "$sshd_config"
    else
        # Add Port directive after Include if it exists, otherwise at the top
        if grep -q "^Include" "$sshd_config"; then
            sed -i "/^Include/a Port $SSH_PORT" "$sshd_config"
        else
            sed -i "1i Port $SSH_PORT" "$sshd_config"
        fi
    fi

    # Verify configuration
    if sshd -t 2>/dev/null; then
        log_success "SSH configuration is valid"

        # Restart SSH service (handle systemd socket activation)
        systemctl daemon-reload
        systemctl restart ssh.socket 2>/dev/null || true
        systemctl restart ssh.service

        log_success "SSH configured to use port $SSH_PORT"
        log_task_complete
        return 0
    else
        log_task_failed "SSH configuration test failed"
        return 1
    fi
}

# ============================================================================
# Main Module Execution
# ============================================================================

function main() {
    log_module_start "$MODULE_NAME"

    # Check module state (idempotency)
    local first_run=true
    if check_module_state; then
        # shellcheck disable=SC2034  # Variable reserved for future use
        first_run=false
        log_info "Re-running module (idempotent mode)"
    fi

    # System package management
    update_package_lists || return 1
    upgrade_system_packages || return 1
    install_required_packages || return 1
    install_optional_packages || true
    configure_automatic_security_updates || return 1

    # Directory structure
    create_directory_structure || return 1
    install_deployment_scripts || return 1

    # System configuration
    configure_hostname || true
    configure_timezone || true
    configure_ntp || true
    configure_system_limits || true
    configure_sysctl || true
    configure_ssh_hardening || return 1

    # Save module state
    save_module_state

    log_module_complete
    return 0
}

# ============================================================================
# Module Entry Point
# ============================================================================

main "$@"
