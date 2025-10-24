#!/bin/bash
# module-jenkins.sh - Jenkins CI/CD server configuration module
# Part of Home CI/CD Server deployment automation
#
# This module configures Jenkins including:
# - Jenkins installation (if not already installed)
# - Jenkins initial setup and configuration
# - Plugin installation
# - Integration with Nginx reverse proxy
# - Webhook configuration for GitHub/GitLab
# - Build environment setup
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
MODULE_NAME="jenkins"
MODULE_VERSION="1.0.0"
# shellcheck disable=SC2034  # Used by deployment system
MODULE_DESCRIPTION="Jenkins CI/CD server configuration"

# ============================================================================
# Configuration
# ============================================================================

# Jenkins paths
JENKINS_HOME="${JENKINS_HOME:-/var/lib/jenkins}"
JENKINS_PORT="${JENKINS_PORT:-8080}"
JENKINS_USER="jenkins"

# Jenkins configuration
JENKINS_JAVA_OPTIONS="${JENKINS_JAVA_OPTIONS:--Xmx2048m -Djava.awt.headless=true}"
JENKINS_PLUGINS="${JENKINS_PLUGINS:-git,github,gitlab-plugin,docker-workflow,workflow-aggregator,credentials-binding}"

# Domain configuration
DOMAIN_NAME="${DOMAIN_NAME:-core.mohjave.com}"
JENKINS_URL="http://jenkins.${DOMAIN_NAME}"

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

JENKINS_INSTALLED=yes
JENKINS_CONFIGURED=yes
PLUGINS_INSTALLED=yes
EOF

    chmod 600 "$state_file"
}

# ============================================================================
# Java Installation
# ============================================================================

function install_java() {
    log_task_start "Install Java (OpenJDK 21)"

    # Check if Java is already installed
    if check_command java; then
        local java_version
        java_version=$(java -version 2>&1 | head -n 1)
        log_info "Java already installed: $java_version"
        log_task_complete
        return 0
    fi

    # Install fontconfig and OpenJDK 21 as per official Jenkins docs
    log_info "Installing Java (OpenJDK 21) and fontconfig..."
    if DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Progress-Fancy="1" fontconfig openjdk-21-jre 2>&1 | \
        grep --line-buffered -E "Get:|Unpacking|Setting up|Progress:" || \
        DEBIAN_FRONTEND=noninteractive apt-get install -y fontconfig openjdk-21-jre; then
        log_success "Java installed successfully"
        log_task_complete
        return 0
    else
        log_task_failed "Failed to install Java"
        return 1
    fi
}

# ============================================================================
# Jenkins Installation
# ============================================================================

function add_jenkins_repository() {
    log_task_start "Add Jenkins repository"

    # Ensure keyrings directory exists
    if [[ ! -d /etc/apt/keyrings ]]; then
        log_info "Creating /etc/apt/keyrings directory..."
        mkdir -p /etc/apt/keyrings
        chmod 755 /etc/apt/keyrings
    fi

    # Add Jenkins GPG key with retry logic using wget (official method)
    if [[ ! -f /etc/apt/keyrings/jenkins-keyring.asc ]]; then
        log_info "Downloading Jenkins GPG key..."
        local retries=3
        local count=0
        while [[ $count -lt $retries ]]; do
            if wget -O /etc/apt/keyrings/jenkins-keyring.asc https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key && \
                [[ -s /etc/apt/keyrings/jenkins-keyring.asc ]]; then
                log_success "Jenkins GPG key downloaded successfully"
                break
            else
                ((count++))
                if [[ $count -lt $retries ]]; then
                    log_warn "Failed to download GPG key, retrying ($count/$retries)..."
                    rm -f /etc/apt/keyrings/jenkins-keyring.asc
                    sleep 5
                else
                    log_task_failed "Failed to download Jenkins GPG key after $retries attempts"
                    return 1
                fi
            fi
        done
    else
        log_info "Jenkins GPG key already exists"
    fi

    # Verify the key file is not empty
    if [[ ! -s /etc/apt/keyrings/jenkins-keyring.asc ]]; then
        log_task_failed "Jenkins GPG key file is empty"
        return 1
    fi

    # Add Jenkins repository with official path
    if [[ ! -f /etc/apt/sources.list.d/jenkins.list ]]; then
        log_info "Adding Jenkins repository..."
        echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" | \
            tee /etc/apt/sources.list.d/jenkins.list > /dev/null
    else
        log_info "Jenkins repository already configured"
    fi

    # Update package lists with retry logic
    log_info "Updating package lists..."
    local retries=3
    local count=0
    while [[ $count -lt $retries ]]; do
        if apt-get update 2>&1 | tee /tmp/apt-update.log; then
            # Check if the update succeeded for Jenkins repository
            if grep -qi "jenkins" /tmp/apt-update.log && ! grep -qi "error.*jenkins" /tmp/apt-update.log; then
                log_success "Package lists updated successfully"
                rm -f /tmp/apt-update.log
                break
            fi
        fi
        ((count++))
        if [[ $count -lt $retries ]]; then
            log_warn "Package update failed, retrying ($count/$retries)..."
            sleep 5
        else
            log_warn "Package update completed with warnings (continuing)"
            rm -f /tmp/apt-update.log
            break
        fi
    done

    log_task_complete
    return 0
}

