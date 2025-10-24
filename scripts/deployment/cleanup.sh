#!/usr/bin/env bash
#
# Cleanup Script for Home CI/CD Server
# This script removes all components installed by the deployment system
# and restores the machine to its previous state
#
# Usage: sudo ./cleanup.sh [--dry-run] [--keep-packages]
#

set -euo pipefail

# ============================================================================
# Script Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

# Source libraries
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/logging.sh
source "${SCRIPT_DIR}/lib/logging.sh"

# ============================================================================
# Configuration Variables
# ============================================================================

DEPLOYMENT_ROOT="/opt/core-setup"
DATA_ROOT="/srv/data"
BACKUP_ROOT="/srv/backups"
NGINX_CONF_DIR="/etc/nginx"
LOG_DIR="/var/log/central"

# Dry run mode
DRY_RUN=false
KEEP_PACKAGES=false

# Backup directory for configs before deletion
CLEANUP_BACKUP_DIR="/tmp/core-cleanup-backup-$(date +%Y%m%d-%H%M%S)"

# ============================================================================
# Parse Arguments
# ============================================================================

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                log_info "Running in DRY RUN mode - no changes will be made"
                shift
                ;;
            --keep-packages)
                KEEP_PACKAGES=true
                log_info "Will keep installed packages"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

show_help() {
    cat << EOF
Usage: sudo $SCRIPT_NAME [OPTIONS]

Cleanup script to remove all Home CI/CD Server components and restore
the machine to its previous state.

OPTIONS:
    --dry-run         Show what would be done without making changes
    --keep-packages   Keep installed packages (only remove configs/data)
    -h, --help        Show this help message

WHAT THIS SCRIPT DOES:
    1. Stops all services (Jenkins, Nginx, Netdata, Auth Service, Artifact Upload, Fail2ban)
    2. Removes service configurations
    3. Uninstalls packages (unless --keep-packages is used)
    4. Removes all data directories (including matrix landing page)
    5. Resets firewall rules (SSH access is preserved)
    6. Removes cron jobs
    7. Creates backup of configs before deletion

WHAT IS PRESERVED:
    • SSH access (port 4926/tcp firewall rule)
    • OpenSSH server (not uninstalled)
    • System packages (unless explicitly part of deployment)

BACKUP LOCATION:
    Configs will be backed up to: $CLEANUP_BACKUP_DIR

WARNING: This operation is destructive and cannot be easily undone!

EOF
}

# ============================================================================
# Backup Functions
# ============================================================================

create_backup() {
    log_info "Creating backup of configurations before cleanup"

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would create backup at: $CLEANUP_BACKUP_DIR"
        return 0
    fi

    mkdir -p "$CLEANUP_BACKUP_DIR"

    # Backup deployment configs if they exist
    if [[ -d "$DEPLOYMENT_ROOT" ]]; then
        cp -r "$DEPLOYMENT_ROOT" "$CLEANUP_BACKUP_DIR/" 2>/dev/null || true
    fi

    # Backup nginx configs
    if [[ -d "$NGINX_CONF_DIR" ]]; then
        mkdir -p "$CLEANUP_BACKUP_DIR/nginx"
        cp -r "$NGINX_CONF_DIR/sites-available" "$CLEANUP_BACKUP_DIR/nginx/" 2>/dev/null || true
        cp -r "$NGINX_CONF_DIR/sites-enabled" "$CLEANUP_BACKUP_DIR/nginx/" 2>/dev/null || true
        cp -r "$NGINX_CONF_DIR/conf.d" "$CLEANUP_BACKUP_DIR/nginx/" 2>/dev/null || true
        cp "$NGINX_CONF_DIR/nginx.conf" "$CLEANUP_BACKUP_DIR/nginx/" 2>/dev/null || true
    fi

    log_success "Backup created at: $CLEANUP_BACKUP_DIR"
}

# ============================================================================
# Service Cleanup Functions
# ============================================================================

