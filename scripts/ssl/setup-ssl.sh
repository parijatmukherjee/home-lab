#!/bin/bash
# setup-ssl.sh - Let's Encrypt SSL Certificate Setup
# Part of Home CI/CD Server
#
# This script obtains free SSL certificates from Let's Encrypt using certbot
# and configures nginx to use HTTPS for all subdomains.
#
# Usage: sudo ./setup-ssl.sh [--email EMAIL] [--domains DOMAINS] [--staging]

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

# Default configuration
DOMAIN_NAME="${DOMAIN_NAME:-core.mohjave.com}"
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@${DOMAIN_NAME}}"

# All subdomains to get certificates for
SUBDOMAINS=(
    "${DOMAIN_NAME}"
    "jenkins.${DOMAIN_NAME}"
    "artifacts.${DOMAIN_NAME}"
    "monitoring.${DOMAIN_NAME}"
)

# Certbot options
CERTBOT_OPTIONS="--nginx --agree-tos --non-interactive --redirect"
STAGING_MODE=false

# Colors for output
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# ============================================================================
# Helper Functions
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

print_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$*${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

# ============================================================================
# Pre-flight Checks
# ============================================================================

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

check_nginx() {
    if ! systemctl is-active --quiet nginx; then
        log_error "Nginx is not running. Please deploy the system first with: make deploy"
        exit 1
    fi

    if ! nginx -t >/dev/null 2>&1; then
        log_error "Nginx configuration has errors. Please fix them first."
        nginx -t
        exit 1
    fi

    log_success "Nginx is running and configured correctly"
}

check_dns() {
    log_info "Checking DNS resolution for domains..."
    local failed=0

    for subdomain in "${SUBDOMAINS[@]}"; do
        log_info "Checking $subdomain..."
        if host "$subdomain" >/dev/null 2>&1; then
            local ip
            ip=$(host "$subdomain" | grep "has address" | head -1 | awk '{print $4}')
            log_success "$subdomain resolves to $ip"
        else
            log_error "$subdomain does not resolve to an IP address"
            failed=1
        fi
    done

    if [[ $failed -eq 1 ]]; then
        log_error "DNS resolution failed for one or more domains"
        log_warn "Please ensure all domains are pointing to this server's IP before proceeding"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

check_port_80() {
    log_info "Checking if port 80 is accessible..."

    if ! ss -tuln | grep -q ":80 "; then
        log_error "Port 80 is not listening"
        exit 1
    fi

    log_success "Port 80 is accessible"
}

# ============================================================================
# Certbot Installation
# ============================================================================

install_certbot() {
    if command -v certbot >/dev/null 2>&1; then
        log_success "Certbot is already installed ($(certbot --version))"
        return 0
    fi

    log_info "Installing certbot..."

    # Update package list
    apt-get update -qq

    # Install certbot and nginx plugin
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        certbot \
        python3-certbot-nginx

    if command -v certbot >/dev/null 2>&1; then
        log_success "Certbot installed successfully ($(certbot --version))"
    else
        log_error "Failed to install certbot"
        exit 1
    fi
}

# ============================================================================
# Certificate Obtainment
# ============================================================================

obtain_certificates() {
    print_header "Obtaining SSL Certificates"

    # Build domain list for certbot
    local domain_args=""
    for subdomain in "${SUBDOMAINS[@]}"; do
        domain_args="$domain_args -d $subdomain"
    done

    # Add staging flag if requested
    local staging_flag=""
    if [[ "$STAGING_MODE" == "true" ]]; then
        staging_flag="--staging"
        log_warn "Using Let's Encrypt STAGING environment (certificates will not be trusted)"
    fi

    log_info "Requesting certificates for: ${SUBDOMAINS[*]}"
    log_info "Email: $ADMIN_EMAIL"

    # Run certbot
    if certbot certonly \
        $CERTBOT_OPTIONS \
        $staging_flag \
        --email "$ADMIN_EMAIL" \
        $domain_args; then

        log_success "Certificates obtained successfully!"
        return 0
    else
        log_error "Failed to obtain certificates"
        log_warn "Common issues:"
        log_warn "  1. DNS records not pointing to this server"
        log_warn "  2. Port 80 not accessible from the internet"
        log_warn "  3. Firewall blocking HTTP traffic"
        log_warn "  4. Rate limit reached (try --staging for testing)"
        return 1
    fi
}

# ============================================================================
# Nginx HTTPS Configuration
# ============================================================================

configure_nginx_https() {
    print_header "Configuring Nginx for HTTPS"

    log_info "Nginx will be automatically configured by certbot's nginx plugin"
    log_info "The following changes will be made:"
    log_info "  • HTTP (port 80) will redirect to HTTPS (port 443)"
    log_info "  • SSL certificates will be configured for all domains"
    log_info "  • HSTS headers will be added for security"

    # Apply nginx configuration using certbot
    local domain_args=""
    for subdomain in "${SUBDOMAINS[@]}"; do
        domain_args="$domain_args -d $subdomain"
    done

    local staging_flag=""
    if [[ "$STAGING_MODE" == "true" ]]; then
        staging_flag="--staging"
    fi

    if certbot --nginx \
        $staging_flag \
        --email "$ADMIN_EMAIL" \
        --agree-tos \
        --non-interactive \
        --redirect \
        $domain_args; then

        log_success "Nginx configured for HTTPS"
    else
        log_error "Failed to configure nginx"
        return 1
    fi

    # Test nginx configuration
    if nginx -t; then
        log_success "Nginx configuration is valid"
        systemctl reload nginx
        log_success "Nginx reloaded"
    else
        log_error "Nginx configuration has errors"
        return 1
    fi
}

# ============================================================================
# Auto-renewal Setup
# ============================================================================

setup_auto_renewal() {
    print_header "Setting Up Auto-Renewal"

    log_info "Certbot automatically creates a systemd timer for certificate renewal"

    # Check if timer is active
    if systemctl is-active --quiet certbot.timer; then
        log_success "Certbot auto-renewal timer is active"
    else
        log_info "Enabling certbot auto-renewal timer..."
        systemctl enable certbot.timer
        systemctl start certbot.timer
        log_success "Certbot auto-renewal timer enabled"
    fi

    # Show renewal timer status
    log_info "Renewal timer status:"
    systemctl status certbot.timer --no-pager -l || true

    log_info "Certificates will be automatically renewed when they expire"
    log_info "You can test renewal with: sudo certbot renew --dry-run"
}

# ============================================================================
# Verification
# ============================================================================

verify_certificates() {
    print_header "Verifying Certificates"

    for subdomain in "${SUBDOMAINS[@]}"; do
        log_info "Checking certificate for $subdomain..."

        if certbot certificates -d "$subdomain" 2>/dev/null | grep -q "VALID"; then
            log_success "Certificate for $subdomain is valid"
        else
            log_warn "Could not verify certificate for $subdomain"
        fi
    done

    log_info ""
    log_info "Full certificate information:"
    certbot certificates
}

# ============================================================================
# Display Information
# ============================================================================

show_summary() {
    print_header "SSL Setup Complete!"

    echo -e "${GREEN}✓ Certificates obtained and installed${NC}"
    echo -e "${GREEN}✓ Nginx configured for HTTPS${NC}"
    echo -e "${GREEN}✓ Auto-renewal configured${NC}"
    echo ""
    echo -e "${BLUE}Your sites are now available via HTTPS:${NC}"
    echo ""
    for subdomain in "${SUBDOMAINS[@]}"; do
        echo -e "  ${GREEN}https://${subdomain}${NC}"
    done
    echo ""
    echo -e "${BLUE}Certificate Details:${NC}"
    echo -e "  • Issuer: Let's Encrypt"
    echo -e "  • Valid for: 90 days"
    echo -e "  • Auto-renewal: Enabled"
    echo ""
    echo -e "${YELLOW}Note:${NC} HTTP requests will automatically redirect to HTTPS"
    echo ""
    echo -e "${BLUE}Useful Commands:${NC}"
    echo -e "  • Check certificates:  ${GREEN}sudo certbot certificates${NC}"
    echo -e "  • Renew certificates:  ${GREEN}sudo certbot renew${NC}"
    echo -e "  • Test renewal:        ${GREEN}sudo certbot renew --dry-run${NC}"
    echo -e "  • Revoke certificate:  ${GREEN}sudo certbot revoke --cert-name ${DOMAIN_NAME}${NC}"
    echo ""
}

# ============================================================================
# Argument Parsing
# ============================================================================

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --email)
                ADMIN_EMAIL="$2"
                shift 2
                ;;
            --domains)
                IFS=',' read -ra SUBDOMAINS <<< "$2"
                shift 2
                ;;
            --staging)
                STAGING_MODE=true
                shift
                ;;
            --help|-h)
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
Let's Encrypt SSL Certificate Setup