function install_jenkins() {
    log_task_start "Install Jenkins"

    # Check if Jenkins is already installed
    if check_command jenkins; then
        log_info "Jenkins already installed"
        log_task_complete
        return 0
    fi

    # Verify Jenkins package is available
    log_info "Verifying Jenkins package availability..."
    local jenkins_candidate
    jenkins_candidate=$(apt-cache policy jenkins | grep "Candidate:" | awk '{print $2}')

    if [[ -z "$jenkins_candidate" ]] || [[ "$jenkins_candidate" == "(none)" ]]; then
        log_error "Jenkins package is not available in configured repositories"
        log_info "Checking apt-cache policy output for debugging:"
        apt-cache policy jenkins 2>&1 | head -20
        log_task_failed "Jenkins package not available"
        return 1
    fi

    log_info "Jenkins package candidate version: $jenkins_candidate"

    # Install Jenkins with progress output and retry logic
    log_info "Downloading Jenkins (this may take a minute for ~95MB)..."

    local retries=2
    local count=0
    while [[ $count -lt $retries ]]; do
        # Show download progress by filtering apt-get output
        if DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Progress-Fancy="1" jenkins 2>&1 | \
            grep --line-buffered -E "Get:|Fetched|Unpacking|Setting up|Progress:|%|MB"; then
            log_success "Jenkins installed successfully"
            log_task_complete
            return 0
        fi

        ((count++))
        if [[ $count -lt $retries ]]; then
            log_warn "Jenkins installation failed, retrying ($count/$retries)..."
            sleep 5
        else
            # Try one more time without fancy output
            log_info "Trying installation without progress output..."
            if DEBIAN_FRONTEND=noninteractive apt-get install -y jenkins; then
                log_success "Jenkins installed successfully"
                log_task_complete
                return 0
            else
                log_task_failed "Failed to install Jenkins after $retries attempts"
                return 1
            fi
        fi
    done

    log_task_failed "Failed to install Jenkins"
    return 1
}

function ensure_jenkins_user() {
    log_task_start "Ensure Jenkins user exists"

    # Check if jenkins user already exists
    if id -u jenkins >/dev/null 2>&1; then
        log_info "Jenkins user already exists"

        # Ensure directories have correct ownership
        if [[ -d "$JENKINS_HOME" ]]; then
            chown -R jenkins:jenkins "$JENKINS_HOME"
        fi
        if [[ -d "/var/cache/jenkins" ]]; then
            chown -R jenkins:jenkins "/var/cache/jenkins"
        fi

        log_task_complete
        return 0
    fi

    log_warn "Jenkins user missing (likely after cleanup) - reinstalling Jenkins to fix"

    # If user doesn't exist but Jenkins is installed, the installation is corrupted
    # Best solution is to purge and reinstall
    if check_command jenkins; then
        log_info "Purging corrupted Jenkins installation..."
        DEBIAN_FRONTEND=noninteractive apt-get purge -y jenkins >/dev/null 2>&1 || true

        log_info "Reinstalling Jenkins..."
        if DEBIAN_FRONTEND=noninteractive apt-get install -y jenkins; then
            log_success "Jenkins reinstalled successfully"
        else
            log_task_failed "Failed to reinstall Jenkins"
            return 1
        fi
    fi

    # Verify user was created by package installation
    if ! id -u jenkins >/dev/null 2>&1; then
        log_error "Jenkins user still doesn't exist after reinstallation"
        log_task_failed "Failed to create Jenkins user"
        return 1
    fi

    # Ensure directories have correct ownership
    if [[ -d "$JENKINS_HOME" ]]; then
        chown -R jenkins:jenkins "$JENKINS_HOME"
        chmod 755 "$JENKINS_HOME"
    fi
    if [[ -d "/var/cache/jenkins" ]]; then
        chown -R jenkins:jenkins "/var/cache/jenkins"
    fi

    log_success "Jenkins user verified"
    log_task_complete
    return 0
}

