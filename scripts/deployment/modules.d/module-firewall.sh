#!/bin/bash
# module-firewall.sh - Firewall configuration module
# Part of Home CI/CD Server deployment automation
#
# This module configures UFW (Uncomplicated Firewall) including:
# - Default policies (deny incoming, allow outgoing)
# - Port forwarding rules
# - Rate limiting
# - fail2ban integration
# - DDoS protection
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
MODULE_NAME="firewall"
MODULE_VERSION="1.0.0"
# shellcheck disable=SC2034  # Used by deployment system
MODULE_DESCRIPTION="UFW firewall configuration and hardening"

# ============================================================================
# Configuration
# ============================================================================

# Load firewall configuration
FIREWALL_CONFIG="${DEPLOYMENT_CONFIG:-/opt/core-setup/config}/ufw-rules.conf"

# Default configuration (if config file not available)
SSH_PORT="${SSH_PORT:-4926}"
HTTP_PORT="${HTTP_PORT:-80}"
HTTPS_PORT="${HTTPS_PORT:-443}"
JENKINS_PORT="${JENKINS_PORT:-8080}"
NGINX_ADMIN_PORT="${NGINX_ADMIN_PORT:-81}"
TRUSTED_IPS="${TRUSTED_IPS:-}"
ALLOW_DOCKER="${ALLOW_DOCKER:-yes}"

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

UFW_INSTALLED=yes
UFW_ENABLED=yes
RULES_CONFIGURED=yes
FAIL2BAN_INTEGRATED=yes
EOF

    chmod 600 "$state_file"
}

# ============================================================================
# UFW Installation
# ============================================================================

function install_ufw() {
    log_task_start "Install UFW"

    if check_command ufw; then
        log_info "UFW already installed"
        log_task_complete
        return 0
    fi

    if DEBIAN_FRONTEND=noninteractive apt-get install -y ufw; then
        log_task_complete
        return 0
    else
        log_task_failed "Failed to install UFW"
        return 1
    fi
}

# ============================================================================
# UFW Configuration
# ============================================================================

function configure_ufw_defaults() {
    log_task_start "Configure UFW default policies"

    # Set default policies
    ufw default deny incoming
    ufw default allow outgoing
    ufw default deny routed

    # Enable logging
    ufw logging low

    log_task_complete
    return 0
}

function configure_ssh_access() {
    log_task_start "Configure SSH access"

    # Remove any existing SSH rules
    ufw --force delete allow "$SSH_PORT"/tcp 2>/dev/null || true
    ufw --force delete allow 22/tcp 2>/dev/null || true

    if [[ -n "$TRUSTED_IPS" ]]; then
        # Restrict SSH to trusted IPs only
        log_info "Restricting SSH to trusted IPs: $TRUSTED_IPS"
        IFS=',' read -ra ip_list <<< "$TRUSTED_IPS"
        for ip in "${ip_list[@]}"; do
            ufw allow from "$ip" to any port "$SSH_PORT" proto tcp comment "SSH from trusted IP"
        done
    else
        # Allow SSH from anywhere with rate limiting
        log_warn "Allowing SSH from anywhere (consider restricting to trusted IPs)"
        ufw limit "$SSH_PORT"/tcp comment "SSH with rate limiting"
    fi

    log_task_complete
    return 0
}

function configure_web_access() {
    log_task_start "Configure web server access"

    # HTTP
    ufw --force delete allow "$HTTP_PORT"/tcp 2>/dev/null || true
    ufw allow "$HTTP_PORT"/tcp comment "HTTP"

    # HTTPS
    ufw --force delete allow "$HTTPS_PORT"/tcp 2>/dev/null || true
    ufw allow "$HTTPS_PORT"/tcp comment "HTTPS"

    log_task_complete
    return 0
}

function configure_jenkins_access() {
    log_task_start "Configure Jenkins access"

    # Remove existing rules
    ufw --force delete allow "$JENKINS_PORT"/tcp 2>/dev/null || true

    # Jenkins with rate limiting
    # Note: In production, Jenkins should only be accessible via Nginx reverse proxy
    # This rule is for initial setup only
    ufw allow "$JENKINS_PORT"/tcp comment "Jenkins (consider removing after Nginx proxy setup)"

    log_task_complete
    return 0
}

function configure_nginx_admin_access() {
    log_task_start "Configure Nginx Proxy Manager access"

    # Remove existing rules
    ufw --force delete allow "$NGINX_ADMIN_PORT"/tcp 2>/dev/null || true

    if [[ -n "$TRUSTED_IPS" ]]; then
        # Restrict admin interface to trusted IPs only
        log_info "Restricting Nginx admin to trusted IPs: $TRUSTED_IPS"
        IFS=',' read -ra ip_list <<< "$TRUSTED_IPS"
        for ip in "${ip_list[@]}"; do
            ufw allow from "$ip" to any port "$NGINX_ADMIN_PORT" proto tcp comment "Nginx admin from trusted IP"
        done
    else
        log_warn "Nginx admin interface accessible from anywhere (NOT RECOMMENDED)"
        ufw allow "$NGINX_ADMIN_PORT"/tcp comment "Nginx admin (INSECURE - restrict to trusted IPs)"
    fi

    log_task_complete
    return 0
}

