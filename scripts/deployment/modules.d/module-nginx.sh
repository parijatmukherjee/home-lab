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

    # Auth API proxy
    location /api/auth {
        proxy_pass http://127.0.0.1:3001;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    # Matrix landing page (public access - has its own UI)
    location / {
        root /var/www/matrix-landing;
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

    # Jenkins at root path
    location / {
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

    # Proxy all requests to Netdata
    location / {
        proxy_pass http://netdata/;
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
# Auth Service Deployment
# ============================================================================

function deploy_auth_service() {
    log_task_start "Deploy authentication service"

    local auth_service_script="${DEPLOYMENT_SCRIPTS}/auth-service.js"
    local systemd_service="/etc/systemd/system/auth-service.service"

    # Create auth service script
    cat > "$auth_service_script" << 'EOF'
const http = require('http');

const ADMIN_USERNAME = 'admin';
let ADMIN_PASSWORD = 'cTTcudJxW0UVSH8SZtussnlA';

// Try to read password from config file
const fs = require('fs');
const configPath = '/opt/core-setup/config/.admin-password';
try {
  const content = fs.readFileSync(configPath, 'utf8');
  const match = content.match(/Password:\s*(.+)/);
  if (match) {
    ADMIN_PASSWORD = match[1].trim();
  }
} catch (err) {
  console.error('Warning: Could not read admin password from config, using default');
}

const server = http.createServer((req, res) => {
  // CORS headers
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.writeHead(200);
    res.end();
    return;
  }

  if (req.method === 'POST' && req.url === '/api/auth') {
    let body = '';

    req.on('data', chunk => {
      body += chunk.toString();
    });

    req.on('end', () => {
      try {
        const { username, password } = JSON.parse(body);

        if (username === ADMIN_USERNAME && password === ADMIN_PASSWORD) {
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({
            success: true,
            message: 'Authentication successful',
            username: ADMIN_USERNAME
          }));
        } else {
          res.writeHead(401, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({
            success: false,
            message: 'Invalid credentials'
          }));
        }
      } catch (error) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({
          success: false,
          message: 'Bad request'
        }));
      }
    });
  } else {
    res.writeHead(404, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ success: false, message: 'Not found' }));
  }
});