# ============================================================================
# Jenkins Configuration
# ============================================================================

function configure_jenkins_defaults() {
    log_task_start "Configure Jenkins defaults"

    local jenkins_defaults="/etc/default/jenkins"

    if [[ ! -f "$jenkins_defaults" ]]; then
        log_warn "Jenkins defaults file not found, creating new one"
        touch "$jenkins_defaults"
    fi

    backup_file "$jenkins_defaults"

    # Configure Jenkins environment
    cat > "$jenkins_defaults" << EOF
# Home CI/CD Server - Jenkins Configuration

# Jenkins home directory
JENKINS_HOME=${JENKINS_HOME}

# Jenkins user
JENKINS_USER=${JENKINS_USER}

# Port Jenkins listens on
HTTP_PORT=${JENKINS_PORT}

# Java options
JAVA_ARGS="${JENKINS_JAVA_OPTIONS}"

# Jenkins arguments
JENKINS_ARGS="--webroot=/var/cache/\$NAME/war --httpPort=\$HTTP_PORT"

# Prefix for Jenkins URL (for reverse proxy)
# This will be set after SSL is configured
# JENKINS_ARGS="\$JENKINS_ARGS --prefix=/jenkins"
EOF

    log_task_complete
    return 0
}

function configure_jenkins_systemd() {
    log_task_start "Configure Jenkins systemd service"

    local systemd_override="/etc/systemd/system/jenkins.service.d/override.conf"

    ensure_directory "$(dirname "$systemd_override")" "755" "root:root"

    cat > "$systemd_override" << EOF
[Service]
# Increase timeout for Jenkins startup
TimeoutStartSec=300

# Environment variables
Environment="JENKINS_HOME=${JENKINS_HOME}"
Environment="JAVA_OPTS=${JENKINS_JAVA_OPTIONS}"

# Restart policy
Restart=on-failure
RestartSec=10
EOF

    # Reload systemd
    systemctl daemon-reload

    log_task_complete
    return 0
}

function configure_jenkins_url() {
    log_task_start "Configure Jenkins URL"

    local jenkins_location="${JENKINS_HOME}/jenkins.model.JenkinsLocationConfiguration.xml"

    # Wait for Jenkins to create the file first
    if [[ -f "$jenkins_location" ]]; then
        backup_file "$jenkins_location"

        # Update Jenkins URL
        cat > "$jenkins_location" << EOF
<?xml version='1.1' encoding='UTF-8'?>
<jenkins.model.JenkinsLocationConfiguration>
  <adminAddress>admin@${DOMAIN_NAME}</adminAddress>
  <jenkinsUrl>${JENKINS_URL}/</jenkinsUrl>
</jenkins.model.JenkinsLocationConfiguration>
EOF

        chown jenkins:jenkins "$jenkins_location"
    else
        log_info "Jenkins location config not yet created (will be set on first run)"
    fi

    log_task_complete
    return 0
}

# ============================================================================
# Jenkins Security Configuration
# ============================================================================

function configure_jenkins_security() {
    log_task_start "Configure Jenkins security"

    # shellcheck disable=SC2034  # Variable reserved for future use
    local security_realm="${JENKINS_HOME}/config.xml"

    # This will be configured after Jenkins first start
    # For now, we'll create a placeholder configuration

    log_info "Jenkins security will be configured on first run"
    log_info "Initial admin password will be available at: ${JENKINS_HOME}/secrets/initialAdminPassword"

    log_task_complete
    return 0
}

function disable_jenkins_setup_wizard() {
    log_task_start "Configure Jenkins setup wizard"

    local jenkins_config="${JENKINS_HOME}/jenkins.install.UpgradeWizard.state"

    # Skip the setup wizard (plugins will be installed via script)
    echo "2.0" > "$jenkins_config"
    chown jenkins:jenkins "$jenkins_config"

    # Disable install wizard
    local install_state="${JENKINS_HOME}/jenkins.install.InstallUtil.lastExecVersion"
    echo "2.0" > "$install_state"
    chown jenkins:jenkins "$install_state"

    log_task_complete
    return 0
}

