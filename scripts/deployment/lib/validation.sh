#!/bin/bash
# validation.sh - System validation and health check functions
# Part of Home CI/CD Server deployment automation

set -euo pipefail

# Source common functions if not already loaded
if [[ -z "${COLOR_GREEN:-}" ]]; then
    SCRIPT_DIR_VAL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck source=./common.sh
    source "$SCRIPT_DIR_VAL/common.sh"
fi

# Source logging functions if not already loaded
if ! declare -f log_info &>/dev/null; then
    SCRIPT_DIR_VAL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck source=./logging.sh
    source "$SCRIPT_DIR_VAL/logging.sh"
fi

# ============================================================================
# Prerequisites Validation
# ============================================================================

# Check if running on supported OS
function validate_os() {
    log_info "Validating operating system..."

    if [[ ! -f /etc/os-release ]]; then
        log_error "Cannot determine OS (no /etc/os-release file)"
        return 1
    fi

    # shellcheck source=/dev/null
    source /etc/os-release

    case "$ID" in
        ubuntu)
            if [[ "${VERSION_ID%%.*}" -lt 20 ]]; then
                log_warn "Ubuntu version $VERSION_ID detected, recommended 20.04+"
            else
                log_success "Ubuntu $VERSION_ID (supported)"
            fi
            ;;
        debian)
            if [[ "${VERSION_ID%%.*}" -lt 11 ]]; then
                log_warn "Debian version $VERSION_ID detected, recommended 11+"
            else
                log_success "Debian $VERSION_ID (supported)"
            fi
            ;;
        *)
            log_warn "Unsupported OS: $ID $VERSION_ID (tested on Ubuntu 20.04+, Debian 11+)"
            if ! ask_yes_no "Continue anyway?"; then
                return 1
            fi
            ;;
    esac

    return 0
}

# Check internet connectivity
function validate_internet() {
    log_info "Checking internet connectivity..."

    local test_hosts=("8.8.8.8" "1.1.1.1" "208.67.222.222")
    local success=0

    for host in "${test_hosts[@]}"; do
        if ping -c 1 -W 2 "$host" &> /dev/null; then
            ((success++))
            break
        fi
    done

    if [[ $success -eq 0 ]]; then
        log_error "No internet connectivity detected"
        return 1
    fi

    log_success "Internet connectivity OK"
    return 0
}

# Check DNS resolution
# shellcheck disable=SC2120  # Optional parameter with default value
function validate_dns() {
    local domain="${1:-google.com}"

    log_info "Checking DNS resolution..."

    if ! host "$domain" &> /dev/null; then
        log_error "DNS resolution failed for $domain"
        return 1
    fi

    log_success "DNS resolution OK"
    return 0
}

# Check package repositories
function validate_repositories() {
    log_info "Checking package repositories..."

    if ! apt-get update &> /dev/null; then
        log_error "Failed to update package lists"
        return 1
    fi

    log_success "Package repositories OK"
    return 0
}

# Check required commands
function validate_required_commands() {
    log_info "Checking required commands..."

    local required_commands=(
        "curl"
        "wget"
        "git"
        "systemctl"
        "openssl"
        "apt-get"
    )

    local missing_commands=()

    for cmd in "${required_commands[@]}"; do
        if ! check_command "$cmd"; then
            missing_commands+=("$cmd")
        fi
    done

    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        log_error "Missing required commands: ${missing_commands[*]}"
        log_info "Install with: apt-get install -y ${missing_commands[*]}"
        return 1
    fi

    log_success "All required commands present"
    return 0
}

# ============================================================================
# Service Validation
# ============================================================================

# Check if service is installed
function validate_service_installed() {
    local service_name="$1"

    if systemctl list-unit-files | grep -q "^${service_name}.service"; then
        return 0
    else
        return 1
    fi
}

# Check if service is running
function validate_service_running() {
    local service_name="$1"

    if systemctl is-active --quiet "$service_name"; then
        log_success "Service $service_name is running"
        return 0
    else
        log_error "Service $service_name is not running"
        return 1
    fi
}

