# E2E Testing System

End-to-end testing for the Home CI/CD Server deployment and cleanup scripts.

## Overview

This testing system validates that:
1. ✅ Deployment scripts successfully install all services
2. ✅ All services are running and accessible
3. ✅ Admin user can authenticate to all services
4. ✅ Cleanup scripts remove everything completely
5. ✅ System returns to initial state after cleanup

## Prerequisites

- Docker Engine installed
- Bash 4.0+
- At least 4GB RAM available for Docker
- At least 10GB disk space

## Quick Start

### Run All Tests

```bash
cd tests/e2e
./run-e2e-tests.sh
```

### Keep Docker Image After Tests

```bash
./run-e2e-tests.sh --keep-image
```

## What Gets Tested

### Phase 1: Build Test Environment
- Creates Ubuntu 24.04 container with systemd
- Installs basic dependencies

### Phase 2: Start Container
- Launches privileged container
- Mounts project scripts
- Waits for systemd initialization

### Phase 3: Prepare Scripts
- Copies scripts to writable location
- Sets executable permissions

### Phase 4: Run Deployment
- Executes `redeploy.sh`
- Captures all output

### Phase 5: Test Deployment
Tests include:

**Services Running:**
- ✓ Jenkins
- ✓ Nginx
- ✓ Netdata
- ✓ Artifact Upload API
- ✓ Fail2ban

**Ports Listening:**
- ✓ 8080 (Jenkins)
- ✓ 80 (Nginx HTTP)
- ✓ 19999 (Netdata)
- ✓ 8081 (Artifact Upload)

**Directories Created:**
- ✓ /opt/core-setup
- ✓ /srv/data/artifacts
- ✓ /var/lib/jenkins
- ✓ Configuration files

**Packages Installed:**
- ✓ Jenkins
- ✓ Nginx
- ✓ Netdata
- ✓ Fail2ban

**HTTP Endpoints:**
- ✓ Main site requires authentication
- ✓ Jenkins is accessible
- ✓ Netdata dashboard works
- ✓ Artifact repository accessible

**Authentication:**
- ✓ Admin user can authenticate
- ✓ htpasswd file created
- ✓ Admin password stored

### Phase 6: Run Cleanup
- Executes `cleanup.sh`
- Accepts automatic confirmation

### Phase 7: Test Cleanup
Tests include:

**Services Stopped:**
- ✓ All services inactive

**Directories Removed:**
- ✓ /opt/core-setup deleted
- ✓ /srv/data deleted
- ✓ /var/lib/jenkins deleted
- ✓ /var/lib/netdata deleted

**Packages Removed:**
- ✓ Jenkins uninstalled
- ✓ Nginx uninstalled
- ✓ Netdata uninstalled
- ✓ Fail2ban uninstalled

## Test Results

### Console Output

Tests display real-time progress with color-coded output:
- 🔵 **BLUE**: Informational messages
- 🟢 **GREEN**: Successful tests
- 🔴 **RED**: Failed tests
- 🟡 **YELLOW**: Warnings

### Log Files

All test output is saved to:
```
tests/e2e/logs/e2e-test-YYYYMMDD-HHMMSS.log
```

### Final Report

```
╔════════════════════════════════════════════════════════════════╗
║                     E2E TEST RESULTS                           ║
╚════════════════════════════════════════════════════════════════╝

  Total Tests:  45
  Passed:       45
  Failed:       0

  Status:       ✓ ALL TESTS PASSED
```

## CI/CD Integration

### GitHub Actions

Tests run automatically on:
- Push to `main`, `master`, or `develop` branches
- Pull requests to these branches
- Manual workflow dispatch

Configuration: `.github/workflows/e2e-tests.yml`

### GitLab CI

Tests run automatically on:
- Merge requests
- Commits to `main`, `master`, or `develop`
- Manual pipeline triggers

Configuration: `.gitlab-ci.yml`

## Troubleshooting

### Docker Permission Issues

If you get permission errors:
```bash
sudo usermod -aG docker $USER
newgrp docker
```

### Container Fails to Start

Check Docker is running:
```bash
sudo systemctl status docker
```

Check available resources:
```bash
docker system df
docker system prune  # if needed
```