# ============================================================================
# Jenkins Plugin Management
# ============================================================================

function install_jenkins_plugin_manager() {
    log_task_start "Install Jenkins Plugin Manager CLI"

    local plugin_manager_jar="${JENKINS_HOME}/jenkins-plugin-manager.jar"

    # Download Jenkins Plugin Manager
    if [[ ! -f "$plugin_manager_jar" ]]; then
        local plugin_manager_url="https://github.com/jenkinsci/plugin-installation-manager-tool/releases/latest/download/jenkins-plugin-manager-2.12.13.jar"

        if download_file "$plugin_manager_url" "$plugin_manager_jar"; then
            chown jenkins:jenkins "$plugin_manager_jar"
            log_task_complete
            return 0
        else
            log_task_failed "Failed to download Jenkins Plugin Manager"
            return 1
        fi
    else
        log_info "Jenkins Plugin Manager already installed"
        log_task_complete
        return 0
    fi
}

function install_jenkins_plugins() {
    log_task_start "Install Jenkins plugins"

    # Ensure Jenkins is stopped before plugin installation
    if systemctl is-active --quiet jenkins; then
        systemctl stop jenkins
        sleep 5
    fi

    # Create plugins directory
    ensure_directory "${JENKINS_HOME}/plugins" "755" "jenkins:jenkins"

    # Install plugins using plugin manager
    local plugin_list="/tmp/jenkins-plugins.txt"

    # Convert comma-separated list to newline-separated
    echo "$JENKINS_PLUGINS" | tr ',' '\n' > "$plugin_list"

    log_info "Installing Jenkins plugins: $JENKINS_PLUGINS"

    # Install plugins (this may take a while)
    if sudo -u jenkins java -jar "${JENKINS_HOME}/jenkins-plugin-manager.jar" \
        --war /usr/share/java/jenkins.war \
        --plugin-download-directory "${JENKINS_HOME}/plugins" \
        --plugin-file "$plugin_list" \
        --verbose; then

        log_success "Jenkins plugins installed successfully"
        rm -f "$plugin_list"
        log_task_complete
        return 0
    else
        log_warn "Some plugins may have failed to install (continuing anyway)"
        rm -f "$plugin_list"
        log_task_complete
        return 0
    fi
}

# ============================================================================
# Jenkins Build Environment
# ============================================================================