# Check if service is enabled
function validate_service_enabled() {
    local service_name="$1"

    if systemctl is-enabled --quiet "$service_name"; then
        log_success "Service $service_name is enabled"
        return 0
    else
        log_warn "Service $service_name is not enabled"
        return 1
    fi
}

# Comprehensive service check
function validate_service() {
    local service_name="$1"

    log_info "Validating service: $service_name"

    if ! validate_service_installed "$service_name"; then
        log_error "Service $service_name is not installed"
        return 1
    fi

    validate_service_running "$service_name" || return 1
    validate_service_enabled "$service_name" || log_warn "Service not enabled (will not start on boot)"

    return 0
}

# ============================================================================
# Network Validation
# ============================================================================

# Check if port is listening
function validate_port_listening() {
    local port="$1"
    local protocol="${2:-tcp}"

    log_info "Checking if port $port ($protocol) is listening..."

    if ss -tuln | grep -q ":${port} "; then
        log_success "Port $port is listening"
        return 0
    else
        log_error "Port $port is not listening"
        return 1
    fi
}

# Check if firewall allows port
function validate_firewall_port() {
    local port="$1"
    local protocol="${2:-tcp}"

    log_info "Checking firewall rules for port $port..."

    if command -v ufw &> /dev/null; then
        if ufw status | grep -q "${port}/${protocol}.*ALLOW"; then
            log_success "Firewall allows port $port/$protocol"
            return 0
        else
            log_error "Firewall blocks port $port/$protocol"
            return 1
        fi
    else
        log_warn "UFW not installed, cannot check firewall rules"
        return 0
    fi
}

# Test HTTP endpoint
function validate_http_endpoint() {
    local url="$1"
    local expected_code="${2:-200}"

    log_info "Testing HTTP endpoint: $url"

    local response_code
    response_code=$(curl -s -o /dev/null -w "%{http_code}" "$url" || echo "000")

    if [[ "$response_code" == "$expected_code" ]]; then
        log_success "HTTP endpoint returned $response_code"
        return 0
    else
        log_error "HTTP endpoint returned $response_code (expected $expected_code)"
        return 1
    fi
}

# ============================================================================
# SSL/TLS Validation
# ============================================================================

# Check SSL certificate validity
function validate_ssl_certificate() {
    local domain="$1"
    local cert_file="${2:-/etc/letsencrypt/live/${domain}/fullchain.pem}"

    log_info "Validating SSL certificate for $domain..."

    if [[ ! -f "$cert_file" ]]; then
        log_error "Certificate file not found: $cert_file"
        return 1
    fi

    # Check expiry date
    local expiry_date
    expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" | cut -d= -f2)
    local expiry_epoch
    expiry_epoch=$(date -d "$expiry_date" +%s)
    local now_epoch
    now_epoch=$(date +%s)
    local days_until_expiry=$(( (expiry_epoch - now_epoch) / 86400 ))

    if [[ $days_until_expiry -lt 0 ]]; then
        log_error "Certificate expired $((days_until_expiry * -1)) days ago"
        return 1
    elif [[ $days_until_expiry -lt 30 ]]; then
        log_warn "Certificate expires in $days_until_expiry days"
        return 0
    else
        log_success "Certificate valid for $days_until_expiry days"
        return 0
    fi
}

# Test HTTPS connectivity
function validate_https_endpoint() {
    local url="$1"

    log_info "Testing HTTPS endpoint: $url"

    if curl -sSL --max-time 10 "$url" > /dev/null 2>&1; then
        log_success "HTTPS endpoint accessible"
        return 0
    else
        log_error "HTTPS endpoint not accessible"
        return 1
    fi
}

# ============================================================================
# File and Directory Validation
# ============================================================================