const PORT = 3001;
server.listen(PORT, '127.0.0.1', () => {
  console.log(\`Auth service running on http://127.0.0.1:\${PORT}\`);
});
EOF

    chmod 755 "$auth_service_script"

    # Create systemd service
    cat > "$systemd_service" << EOF
[Unit]
Description=Matrix Landing Page Auth Service
After=network.target

[Service]
Type=simple
User=www-data
WorkingDirectory=${DEPLOYMENT_SCRIPTS}
ExecStart=/usr/bin/node ${auth_service_script}
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    # Enable and start service
    systemctl daemon-reload
    systemctl enable auth-service
    systemctl restart auth-service

    if systemctl is-active --quiet auth-service; then
        log_success "Auth service deployed and running"
        log_task_complete
        return 0
    else
        log_task_failed "Auth service failed to start"
        return 1
    fi
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
# Matrix Artifacts Page Deployment
# ============================================================================

function deploy_matrix_artifacts_page() {
    log_task_start "Deploy matrix-themed artifacts page"

    local artifacts_index="${ARTIFACTS_DIR}/index.html"

    # Ensure artifacts directory exists
    ensure_directory "$ARTIFACTS_DIR" "755" "www-data:www-data"

    # Create matrix-themed artifacts index page
    cat > "$artifacts_index" << 'ARTIFACTSEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Artifact Repository - Mohjave Core Systems</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: 'Courier New', monospace;
            background-color: #000000;
            color: #00ff41;
            overflow-x: hidden;
            min-height: 100vh;
        }

        /* Matrix rain canvas */
        #matrix-rain {
            position: fixed;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            z-index: 1;
            opacity: 0.8;
        }

        /* Scan lines overlay */
        .scanlines {
            position: fixed;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            z-index: 2;
            pointer-events: none;
            background-image: repeating-linear-gradient(
                0deg,
                transparent,
                transparent 2px,
                rgba(0, 255, 65, 0.03) 2px,
                rgba(0, 255, 65, 0.03) 4px
            );
            opacity: 0.1;
        }

        /* Main content */
        .content {
            position: relative;
            z-index: 10;
            max-width: 1200px;
            margin: 0 auto;
            padding: 40px 20px;
            min-height: 100vh;
        }

        /* Header */
        .header {
            text-align: center;
            margin-bottom: 40px;
            padding: 20px;
            border: 2px solid #00ff41;
            background-color: rgba(0, 0, 0, 0.8);
            box-shadow: 0 0 20px rgba(0, 255, 65, 0.3);
            animation: glow 2s ease-in-out infinite alternate;
        }

        @keyframes glow {
            from {
                box-shadow: 0 0 10px rgba(0, 255, 65, 0.2);
            }
            to {
                box-shadow: 0 0 20px rgba(0, 255, 65, 0.5);
            }
        }

        .header h1 {
            font-size: 3rem;
            margin-bottom: 10px;
            text-shadow: 0 0 10px #00ff41;
            letter-spacing: 4px;
        }

        .header .subtitle {
            font-size: 1rem;
            color: #00cc33;
            margin-top: 10px;
        }

        .warning-box {
            background-color: rgba(255, 0, 0, 0.1);
            border: 1px solid #ff0000;
            padding: 15px;
            margin: 20px 0;
            text-align: left;
        }

        .warning-box p {
            color: #ff0000;
            font-size: 0.9rem;
            margin: 5px 0;
        }

        /* Artifact grid */
        .artifacts-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin: 30px 0;
        }

        .artifact-card {
            background-color: rgba(0, 20, 0, 0.9);
            border: 2px solid #00ff41;
            padding: 25px;
            transition: all 0.3s ease;
            position: relative;
            overflow: hidden;
        }

        .artifact-card::before {
            content: '';
            position: absolute;
            top: 0;
            left: -100%;
            width: 100%;
            height: 100%;
            background: linear-gradient(90deg, transparent, rgba(0, 255, 65, 0.2), transparent);
            transition: left 0.5s;
        }

        .artifact-card:hover {
            transform: translateY(-5px);
            box-shadow: 0 0 30px rgba(0, 255, 65, 0.5);
            border-color: #00ff99;
        }

        .artifact-card:hover::before {
            left: 100%;
        }

        .artifact-card h2 {
            color: #00ff41;
            font-size: 1.5rem;
            margin-bottom: 15px;
            text-shadow: 0 0 5px #00ff41;
        }

        .artifact-card p {
            color: #00cc33;
            margin-bottom: 15px;
            font-size: 0.9rem;
            line-height: 1.6;
        }

        .artifact-card a {
            color: #00ff99;
            text-decoration: none;
            font-weight: bold;
            display: inline-block;
            padding: 10px 20px;
            border: 1px solid #00ff41;
            background-color: rgba(0, 255, 65, 0.1);
            transition: all 0.3s ease;
        }

        .artifact-card a:hover {
            background-color: rgba(0, 255, 65, 0.3);
            box-shadow: 0 0 15px rgba(0, 255, 65, 0.6);
        }

        /* API section */
        .api-section {
            background-color: rgba(0, 20, 0, 0.9);
            border: 2px solid #00cc33;
            padding: 25px;
            margin: 30px 0;
        }

        .api-section h2 {
            color: #00ff41;
            margin-bottom: 15px;
            font-size: 1.8rem;
        }

        .api-section pre {
            background-color: rgba(0, 0, 0, 0.8);
            border: 1px solid #00ff41;
            padding: 15px;
            overflow-x: auto;
            margin: 15px 0;
            color: #00cc33;
        }

        .api-section code {
            font-family: 'Courier New', monospace;
            font-size: 0.9rem;
        }

        /* Footer */
        .footer {
            text-align: center;
            margin-top: 40px;
            padding: 20px;
            border-top: 1px solid #00ff41;
            color: #00cc33;
            font-size: 0.8rem;
        }

        .footer p {
            margin: 5px 0;
        }

        /* Glitch effect for title */
        @keyframes glitch {
            0% {
                text-shadow: 0 0 10px #00ff41;
            }
            25% {
                text-shadow: -2px 0 #ff00ff, 2px 0 #00ffff;
            }
            50% {
                text-shadow: 0 0 10px #00ff41;
            }
            75% {
                text-shadow: 2px 0 #ff00ff, -2px 0 #00ffff;
            }
            100% {
                text-shadow: 0 0 10px #00ff41;
            }
        }

        .glitch {
            animation: glitch 0.5s infinite;
        }

        /* Loading animation */
        @keyframes fadeIn {
            from {
                opacity: 0;
                transform: translateY(20px);
            }
            to {
                opacity: 1;
                transform: translateY(0);
            }
        }

        .fade-in {
            animation: fadeIn 0.6s ease-out;
        }
    </style>
</head>
<body>
    <!-- Matrix rain canvas -->
    <canvas id="matrix-rain"></canvas>

    <!-- Scan lines overlay -->
    <div class="scanlines"></div>

    <!-- Main content -->
    <div class="content fade-in">
        <div class="header">
            <h1 class="glitch">ARTIFACT REPOSITORY</h1>
            <p class="subtitle">&gt; Mohjave Core Systems | Build Artifact Storage</p>

            <div class="warning-box">
                <p>[!] SECURE AREA: All access is logged and monitored</p>
                <p>&gt; IP Address: <span id="ip-address"></span></p>
                <p>&gt; Timestamp: <span id="timestamp"></span></p>
                <p>&gt; Access Level: PUBLIC</p>
            </div>
        </div>

        <div class="artifacts-grid">
            <div class="artifact-card">
                <h2>&gt; ISO Images</h2>
                <p>Operating system images and bootable ISOs for deployment and testing.</p>
                <a href="iso/">Browse ISO Artifacts &rarr;</a>
            </div>

            <div class="artifact-card">
                <h2>&gt; JAR Files</h2>
                <p>Java application packages, libraries, and compiled bytecode artifacts.</p>
                <a href="jar/">Browse JAR Artifacts &rarr;</a>
            </div>

            <div class="artifact-card">
                <h2>&gt; NPM Packages</h2>
                <p>Node.js packages, modules, and JavaScript dependencies.</p>
                <a href="npm/">Browse NPM Artifacts &rarr;</a>
            </div>

            <div class="artifact-card">
                <h2>&gt; Python Packages</h2>
                <p>Python wheels, source distributions, and pip-installable packages.</p>
                <a href="python/">Browse Python Artifacts &rarr;</a>
            </div>

            <div class="artifact-card">
                <h2>&gt; Docker Images</h2>
                <p>Container images, Dockerfiles, and registry artifacts.</p>
                <a href="docker/">Browse Docker Artifacts &rarr;</a>
            </div>

            <div class="artifact-card">
                <h2>&gt; Generic Artifacts</h2>
                <p>Miscellaneous build artifacts, binaries, and other files.</p>
                <a href="generic/">Browse Generic Artifacts &rarr;</a>
            </div>
        </div>

        <div class="api-section">
            <h2>&gt; API Documentation</h2>
            <p style="color: #00cc33;">Upload artifacts using the REST API endpoint:</p>
            <pre><code>curl -X POST \
  -F "file=@artifact.jar" \
  -F "project=myproject" \
  -F "version=1.0.0" \
  -u username:password \
  http://artifacts.core.mohjave.com/upload</code></pre>

            <p style="color: #00cc33; margin-top: 15px;">Download artifacts directly via HTTP:</p>
            <pre><code>wget http://artifacts.core.mohjave.com/jar/myproject/1.0.0/artifact.jar</code></pre>
        </div>

        <div class="footer">
            <p>&gt; Artifact Repository - Part of Mohjave Home CI/CD Server</p>
            <p>&gt; System Version: 2.0.77 | Status: ONLINE</p>
            <p>&gt; "The code is the path. The artifacts are the destination."</p>
        </div>
    </div>

    <script>
        // Matrix rain effect
        const canvas = document.getElementById('matrix-rain');
        const ctx = canvas.getContext('2d');

        canvas.width = window.innerWidth;
        canvas.height = window.innerHeight;

        const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@#$%^&*()_+-=[]{}|;:,.<>?';
        const fontSize = 14;
        const columns = canvas.width / fontSize;

        const drops = [];
        for (let i = 0; i < columns; i++) {
            drops[i] = Math.random() * canvas.height / fontSize;
        }

        function drawMatrix() {
            ctx.fillStyle = 'rgba(0, 0, 0, 0.05)';
            ctx.fillRect(0, 0, canvas.width, canvas.height);

            ctx.fillStyle = '#00ff41';
            ctx.font = fontSize + 'px monospace';

            for (let i = 0; i < drops.length; i++) {
                const text = chars[Math.floor(Math.random() * chars.length)];
                ctx.fillText(text, i * fontSize, drops[i] * fontSize);

                if (drops[i] * fontSize > canvas.height && Math.random() > 0.975) {
                    drops[i] = 0;
                }
                drops[i]++;
            }
        }

        setInterval(drawMatrix, 35);

        // Resize canvas on window resize
        window.addEventListener('resize', () => {
            canvas.width = window.innerWidth;
            canvas.height = window.innerHeight;
        });

        // Update timestamp
        function updateTimestamp() {
            const now = new Date();
            const timestamp = now.toISOString().replace('T', ' ').split('.')[0];
            document.getElementById('timestamp').textContent = timestamp;
        }

        // Generate random IP address (for effect)
        function generateRandomIP() {
            return Array.from({length: 4}, () => Math.floor(Math.random() * 256)).join('.');
        }

        document.getElementById('ip-address').textContent = generateRandomIP();
        updateTimestamp();
        setInterval(updateTimestamp, 1000);
    </script>
</body>
</html>
ARTIFACTSEOF

    chown www-data:www-data "$artifacts_index"
    chmod 644 "$artifacts_index"

    log_success "Matrix artifacts page deployed to $artifacts_index"
    log_task_complete
    return 0
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

    # Deploy auth service
    deploy_auth_service || return 1

    # Deploy matrix artifacts page
    deploy_matrix_artifacts_page || return 1

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