stop_and_disable_service() {
    local service_name=$1

    log_info "Stopping and disabling service: $service_name"

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would stop and disable: $service_name"
        return 0
    fi

    if systemctl is-active --quiet "$service_name" 2>/dev/null; then
        systemctl stop "$service_name" || log_warn "Failed to stop $service_name"
    fi

    if systemctl is-enabled --quiet "$service_name" 2>/dev/null; then
        systemctl disable "$service_name" || log_warn "Failed to disable $service_name"
    fi

    log_success "Service stopped: $service_name"
}

remove_systemd_service() {
    local service_name=$1
    local service_file="/etc/systemd/system/${service_name}.service"

    if [[ -f "$service_file" ]]; then
        log_info "Removing systemd service file: $service_file"

        if [[ "$DRY_RUN" == true ]]; then
            log_info "[DRY RUN] Would remove: $service_file"
        else
            rm -f "$service_file"
            systemctl daemon-reload
            log_success "Removed: $service_file"
        fi
    fi
}

cleanup_services() {
    echo ""; echo "=== Cleaning up services ==="; echo ""

    local services=(
        "artifact-upload"
        "auth-service"
        "netdata"
        "jenkins"
        "nginx"
        "fail2ban"
    )

    for service in "${services[@]}"; do
        stop_and_disable_service "$service"
    done

    # Remove custom systemd services
    remove_systemd_service "artifact-upload"
    remove_systemd_service "auth-service"
}

# ============================================================================
# Package Cleanup Functions
# ============================================================================

uninstall_packages() {
    if [[ "$KEEP_PACKAGES" == true ]]; then
        log_info "Skipping package removal (--keep-packages flag set)"
        return 0
    fi

    echo ""; echo "=== Uninstalling packages ==="; echo ""

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would uninstall Jenkins, Nginx, Netdata, Fail2ban and related packages"
        return 0
    fi

    # Remove Jenkins
    if dpkg -l | grep -q "^ii.*jenkins"; then
        log_info "Uninstalling Jenkins"
        # Stop service first
        systemctl stop jenkins 2>/dev/null || true
        systemctl disable jenkins 2>/dev/null || true
        # Remove package
        DEBIAN_FRONTEND=noninteractive apt-get remove --purge -y jenkins || {
            log_warn "Failed to remove jenkins with apt, trying dpkg"
            dpkg --purge jenkins 2>/dev/null || log_error "Failed to remove jenkins"
        }
        # Remove directories
        rm -rf /var/lib/jenkins /var/cache/jenkins /var/log/jenkins 2>/dev/null || true
    fi

    # Remove Fail2ban
    if dpkg -l | grep -q "^ii.*fail2ban"; then
        log_info "Uninstalling Fail2ban"
        systemctl stop fail2ban 2>/dev/null || true
        systemctl disable fail2ban 2>/dev/null || true
        DEBIAN_FRONTEND=noninteractive apt-get remove --purge -y fail2ban || {
            log_warn "Failed to remove fail2ban with apt, trying dpkg"
            dpkg --purge fail2ban 2>/dev/null || log_error "Failed to remove fail2ban"
        }
        rm -rf /etc/fail2ban 2>/dev/null || true
    fi

    # Remove Nginx and related packages
    if dpkg -l | grep -q "^ii.*nginx"; then
        log_info "Uninstalling Nginx"
        systemctl stop nginx 2>/dev/null || true
        systemctl disable nginx 2>/dev/null || true
        DEBIAN_FRONTEND=noninteractive apt-get remove --purge -y nginx nginx-common nginx-core nginx-full python3-certbot-nginx || {
            log_warn "Failed to remove nginx with apt, trying dpkg"
            dpkg --purge nginx nginx-common nginx-core nginx-full 2>/dev/null || log_error "Failed to remove nginx"
        }
        rm -rf /etc/nginx /var/www/matrix-landing /var/www/html 2>/dev/null || true
    fi

    # Remove auth service script
    if [[ -f "/opt/core-setup/scripts/auth-service.js" ]]; then
        log_info "Removing auth-service.js"
        rm -f /opt/core-setup/scripts/auth-service.js 2>/dev/null || true
    fi

    # Remove all Netdata packages (including plugins)
    if dpkg -l | grep -q "^ii.*netdata"; then
        log_info "Uninstalling Netdata and all plugins"
        # Stop service first
        systemctl stop netdata 2>/dev/null || true
        systemctl disable netdata 2>/dev/null || true
        # First, try to use the netdata uninstaller if it exists
        if [ -x /usr/libexec/netdata/netdata-uninstaller.sh ]; then
            log_info "Using Netdata uninstaller"
            /usr/libexec/netdata/netdata-uninstaller.sh --yes --force 2>/dev/null || log_warn "Netdata uninstaller failed"
        fi
        # Then remove any remaining packages
        DEBIAN_FRONTEND=noninteractive apt-get remove --purge -y netdata netdata-core netdata-plugins-bash netdata-plugins-python netdata-web || {
            log_warn "Failed to remove netdata with apt, trying dpkg"
            dpkg --purge netdata netdata-core netdata-plugins-bash netdata-plugins-python netdata-web 2>/dev/null || log_error "Failed to remove netdata"
        }
        rm -rf /etc/netdata /opt/netdata /var/lib/netdata /var/cache/netdata /var/log/netdata 2>/dev/null || true
    fi

    log_info "Running apt autoremove"
    DEBIAN_FRONTEND=noninteractive apt-get autoremove -y || true

    log_info "Running apt clean"
    apt-get clean || true
}