Usage: sudo $0 [OPTIONS]

Options:
  --email EMAIL       Admin email for Let's Encrypt notifications
                      Default: admin@${DOMAIN_NAME}

  --domains DOMAINS   Comma-separated list of domains
                      Default: ${SUBDOMAINS[*]}

  --staging           Use Let's Encrypt staging environment for testing
                      (certificates won't be trusted by browsers)

  --help, -h          Show this help message

Examples:
  # Basic usage (interactive):
  sudo $0

  # Specify custom email:
  sudo $0 --email me@example.com

  # Test with staging (for development):
  sudo $0 --staging

  # Custom domains:
  sudo $0 --domains "example.com,www.example.com,api.example.com"

Notes:
  • This script requires root privileges (use sudo)
  • DNS records must point to this server before running
  • Port 80 must be accessible from the internet
  • Nginx must be running and configured

For more information:
  https://letsencrypt.org/
  https://certbot.eff.org/

EOF
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    parse_arguments "$@"

    print_header "Let's Encrypt SSL Certificate Setup"

    log_info "Domain: $DOMAIN_NAME"
    log_info "Email: $ADMIN_EMAIL"
    log_info "Subdomains: ${SUBDOMAINS[*]}"

    if [[ "$STAGING_MODE" == "true" ]]; then
        log_warn "STAGING MODE: Certificates will not be trusted!"
    fi

    echo ""
    read -p "Continue with SSL certificate setup? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Aborted by user"
        exit 0
    fi

    check_root
    check_nginx
    check_port_80
    check_dns
    install_certbot
    obtain_certificates
    configure_nginx_https
    setup_auto_renewal
    verify_certificates
    show_summary

    log_success "SSL setup completed successfully!"
}

# Run main function
main "$@"
