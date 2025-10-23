# Home CI/CD Server

Complete deployment system for a home CI/CD server with automated testing.

## Features

- **Jenkins** - CI/CD automation server
- **Nginx** - Reverse proxy with authentication
- **Netdata** - Real-time monitoring dashboard
- **Artifact Storage** - Store build artifacts (ISO, JAR, NPM, Docker, etc.)
- **Fail2ban** - Intrusion prevention
- **UFW Firewall** - Network security

## Prerequisites

- Ubuntu/Debian-based system
- Sudo access
- Docker (for E2E tests)
- Domain configured: `core.mohjave.com`

## Quick Start

```bash
# Deploy everything
make deploy

# Check status
make status

# Run E2E tests
make test

# Clean up everything
make clean
```

## Commands

```bash
make help          # Show all commands
make deploy        # Deploy complete server
make status        # Check service status
make test          # Run E2E tests
make clean         # Remove everything
make validate      # Validate scripts
```

## Project Structure

```
home-lab/
├── Makefile                    # Easy-to-use commands
├── scripts/
│   └── deployment/
│       ├── redeploy.sh         # Main deployment script
│       ├── cleanup.sh          # Cleanup script
│       ├── lib/                # Shared libraries
│       ├── modules.d/          # Deployment modules
│       └── config/             # Configuration templates
└── tests/
    └── e2e/
        ├── Dockerfile          # Test container
        ├── run-e2e-tests.sh    # E2E test suite
        └── README.md           # Testing documentation
```

## Deployment

The deployment creates:

- `/opt/core-setup/` - Deployment files and configs
- `/srv/data/artifacts/` - Artifact storage
- `/srv/backups/` - System backups
- `/var/lib/jenkins/` - Jenkins workspace

## Endpoints

After deployment:

- **Main Site**: http://core.mohjave.com (requires auth)
- **Jenkins**: http://jenkins.core.mohjave.com
- **Artifacts**: http://artifacts.core.mohjave.com (public)
- **Monitoring**: http://monitoring.core.mohjave.com (requires auth)

Default credentials: Check `/opt/core-setup/config/.admin-password` after deployment

## Testing

```bash
# Run complete E2E test suite
make test

# Keep Docker image for debugging
make test-keep

# View test logs
make test-logs

# Clean test artifacts
make test-clean
```

The E2E tests verify:
- ✅ All services deploy and start correctly
- ✅ All ports are listening
- ✅ Admin user can access all services
- ✅ Cleanup removes everything completely

See [tests/e2e/README.md](tests/e2e/README.md) for details.

## CI/CD

Tests run automatically on:
- GitHub: Every push and PR (see `.github/workflows/e2e-tests.yml`)
- GitLab: Every merge request (see `.gitlab-ci.yml`)

## Security

- SSH access preserved during cleanup (port 4926)
- All services protected with htpasswd authentication (except artifacts)
- Fail2ban monitors for intrusion attempts
- UFW firewall configured
- Rate limiting on SSH and uploads

## Ports

Router should forward:
- `4926` → 22 (SSH)
- `80` → 80 (HTTP)
- `443` → 443 (HTTPS)
- `8080` → 8080 (Jenkins)
- `81` → 81 (Nginx Admin)

## Documentation

- [QUICKSTART.md](QUICKSTART.md) - Quick start guide with common tasks
- [tests/e2e/README.md](tests/e2e/README.md) - E2E testing documentation

## Troubleshooting

```bash
# Check service status
make status

# View deployment logs
make logs

# Validate scripts
make validate

# Fix permissions
make fix-permissions

# Complete reset
make redeploy
```

## License

MIT
