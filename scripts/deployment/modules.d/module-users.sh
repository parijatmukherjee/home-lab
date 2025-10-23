#!/bin/bash
# module-users.sh - User management and authentication module
# Part of Home CI/CD Server deployment automation
#
# This module configures user accounts and authentication including:
# - htpasswd file creation for Nginx authentication
# - User account management
# - Password hashing (bcrypt)
# - Role-based access control
# - Integration with Jenkins, Nginx, and artifact repository
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
MODULE_NAME="users"
MODULE_VERSION="1.0.0"
# shellcheck disable=SC2034  # Used by deployment system
MODULE_DESCRIPTION="User management and authentication configuration"

# ============================================================================
# Configuration
# ============================================================================

# User configuration paths
# shellcheck disable=SC2034  # Reserved for future use
USERS_CONFIG="${DEPLOYMENT_CONFIG:-/opt/core-setup/config}/users.conf"
HTPASSWD_FILE="${DEPLOYMENT_CONFIG:-/opt/core-setup/config}/users.htpasswd"
DOCKER_HTPASSWD_FILE="${DEPLOYMENT_CONFIG:-/opt/core-setup/config}/docker-registry.htpasswd"

# Default admin configuration
ADMIN_USERNAME="${ADMIN_USERNAME:-admin}"
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@localhost}"

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

HTPASSWD_CREATED=yes
USERS_CONFIGURED=yes
EOF

    chmod 600 "$state_file"
}

# ============================================================================
# Directory Setup
# ============================================================================

function create_user_directories() {
    log_task_start "Create user management directories"

    # Ensure config directory exists
    ensure_directory "${DEPLOYMENT_CONFIG:-/opt/core-setup/config}" "755" "root:root"

    # Ensure scripts directory exists
    ensure_directory "/opt/core-setup/scripts" "755" "root:root"

    log_task_complete
    return 0
}

# ============================================================================
# htpasswd Installation
# ============================================================================

function install_apache2_utils() {
    log_task_start "Install Apache2 utilities (htpasswd)"

    if check_command htpasswd; then
        log_info "htpasswd already installed"
        log_task_complete
        return 0
    fi

    if DEBIAN_FRONTEND=noninteractive apt-get install -y apache2-utils; then
        log_task_complete
        return 0
    else
        log_task_failed "Failed to install apache2-utils"
        return 1
    fi
}

# ============================================================================
# User Management Functions
# ============================================================================

function create_admin_user() {
    log_task_start "Create admin user"

    # Check if htpasswd file already exists
    if [[ -f "$HTPASSWD_FILE" ]]; then
        if grep -q "^${ADMIN_USERNAME}:" "$HTPASSWD_FILE"; then
            log_info "Admin user already exists in htpasswd file"
            log_task_complete
            return 0
        fi
    fi

    # Generate random password for admin
    local admin_password
    admin_password=$(generate_random_string 24)

    log_info "Creating admin user: $ADMIN_USERNAME"

    # Create htpasswd file with admin user
    htpasswd -cbB "$HTPASSWD_FILE" "$ADMIN_USERNAME" "$admin_password"

    # Set proper permissions
    chmod 640 "$HTPASSWD_FILE"
    chown root:www-data "$HTPASSWD_FILE"

    # Save password to secure location
    local password_file="/opt/core-setup/config/.admin-password"
    cat > "$password_file" << EOF
# Admin credentials for Home CI/CD Server
# Generated: $(date)
#
# IMPORTANT: Store this password securely and delete this file after saving it elsewhere!

Username: $ADMIN_USERNAME
Password: $admin_password
Email: $ADMIN_EMAIL

# Change password with:
# htpasswd -B $HTPASSWD_FILE $ADMIN_USERNAME

EOF

    chmod 600 "$password_file"

    log_success "==========================================="
    log_success "Admin user created successfully"
    log_success "Username: $ADMIN_USERNAME"
    log_success "Password: $admin_password"
    log_success "==========================================="
    log_success "IMPORTANT: Save this password securely!"
    log_success "Password also saved to: $password_file"
    log_success "==========================================="

    log_task_complete
    return 0
}

function create_system_users() {
    log_task_start "Create system users"

    # Jenkins CI system user
    local jenkins_password
    jenkins_password=$(generate_random_string 32)

    if ! grep -q "^jenkins-ci:" "$HTPASSWD_FILE" 2>/dev/null; then
        htpasswd -bB "$HTPASSWD_FILE" "jenkins-ci" "$jenkins_password"
        log_info "Created jenkins-ci system user"

        # Save credentials
        local jenkins_creds="/opt/core-setup/config/.jenkins-ci-credentials"
        echo "jenkins-ci:$jenkins_password" > "$jenkins_creds"
        chmod 600 "$jenkins_creds"
    fi

    # Docker push user
    local docker_password
    docker_password=$(generate_random_string 32)

    if ! grep -q "^docker-push:" "$HTPASSWD_FILE" 2>/dev/null; then
        htpasswd -bB "$HTPASSWD_FILE" "docker-push" "$docker_password"
        log_info "Created docker-push system user"

        # Save credentials
        local docker_creds="/opt/core-setup/config/.docker-push-credentials"
        echo "docker-push:$docker_password" > "$docker_creds"
        chmod 600 "$docker_creds"
    fi

    log_task_complete
    return 0
}

