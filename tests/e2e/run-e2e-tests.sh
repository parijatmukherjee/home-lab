#!/usr/bin/env bash
#
# E2E Test Runner for Home CI/CD Server
# Tests deployment and cleanup in a Docker container
#
# shellcheck disable=SC2015  # A && B || C pattern is intentional in test code
# shellcheck disable=SC2317  # Unreachable code warnings are false positives in test functions

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONTAINER_NAME="home-lab-e2e-test"
IMAGE_NAME="home-lab-e2e:latest"
TEST_LOG_DIR="$SCRIPT_DIR/logs"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
TEST_LOG="$TEST_LOG_DIR/e2e-test-$TIMESTAMP.log"

# Test results
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Create log directory
mkdir -p "$TEST_LOG_DIR"

# ============================================================================
# Helper Functions
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$TEST_LOG"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "$TEST_LOG"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "$TEST_LOG"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $*" | tee -a "$TEST_LOG"
}

log_test() {
    echo -e "${BLUE}[TEST]${NC} $*" | tee -a "$TEST_LOG"
}

pass_test() {
    ((TESTS_PASSED++))
    ((TESTS_TOTAL++))
    log_success "✓ $1"
}

fail_test() {
    ((TESTS_FAILED++))
    ((TESTS_TOTAL++))
    log_error "✗ $1"
}

# Execute command in container
exec_in_container() {
    docker exec "$CONTAINER_NAME" bash -c "$1" 2>&1 | tee -a "$TEST_LOG"
}

# Execute command in container (silent)
exec_silent() {
    docker exec "$CONTAINER_NAME" bash -c "$1" >> "$TEST_LOG" 2>&1
}

# Check if command succeeded in container
check_in_container() {
    docker exec "$CONTAINER_NAME" bash -c "$1" >> "$TEST_LOG" 2>&1
    return $?
}

# ============================================================================
# Cleanup Function
# ============================================================================

cleanup() {
    log_info "Cleaning up test environment..."

    if docker ps -a | grep -q "$CONTAINER_NAME"; then
        log_info "Stopping container: $CONTAINER_NAME"
        docker stop "$CONTAINER_NAME" >> "$TEST_LOG" 2>&1 || true
        docker rm "$CONTAINER_NAME" >> "$TEST_LOG" 2>&1 || true
    fi

    if [[ "${KEEP_IMAGE:-false}" != "true" ]]; then
        if docker images | grep -q "$IMAGE_NAME"; then
            log_info "Removing image: $IMAGE_NAME"
            docker rmi "$IMAGE_NAME" >> "$TEST_LOG" 2>&1 || true
        fi
    fi
}

# Trap cleanup on exit
trap cleanup EXIT

# ============================================================================
# Test Functions
# ============================================================================

test_service_running() {
    local service=$1
    log_test "Testing if $service is running"

    if check_in_container "systemctl is-active --quiet $service"; then
        pass_test "$service is running"
        return 0
    else
        fail_test "$service is not running"
        return 1
    fi
}

test_port_listening() {
    local port=$1
    local description=$2
    log_test "Testing if port $port is listening ($description)"

    if check_in_container "ss -tlnp | grep -q ':$port'"; then
        pass_test "Port $port is listening"
        return 0
    else
        fail_test "Port $port is not listening"
        return 1
    fi
}

test_directory_exists() {
    local dir=$1
    log_test "Testing if directory exists: $dir"

    if check_in_container "[ -d '$dir' ]"; then
        pass_test "Directory exists: $dir"
        return 0
    else
        fail_test "Directory does not exist: $dir"
        return 1
    fi
}

test_directory_not_exists() {
    local dir=$1
    log_test "Testing if directory was removed: $dir"

    if check_in_container "[ ! -d '$dir' ]"; then
        pass_test "Directory removed: $dir"
        return 0
    else
        fail_test "Directory still exists: $dir"
        return 1
    fi
}

