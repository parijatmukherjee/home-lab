#!/bin/bash
# common.sh - Shared utility functions for deployment scripts
# Part of Home CI/CD Server deployment automation

set -euo pipefail

# ============================================================================
# Constants
# ============================================================================

# Only set if not already set (avoid readonly variable conflicts)
if [[ -z "${SCRIPT_DIR:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

if [[ -z "${REPO_ROOT:-}" ]]; then
    REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
fi

if [[ -z "${DEPLOYMENT_ROOT:-}" ]]; then
    DEPLOYMENT_ROOT="/opt/core-setup"
fi

if [[ -z "${LOG_DIR:-}" ]]; then
    LOG_DIR="${DEPLOYMENT_ROOT}/logs"
fi

if [[ -z "${CONFIG_DIR:-}" ]]; then
    CONFIG_DIR="${DEPLOYMENT_ROOT}/config"
fi

if [[ -z "${BACKUP_DIR:-}" ]]; then
    BACKUP_DIR="${DEPLOYMENT_ROOT}/backups"
fi

# Colors for output (if terminal supports it)
if [[ -t 1 ]]; then
    COLOR_RESET=${COLOR_RESET:-'\033[0m'}
    COLOR_RED=${COLOR_RED:-'\033[0;31m'}
    COLOR_GREEN=${COLOR_GREEN:-'\033[0;32m'}
    COLOR_YELLOW=${COLOR_YELLOW:-'\033[0;33m'}
    COLOR_BLUE=${COLOR_BLUE:-'\033[0;34m'}
else
    COLOR_RESET=${COLOR_RESET:-''}
    COLOR_RED=${COLOR_RED:-''}
    COLOR_GREEN=${COLOR_GREEN:-''}
    COLOR_YELLOW=${COLOR_YELLOW:-''}
    COLOR_BLUE=${COLOR_BLUE:-''}
fi

# ============================================================================
# Utility Functions
# ============================================================================

# Print colored message
function print_color() {
    local color="$1"
    shift
    echo -e "${color}$*${COLOR_RESET}"
}

# Check if command exists
function check_command() {
    local cmd="$1"
    if command -v "$cmd" &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# Check if running as root
function require_root() {
    if [[ $EUID -ne 0 ]]; then
        print_color "$COLOR_RED" "ERROR: This script must be run as root (use sudo)"
        exit 1
    fi
}

# Check if running as non-root
function require_non_root() {
    if [[ $EUID -eq 0 ]]; then
        print_color "$COLOR_RED" "ERROR: This script should NOT be run as root"
        exit 1
    fi
}

# Ensure directory exists with proper permissions
function ensure_directory() {
    local dir_path="$1"
    local permissions="${2:-755}"
    local owner="${3:-root:root}"

    if [[ ! -d "$dir_path" ]]; then
        mkdir -p "$dir_path"
        chmod "$permissions" "$dir_path"
        chown "$owner" "$dir_path"
    fi
}

# Backup file before modification
function backup_file() {
    local file_path="$1"
    local backup_dir
    backup_dir="${BACKUP_DIR}/config-snapshots/$(date +%Y-%m-%d)"

    if [[ -f "$file_path" ]]; then
        ensure_directory "$backup_dir"
        local filename
        filename="$(basename "$file_path")"
        cp -p "$file_path" "${backup_dir}/${filename}.$(date +%H%M%S)"
        print_color "$COLOR_BLUE" "Backed up: $file_path"
    fi
}

# Copy template and replace placeholders
function install_template() {
    local template_file="$1"
    local dest_file="$2"
    shift 2
    local -a replacements=("$@")

    if [[ ! -f "$template_file" ]]; then
        print_color "$COLOR_RED" "ERROR: Template not found: $template_file"
        return 1
    fi

    # Backup existing file if present
    backup_file "$dest_file"

    # Copy template
    cp "$template_file" "$dest_file"

    # Apply replacements (format: "PLACEHOLDER:value")
    for replacement in "${replacements[@]}"; do
        local placeholder="${replacement%%:*}"
        local value="${replacement#*:}"
        sed -i "s|{{ ${placeholder} }}|${value}|g" "$dest_file"
    done

    print_color "$COLOR_GREEN" "Installed: $dest_file"
}

# Wait for service to be ready
function wait_for_service() {
    local service_name="$1"
    local max_wait="${2:-30}"
    local counter=0

    while [[ $counter -lt $max_wait ]]; do
        if systemctl is-active --quiet "$service_name"; then
            print_color "$COLOR_GREEN" "Service $service_name is ready"
            return 0
        fi
        sleep 1
        ((counter++))
    done

    print_color "$COLOR_RED" "ERROR: Service $service_name failed to start after ${max_wait}s"
    return 1
}

# Check if port is listening
function check_port() {
    local port="$1"
    # shellcheck disable=SC2034  # protocol reserved for future use
    local protocol="${2:-tcp}"

    if ss -tuln | grep -q ":${port} "; then
        return 0
    else
        return 1
    fi
}

# Download file with retry
function download_file() {
    local url="$1"
    local dest="$2"
    local max_retries="${3:-3}"
    local retry=0

    while [[ $retry -lt $max_retries ]]; do
        if curl -sSL -o "$dest" "$url"; then
            print_color "$COLOR_GREEN" "Downloaded: $url"
            return 0
        fi
        ((retry++))
        print_color "$COLOR_YELLOW" "Download failed, retrying ($retry/$max_retries)..."
        sleep 2
    done

    print_color "$COLOR_RED" "ERROR: Failed to download after $max_retries attempts: $url"
    return 1
}

# Generate random string
function generate_random_string() {
    local length="${1:-32}"
    tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$length"
}

# Hash password with bcrypt
function hash_password() {
    local password="$1"
    # Using htpasswd for bcrypt hashing
    echo "$password" | htpasswd -nBi admin | cut -d: -f2
}

# Verify hash matches password
function verify_password_hash() {
    local password="$1"
    local hash="$2"
    # htpasswd verification (returns 0 if match)
    echo "$password" | htpasswd -vb <(echo "user:$hash") user 2>/dev/null
}

# Check if system has minimum requirements
function check_system_requirements() {
    local min_ram_gb=8
    local min_disk_gb=500
    local min_cpu_cores=4

    # Check RAM
    local total_ram_gb
    total_ram_gb=$(free -g | awk '/^Mem:/{print $2}')
    if [[ $total_ram_gb -lt $min_ram_gb ]]; then
        print_color "$COLOR_YELLOW" "WARNING: RAM is ${total_ram_gb}GB, recommended ${min_ram_gb}GB"
    fi

    # Check disk space
    local available_disk_gb
    available_disk_gb=$(df -BG /srv 2>/dev/null | awk 'NR==2{print $4}' | tr -d 'G')
    if [[ ${available_disk_gb:-0} -lt $min_disk_gb ]]; then
        print_color "$COLOR_YELLOW" "WARNING: Disk space is ${available_disk_gb}GB, recommended ${min_disk_gb}GB"
    fi

    # Check CPU cores
    local cpu_cores
    cpu_cores=$(nproc)
    if [[ $cpu_cores -lt $min_cpu_cores ]]; then
        print_color "$COLOR_YELLOW" "WARNING: CPU cores is ${cpu_cores}, recommended ${min_cpu_cores}"
    fi
}

# Ask yes/no question
function ask_yes_no() {
    local question="$1"
    local default="${2:-n}"

    if [[ "$default" == "y" ]]; then
        local prompt="[Y/n]"
    else
        local prompt="[y/N]"
    fi

    while true; do
        read -r -p "$question $prompt " answer
        answer="${answer:-$default}"
        case "${answer,,}" in
            y|yes) return 0 ;;
            n|no) return 1 ;;
            *) echo "Please answer yes or no." ;;
        esac
    done
}