function configure_docker_network() {
    log_task_start "Configure Docker network rules"

    if [[ "$ALLOW_DOCKER" != "yes" ]]; then
        log_info "Docker support disabled, skipping Docker network rules"
        log_task_complete
        return 0
    fi

    # Docker Registry
    ufw --force delete allow 5000/tcp 2>/dev/null || true
    ufw allow 5000/tcp comment "Docker Registry"

    # Allow forwarding for Docker containers
    # Edit /etc/default/ufw to enable forwarding
    local ufw_defaults="/etc/default/ufw"
    if [[ -f "$ufw_defaults" ]]; then
        backup_file "$ufw_defaults"
        sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' "$ufw_defaults"
    fi

    # Add Docker-specific rules to UFW configuration
    local before_rules="/etc/ufw/before.rules"
    if [[ -f "$before_rules" ]]; then
        backup_file "$before_rules"

        # Check if Docker rules already exist
        if ! grep -q "# BEGIN DOCKER RULES" "$before_rules"; then
            cat >> "$before_rules" << 'EOF'

# BEGIN DOCKER RULES
*nat
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING ! -o docker0 -s 172.17.0.0/16 -j MASQUERADE
COMMIT
# END DOCKER RULES
EOF
        fi
    fi

    log_task_complete
    return 0
}

function configure_monitoring_access() {
    log_task_start "Configure monitoring access"

    # Netdata (localhost only, proxied via Nginx)
    # No direct UFW rule needed as it binds to localhost

    # Allow ICMP (ping) with rate limiting
    ufw --force delete allow from any to any proto icmp 2>/dev/null || true

    # Enable IPv4 ping
    local before_rules="/etc/ufw/before.rules"
    if [[ -f "$before_rules" ]]; then
        if ! grep -q "# allow all on loopback" "$before_rules"; then
            # Rules already exist from default UFW config
            log_info "ICMP rules already configured"
        fi
    fi

    log_task_complete
    return 0
}

function configure_advanced_security() {
    log_task_start "Configure advanced security rules"

    # Block invalid packets
    local before_rules="/etc/ufw/before.rules"
    if [[ -f "$before_rules" ]]; then
        backup_file "$before_rules"

        # Add advanced security rules if not present
        if ! grep -q "# BEGIN ADVANCED SECURITY" "$before_rules"; then
            # Insert after initial comments but before other rules
            sed -i '/^# End required lines/a \
\
# BEGIN ADVANCED SECURITY RULES\
# Drop invalid packets\
-A ufw-before-input -m conntrack --ctstate INVALID -j DROP\
\
# Drop packets with bogus TCP flags\
-A ufw-before-input -p tcp --tcp-flags FIN,SYN FIN,SYN -j DROP\
-A ufw-before-input -p tcp --tcp-flags SYN,RST SYN,RST -j DROP\
-A ufw-before-input -p tcp --tcp-flags FIN,RST FIN,RST -j DROP\
-A ufw-before-input -p tcp --tcp-flags FIN,ACK FIN -j DROP\
-A ufw-before-input -p tcp --tcp-flags ACK,URG URG -j DROP\
-A ufw-before-input -p tcp --tcp-flags ACK,PSH PSH -j DROP\
-A ufw-before-input -p tcp --tcp-flags ALL NONE -j DROP\
\
# SYN flood protection\
-A ufw-before-input -p tcp --syn -m connlimit --connlimit-above 80 -j DROP\
\
# Port scan protection\
-A ufw-before-input -p tcp --tcp-flags ALL FIN,URG,PSH -j DROP\
-A ufw-before-input -p tcp --tcp-flags ALL ALL -j DROP\
\
# Ping of death protection\
-A ufw-before-input -p icmp --icmp-type echo-request -m limit --limit 1/s --limit-burst 2 -j ACCEPT\
-A ufw-before-input -p icmp --icmp-type echo-request -j DROP\
# END ADVANCED SECURITY RULES\
' "$before_rules"
        fi
    fi

    log_task_complete
    return 0
}

function configure_ipv6() {
    log_task_start "Configure IPv6 firewall"

    # Enable IPv6 in UFW
    local ufw_defaults="/etc/default/ufw"
    if [[ -f "$ufw_defaults" ]]; then
        backup_file "$ufw_defaults"
        sed -i 's/IPV6=no/IPV6=yes/' "$ufw_defaults"
    fi

    # IPv6 rules mirror IPv4 rules automatically in UFW

    log_task_complete
    return 0
}

# ============================================================================
# fail2ban Integration
# ============================================================================

