#!/bin/bash
# setup-ssl-dns.sh - Let's Encrypt SSL Certificate Setup (DNS Challenge)
# Part of Home CI/CD Server
#
# This script obtains free SSL certificates from Let's Encrypt using DNS-01 challenge.
# This method works when HTTP-01 fails due to DNS CAA issues.
#
# Usage: sudo ./setup-ssl-dns.sh [--email EMAIL] [--staging]

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
STAGING_MODE=false
CERT_NAME="core.mohjave.com"

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

print_box() {
    local message="$1"
    local length=${#message}
    local border
    border=$(printf '=%.0s' $(seq 1 $((length + 4))))

    echo -e "${YELLOW}${border}${NC}"
    echo -e "${YELLOW}| ${message} |${NC}"
    echo -e "${YELLOW}${border}${NC}"
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

# ============================================================================
# Certbot Installation
# ============================================================================

install_certbot() {
    log_info "Checking certbot installation..."

    if command -v certbot >/dev/null 2>&1; then
        log_success "Certbot is already installed ($(certbot --version))"
        return 0
    fi

    log_info "Installing certbot..."

    # Update package list
    apt-get update -qq

    # Install certbot (no nginx plugin needed for DNS challenge)
    DEBIAN_FRONTEND=noninteractive apt-get install -y certbot

    if command -v certbot >/dev/null 2>&1; then
        log_success "Certbot installed successfully ($(certbot --version))"
    else
        log_error "Failed to install certbot"
        exit 1
    fi
}

# ============================================================================
# Certificate Obtainment (DNS Challenge)
# ============================================================================

obtain_certificates_dns() {
    print_header "Obtaining SSL Certificates (DNS Challenge)"

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
    log_info ""
    log_warn "DNS CHALLENGE METHOD:"
    log_warn "You will be prompted to create DNS TXT records"
    log_warn "You must add these records in your DNS provider (Dynu)"
    log_warn "before continuing with the validation"
    echo ""

    # Run certbot with manual DNS challenge
    if certbot certonly \
        --manual \
        --preferred-challenges dns \
        --agree-tos \
        --non-interactive \
        $staging_flag \
        --email "$ADMIN_EMAIL" \
        --manual-auth-hook /bin/true \
        --cert-name "$CERT_NAME" \
        $domain_args 2>&1 | tee /tmp/certbot-dns-output.log; then

        log_success "Certificates obtained successfully!"
        return 0
    else
        # Manual mode requires interactive input, so we'll use a different approach
        log_info "Running certbot in interactive mode..."

        certbot certonly \
            --manual \
            --preferred-challenges dns \
            --agree-tos \
            $staging_flag \
            --email "$ADMIN_EMAIL" \
            --cert-name "$CERT_NAME" \
            $domain_args

        local exit_code=$?
        if [[ $exit_code -eq 0 ]]; then
            log_success "Certificates obtained successfully!"
            return 0
        else
            log_error "Failed to obtain certificates"
            log_warn "Common issues:"
            log_warn "  1. DNS TXT records not added correctly"
            log_warn "  2. DNS propagation not complete (wait a few minutes)"
            log_warn "  3. Incorrect DNS record values"
            return 1
        fi
    fi
}

# ============================================================================
# Nginx HTTPS Configuration
# ============================================================================

configure_nginx_https() {
    print_header "Configuring Nginx for HTTPS"

    local cert_dir="/etc/letsencrypt/live/${CERT_NAME}"

    # Check if certificates exist
    if [[ ! -f "${cert_dir}/fullchain.pem" ]] || [[ ! -f "${cert_dir}/privkey.pem" ]]; then
        log_error "Certificate files not found in ${cert_dir}"
        return 1
    fi

    log_success "Certificate files found"

    # Backup current nginx configs
    log_info "Backing up current nginx configurations..."
    local backup_dir
    backup_dir="/tmp/nginx-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"
    cp -r /etc/nginx/conf.d "$backup_dir/" 2>/dev/null || true
    log_info "Backup created at: $backup_dir"

    # Update each nginx config file to use SSL
    log_info "Updating nginx configurations for HTTPS..."

    # Main site
    update_nginx_config_for_ssl "/etc/nginx/conf.d/core.conf" "${DOMAIN_NAME}" "$cert_dir"

    # Jenkins
    update_nginx_config_for_ssl "/etc/nginx/conf.d/jenkins.conf" "jenkins.${DOMAIN_NAME}" "$cert_dir"

    # Artifacts
    update_nginx_config_for_ssl "/etc/nginx/conf.d/artifacts.conf" "artifacts.${DOMAIN_NAME}" "$cert_dir"

    # Monitoring
    update_nginx_config_for_ssl "/etc/nginx/conf.d/monitoring.conf" "monitoring.${DOMAIN_NAME}" "$cert_dir"

    # Test nginx configuration
    if nginx -t; then
        log_success "Nginx configuration is valid"
        systemctl reload nginx
        log_success "Nginx reloaded with HTTPS configuration"
    else
        log_error "Nginx configuration has errors"
        log_warn "Restoring backup from: $backup_dir"
        cp -r "$backup_dir/conf.d/"* /etc/nginx/conf.d/ 2>/dev/null || true
        nginx -t
        return 1
    fi
}

update_nginx_config_for_ssl() {
    local config_file="$1"
    local server_name="$2"
    local cert_dir="$3"

    if [[ ! -f "$config_file" ]]; then
        log_warn "Config file not found: $config_file"
        return 0
    fi

    log_info "Updating: $(basename $config_file)"

    # Check if already has SSL configuration
    if grep -q "listen 443 ssl" "$config_file"; then
        log_info "  Already configured for SSL"
        return 0
    fi

    # Create temporary file with SSL configuration
    local temp_file
    temp_file=$(mktemp)

    # Read the existing config and add SSL
    cat "$config_file" | sed -E '
        # After "listen 80", add SSL listener
        /listen 80;/a\
    listen 443 ssl http2;\
    listen [::]:443 ssl http2;

        # After server_name, add SSL certificate paths
        /server_name/a\
\
    # SSL Configuration\
    ssl_certificate '"${cert_dir}/fullchain.pem"';\
    ssl_certificate_key '"${cert_dir}/privkey.pem"';\
    ssl_protocols TLSv1.2 TLSv1.3;\
    ssl_ciphers HIGH:!aNULL:!MD5;\
    ssl_prefer_server_ciphers on;\
    ssl_session_cache shared:SSL:10m;\
    ssl_session_timeout 10m;
    ' > "$temp_file"

    # Also add HTTP to HTTPS redirect server block
    echo "" >> "$temp_file"
    echo "# HTTP to HTTPS redirect" >> "$temp_file"
    echo "server {" >> "$temp_file"
    echo "    listen 80;" >> "$temp_file"
    echo "    listen [::]:80;" >> "$temp_file"
    echo "    server_name $server_name;" >> "$temp_file"
    echo "    return 301 https://\$host\$request_uri;" >> "$temp_file"
    echo "}" >> "$temp_file"

    # Replace original with modified
    mv "$temp_file" "$config_file"
    log_success "  Updated $(basename $config_file)"
}

# ============================================================================
# Auto-renewal Setup
# ============================================================================

setup_auto_renewal() {
    print_header "Setting Up Auto-Renewal"

    log_warn "DNS challenge requires manual DNS updates for renewal"
    log_warn "Automatic renewal is NOT fully automated with DNS challenge"
    log_info ""
    log_info "To renew certificates manually:"
    log_info "  1. Run: sudo certbot renew --manual"
    log_info "  2. Follow prompts to update DNS TXT records"
    log_info "  3. Wait for DNS propagation"
    log_info "  4. Complete validation"
    log_info ""
    log_info "Consider switching to a DNS provider with API support for automated renewal"
    log_info "(e.g., Cloudflare, Route53, DigitalOcean)"
}

# ============================================================================
# Verification
# ============================================================================

verify_certificates() {
    print_header "Verifying Certificates"

    if certbot certificates 2>/dev/null | grep -q "$CERT_NAME"; then
        log_success "Certificate is installed"
        echo ""
        certbot certificates
    else
        log_warn "Could not verify certificate"
    fi
}

verify_https_access() {
    print_header "Verifying HTTPS Access"

    for subdomain in "${SUBDOMAINS[@]}"; do
        log_info "Testing: https://${subdomain}"

        if curl -k -s -o /dev/null -w "%{http_code}" "https://${subdomain}" | grep -q "200\|301\|302"; then
            log_success "  HTTPS is working for ${subdomain}"
        else
            log_warn "  Could not verify HTTPS for ${subdomain}"
        fi
    done
}

# ============================================================================
# Display Information
# ============================================================================

show_summary() {
    print_header "SSL Setup Complete!"

    echo -e "${GREEN}✓ Certificates obtained${NC}"
    echo -e "${GREEN}✓ Nginx configured for HTTPS${NC}"
    echo -e "${YELLOW}⚠ Manual renewal required (DNS challenge)${NC}"
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
    echo -e "  • Challenge: DNS-01 (manual)"
    echo ""
    echo -e "${YELLOW}Important Notes:${NC}"
    echo -e "  • HTTP requests will automatically redirect to HTTPS"
    echo -e "  • Certificate renewal requires manual DNS TXT record updates"
    echo -e "  • Set a reminder to renew before expiration (60 days recommended)"
    echo ""
    echo -e "${BLUE}Useful Commands:${NC}"
    echo -e "  • Check certificates:  ${GREEN}sudo certbot certificates${NC}"
    echo -e "  • Renew certificates:  ${GREEN}sudo certbot renew --manual${NC}"
    echo -e "  • Revoke certificate:  ${GREEN}sudo certbot revoke --cert-name ${CERT_NAME}${NC}"
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
Let's Encrypt SSL Certificate Setup (DNS Challenge)

This script uses DNS-01 challenge which works when HTTP-01 fails due to
DNS provider limitations (like CAA record issues).

Usage: sudo $0 [OPTIONS]

Options:
  --email EMAIL       Admin email for Let's Encrypt notifications
                      Default: admin@${DOMAIN_NAME}

  --staging           Use Let's Encrypt staging environment for testing
                      (certificates won't be trusted by browsers)

  --help, -h          Show this help message

DNS Challenge Process:
  1. Script requests certificates from Let's Encrypt
  2. You'll be prompted to add DNS TXT records
  3. Login to Dynu.com and add the TXT records
  4. Wait for DNS propagation (2-5 minutes)
  5. Press Enter to continue validation
  6. Certificates are issued and nginx is configured

Examples:
  # Basic usage:
  sudo $0

  # Specify custom email:
  sudo $0 --email me@example.com

  # Test with staging:
  sudo $0 --staging

Notes:
  • This script requires root privileges (use sudo)
  • You need access to Dynu.com to add DNS TXT records
  • Certificate renewal requires repeating the DNS challenge
  • Consider API-enabled DNS providers for automated renewal

For more information:
  https://letsencrypt.org/docs/challenge-types/#dns-01-challenge

EOF
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    parse_arguments "$@"

    print_header "Let's Encrypt SSL Setup (DNS Challenge)"

    log_info "Domain: $DOMAIN_NAME"
    log_info "Email: $ADMIN_EMAIL"
    log_info "Subdomains: ${SUBDOMAINS[*]}"
    log_info "Method: DNS-01 Challenge (Manual)"

    if [[ "$STAGING_MODE" == "true" ]]; then
        log_warn "STAGING MODE: Certificates will not be trusted!"
    fi

    echo ""
    log_warn "This method requires you to manually add DNS TXT records"
    log_warn "You will need access to Dynu.com during this process"
    echo ""
    read -p "Continue with SSL certificate setup? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Aborted by user"
        exit 0
    fi

    check_root
    check_nginx
    install_certbot
    obtain_certificates_dns || exit 1
    configure_nginx_https || exit 1
    setup_auto_renewal
    verify_certificates
    verify_https_access
    show_summary

    log_success "SSL setup completed successfully!"
}

# Run main function
main "$@"