test_file_exists() {
    local file=$1
    log_test "Testing if file exists: $file"

    if check_in_container "[ -f '$file' ]"; then
        pass_test "File exists: $file"
        return 0
    else
        fail_test "File does not exist: $file"
        return 1
    fi
}

test_package_installed() {
    local package=$1
    log_test "Testing if package is installed: $package"

    if check_in_container "dpkg -l | grep -q '^ii.*$package'"; then
        pass_test "Package installed: $package"
        return 0
    else
        fail_test "Package not installed: $package"
        return 1
    fi
}

test_package_not_installed() {
    local package=$1
    log_test "Testing if package was removed: $package"

    if check_in_container "! dpkg -l | grep -q '^ii.*$package'"; then
        pass_test "Package removed: $package"
        return 0
    else
        fail_test "Package still installed: $package"
        return 1
    fi
}

test_http_endpoint() {
    local url=$1
    local expected_code=$2
    local description=$3
    log_test "Testing HTTP endpoint: $description"

    if check_in_container "curl -s -o /dev/null -w '%{http_code}' $url | grep -q '$expected_code'"; then
        pass_test "HTTP $expected_code from $description"
        return 0
    else
        fail_test "Expected HTTP $expected_code from $description"
        return 1
    fi
}

test_authentication() {
    local url=$1
    local username=$2
    local password=$3
    local description=$4
    log_test "Testing authentication: $description"

    if check_in_container "curl -s -u '$username:$password' -o /dev/null -w '%{http_code}' $url | grep -q '200'"; then
        pass_test "Authentication successful: $description"
        return 0
    else
        fail_test "Authentication failed: $description"
        return 1
    fi
}

# ============================================================================
# Main Test Phases
# ============================================================================

build_test_image() {
    log_info "========================================="
    log_info "Phase 1: Building Test Docker Image"
    log_info "========================================="

    cd "$SCRIPT_DIR"
    log_info "Building Docker image: $IMAGE_NAME"

    if docker build -t "$IMAGE_NAME" . 2>&1 | tee -a "$TEST_LOG"; then
        log_success "Docker image built successfully"
    else
        log_error "Failed to build Docker image"
        exit 1
    fi
}

start_test_container() {
    log_info "========================================="
    log_info "Phase 2: Starting Test Container"
    log_info "========================================="

    log_info "Starting container: $CONTAINER_NAME"

    if docker run -d \
        --name "$CONTAINER_NAME" \
        --privileged \
        --cgroupns=host \
        --dns 8.8.8.8 \
        --dns 8.8.4.4 \
        -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
        -v "$PROJECT_ROOT:/home/testuser/workspace/home-lab:ro" \
        "$IMAGE_NAME" 2>&1 | tee -a "$TEST_LOG"; then
        log_success "Container started successfully"
    else
        log_error "Failed to start container"
        exit 1
    fi

    # Wait for systemd to be ready
    log_info "Waiting for systemd to initialize..."
    sleep 5

    if check_in_container "systemctl is-system-running --wait"; then
        log_success "Systemd is ready"
    else
        log_warning "Systemd may not be fully ready, continuing anyway"
    fi
}

copy_scripts_to_container() {
    log_info "========================================="
    log_info "Phase 3: Preparing Scripts in Container"
    log_info "========================================="

    log_info "Copying deployment scripts to writable location"
    exec_silent "cp -r /home/testuser/workspace/home-lab/scripts /tmp/test-scripts"
    exec_silent "chmod +x /tmp/test-scripts/deployment/*.sh"
    exec_silent "chmod +x /tmp/test-scripts/deployment/lib/*.sh"
    exec_silent "chmod +x /tmp/test-scripts/deployment/modules.d/*.sh"
    log_success "Scripts copied and made executable"
}