# Check if directory exists and has correct permissions
function validate_directory() {
    local dir_path="$1"
    local expected_perms="${2:-755}"
    local expected_owner="${3:-root:root}"

    log_info "Validating directory: $dir_path"

    if [[ ! -d "$dir_path" ]]; then
        log_error "Directory does not exist: $dir_path"
        return 1
    fi

    local actual_perms
    actual_perms=$(stat -c "%a" "$dir_path")
    if [[ "$actual_perms" != "$expected_perms" ]]; then
        log_warn "Directory permissions are $actual_perms (expected $expected_perms)"
    fi

    local actual_owner
    actual_owner=$(stat -c "%U:%G" "$dir_path")
    if [[ "$actual_owner" != "$expected_owner" ]]; then
        log_warn "Directory owner is $actual_owner (expected $expected_owner)"
    fi

    log_success "Directory validated: $dir_path"
    return 0
}

# Check if file exists and is readable
function validate_file_exists() {
    local file_path="$1"

    if [[ -f "$file_path" && -r "$file_path" ]]; then
        log_success "File exists and is readable: $file_path"
        return 0
    else
        log_error "File does not exist or is not readable: $file_path"
        return 1
    fi
}

# ============================================================================
# Configuration Validation
# ============================================================================

# Validate Nginx configuration
function validate_nginx_config() {
    log_info "Validating Nginx configuration..."

    if ! command -v nginx &> /dev/null; then
        log_error "Nginx not installed"
        return 1
    fi

    if nginx -t &> /dev/null; then
        log_success "Nginx configuration is valid"
        return 0
    else
        log_error "Nginx configuration has errors"
        nginx -t
        return 1
    fi
}

# Validate Jenkins is accessible
# shellcheck disable=SC2120  # Optional parameter with default value
function validate_jenkins() {
    local jenkins_url="${1:-http://localhost:8080}"

    log_info "Validating Jenkins at $jenkins_url..."

    # Check if Jenkins is running
    if ! validate_service_running jenkins; then
        return 1
    fi

    # Check if port 8080 is listening
    if ! validate_port_listening 8080; then
        return 1
    fi

    # Test HTTP endpoint
    if validate_http_endpoint "$jenkins_url" "403"; then
        log_success "Jenkins is accessible (403 = login required, expected)"
        return 0
    fi

    return 0
}

# ============================================================================
# Complete System Validation
# ============================================================================

# Run all validation checks
function validate_all() {
    log_info "Running complete system validation..."

    local failures=0

    validate_os || ((failures++))
    validate_internet || ((failures++))
    # shellcheck disable=SC2119  # Function has optional parameter
    validate_dns || ((failures++))
    validate_required_commands || ((failures++))

    # Service validation (if installed)
    if validate_service_installed nginx; then
        validate_service nginx || ((failures++))
        validate_nginx_config || ((failures++))
    fi

    if validate_service_installed jenkins; then
        validate_service jenkins || ((failures++))
        # shellcheck disable=SC2119  # Function has optional parameter
        validate_jenkins || ((failures++))
    fi

    if validate_service_installed fail2ban; then
        validate_service fail2ban || ((failures++))
    fi

    # Port validation
    for port in 80 443 4926 8080; do
        if ss -tuln | grep -q ":${port} "; then
            validate_port_listening "$port" || ((failures++))
        fi
    done

    if [[ $failures -eq 0 ]]; then
        log_success "All validation checks passed!"
        return 0
    else
        log_error "$failures validation check(s) failed"
        return 1
    fi
}

# ============================================================================
# Export Functions
# ============================================================================

export -f validate_os
export -f validate_internet
export -f validate_dns
export -f validate_repositories
export -f validate_required_commands
export -f validate_service_installed
export -f validate_service_running
export -f validate_service_enabled
export -f validate_service
export -f validate_port_listening
export -f validate_firewall_port
export -f validate_http_endpoint
export -f validate_ssl_certificate
export -f validate_https_endpoint
export -f validate_directory
export -f validate_file_exists
export -f validate_nginx_config
export -f validate_jenkins
export -f validate_all