# Prompt for input with default
function prompt_input() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"

    if [[ -n "$default" ]]; then
        read -r -p "$prompt [$default]: " input
        input="${input:-$default}"
    else
        read -r -p "$prompt: " input
    fi

    eval "$var_name=\"$input\""
}

# Validate email address
function validate_email() {
    local email="$1"
    if [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Validate domain name
function validate_domain() {
    local domain="$1"
    if [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 0
    else
        return 1
    fi
}

# Get current timestamp (ISO 8601)
function get_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Calculate duration between two timestamps
function calculate_duration() {
    local start_time="$1"
    local end_time="$2"
    local duration=$((end_time - start_time))
    echo "$duration"
}

# Format duration in human-readable format
function format_duration() {
    local seconds="$1"
    local hours=$((seconds / 3600))
    local minutes=$(((seconds % 3600) / 60))
    local secs=$((seconds % 60))

    if [[ $hours -gt 0 ]]; then
        printf "%dh %dm %ds" "$hours" "$minutes" "$secs"
    elif [[ $minutes -gt 0 ]]; then
        printf "%dm %ds" "$minutes" "$secs"
    else
        printf "%ds" "$secs"
    fi
}

# Cleanup function (call with trap)
function cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        print_color "$COLOR_RED" "Deployment failed with exit code: $exit_code"
    fi
}

# Export functions for use in other scripts
export -f print_color
export -f check_command
export -f require_root
export -f require_non_root
export -f ensure_directory
export -f backup_file
export -f install_template
export -f wait_for_service
export -f check_port
export -f download_file
export -f generate_random_string
export -f hash_password
export -f check_system_requirements
export -f ask_yes_no
export -f prompt_input
export -f validate_email
export -f validate_domain
export -f get_timestamp
export -f calculate_duration
export -f format_duration
export -f cleanup_on_exit
