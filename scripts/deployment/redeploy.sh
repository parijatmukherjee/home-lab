#!/bin/bash
# redeploy.sh - Master orchestration script for Home CI/CD Server deployment
# Part of Home CI/CD Server deployment automation
#
# This script orchestrates the complete deployment of the home CI/CD server,
# including all services, configurations, and security measures.
#
# Usage:
#   sudo ./redeploy.sh [options]
#
# Options:
#   --full                 Full deployment (all modules)
#   --modules <list>       Deploy specific modules (comma-separated)
#   --skip <list>          Skip specific modules (comma-separated)
#   --dry-run              Show what would be done without executing
#   --force                Force deployment even with warnings
#   --skip-validation      Skip pre-deployment validation checks (for testing)
#   --config <file>        Use custom configuration file
#   --help                 Show this help message
#
# Examples:
#   sudo ./redeploy.sh --full
#   sudo ./redeploy.sh --modules base-system,firewall,nginx
#   sudo ./redeploy.sh --skip backup,monitoring --force
#
# Exit codes:
#   0 - Success
#   1 - General error
#   2 - Prerequisite check failed
#   3 - User aborted
#   4 - Module execution failed

set -euo pipefail

# ============================================================================
# Script Initialization
# ============================================================================

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source library functions
# shellcheck source=./lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=./lib/logging.sh
source "$SCRIPT_DIR/lib/logging.sh"
# shellcheck source=./lib/validation.sh
source "$SCRIPT_DIR/lib/validation.sh"

# Initialize logging
init_logging

# Trap errors and cleanup
trap cleanup_on_exit EXIT
trap 'log_task_failed "Interrupted by user"' INT TERM

# ============================================================================
# Configuration
# ============================================================================

# Deployment configuration file
DEFAULT_CONFIG_FILE="$SCRIPT_DIR/config/deployment.conf"
CONFIG_FILE="${DEFAULT_CONFIG_FILE}"

# Module directory
MODULES_DIR="$SCRIPT_DIR/modules.d"

# Deployment options (set via command line)
DEPLOYMENT_MODE="full"
SELECTED_MODULES=""
SKIP_MODULES=""
DRY_RUN=false
FORCE_DEPLOY=false
SKIP_VALIDATION=false

# Available modules (in dependency order)
ALL_MODULES=(
    "base-system"
    "firewall"
    "users"
    "nginx"
    "netdata"
    "jenkins"
    "artifact-storage"
)

# Module dependencies (module:dependency1,dependency2,...)
declare -A MODULE_DEPS=(
    ["base-system"]=""
    ["firewall"]="base-system"
    ["users"]="base-system"
    ["nginx"]="base-system,firewall"
    ["netdata"]="base-system"
    ["jenkins"]="base-system,firewall,users"
    ["artifact-storage"]="base-system,nginx,users"
)

# ============================================================================
# Helper Functions
# ============================================================================

# Print usage information
function show_usage() {
    cat << EOF
Usage: sudo ./redeploy.sh [options]

Master orchestration script for Home CI/CD Server deployment.

Options:
  --full                 Full deployment (all modules)
  --modules <list>       Deploy specific modules (comma-separated)
  --skip <list>          Skip specific modules (comma-separated)
  --dry-run              Show what would be done without executing
  --force                Force deployment even with warnings
  --skip-validation      Skip pre-deployment validation checks (for testing)
  --config <file>        Use custom configuration file
  --help                 Show this help message

Available modules:
$(printf "  - %s\n" "${ALL_MODULES[@]}")

Examples:
  # Full deployment
  sudo ./redeploy.sh --full

  # Deploy specific modules
  sudo ./redeploy.sh --modules base-system,firewall,nginx

  # Deploy all except backup and monitoring
  sudo ./redeploy.sh --skip backup,monitoring

  # Dry run to see what would happen
  sudo ./redeploy.sh --full --dry-run

  # Force deployment (skip confirmation prompts)
  sudo ./redeploy.sh --full --force

Exit codes:
  0 - Success
  1 - General error
  2 - Prerequisite check failed
  3 - User aborted
  4 - Module execution failed

For more information, see: $REPO_ROOT/README.md
EOF
}