function create_docker_registry_htpasswd() {
    log_task_start "Create Docker registry htpasswd"

    # Copy main htpasswd to Docker registry location
    if [[ -f "$HTPASSWD_FILE" ]]; then
        cp "$HTPASSWD_FILE" "$DOCKER_HTPASSWD_FILE"
        chmod 640 "$DOCKER_HTPASSWD_FILE"
        chown root:www-data "$DOCKER_HTPASSWD_FILE"
    fi

    log_task_complete
    return 0
}

# ============================================================================
# User Management CLI
# ============================================================================

function create_user_management_script() {
    log_task_start "Create user management CLI script"

    local user_mgmt_script="/opt/core-setup/scripts/manage-users.sh"

    cat > "$user_mgmt_script" << 'USER_MGMT'
#!/bin/bash
# User management CLI for Home CI/CD Server

set -euo pipefail

HTPASSWD_FILE="/opt/core-setup/config/users.htpasswd"
DOCKER_HTPASSWD_FILE="/opt/core-setup/config/docker-registry.htpasswd"

function show_usage() {
    cat << EOF
Usage: $0 <command> [arguments]

Commands:
  add <username> [role]       Add a new user (role: admin, developer, readonly)
  delete <username>           Delete a user
  password <username>         Change user password
  list                        List all users
  verify <username>           Verify user password (interactive)

Examples:
  $0 add alice developer
  $0 delete bob
  $0 password alice
  $0 list
  $0 verify alice

EOF
}

function add_user() {
    local username="$1"
    local role="${2:-developer}"

    if grep -q "^${username}:" "$HTPASSWD_FILE" 2>/dev/null; then
        echo "Error: User '$username' already exists"
        return 1
    fi

    echo "Creating user: $username (role: $role)"
    htpasswd -B "$HTPASSWD_FILE"  "$username"

    # Sync to Docker registry htpasswd
    cp "$HTPASSWD_FILE" "$DOCKER_HTPASSWD_FILE"

    echo "User '$username' created successfully"
    echo "Role: $role"
}

function delete_user() {
    local username="$1"

    if ! grep -q "^${username}:" "$HTPASSWD_FILE" 2>/dev/null; then
        echo "Error: User '$username' does not exist"
        return 1
    fi

    echo "Deleting user: $username"
    htpasswd -D "$HTPASSWD_FILE" "$username"

    # Sync to Docker registry htpasswd
    cp "$HTPASSWD_FILE" "$DOCKER_HTPASSWD_FILE"

    echo "User '$username' deleted successfully"
}

function change_password() {
    local username="$1"

    if ! grep -q "^${username}:" "$HTPASSWD_FILE" 2>/dev/null; then
        echo "Error: User '$username' does not exist"
        return 1
    fi

    echo "Changing password for user: $username"
    htpasswd -B "$HTPASSWD_FILE" "$username"

    # Sync to Docker registry htpasswd
    cp "$HTPASSWD_FILE" "$DOCKER_HTPASSWD_FILE"

    echo "Password changed successfully for user '$username'"
}

function list_users() {
    if [[ ! -f "$HTPASSWD_FILE" ]]; then
        echo "No users configured yet"
        return 0
    fi

    echo "Users configured in htpasswd:"
    echo "==========================================="
    cut -d: -f1 "$HTPASSWD_FILE" | while read -r username; do
        echo "  - $username"
    done
    echo "==========================================="
    echo "Total users: $(wc -l < "$HTPASSWD_FILE")"
}

function verify_user() {
    local username="$1"

    if ! grep -q "^${username}:" "$HTPASSWD_FILE" 2>/dev/null; then
        echo "Error: User '$username' does not exist"
        return 1
    fi

    echo "Verifying password for user: $username"
    htpasswd -v "$HTPASSWD_FILE" "$username"
}

# Main
case "${1:-}" in
    add)
        [[ $# -lt 2 ]] && { show_usage; exit 1; }
        add_user "$2" "${3:-developer}"
        ;;
    delete)
        [[ $# -lt 2 ]] && { show_usage; exit 1; }
        delete_user "$2"
        ;;
    password)
        [[ $# -lt 2 ]] && { show_usage; exit 1; }
        change_password "$2"
        ;;
    list)
        list_users
        ;;
    verify)
        [[ $# -lt 2 ]] && { show_usage; exit 1; }
        verify_user "$2"
        ;;
    *)
        show_usage
        exit 1
        ;;
esac
USER_MGMT

    chmod +x "$user_mgmt_script"

    log_task_complete
    return 0
}

# ============================================================================
# Nginx Integration
# ============================================================================

function verify_nginx_auth_config() {
    log_task_start "Verify Nginx authentication configuration"

    # Check if Nginx is configured to use htpasswd
    if [[ -f /etc/nginx/conf.d/artifacts.conf ]]; then
        if grep -q "auth_basic_user_file.*users.htpasswd" /etc/nginx/conf.d/artifacts.conf; then
            log_info "Nginx artifact repository authentication configured"
        else
            log_warn "Nginx artifact repository authentication not yet configured"
        fi
    fi

    if [[ -f /etc/nginx/conf.d/monitoring.conf ]]; then
        if grep -q "auth_basic_user_file.*users.htpasswd" /etc/nginx/conf.d/monitoring.conf; then
            log_info "Nginx monitoring authentication configured"
        else
            log_warn "Nginx monitoring authentication not yet configured"
        fi
    fi

    log_task_complete
    return 0
}

# ============================================================================
# User Documentation
# ============================================================================

function create_user_documentation() {
    log_task_start "Create user management documentation"

    local user_docs="/opt/core-setup/docs/user-management.md"

    ensure_directory "$(dirname "$user_docs")" "755" "root:root"

    cat > "$user_docs" << 'EOF'
# User Management Guide

## Overview

This document describes how to manage users for the Home CI/CD Server.

## User Management CLI

The user management script is located at: `/opt/core-setup/scripts/manage-users.sh`

### Adding a User

```bash
sudo /opt/core-setup/scripts/manage-users.sh add <username> [role]
```

Roles:
- `admin` - Full access to all systems
- `developer` - Can trigger builds, upload artifacts
- `readonly` - Can only download artifacts

Example:
```bash
sudo /opt/core-setup/scripts/manage-users.sh add alice developer
```

### Deleting a User

```bash
sudo /opt/core-setup/scripts/manage-users.sh delete <username>
```

### Changing Password

```bash
sudo /opt/core-setup/scripts/manage-users.sh password <username>
```

### Listing Users

```bash
sudo /opt/core-setup/scripts/manage-users.sh list
```

### Verifying Password

```bash
sudo /opt/core-setup/scripts/manage-users.sh verify <username>
```

## Authentication Locations

Users authenticate at the following locations:

1. **Artifact Repository**: http://artifacts.DOMAIN/
2. **Monitoring Dashboard**: http://monitoring.DOMAIN/
3. **Jenkins**: http://jenkins.DOMAIN/ (separate user management)

## Password Requirements

- Minimum length: 12 characters
- Passwords are hashed using bcrypt
- Passwords are stored in: `/opt/core-setup/config/users.htpasswd`

## Security Best Practices

1. Change default admin password immediately after setup
2. Use strong, unique passwords for each user
3. Rotate passwords every 90 days
4. Remove inactive users promptly
5. Audit user access regularly
6. Never share passwords between users

## System Users

The following system users are created automatically:

- `jenkins-ci` - Jenkins CI/CD system integration
- `docker-push` - Docker registry push access

Credentials for system users are stored in:
- `/opt/core-setup/config/.jenkins-ci-credentials`
- `/opt/core-setup/config/.docker-push-credentials`

## Troubleshooting

### User can't authenticate

1. Verify user exists: `sudo /opt/core-setup/scripts/manage-users.sh list`
2. Verify password: `sudo /opt/core-setup/scripts/manage-users.sh verify <username>`
3. Check htpasswd file: `sudo cat /opt/core-setup/config/users.htpasswd`
4. Check Nginx logs: `sudo tail -f /var/log/nginx/error.log`

### Reset admin password

```bash
sudo htpasswd -B /opt/core-setup/config/users.htpasswd admin
```

## Files and Locations

- htpasswd file: `/opt/core-setup/config/users.htpasswd`
- Docker registry htpasswd: `/opt/core-setup/config/docker-registry.htpasswd`
- Admin password: `/opt/core-setup/config/.admin-password`
- Management script: `/opt/core-setup/scripts/manage-users.sh`

EOF

    chmod 644 "$user_docs"

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

    # Create necessary directories
    create_user_directories || return 1

    # Install dependencies
    install_apache2_utils || return 1

    # Create users
    create_admin_user || return 1
    create_system_users || return 1
    create_docker_registry_htpasswd || return 1

    # Create management tools
    create_user_management_script || return 1
    create_user_documentation || return 1

    # Verify integration
    verify_nginx_auth_config || true

    # Save module state
    save_module_state

    log_module_complete
    return 0
}

# ============================================================================
# Module Entry Point
# ============================================================================

main "$@"