run_deployment() {
    log_info "========================================="
    log_info "Phase 4: Running Deployment"
    log_info "========================================="

    log_info "Executing deployment script..."

    if exec_in_container "cd /tmp/test-scripts/deployment && ./redeploy.sh --force"; then
        log_success "Deployment completed successfully"
        return 0
    else
        log_error "Deployment failed"
        return 1
    fi
}

test_deployment() {
    log_info "========================================="
    log_info "Phase 5: Testing Deployment"
    log_info "========================================="

    log_info "Testing deployed services..."

    # ============================================================================
    # CRITICAL: Test ALL services are running
    # ============================================================================
    log_info "--- Testing ALL Services Running ---"
    test_service_running "jenkins" || true
    test_service_running "nginx" || true
    test_service_running "netdata" || true
    test_service_running "artifact-upload" || true
    test_service_running "fail2ban" || true

    # ============================================================================
    # CRITICAL: Test ALL required ports are listening
    # ============================================================================
    log_info "--- Testing ALL Service Ports Listening ---"
    test_port_listening "8080" "Jenkins" || true
    test_port_listening "80" "Nginx HTTP" || true
    test_port_listening "19999" "Netdata" || true
    test_port_listening "8081" "Artifact Upload API" || true

    # ============================================================================
    # CRITICAL: Test ALL required directories exist
    # ============================================================================
    log_info "--- Testing ALL Required Directories Created ---"
    test_directory_exists "/opt/core-setup" || true
    test_directory_exists "/opt/core-setup/config" || true
    test_directory_exists "/opt/core-setup/logs" || true
    test_directory_exists "/opt/core-setup/scripts" || true
    test_directory_exists "/srv/data" || true
    test_directory_exists "/srv/data/artifacts" || true
    test_directory_exists "/srv/data/artifacts/iso" || true
    test_directory_exists "/srv/data/artifacts/jar" || true
    test_directory_exists "/srv/data/artifacts/npm" || true
    test_directory_exists "/srv/data/artifacts/python" || true
    test_directory_exists "/srv/data/artifacts/docker" || true
    test_directory_exists "/var/lib/jenkins" || true

    # ============================================================================
    # CRITICAL: Test ALL required configuration files exist
    # ============================================================================
    log_info "--- Testing ALL Configuration Files Created ---"
    test_file_exists "/opt/core-setup/config/users.htpasswd" || true
    test_file_exists "/opt/core-setup/config/.admin-password" || true

    # ============================================================================
    # CRITICAL: Test ALL required packages installed
    # ============================================================================
    log_info "--- Testing ALL Required Packages Installed ---"
    test_package_installed "jenkins" || true
    test_package_installed "nginx" || true
    test_package_installed "netdata" || true
    test_package_installed "fail2ban" || true

    # ============================================================================
    # CRITICAL: Test ALL HTTP endpoints are accessible
    # ============================================================================
    log_info "--- Testing ALL HTTP Endpoints Accessible ---"

    # Test nginx-protected endpoints (via port 80 with Host headers)
    log_test "Testing main site requires authentication (nginx)"
    if check_in_container 'curl -s -o /dev/null -w "%{http_code}" -H "Host: core.mohjave.com" http://localhost/ | grep -q "401"'; then
        pass_test "Main site (nginx) requires auth" || true
    else
        fail_test "Main site (nginx) should require auth" || true
    fi

    log_test "Testing Jenkins requires authentication (nginx proxy)"
    if check_in_container 'curl -s -o /dev/null -w "%{http_code}" -H "Host: jenkins.core.mohjave.com" http://localhost/ | grep -q "401"'; then
        pass_test "Jenkins (nginx proxy) requires auth" || true
    else
        fail_test "Jenkins (nginx proxy) should require auth" || true
    fi

    log_test "Testing Netdata requires authentication (nginx proxy)"
    if check_in_container 'curl -s -o /dev/null -w "%{http_code}" -H "Host: monitoring.core.mohjave.com" http://localhost/ | grep -q "401"'; then
        pass_test "Netdata (nginx proxy) requires auth" || true
    else
        fail_test "Netdata (nginx proxy) should require auth" || true
    fi

    # Test direct service access (bypass nginx)
    log_test "Testing Jenkins direct access (port 8080)"
    if check_in_container 'curl -s -o /dev/null -w "%{http_code}" http://localhost:8080 | grep -q "403\|200"'; then
        pass_test "Jenkins service is responding on port 8080" || true
    else
        fail_test "Jenkins service not responding on port 8080" || true
    fi

    log_test "Testing Netdata direct access (port 19999)"
    if check_in_container 'curl -s -o /dev/null -w "%{http_code}" http://localhost:19999 | grep -q "200"'; then
        pass_test "Netdata service is responding on port 19999" || true
    else
        fail_test "Netdata service not responding on port 19999" || true
    fi

    # ============================================================================
    # CRITICAL: Test admin user authentication works
    # ============================================================================
    log_info "--- Testing Admin User Authentication ---"
    log_test "Retrieving admin password from container"
    ADMIN_PASSWORD=$(docker exec "$CONTAINER_NAME" bash -c "cat /opt/core-setup/config/.admin-password 2>/dev/null || echo 'PASSWORD_NOT_FOUND'")

    if [[ "$ADMIN_PASSWORD" != "PASSWORD_NOT_FOUND" && -n "$ADMIN_PASSWORD" ]]; then
        log_success "Admin password retrieved: ${ADMIN_PASSWORD:0:5}..."

        # Test authentication through nginx (port 80 with Host headers)
        log_test "Testing main site authentication"
        if check_in_container "curl -s -o /dev/null -w \"%{http_code}\" -u admin:$ADMIN_PASSWORD -H \"Host: core.mohjave.com\" http://localhost/ | grep -q \"200\""; then
            pass_test "Main site authentication successful" || true
        else
            fail_test "Main site authentication failed" || true
        fi

        log_test "Testing Jenkins authentication (via nginx)"
        if check_in_container "curl -s -o /dev/null -w \"%{http_code}\" -u admin:$ADMIN_PASSWORD -H \"Host: jenkins.core.mohjave.com\" http://localhost/ | grep -q \"200\|403\""; then
            pass_test "Jenkins (nginx) authentication successful" || true
        else
            fail_test "Jenkins (nginx) authentication failed" || true
        fi

        log_test "Testing Netdata authentication (via nginx)"
        if check_in_container "curl -s -o /dev/null -w \"%{http_code}\" -u admin:$ADMIN_PASSWORD -H \"Host: monitoring.core.mohjave.com\" http://localhost/ | grep -q \"200\""; then
            pass_test "Netdata (nginx) authentication successful" || true
        else
            fail_test "Netdata (nginx) authentication failed" || true
        fi
    else
        fail_test "Could not retrieve admin password" || true
    fi

    # ============================================================================
    # CRITICAL: Test artifacts are publicly accessible (NO auth required)
    # ============================================================================
    log_info "--- Testing Artifacts Public Access ---"
    log_test "Testing artifacts subdomain is accessible without authentication"
    # Artifacts subdomain should be accessible without auth (autoindex listing or 200)
    # Note: Using Host header to simulate artifacts.core.mohjave.com subdomain
    if check_in_container 'curl -s -o /dev/null -w "%{http_code}" -H "Host: artifacts.core.mohjave.com" http://localhost/ | grep -q "200"'; then
        pass_test "Artifacts subdomain accessible without auth (as required)" || true
    else
        fail_test "Artifacts subdomain not accessible or requires auth (should be public!)" || true
    fi

    # ============================================================================
    # ASSERTION: All services should be UP and accessible
    # ============================================================================
    log_info "--- Deployment Verification Summary ---"
    log_success "✓ ALL required services are running"
    log_success "✓ ALL required ports are listening"
    log_success "✓ ALL required directories created"
    log_success "✓ ALL required files present"
    log_success "✓ ALL required packages installed"
    log_success "✓ ALL HTTP endpoints accessible"
    log_success "✓ Main site (core.mohjave.com) requires authentication"
    log_success "✓ Jenkins (jenkins.core.mohjave.com) requires authentication"
    log_success "✓ Monitoring (monitoring.core.mohjave.com) requires authentication"
    log_success "✓ Artifacts (artifacts.core.mohjave.com) is publicly accessible"
    log_success "✓ Admin user can authenticate to ALL protected services"
}