# Parse command line arguments
function parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --full)
                DEPLOYMENT_MODE="full"
                shift
                ;;
            --modules)
                DEPLOYMENT_MODE="selected"
                SELECTED_MODULES="$2"
                shift 2
                ;;
            --skip)
                SKIP_MODULES="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE_DEPLOY=true
                shift
                ;;
            --skip-validation)
                SKIP_VALIDATION=true
                shift
                ;;
            --config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Load deployment configuration
function load_configuration() {
    if [[ -f "$CONFIG_FILE" ]]; then
        log_info "Loading configuration from: $CONFIG_FILE"
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
    else
        log_warn "Configuration file not found: $CONFIG_FILE"
        log_warn "Using default configuration"
    fi
}

# Get list of modules to deploy
function get_deployment_modules() {
    local modules=()

    if [[ "$DEPLOYMENT_MODE" == "full" ]]; then
        modules=("${ALL_MODULES[@]}")
    elif [[ "$DEPLOYMENT_MODE" == "selected" ]]; then
        IFS=',' read -ra modules <<< "$SELECTED_MODULES"
    fi

    # Remove skipped modules
    if [[ -n "$SKIP_MODULES" ]]; then
        IFS=',' read -ra skip_list <<< "$SKIP_MODULES"
        for skip_module in "${skip_list[@]}"; do
            modules=("${modules[@]/$skip_module}")
        done
    fi

    # Print module list
    echo "${modules[@]}"
}

# Check module dependencies
function check_module_dependencies() {
    local module="$1"
    local deps="${MODULE_DEPS[$module]}"

    if [[ -z "$deps" ]]; then
        return 0
    fi

    IFS=',' read -ra dep_list <<< "$deps"
    for dep in "${dep_list[@]}"; do
        if [[ ! -f "${MODULES_DIR}/module-${dep}.sh" ]]; then
            log_error "Missing dependency for module '$module': $dep"
            return 1
        fi
    done

    return 0
}

# Execute a deployment module
function execute_module() {
    local module_name="$1"
    local module_script="${MODULES_DIR}/module-${module_name}.sh"

    log_module_start "$module_name"

    # Check if module script exists
    if [[ ! -f "$module_script" ]]; then
        log_module_failed "$module_name" "Module script not found: $module_script"
        return 1
    fi

    # Check dependencies
    if ! check_module_dependencies "$module_name"; then
        log_module_failed "$module_name" "Dependency check failed"
        return 1
    fi

    # Execute module
    if [[ "$DRY_RUN" == true ]]; then
        log_info "DRY RUN: Would execute module: $module_name"
        log_module_complete
        return 0
    fi

    # Execute module script
    if bash "$module_script"; then
        log_module_complete
        log_change "MODULE_DEPLOYED" "$module_name"
        return 0
    else
        log_module_failed "$module_name" "Module execution failed (exit code: $?)"
        return 1
    fi
}

# Pre-deployment checks
function pre_deployment_checks() {
    log_task_start "Pre-deployment checks"

    # Check if running as root
    require_root

    if [[ "$SKIP_VALIDATION" == true ]]; then
        log_warn "Skipping validation checks (--skip-validation flag set)"
        log_task_complete
        return 0
    fi

    # Validate OS
    if ! validate_os; then
        log_task_failed "OS validation failed"
        return 2
    fi

    # Check internet connectivity
    if ! validate_internet; then
        log_task_failed "Internet connectivity check failed"
        return 2
    fi

    # Check DNS resolution
    if ! validate_dns; then
        log_task_failed "DNS resolution check failed"
        return 2
    fi

    # Check required commands
    if ! validate_required_commands; then
        log_task_failed "Required commands check failed"
        return 2
    fi

    # Check system requirements
    check_system_requirements

    log_task_complete
    return 0
}