function configure_build_tools() {
    log_task_start "Configure build tools"

    # Install common build tools
    local build_packages=(
        "build-essential"
        "git"
        "maven"
        "gradle"
        "python3"
        "python3-pip"
        "nodejs"
        "npm"
        "docker.io"
    )

    local missing_packages=()
    for package in "${build_packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package "; then
            missing_packages+=("$package")
        fi
    done

    if [[ ${#missing_packages[@]} -gt 0 ]]; then
        log_info "Installing build tools: ${missing_packages[*]}"
        DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing_packages[@]}" || \
            log_warn "Some build tools failed to install (continuing)"
    else
        log_info "All build tools already installed"
    fi

    # Add jenkins user to docker group
    if check_command docker; then
        usermod -aG docker jenkins || log_warn "Failed to add jenkins to docker group"
    fi

    log_task_complete
    return 0
}

function create_jenkins_workspace() {
    log_task_start "Create Jenkins workspace structure"

    # Ensure workspace directory exists
    ensure_directory "${JENKINS_HOME}/workspace" "755" "jenkins:jenkins"

    # Create logs directory
    ensure_directory "/var/log/jenkins" "755" "jenkins:jenkins"

    # Create cache directory
    ensure_directory "/var/cache/jenkins" "755" "jenkins:jenkins"

    log_task_complete
    return 0
}

# ============================================================================
# Jenkins Service Management
# ============================================================================

function start_jenkins() {
    log_task_start "Start Jenkins service"

    # Enable Jenkins to start on boot
    systemctl enable jenkins

    # Start Jenkins (with detailed error logging)
    log_info "Attempting to start Jenkins..."
    if ! systemctl start jenkins; then
        log_warn "Initial Jenkins start failed, checking status..."
        systemctl status jenkins --no-pager || true
        log_warn "Checking Jenkins logs..."
        journalctl -xeu jenkins.service --no-pager -n 50 || true

        # Try to start again after a brief delay
        log_info "Waiting 5 seconds and retrying..."
        sleep 5
        if ! systemctl start jenkins; then
            log_error "Jenkins failed to start after retry"
            log_task_failed "Failed to start Jenkins"
            return 1
        fi
    fi

    log_info "Waiting for Jenkins to start (this may take 1-2 minutes)..."

    # Wait for Jenkins to be fully ready
    local max_wait=180
    local counter=0
    while [[ $counter -lt $max_wait ]]; do
        if systemctl is-active --quiet jenkins; then
            # Check if Jenkins is responding
            if curl -s -o /dev/null -w "%{http_code}" "http://localhost:${JENKINS_PORT}" | grep -q "403\|200"; then
                log_success "Jenkins started successfully"
                log_task_complete
                return 0
            fi
        fi
        sleep 3
        ((counter+=3))
    done

    log_warn "Jenkins may not be fully ready yet (continuing)"
    log_task_complete
    return 0
}

function get_initial_admin_password() {
    log_task_start "Get initial admin password"

    local password_file="${JENKINS_HOME}/secrets/initialAdminPassword"

    if [[ -f "$password_file" ]]; then
        local admin_password
        admin_password=$(cat "$password_file")

        log_success "==========================================="
        log_success "Jenkins Initial Admin Password:"
        log_success "$admin_password"
        log_success "==========================================="
        log_success "Save this password! You'll need it to complete Jenkins setup."
        log_success "Access Jenkins at: ${JENKINS_URL}"
        log_success "==========================================="

        # Save to secure location
        local password_backup="/opt/core-setup/config/.jenkins-initial-password"
        echo "$admin_password" > "$password_backup"
        chmod 600 "$password_backup"
        log_info "Password also saved to: $password_backup"
    else
        log_warn "Initial admin password file not found yet (Jenkins may still be starting)"
    fi

    log_task_complete
    return 0
}

# ============================================================================
# Post-Installation Configuration
# ============================================================================

function create_jenkins_webhook_script() {
    log_task_start "Create Jenkins webhook helper script"

    local webhook_script="/opt/core-setup/scripts/jenkins-webhook.sh"

    cat > "$webhook_script" << 'WEBHOOK_SCRIPT'
#!/bin/bash
# Jenkins webhook configuration helper
# This script helps configure webhooks for GitHub/GitLab

set -euo pipefail

JENKINS_URL="${1:-http://localhost:8080}"
PROJECT_NAME="${2:-}"

if [[ -z "$PROJECT_NAME" ]]; then
    echo "Usage: $0 <jenkins-url> <project-name>"
    echo "Example: $0 http://jenkins.core.mohjave.com my-project"
    exit 1
fi

echo "==========================================="
echo "Jenkins Webhook Configuration"
echo "==========================================="
echo ""
echo "GitHub Webhook URL:"
echo "${JENKINS_URL}/github-webhook/"
echo ""
echo "GitLab Webhook URL:"
echo "${JENKINS_URL}/project/${PROJECT_NAME}"
echo ""
echo "Webhook Events to Enable:"
echo "  - Push events"
echo "  - Pull request events (GitHub)"
echo "  - Merge request events (GitLab)"
echo ""
echo "==========================================="
WEBHOOK_SCRIPT

    chmod +x "$webhook_script"

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

    # Install dependencies
    install_java || return 1

    # Install Jenkins
    add_jenkins_repository || return 1
    install_jenkins || return 1
    ensure_jenkins_user || return 1

    # Configure Jenkins
    configure_jenkins_defaults || return 1
    configure_jenkins_systemd || return 1
    disable_jenkins_setup_wizard || return 1
    create_jenkins_workspace || return 1

    # Install plugins
    install_jenkins_plugin_manager || return 1
    install_jenkins_plugins || return 1

    # Configure build environment
    configure_build_tools || return 1

    # Start Jenkins
    start_jenkins || return 1

    # Post-installation
    get_initial_admin_password || true
    configure_jenkins_url || true
    create_jenkins_webhook_script || return 1

    # Save module state
    save_module_state

    log_module_complete
    return 0
}

# ============================================================================
# Module Entry Point
# ============================================================================

main "$@"