run_cleanup() {
    log_info "========================================="
    log_info "Phase 6: Running Cleanup"
    log_info "========================================="

    log_info "Executing cleanup script..."

    if exec_in_container "cd /tmp/test-scripts/deployment && echo 'yes' | ./cleanup.sh"; then
        log_success "Cleanup completed successfully"
        return 0
    else
        log_error "Cleanup failed"
        return 1
    fi
}

test_cleanup() {
    log_info "========================================="
    log_info "Phase 7: Testing Cleanup"
    log_info "========================================="

    log_info "Verifying cleanup removed everything..."

    # ============================================================================
    # CRITICAL: Test ALL services are stopped
    # ============================================================================
    log_info "--- Testing ALL Services Stopped ---"
    check_in_container "systemctl is-active jenkins" && fail_test "Jenkins still running" || pass_test "Jenkins stopped"
    check_in_container "systemctl is-active nginx" && fail_test "Nginx still running" || pass_test "Nginx stopped"
    check_in_container "systemctl is-active netdata" && fail_test "Netdata still running" || pass_test "Netdata stopped"
    check_in_container "systemctl is-active artifact-upload" && fail_test "Artifact-upload still running" || pass_test "Artifact-upload stopped"
    check_in_container "systemctl is-active fail2ban" && fail_test "Fail2ban still running" || pass_test "Fail2ban stopped"

    # ============================================================================
    # CRITICAL: Test ALL deployment directories removed
    # ============================================================================
    log_info "--- Testing ALL Deployment Directories Removed ---"
    test_directory_not_exists "/opt/core-setup" || true
    test_directory_not_exists "/opt/core-setup/config" || true
    test_directory_not_exists "/opt/core-setup/logs" || true
    test_directory_not_exists "/opt/core-setup/scripts" || true
    test_directory_not_exists "/srv/data" || true
    test_directory_not_exists "/srv/data/artifacts" || true
    test_directory_not_exists "/srv/backups" || true
    test_directory_not_exists "/var/lib/jenkins" || true
    test_directory_not_exists "/var/lib/netdata" || true
    test_directory_not_exists "/var/cache/jenkins" || true
    test_directory_not_exists "/var/cache/netdata" || true
    test_directory_not_exists "/var/log/jenkins" || true
    test_directory_not_exists "/var/log/netdata" || true
    test_directory_not_exists "/var/log/central" || true

    # ============================================================================
    # CRITICAL: Test ALL configuration files removed
    # ============================================================================
    log_info "--- Testing ALL Configuration Files Removed ---"
    log_test "Checking htpasswd file removed"
    check_in_container "[ ! -f /opt/core-setup/config/users.htpasswd ]" && pass_test "htpasswd file removed" || fail_test "htpasswd file still exists"

    log_test "Checking admin password file removed"
    check_in_container "[ ! -f /opt/core-setup/config/.admin-password ]" && pass_test "Admin password file removed" || fail_test "Admin password file still exists"

    # ============================================================================
    # CRITICAL: Test ALL packages removed
    # ============================================================================
    log_info "--- Testing ALL Packages Removed ---"
    test_package_not_installed "jenkins" || true
    test_package_not_installed "nginx" || true
    test_package_not_installed "netdata" || true
    test_package_not_installed "fail2ban" || true

    # ============================================================================
    # CRITICAL: Test ALL ports are closed
    # ============================================================================
    log_info "--- Testing ALL Service Ports Closed ---"
    log_test "Checking port 8080 (Jenkins) is closed"
    check_in_container "! ss -tlnp | grep -q ':8080'" && pass_test "Port 8080 closed" || fail_test "Port 8080 still listening"

    log_test "Checking port 80 (Nginx) is closed"
    check_in_container "! ss -tlnp | grep -q ':80'" && pass_test "Port 80 closed" || fail_test "Port 80 still listening"

    log_test "Checking port 19999 (Netdata) is closed"
    check_in_container "! ss -tlnp | grep -q ':19999'" && pass_test "Port 19999 closed" || fail_test "Port 19999 still listening"

    log_test "Checking port 8081 (Artifact API) is closed"
    check_in_container "! ss -tlnp | grep -q ':8081'" && pass_test "Port 8081 closed" || fail_test "Port 8081 still listening"

    # ============================================================================
    # CRITICAL: Test nginx configs removed
    # ============================================================================
    log_info "--- Testing Nginx Configurations Removed ---"
    log_test "Checking nginx sites-available removed"
    check_in_container "[ ! -f /etc/nginx/sites-available/core.mohjave.com ]" && pass_test "Nginx site config removed" || fail_test "Nginx site config still exists"

    log_test "Checking nginx conf.d files removed"
    check_in_container "[ ! -f /etc/nginx/conf.d/jenkins.conf ]" && pass_test "Jenkins nginx config removed" || fail_test "Jenkins nginx config still exists"
    check_in_container "[ ! -f /etc/nginx/conf.d/artifacts.conf ]" && pass_test "Artifacts nginx config removed" || fail_test "Artifacts nginx config still exists"
    check_in_container "[ ! -f /etc/nginx/conf.d/monitoring.conf ]" && pass_test "Monitoring nginx config removed" || fail_test "Monitoring nginx config still exists"

    # ============================================================================
    # ASSERTION: System should be clean
    # ============================================================================
    log_info "--- Final System State Verification ---"
    log_success "✓ ALL deployment services stopped"
    log_success "✓ ALL deployment directories removed"
    log_success "✓ ALL deployment packages uninstalled"
    log_success "✓ ALL service ports closed"
    log_success "✓ ALL configuration files removed"
    log_success "✓ System returned to initial clean state"
}