### Tests Timeout

Increase container resources in Docker settings or:
```bash
# Edit timeout in run-e2e-tests.sh
# Default is 60 minutes in CI/CD
```

### Systemd Not Working in Container

Ensure Docker is in privileged mode and cgroups are properly mounted.
This is handled automatically by the test script.

### Failed Tests

Check the log file for details:
```bash
cat tests/e2e/logs/e2e-test-*.log | grep -A5 "ERROR"
```

Common issues:
- Port conflicts (if running on host that already has services)
- Network connectivity issues
- Insufficient disk space
- Resource constraints (RAM/CPU)

## Local Development

### Test Individual Phases

You can modify the script to test specific phases:

```bash
# In run-e2e-tests.sh, comment out phases you don't want to run
# main() {
#     build_test_image
#     start_test_container
#     copy_scripts_to_container
#     run_deployment
#     test_deployment  # <-- Only run this
#     # run_cleanup
#     # test_cleanup
#     generate_report
# }
```

### Debug Mode

Get shell access to test container:
```bash
docker exec -it home-lab-e2e-test bash
```

Check service status manually:
```bash
docker exec home-lab-e2e-test systemctl status jenkins
```

View logs:
```bash
docker exec home-lab-e2e-test journalctl -u jenkins -n 50
```

### Keep Container Running

Modify cleanup trap to keep container for debugging:
```bash
# Comment out the trap in run-e2e-tests.sh
# trap cleanup EXIT
```

## Architecture

```
tests/e2e/
├── Dockerfile              # Ubuntu 24.04 with systemd
├── run-e2e-tests.sh        # Main test orchestrator
├── README.md               # This file
└── logs/                   # Test logs (gitignored)
    └── e2e-test-*.log
```

### Container Architecture

```
┌─────────────────────────────────────────┐
│  Ubuntu 24.04 Container                 │
│  ENV E2E_TEST_MODE=true                 │
│                                         │
│  ┌────────────────────────────────┐   │
│  │  systemd (PID 1)               │   │
│  └────────────────────────────────┘   │
│                                         │
│  ┌────────────────────────────────┐   │
│  │  Deployment Scripts (mounted)  │   │
│  │  - redeploy.sh                 │   │
│  │  - cleanup.sh                  │   │
│  │  - modules.d/                  │   │
│  └────────────────────────────────┘   │
│                                         │
│  ┌────────────────────────────────┐   │
│  │  Services (deployed)           │   │
│  │  - Jenkins                     │   │
│  │  - Nginx                       │   │
│  │  - Netdata                     │   │
│  │  - Fail2ban                    │   │
│  │  - DNS (SKIPPED in E2E)        │   │
│  └────────────────────────────────┘   │
└─────────────────────────────────────────┘
```

### Test Environment Variables

The E2E test container sets special environment variables:

- `E2E_TEST_MODE=true` - Marks the environment as a test
  - **Effect**: DNS module is skipped (no Dynu API calls)
  - **Reason**: Tests run in isolated Docker containers without real internet DNS
  - **Modules affected**: `module-dns.sh`

## Performance

Typical test run times:
- Build image: 2-3 minutes (first time)
- Start container: 10-15 seconds
- Deployment: 5-10 minutes
- Test deployment: 30-60 seconds
- Cleanup: 1-2 minutes
- Test cleanup: 30-60 seconds

**Total: ~8-15 minutes**

## Future Enhancements

Potential improvements:
- [ ] Parallel test execution
- [ ] Performance benchmarking
- [ ] Security scanning integration
- [ ] Multi-architecture testing (ARM64)
- [ ] Test different Ubuntu versions
- [ ] Load testing for services
- [ ] Backup/restore testing
- [ ] SSL certificate testing
- [ ] Integration with external services

## Contributing

When adding new deployment features:

1. Update deployment scripts
2. Add corresponding tests in `run-e2e-tests.sh`
3. Run tests locally: `./run-e2e-tests.sh`
4. Commit changes
5. CI/CD will run tests automatically

Test naming convention:
```bash
test_<category>_<what_is_tested>() {
    # Example: test_service_running()
    # Example: test_http_endpoint()
}
```

## License

Same as parent project.