# Deployment summary
function show_deployment_summary() {
    local modules=("$@")

    log_info "=========================================="
    log_info "Deployment Summary"
    log_info "=========================================="
    log_info "Deployment mode: $DEPLOYMENT_MODE"
    log_info "Configuration file: $CONFIG_FILE"
    log_info "Dry run: $DRY_RUN"
    log_info "Force deploy: $FORCE_DEPLOY"
    log_info "=========================================="
    log_info "Modules to deploy:"
    for module in "${modules[@]}"; do
        if [[ -n "$module" ]]; then
            log_info "  - $module"
        fi
    done
    log_info "=========================================="

    # Confirm deployment
    if [[ "$FORCE_DEPLOY" == false && "$DRY_RUN" == false ]]; then
        echo ""
        if ! ask_yes_no "Proceed with deployment?" "n"; then
            log_warn "Deployment aborted by user"
            exit 3
        fi
    fi
}

# Post-deployment validation
function post_deployment_validation() {
    log_task_start "Post-deployment validation"

    # Run complete system validation
    if validate_all; then
        log_task_complete
        return 0
    else
        log_warn "Some validation checks failed (see above)"
        log_task_complete
        return 0
    fi
}

# Generate deployment report
function generate_deployment_report() {
    local start_time="$1"
    local end_time="$2"
    local status="$3"
    local report_file
    report_file="${LOG_DIR}/deployment-report-$(date +%Y-%m-%d-%H%M%S).txt"
    local current_user="${SUDO_USER:-${USER:-$(whoami)}}"

    cat > "$report_file" << EOF
========================================
Home CI/CD Server Deployment Report
========================================

Deployment Date: $(date)
Deployment User: $current_user
Hostname: $(hostname)

Deployment Status: $status
Start Time: $(date -d "@$start_time")
End Time: $(date -d "@$end_time")
Duration: $(format_duration $((end_time - start_time)))

Configuration:
  - Mode: $DEPLOYMENT_MODE
  - Config File: $CONFIG_FILE
  - Dry Run: $DRY_RUN
  - Force: $FORCE_DEPLOY

Modules Deployed:
$(get_deployment_modules | tr ' ' '\n' | sed 's/^/  - /')

Logs:
  - Deployment Log: $DEPLOYMENT_LOG
  - Change History: $CHANGE_HISTORY_LOG

========================================

For detailed logs, see: $DEPLOYMENT_LOG

EOF

    log_info "Deployment report generated: $report_file"
}

# ============================================================================
# Main Deployment Flow
# ============================================================================

function main() {
    local start_time
    local end_time
    local deployment_status="SUCCESS"

    # Parse command line arguments
    parse_arguments "$@"

    # Start deployment logging
    start_time=$(date +%s)
    log_deployment_start "$DEPLOYMENT_MODE"

    # Load configuration
    load_configuration

    # Get modules to deploy
    local modules
    read -ra modules <<< "$(get_deployment_modules)"

    # Show deployment summary
    show_deployment_summary "${modules[@]}"

    # Pre-deployment checks
    if ! pre_deployment_checks; then
        log_deployment_failed "Pre-deployment checks failed"
        exit 2
    fi

    # Execute modules
    local failed_modules=()
    for module in "${modules[@]}"; do
        if [[ -n "$module" ]]; then
            if ! execute_module "$module"; then
                failed_modules+=("$module")
                deployment_status="FAILED"

                # Abort on first failure unless forced
                if [[ "$FORCE_DEPLOY" == false ]]; then
                    log_error "Module '$module' failed, aborting deployment"
                    log_deployment_failed "Module execution failed: $module"
                    exit 4
                fi
            fi
        fi
    done

    # Post-deployment validation
    post_deployment_validation || true

    # End deployment logging
    end_time=$(date +%s)

    if [[ ${#failed_modules[@]} -eq 0 ]]; then
        log_deployment_complete
    else
        log_error "Deployment completed with failures:"
        for failed_module in "${failed_modules[@]}"; do
            log_error "  - $failed_module"
        done
        deployment_status="PARTIAL"
    fi

    # Generate deployment report
    generate_deployment_report "$start_time" "$end_time" "$deployment_status"

    # Exit with appropriate code
    if [[ ${#failed_modules[@]} -eq 0 ]]; then
        exit 0
    else
        exit 4
    fi
}

# ============================================================================
# Script Entry Point
# ============================================================================

main "$@"