# ============================================================================
# Directory Cleanup Functions
# ============================================================================

remove_directory() {
    local dir=$1
    local description=${2:-"directory"}

    if [[ -d "$dir" ]]; then
        log_info "Removing $description: $dir"

        if [[ "$DRY_RUN" == true ]]; then
            log_info "[DRY RUN] Would remove: $dir"
        else
            rm -rf "$dir"
            log_success "Removed: $dir"
        fi
    fi
}

cleanup_directories() {
    echo ""; echo "=== Cleaning up directories ==="; echo ""

    # Deployment directories
    remove_directory "$DEPLOYMENT_ROOT" "deployment root"

    # Data directories
    remove_directory "$DATA_ROOT" "data root"
    remove_directory "$BACKUP_ROOT" "backup root"

    # Log directories
    remove_directory "$LOG_DIR" "central logs"

    # Service-specific directories
    remove_directory "/var/lib/jenkins" "Jenkins data"
    remove_directory "/var/cache/jenkins" "Jenkins cache"
    remove_directory "/var/log/jenkins" "Jenkins logs"

    remove_directory "/var/lib/netdata" "Netdata data"
    remove_directory "/var/cache/netdata" "Netdata cache"
    remove_directory "/var/log/netdata" "Netdata logs"
    remove_directory "/opt/netdata" "Netdata installation"

    remove_directory "/var/lib/fail2ban" "Fail2ban data"
    remove_directory "/var/log/fail2ban" "Fail2ban logs"

    # Nginx directories (selective)
    remove_directory "/var/www/certbot" "Certbot webroot"
}

# ============================================================================
# Configuration Cleanup Functions
# ============================================================================

cleanup_nginx_configs() {
    echo ""; echo "=== Cleaning up Nginx configurations ==="; echo ""

    local nginx_sites=(
        "core.mohjave.com"
        "jenkins.core.mohjave.com"
        "artifacts.core.mohjave.com"
        "monitoring.core.mohjave.com"
    )

    for site in "${nginx_sites[@]}"; do
        if [[ -f "${NGINX_CONF_DIR}/sites-available/${site}" ]]; then
            log_info "Removing Nginx site: $site"

            if [[ "$DRY_RUN" == true ]]; then
                log_info "[DRY RUN] Would remove: ${NGINX_CONF_DIR}/sites-available/${site}"
            else
                rm -f "${NGINX_CONF_DIR}/sites-available/${site}"
                rm -f "${NGINX_CONF_DIR}/sites-enabled/${site}"
            fi
        fi
    done

    # Remove custom conf.d files
    local conf_files=(
        "jenkins.conf"
        "artifacts.conf"
        "monitoring.conf"
        "rate-limits.conf"
    )

    for conf in "${conf_files[@]}"; do
        if [[ -f "${NGINX_CONF_DIR}/conf.d/${conf}" ]]; then
            log_info "Removing Nginx config: $conf"

            if [[ "$DRY_RUN" == true ]]; then
                log_info "[DRY RUN] Would remove: ${NGINX_CONF_DIR}/conf.d/${conf}"
            else
                rm -f "${NGINX_CONF_DIR}/conf.d/${conf}"
            fi
        fi
    done
}

