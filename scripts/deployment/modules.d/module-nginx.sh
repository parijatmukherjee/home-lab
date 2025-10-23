#!/bin/bash
# module-nginx.sh - Nginx web server configuration module
# Part of Home CI/CD Server deployment automation
#
# This module configures Nginx including:
# - Installation of Nginx
# - Reverse proxy for Jenkins
# - Artifact repository web interface
# - SSL/TLS termination (placeholder, configured in ssl module)
# - Rate limiting and security headers
# - Access logging and monitoring
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
MODULE_NAME="nginx"
MODULE_VERSION="1.0.0"
# shellcheck disable=SC2034  # Used by deployment system
MODULE_DESCRIPTION="Nginx web server and reverse proxy configuration"

# ============================================================================
# Configuration
# ============================================================================

# Nginx configuration paths
NGINX_CONF_DIR="/etc/nginx"
NGINX_SITES_AVAILABLE="${NGINX_CONF_DIR}/sites-available"
NGINX_SITES_ENABLED="${NGINX_CONF_DIR}/sites-enabled"
NGINX_CONF_D="${NGINX_CONF_DIR}/conf.d"

# Web root paths
WWW_ROOT="/var/www"
CERTBOT_ROOT="${WWW_ROOT}/certbot"

# Application settings (from config or defaults)
DOMAIN_NAME="${DOMAIN_NAME:-core.mohjave.com}"
JENKINS_PORT="${JENKINS_PORT:-8080}"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-/srv/data/artifacts}"
NGINX_WORKER_PROCESSES="${NGINX_WORKER_PROCESSES:-auto}"
NGINX_WORKER_CONNECTIONS="${NGINX_WORKER_CONNECTIONS:-1024}"
NGINX_CLIENT_MAX_BODY_SIZE="${NGINX_CLIENT_MAX_BODY_SIZE:-1000M}"

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

NGINX_INSTALLED=yes
NGINX_CONFIGURED=yes
SITES_CONFIGURED=yes
EOF

    chmod 600 "$state_file"
}

# ============================================================================
# Nginx Installation
# ============================================================================

function install_nginx() {
    log_task_start "Install Nginx"

    if check_command nginx; then
        local nginx_version
        nginx_version=$(nginx -v 2>&1 | cut -d'/' -f2)
        log_info "Nginx already installed: $nginx_version"
        log_task_complete
        return 0
    fi

    # Install Nginx
    if DEBIAN_FRONTEND=noninteractive apt-get install -y nginx; then
        log_success "Nginx installed successfully"
        log_task_complete
        return 0
    else
        log_task_failed "Failed to install Nginx"
        return 1
    fi
}

# ============================================================================
# Nginx Main Configuration
# ============================================================================

function configure_nginx_main() {
    log_task_start "Configure Nginx main configuration"

    local nginx_conf="${NGINX_CONF_DIR}/nginx.conf"

    backup_file "$nginx_conf"

    cat > "$nginx_conf" << EOF
# Home CI/CD Server - Nginx Configuration
# Generated: $(date)

user www-data;
worker_processes ${NGINX_WORKER_PROCESSES};
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections ${NGINX_WORKER_CONNECTIONS};
    use epoll;
    multi_accept on;
}