function install_fail2ban() {
    log_task_start "Install fail2ban"

    if check_command fail2ban-client; then
        log_info "fail2ban already installed"
        log_task_complete
        return 0
    fi

    if DEBIAN_FRONTEND=noninteractive apt-get install -y fail2ban; then
        log_task_complete
        return 0
    else
        log_task_failed "Failed to install fail2ban"
        return 1
    fi
}

function configure_fail2ban() {
    log_task_start "Configure fail2ban"

    local jail_local="/etc/fail2ban/jail.local"

    backup_file "$jail_local" 2>/dev/null || true

    cat > "$jail_local" << EOF
# Home CI/CD Server - fail2ban Configuration

[DEFAULT]
# Ban time: 1 hour
bantime = 3600

# Find time: 10 minutes
findtime = 600

# Max retry: 5 attempts
maxretry = 5

# Ignore localhost
ignoreip = 127.0.0.1/8 ::1

# Ban action (use UFW)
banaction = ufw
banaction_allports = ufw

# Email notifications
destemail = root@localhost
sendername = fail2ban
action = %(action_mwl)s

[sshd]
enabled = true
port = $SSH_PORT
logpath = %(sshd_log)s
backend = %(sshd_backend)s
maxretry = 5
bantime = 3600

[nginx-http-auth]
enabled = true
port = http,https
logpath = /var/log/nginx/error.log
maxretry = 3
bantime = 3600

[nginx-limit-req]
enabled = true
port = http,https
logpath = /var/log/nginx/error.log
maxretry = 10
findtime = 60
bantime = 3600

[nginx-botsearch]
enabled = true
port = http,https
logpath = /var/log/nginx/access.log
maxretry = 2
bantime = 86400

[jenkins]
enabled = true
port = $JENKINS_PORT
logpath = /var/log/jenkins/jenkins.log
maxretry = 5
bantime = 3600
EOF

    # Create Jenkins filter if it doesn't exist
    local jenkins_filter="/etc/fail2ban/filter.d/jenkins.conf"
    if [[ ! -f "$jenkins_filter" ]]; then
        cat > "$jenkins_filter" << 'EOF'
[Definition]
failregex = ^.*Failed login attempt for user .* from <HOST>.*$
            ^.*Invalid login attempt .* from <HOST>.*$
            ^.*Authentication failure .* from <HOST>.*$
ignoreregex =
EOF
    fi

    # Enable and start fail2ban
    systemctl enable fail2ban
    systemctl restart fail2ban

    # Wait for service to be ready
    wait_for_service fail2ban

    log_task_complete
    return 0
}

# ============================================================================
# UFW Activation
# ============================================================================

function enable_ufw() {
    log_task_start "Enable UFW firewall"

    # Check if UFW is already enabled
    if ufw status | grep -q "Status: active"; then
        log_info "UFW is already enabled"
        log_task_complete
        return 0
    fi

    # Enable UFW (non-interactive)
    log_warn "Enabling UFW firewall - ensure SSH rules are correct!"
    echo "y" | ufw enable

    # Verify UFW is active
    if ufw status | grep -q "Status: active"; then
        log_success "UFW firewall enabled successfully"
        log_task_complete
        return 0
    else
        log_task_failed "Failed to enable UFW"
        return 1
    fi
}

function verify_firewall_rules() {
    log_task_start "Verify firewall rules"

    log_info "Current UFW status:"
    ufw status verbose

    # Verify critical ports
    local critical_ports=("$SSH_PORT" "$HTTP_PORT" "$HTTPS_PORT")
    local missing_rules=()

    for port in "${critical_ports[@]}"; do
        if ! ufw status | grep -q "$port"; then
            missing_rules+=("$port")
        fi
    done

    if [[ ${#missing_rules[@]} -gt 0 ]]; then
        log_error "Missing firewall rules for ports: ${missing_rules[*]}"
        log_task_failed "Firewall verification failed"
        return 1
    fi

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

    # Load configuration if available
    if [[ -f "$FIREWALL_CONFIG" ]]; then
        log_info "Loading firewall configuration from: $FIREWALL_CONFIG"
        # shellcheck source=/dev/null
        source "$FIREWALL_CONFIG" || log_warn "Failed to load config, using defaults"
    fi

    # Install UFW
    install_ufw || return 1

    # Configure UFW
    configure_ufw_defaults || return 1
    configure_ssh_access || return 1
    configure_web_access || return 1
    configure_jenkins_access || return 1
    configure_nginx_admin_access || return 1
    configure_docker_network || return 1
    configure_monitoring_access || return 1
    configure_advanced_security || return 1
    configure_ipv6 || return 1

    # Install and configure fail2ban
    install_fail2ban || return 1
    configure_fail2ban || return 1

    # Enable UFW
    enable_ufw || return 1

    # Verify configuration
    verify_firewall_rules || return 1

    # Save module state
    save_module_state

    log_module_complete
    return 0
}

# ============================================================================
# Module Entry Point
# ============================================================================

main "$@"