cleanup_cron_jobs() {
    echo ""; echo "=== Cleaning up cron jobs ==="; echo ""

    local cron_files=(
        "/etc/cron.d/artifact-cleanup"
        "/etc/cron.d/core-monitoring"
    )

    for cron_file in "${cron_files[@]}"; do
        if [[ -f "$cron_file" ]]; then
            log_info "Removing cron job: $cron_file"

            if [[ "$DRY_RUN" == true ]]; then
                log_info "[DRY RUN] Would remove: $cron_file"
            else
                rm -f "$cron_file"
            fi
        fi
    done

    # Remove DNS update cron job from root's crontab
    if crontab -l 2>/dev/null | grep -q "update-dynu-dns.sh"; then
        log_info "Removing DNS update cron job from root crontab"

        if [[ "$DRY_RUN" == true ]]; then
            log_info "[DRY RUN] Would remove DNS update cron job"
        else
            (crontab -l 2>/dev/null | grep -v "update-dynu-dns.sh") | crontab -
            log_success "DNS update cron job removed"
        fi
    fi
}

cleanup_dns() {
    echo ""; echo "=== Cleaning up DNS configuration ==="; echo ""

    local dns_files=(
        "${DEPLOYMENT_ROOT}/scripts/update-dynu-dns.sh"
        "${DEPLOYMENT_ROOT}/config/.dynu-api-key"
        "${DEPLOYMENT_ROOT}/config/.dns.state"
        "/var/log/dynu-dns-update.log"
    )

    for dns_file in "${dns_files[@]}"; do
        if [[ -f "$dns_file" ]]; then
            log_info "Removing DNS file: $dns_file"

            if [[ "$DRY_RUN" == true ]]; then
                log_info "[DRY RUN] Would remove: $dns_file"
            else
                rm -f "$dns_file"
            fi
        fi
    done
}

# ============================================================================
# Firewall Cleanup Functions
# ============================================================================

cleanup_firewall() {
    echo ""; echo "=== Resetting firewall rules ==="; echo ""

    if ! command -v ufw &> /dev/null; then
        log_info "UFW not installed, skipping firewall cleanup"
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would reset UFW rules"
        return 0
    fi

    log_warn "Removing deployment-specific firewall rules"
    log_warn "Note: SSH rules will be preserved to maintain access"

    # Remove specific rules added by deployment (but keep SSH!)
    ufw delete allow 'Nginx Full' 2>/dev/null || true
    ufw delete allow 80/tcp 2>/dev/null || true
    ufw delete allow 443/tcp 2>/dev/null || true
    ufw delete allow 8080/tcp 2>/dev/null || true
    ufw delete allow 81/tcp 2>/dev/null || true
    ufw delete allow 5000/tcp 2>/dev/null || true

    # Note: NOT removing SSH rule (4926/tcp) to maintain remote access
    # If you need to remove SSH rule manually, run:
    #   sudo ufw delete limit 4926/tcp

    log_success "Firewall rules cleaned up (SSH access preserved)"
}

# ============================================================================
# User Cleanup Functions
# ============================================================================

cleanup_users() {
    echo ""; echo "=== Cleaning up users and groups ==="; echo ""

    local users=(
        "jenkins"
    )

    for user in "${users[@]}"; do
        if id "$user" &>/dev/null; then
            log_info "Removing user: $user"

            if [[ "$DRY_RUN" == true ]]; then
                log_info "[DRY RUN] Would remove user: $user"
            else
                userdel -r "$user" 2>/dev/null || log_warn "Failed to remove user: $user"
            fi
        fi
    done
}