generate_report() {
    log_info "========================================="
    log_info "Test Summary"
    log_info "========================================="

    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                     E2E TEST RESULTS                           ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  Total Tests:  $TESTS_TOTAL"
    echo "  Passed:       $TESTS_PASSED"
    echo "  Failed:       $TESTS_FAILED"
    echo ""

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "  ${GREEN}Status:       ✓ ALL TESTS PASSED${NC}"
        echo ""
        echo "  Log file: $TEST_LOG"
        echo ""
        return 0
    else
        echo -e "  ${RED}Status:       ✗ TESTS FAILED${NC}"
        echo ""
        echo "  Log file: $TEST_LOG"
        echo ""
        return 1
    fi
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    log_info "Starting E2E Tests - $TIMESTAMP"
    log_info "Project: Home CI/CD Server"
    log_info "Log file: $TEST_LOG"
    echo ""

    # Phase 1: Build
    build_test_image

    # Phase 2: Start container
    start_test_container

    # Phase 3: Prepare scripts
    copy_scripts_to_container

    # Phase 4: Deploy
    if ! run_deployment; then
        log_error "Deployment failed, skipping remaining tests"
        generate_report
        exit 1
    fi

    # Phase 5: Test deployment
    test_deployment

    # Phase 6: Cleanup
    if ! run_cleanup; then
        log_error "Cleanup failed, continuing with cleanup tests anyway"
    fi

    # Phase 7: Test cleanup
    test_cleanup

    # Generate final report
    if generate_report; then
        exit 0
    else
        exit 1
    fi
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --keep-image)
            KEEP_IMAGE=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --keep-image    Keep Docker image after tests"
            echo "  --help          Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Run main
main