http {
    ##
    # Basic Settings
    ##

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    server_tokens off;

    # Server names hash bucket size
    server_names_hash_bucket_size 64;

    # MIME types
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    ##
    # SSL Settings (configured by ssl module)
    ##

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;

    ##
    # Logging Settings
    ##

    # Log format with additional security info
    log_format main '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                    '\$status \$body_bytes_sent "\$http_referer" '
                    '"\$http_user_agent" "\$http_x_forwarded_for" '
                    'rt=\$request_time uct=\$upstream_connect_time '
                    'uht=\$upstream_header_time urt=\$upstream_response_time';

    access_log /var/log/nginx/access.log main;
    error_log /var/log/nginx/error.log warn;

    ##
    # Gzip Settings
    ##

    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml text/javascript
               application/json application/javascript application/xml+rss
               application/rss+xml font/truetype font/opentype
               application/vnd.ms-fontobject image/svg+xml;
    gzip_disable "msie6";

    ##
    # Client Body Size
    ##

    client_max_body_size ${NGINX_CLIENT_MAX_BODY_SIZE};
    client_body_buffer_size 128k;

    ##
    # Proxy Settings
    ##

    proxy_connect_timeout 60s;
    proxy_send_timeout 60s;
    proxy_read_timeout 60s;
    proxy_buffering on;
    proxy_buffer_size 8k;
    proxy_buffers 256 8k;
    proxy_busy_buffers_size 64k;
    proxy_temp_file_write_size 64k;

    ##
    # Rate Limiting
    ##

    # Define rate limit zones
    limit_req_zone \$binary_remote_addr zone=general:10m rate=100r/m;
    limit_req_zone \$binary_remote_addr zone=api:10m rate=30r/m;
    limit_req_zone \$binary_remote_addr zone=upload:10m rate=10r/m;

    # Connection limiting
    limit_conn_zone \$binary_remote_addr zone=addr:10m;

    # Request status codes
    limit_req_status 429;
    limit_conn_status 429;

    ##
    # Cache Settings
    ##

    proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=cache:10m
                     max_size=1g inactive=60m use_temp_path=off;

    ##
    # Virtual Host Configs
    ##

    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
EOF

    log_task_complete
    return 0
}

# ============================================================================
# Default Site Configuration
# ============================================================================

function configure_default_site() {
    log_task_start "Configure default site"

    local default_site="${NGINX_SITES_AVAILABLE}/default"

    backup_file "$default_site" 2>/dev/null || true

    cat > "$default_site" << 'EOF'
# Default server block - return 444 for unknown hosts
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    server_name _;

    # Drop requests to unknown hosts
    return 444;
}
EOF

    # Enable default site
    ln -sf "$default_site" "${NGINX_SITES_ENABLED}/default" 2>/dev/null || true

    log_task_complete
    return 0
}

# ============================================================================
# Main Site Configuration (HTTP)
# ============================================================================

function configure_main_site_http() {
    log_task_start "Configure main site (HTTP)"

    local main_site="${NGINX_SITES_AVAILABLE}/${DOMAIN_NAME}"

    backup_file "$main_site" 2>/dev/null || true

    cat > "$main_site" << EOF
# Main site configuration for ${DOMAIN_NAME}
# HTTP only (HTTPS configured by SSL module)

server {
    listen 80;
    listen [::]:80;

    server_name ${DOMAIN_NAME};

    # Webroot for Let's Encrypt challenges
    location /.well-known/acme-challenge/ {
        root ${CERTBOT_ROOT};
        allow all;
    }

    # Redirect all other HTTP to HTTPS (will be enabled after SSL setup)
    # location / {
    #     return 301 https://\$server_name\$request_uri;
    # }

    # Temporary: Serve basic page until SSL is configured
    location / {
        # Global authentication
        auth_basic "Core Server";
        auth_basic_user_file ${DEPLOYMENT_CONFIG}/users.htpasswd;

        root /var/www/html;
        index index.html;
        try_files \$uri \$uri/ =404;
    }

    # Security headers
    add_header X-Frame-Options "DENY" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Access log
    access_log /var/log/nginx/${DOMAIN_NAME}-access.log main;
    error_log /var/log/nginx/${DOMAIN_NAME}-error.log warn;
}
EOF

    # Enable main site
    ln -sf "$main_site" "${NGINX_SITES_ENABLED}/${DOMAIN_NAME}" 2>/dev/null || true

    log_task_complete
    return 0
}

# ============================================================================
# Jenkins Reverse Proxy Configuration
# ============================================================================