# ============================================================================
# Repository Cleanup Functions
# ============================================================================

cleanup_repositories() {
    if [[ "$KEEP_PACKAGES" == true ]]; then
        log_info "Skipping repository cleanup (--keep-packages flag set)"
        return 0
    fi

    echo ""; echo "=== Cleaning up APT repositories ==="; echo ""

    local repo_files=(
        "/etc/apt/sources.list.d/jenkins.list"
        "/etc/apt/keyrings/jenkins-keyring.asc"
    )

    for repo_file in "${repo_files[@]}"; do
        if [[ -f "$repo_file" ]]; then
            log_info "Removing repository file: $repo_file"

            if [[ "$DRY_RUN" == true ]]; then
                log_info "[DRY RUN] Would remove: $repo_file"
            else
                rm -f "$repo_file"
            fi
        fi
    done

    if [[ "$DRY_RUN" == false ]]; then
        apt-get update 2>/dev/null || true
    fi
}

# ============================================================================
# Verification Functions
# ============================================================================

verify_cleanup() {
    echo ""; echo "=== Verifying cleanup ==="; echo ""

    local all_clean=true

    # Check services
    local services=("artifact-upload" "auth-service" "netdata" "jenkins" "nginx" "fail2ban")
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            log_warn "Service still running: $service"
            all_clean=false
        fi
    done

    # Check directories
    local dirs=("$DEPLOYMENT_ROOT" "$DATA_ROOT" "/var/lib/jenkins")
    for dir in "${dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            log_warn "Directory still exists: $dir"
            all_clean=false
        fi
    done

    if [[ "$all_clean" == true ]]; then
        log_success "Cleanup completed successfully!"
    else
        log_warn "Some components may still exist. Check warnings above."
    fi
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    parse_arguments "$@"

    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi

    echo "════════════════════════════════════════════════════════"
    echo "  Home CI/CD Server - Cleanup Script"
    echo "════════════════════════════════════════════════════════"
    echo ""

    if [[ "$DRY_RUN" == false ]]; then
        log_warn "═══════════════════════════════════════════════════════════"
        log_warn "WARNING: This will remove all Home CI/CD Server components!"
        log_warn "═══════════════════════════════════════════════════════════"
        log_warn ""
        log_warn "This operation will:"
        log_warn "  • Stop all services (Jenkins, Nginx, Netdata, Auth Service, etc.)"
        log_warn "  • Remove all configurations (including matrix landing page)"
        log_warn "  • Remove DNS update cron jobs and credentials"
        log_warn "  • Delete all data in $DEPLOYMENT_ROOT"
        log_warn "  • Delete all data in $DATA_ROOT"
        log_warn "  • Reset firewall rules"
        log_warn "  • Uninstall packages (unless --keep-packages is used)"
        log_warn ""
        log_warn "A backup will be created at: $CLEANUP_BACKUP_DIR"
        log_warn ""

        read -r -p "Are you sure you want to continue? [yes/NO]: " confirm
        if [[ "$confirm" != "yes" ]]; then
            log_info "Cleanup cancelled by user"
            exit 0
        fi
    fi

    # Execute cleanup steps
    create_backup
    cleanup_services
    cleanup_nginx_configs
    cleanup_cron_jobs
    cleanup_dns
    cleanup_firewall
    cleanup_directories
    uninstall_packages
    cleanup_directories  # Run again to remove any dirs recreated by package removal
    cleanup_users
    cleanup_repositories

    if [[ "$DRY_RUN" == false ]]; then
        verify_cleanup
    fi

    echo ""
    echo "════════════════════════════════════════════════════════"
    echo "  Cleanup Complete"
    echo "════════════════════════════════════════════════════════"
    log_success "Backup saved to: $CLEANUP_BACKUP_DIR"

    if [[ "$DRY_RUN" == true ]]; then
        log_info "This was a DRY RUN - no changes were made"
        log_info "Run without --dry-run to perform actual cleanup"
    fi
}

# Run main function
main "$@"