function configure_jenkins_proxy() {
    log_task_start "Configure Jenkins reverse proxy"

    local jenkins_conf="${NGINX_CONF_D}/jenkins.conf"

    backup_file "$jenkins_conf" 2>/dev/null || true

    cat > "$jenkins_conf" << EOF
# Jenkins reverse proxy configuration

upstream jenkins {
    server 127.0.0.1:${JENKINS_PORT} fail_timeout=0;
}

# This will be included in the main HTTPS server block
# For now, accessible via HTTP (development only)
server {
    listen 80;
    listen [::]:80;

    server_name jenkins.${DOMAIN_NAME};

    # Rate limiting for Jenkins
    limit_req zone=general burst=20 nodelay;
    limit_conn addr 10;

    # All paths require authentication
    auth_basic "Jenkins CI/CD";
    auth_basic_user_file /opt/core-setup/config/users.htpasswd;

    # Matrix landing page for root
    location = / {
        root /var/www/matrix-landing;
        try_files /index.html =404;
    }

    # Serve matrix landing page static assets
    location /assets/ {
        root /var/www/matrix-landing;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    # Jenkins API and actual service
    location /jenkins {

        proxy_pass http://jenkins;
        proxy_redirect default;
        proxy_http_version 1.1;

        # Required headers for Jenkins
        proxy_set_header Host \$host:\$server_port;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # WebSocket support for Jenkins
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        # Timeouts for long-running builds
        proxy_connect_timeout 90;
        proxy_send_timeout 90;
        proxy_read_timeout 90;

        # Buffering
        proxy_buffering off;
        proxy_request_buffering off;
    }

    # Access log
    access_log /var/log/nginx/jenkins-access.log main;
    error_log /var/log/nginx/jenkins-error.log warn;
}
EOF

    log_task_complete
    return 0
}

# ============================================================================
# Artifact Repository Configuration
# ============================================================================

function configure_artifact_repository() {
    log_task_start "Configure artifact repository"

    local artifacts_conf="${NGINX_CONF_D}/artifacts.conf"

    backup_file "$artifacts_conf" 2>/dev/null || true

    cat > "$artifacts_conf" << EOF
# Artifact repository configuration

server {
    listen 80;
    listen [::]:80;

    server_name artifacts.${DOMAIN_NAME};

    # Rate limiting for uploads
    limit_req zone=upload burst=5 nodelay;

    # Artifact root directory
    root ${ARTIFACTS_DIR};

    # Enable directory browsing with autoindex
    autoindex on;
    autoindex_exact_size off;
    autoindex_localtime on;

    # Charset
    charset utf-8;

    # Default location
    location / {
        # Basic authentication (configured by users module)
        # auth_basic "Artifact Repository";
        # auth_basic_user_file /opt/core-setup/config/users.htpasswd;

        # Allow GET, HEAD, POST (for uploads)
        limit_except GET HEAD POST {
            deny all;
        }

        # Directory listing
        try_files \$uri \$uri/ =404;
    }

    # Upload endpoint (will be handled by custom upload script)
    location /upload {
        # Only authenticated users can upload
        auth_basic "Artifact Upload";
        auth_basic_user_file /opt/core-setup/config/users.htpasswd;

        # Upload handling (delegated to backend)
        proxy_pass http://127.0.0.1:8081;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;

        # Large file uploads
        client_max_body_size ${NGINX_CLIENT_MAX_BODY_SIZE};
    }

    # Serve metadata files
    location ~ \.(md5|sha256|sha512|json)$ {
        add_header Content-Type text/plain;
    }

    # Security headers
    add_header X-Frame-Options "DENY" always;
    add_header X-Content-Type-Options "nosniff" always;

    # Access log
    access_log /var/log/nginx/artifacts-access.log main;
    error_log /var/log/nginx/artifacts-error.log warn;
}
EOF

    log_task_complete
    return 0
}

# ============================================================================
# Monitoring Configuration
# ============================================================================

function configure_monitoring_proxy() {
    log_task_start "Configure monitoring proxy"

    local monitoring_conf="${NGINX_CONF_D}/monitoring.conf"

    backup_file "$monitoring_conf" 2>/dev/null || true

    cat > "$monitoring_conf" << EOF
# Monitoring (Netdata) reverse proxy configuration

upstream netdata {
    server 127.0.0.1:19999;
    keepalive 64;
}

server {
    listen 80;
    listen [::]:80;

    server_name monitoring.${DOMAIN_NAME};

    # All paths require authentication
    auth_basic "Monitoring Dashboard";
    auth_basic_user_file /opt/core-setup/config/users.htpasswd;

    # Matrix landing page for root
    location = / {
        root /var/www/matrix-landing;
        try_files /index.html =404;
    }

    # Serve matrix landing page static assets
    location /assets/ {
        root /var/www/matrix-landing;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    # Monitoring dashboard
    location /netdata {

        proxy_pass http://netdata;
        proxy_redirect default;
        proxy_http_version 1.1;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # WebSocket support
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    # Access log
    access_log /var/log/nginx/monitoring-access.log main;
    error_log /var/log/nginx/monitoring-error.log warn;
}
EOF

    log_task_complete
    return 0
}

# ============================================================================
# Nginx Status Endpoint
# ============================================================================

function configure_nginx_status() {
    log_task_start "Configure Nginx status endpoint"

    local status_conf="${NGINX_CONF_D}/status.conf"

    cat > "$status_conf" << 'EOF'
# Nginx status endpoint (localhost only)

server {
    listen 127.0.0.1:80;

    server_name localhost;

    location /nginx_status {
        stub_status on;
        access_log off;
        allow 127.0.0.1;
        deny all;
    }
}
EOF

    log_task_complete
    return 0
}

# ============================================================================
# Webroot and Placeholder Pages
# ============================================================================

function create_webroot_structure() {
    log_task_start "Create webroot structure"

    # Create web roots
    ensure_directory "${WWW_ROOT}/html" "755" "www-data:www-data"
    ensure_directory "$CERTBOT_ROOT" "755" "www-data:www-data"

    # Create default index page
    cat > "${WWW_ROOT}/html/index.html" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${DOMAIN_NAME} - CI/CD Server</title>
    <style>
        body { font-family: Arial, sans-serif; max-width: 800px; margin: 50px auto; padding: 20px; }
        h1 { color: #333; }
        .service { margin: 20px 0; padding: 15px; background: #f5f5f5; border-radius: 5px; }
        .service a { color: #0066cc; text-decoration: none; }
        .service a:hover { text-decoration: underline; }
    </style>
</head>
<body>
    <h1>Welcome to ${DOMAIN_NAME}</h1>
    <p>Home CI/CD Server - Automated Build and Deployment Platform</p>

    <div class="service">
        <h2>Jenkins CI/CD</h2>
        <p><a href="http://jenkins.${DOMAIN_NAME}">http://jenkins.${DOMAIN_NAME}</a></p>
    </div>

    <div class="service">
        <h2>Artifact Repository</h2>
        <p><a href="http://artifacts.${DOMAIN_NAME}">http://artifacts.${DOMAIN_NAME}</a></p>
    </div>

    <div class="service">
        <h2>Monitoring Dashboard</h2>
        <p><a href="http://monitoring.${DOMAIN_NAME}">http://monitoring.${DOMAIN_NAME}</a></p>
    </div>

    <p><small>Generated: $(date)</small></p>
</body>
</html>
EOF

    chown -R www-data:www-data "${WWW_ROOT}/html"

    log_task_complete
    return 0
}

# ============================================================================
# Matrix Landing Page Deployment
# ============================================================================

function deploy_matrix_landing_page() {
    log_task_start "Deploy matrix landing page"

    local matrix_dest="/var/www/matrix-landing"
    local matrix_source="${SCRIPT_DIR}/../web-assets/matrix-login-escape/dist"

    # Check if source exists
    if [[ ! -d "$matrix_source" ]]; then
        log_warn "Matrix landing page source not found: $matrix_source"

        local build_source="${SCRIPT_DIR}/../web-assets/matrix-login-escape"
        if [[ ! -d "$build_source" ]]; then
            log_warn "Matrix landing page project not found at: $build_source"
            log_warn "Skipping matrix landing page deployment - using placeholder"

            # Create destination directory with a simple placeholder
            ensure_directory "$matrix_dest" "755" "www-data:www-data"
            cat > "$matrix_dest/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Access Denied</title>
    <style>
        body {
            background: #000;
            color: #0f0;
            font-family: monospace;
            display: flex;
            align-items: center;
            justify-content: center;
            min-height: 100vh;
            margin: 0;
        }
        .content {
            text-align: center;
            padding: 20px;
        }
        h1 { font-size: 3em; margin-bottom: 20px; }
        p { font-size: 1.2em; }
    </style>
</head>
<body>
    <div class="content">
        <h1>ACCESS DENIED</h1>
        <p>You're not supposed to be here.</p>
        <p><small>core.mohjave.com</small></p>
    </div>
</body>
</html>
EOF
            chown -R www-data:www-data "$matrix_dest"
            log_success "Placeholder landing page created"
            log_task_complete
            return 0
        fi

        # Try to build if npm is available
        log_info "Attempting to build matrix landing page..."
        cd "$build_source" || return 1
        if command -v npm &>/dev/null; then
            if npm install && npm run build; then
                log_success "Matrix landing page built successfully"
            else
                log_warn "Failed to build matrix landing page, using placeholder"
                cd - > /dev/null || true

                # Use placeholder on build failure
                ensure_directory "$matrix_dest" "755" "www-data:www-data"
                cat > "$matrix_dest/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Access Denied</title>
    <style>
        body {
            background: #000;
            color: #0f0;
            font-family: monospace;
            display: flex;
            align-items: center;
            justify-content: center;
            min-height: 100vh;
            margin: 0;
        }
        .content {
            text-align: center;
            padding: 20px;
        }
        h1 { font-size: 3em; margin-bottom: 20px; }
        p { font-size: 1.2em; }
    </style>
</head>
<body>
    <div class="content">
        <h1>ACCESS DENIED</h1>
        <p>You're not supposed to be here.</p>
        <p><small>core.mohjave.com</small></p>
    </div>
</body>
</html>
EOF
                chown -R www-data:www-data "$matrix_dest"
                log_task_complete
                return 0
            fi
        else
            log_warn "npm not found. Using placeholder landing page"
            cd - > /dev/null || true

            # Use placeholder when npm is not available
            ensure_directory "$matrix_dest" "755" "www-data:www-data"
            cat > "$matrix_dest/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Access Denied</title>
    <style>
        body {
            background: #000;
            color: #0f0;
            font-family: monospace;
            display: flex;
            align-items: center;
            justify-content: center;
            min-height: 100vh;
            margin: 0;
        }
        .content {
            text-align: center;
            padding: 20px;
        }
        h1 { font-size: 3em; margin-bottom: 20px; }
        p { font-size: 1.2em; }
    </style>
</head>
<body>
    <div class="content">
        <h1>ACCESS DENIED</h1>
        <p>You're not supposed to be here.</p>
        <p><small>core.mohjave.com</small></p>
    </div>
</body>
</html>
EOF
            chown -R www-data:www-data "$matrix_dest"
            log_task_complete
            return 0
        fi
        cd - > /dev/null || true
    fi

    # Create destination directory
    ensure_directory "$matrix_dest" "755" "www-data:www-data"

    # Copy built assets
    if cp -r "$matrix_source"/* "$matrix_dest/"; then
        chown -R www-data:www-data "$matrix_dest"
        log_success "Matrix landing page deployed to $matrix_dest"
        log_task_complete
        return 0
    else
        log_task_failed "Failed to deploy matrix landing page"
        return 1
    fi
}

# ============================================================================
# Nginx Service Management
# ============================================================================

function test_nginx_configuration() {
    log_task_start "Test Nginx configuration"

    if nginx -t; then
        log_success "Nginx configuration is valid"
        log_task_complete
        return 0
    else
        log_task_failed "Nginx configuration has errors"
        return 1
    fi
}

function restart_nginx() {
    log_task_start "Restart Nginx service"

    systemctl enable nginx

    if systemctl restart nginx; then
        wait_for_service nginx 10
        log_task_complete
        return 0
    else
        log_task_failed "Failed to restart Nginx"
        return 1
    fi
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

    # Install Nginx
    install_nginx || return 1

    # Configure Nginx
    configure_nginx_main || return 1
    configure_default_site || return 1
    configure_main_site_http || return 1
    configure_jenkins_proxy || return 1
    configure_artifact_repository || return 1
    configure_monitoring_proxy || return 1
    configure_nginx_status || return 1

    # Create webroot structure
    create_webroot_structure || return 1

    # Deploy matrix landing page
    deploy_matrix_landing_page || return 1

    # Test and restart
    test_nginx_configuration || return 1
    restart_nginx || return 1

    # Save module state
    save_module_state

    log_module_complete
    return 0
}

# ============================================================================
# Module Entry Point
# ============================================================================

main "$@"
