# Home CI/CD Server - Quick Start Guide

A simple, powerful deployment system for your home CI/CD server using `make` commands.

## Prerequisites

- Ubuntu/Debian-based system
- Sudo access
- Domain: `core.mohjave.com` configured in your router

## Quick Start

### 1. Deploy Everything

```bash
make deploy
```

This will install and configure:
- TeamCity CI/CD Server
- Nginx Reverse Proxy
- Netdata Monitoring
- Artifact Storage
- Fail2ban Security

### 2. Check Status

```bash
make status
```

Shows running services and available endpoints.

### 3. Access Your Services

- **Main Site**: http://core.mohjave.com (requires authentication)
- **TeamCity**: https://teamcity.core.mohjave.com
- **Artifacts**: http://artifacts.core.mohjave.com (public access)
- **Monitoring**: http://monitoring.core.mohjave.com (requires authentication)

### 4. Get Admin Credentials

After deployment, find your admin password:
```bash
sudo cat /opt/core-setup/config/.admin-password
```

Username: `admin`

## Common Commands

### Deployment

```bash
make deploy              # Full deployment
make deploy-test         # Test without changes (dry-run)
make redeploy            # Clean and redeploy from scratch
```

### Status & Health

```bash
make status              # Service status
make check               # Health check
make logs                # View deployment logs
make info                # Show system information
```

### Service Management

```bash
make start               # Start all services
make stop                # Stop all services
make restart             # Restart all services
```

### Cleanup

```bash
make clean               # Remove everything (asks confirmation)
make clean-dry-run       # Test cleanup without changes
make clean-keep-packages # Remove configs but keep packages
```

### Validation

```bash
make validate            # Check script syntax
make shellcheck          # Run shellcheck (if installed)
```

## Common Tasks

### Initial Setup

```bash
# 1. Validate scripts are ready
make validate

# 2. Test deployment (dry-run)
make deploy-test

# 3. Deploy for real
make deploy

# 4. Check everything is working
make check
```

### Daily Operations

```bash
# Check service status
make status

# View logs
make logs

# Restart a misbehaving service
make restart
```

### Troubleshooting

```bash
# Enable debug mode
make debug
make deploy

# Clean up and start fresh
make redeploy

# Check health
make check

# Fix script permissions if needed
make fix-permissions
```

### Before Updates

```bash
# Backup current configuration
make backup-config

# Test the new deployment
make deploy-test

# Deploy updates
make deploy
```

## Directory Structure

```
home-lab/
├── Makefile                    # This file - all commands
├── scripts/
│   └── deployment/
│       ├── redeploy.sh         # Main deployment script
│       ├── cleanup.sh          # Cleanup script
│       ├── lib/                # Shared libraries
│       ├── modules.d/          # Deployment modules
│       └── config/             # Configuration templates
└── QUICKSTART.md              # This guide
```

## Ports

Your router should forward these ports:

- `4926` → 22 (SSH with rate limiting)
- `80` → 80 (HTTP)
- `443` → 443 (HTTPS)
- `8111` → 8111 (TeamCity)
- `81` → 81 (Nginx Admin)

## Security

- All services protected with authentication (except artifacts)
- Fail2ban monitors for intrusion attempts
- UFW firewall configured
- Rate limiting on SSH and uploads

## What Gets Deployed?

### Services
- **TeamCity** - CI/CD automation server
- **Nginx** - Reverse proxy for all services
- **Netdata** - Real-time monitoring dashboard
- **Artifact Storage** - Store build artifacts (ISO, JAR, NPM, Docker, etc.)
- **Fail2ban** - Intrusion prevention

### Directories
- `/opt/core-setup/` - Deployment files and configs
- `/srv/data/artifacts/` - Artifact storage
- `/srv/backups/` - System backups
- `/srv/data/teamcity/` - TeamCity data and workspace

### Security
- UFW firewall rules
- Fail2ban jails
- User authentication (htpasswd)

## Complete Command Reference

### General
```bash
make help                # Show all commands
make info                # System information
make version             # Script versions
```

### Deployment
```bash
make deploy              # Deploy everything
make deploy-test         # Dry-run deployment
make quick-deploy        # Deploy without prompts
```

### Cleanup
```bash
make clean               # Remove all components
make clean-dry-run       # Test cleanup
make clean-keep-packages # Keep installed packages
```

### Status & Verification
```bash
make status              # Service status
make check               # Health check
make logs                # View logs
```

### Validation
```bash
make validate            # Script syntax check
make shellcheck          # Run shellcheck
```

### Service Management
```bash
make start               # Start services
make stop                # Stop services
make restart             # Restart services
```

### Quick Actions
```bash
make redeploy            # Clean and redeploy
make quick-deploy        # Fast deployment
```

### Development
```bash
make test-modules        # List modules
make list-files          # Show all files
make backup-config       # Backup configuration
```

### Troubleshooting
```bash
make debug               # Enable debug mode
make debug-off           # Disable debug mode
make fix-permissions     # Fix file permissions
make clean-logs          # Clean temporary logs
```

## Examples

### Complete Fresh Install

```bash
# Validate everything first
make validate

# Test deployment
make deploy-test

# Deploy for real
make deploy

# Verify it's working
make check
make status
```

### Recovering from Issues

```bash
# Clean everything
make clean

# Fix any permission issues
make fix-permissions

# Redeploy
make deploy
```

### Regular Maintenance

```bash
# Check service health
make check

# View recent logs
make logs

# Restart services if needed
make restart

# Backup current config
make backup-config
```

### Testing Changes

```bash
# Validate scripts
make validate

# Test in dry-run mode
make deploy-test

# If good, deploy
make deploy
```

## Tips

1. **Always validate first**: Run `make validate` before deployment
2. **Test with dry-run**: Use `make deploy-test` to see what will happen
3. **Backup configs**: Run `make backup-config` before major changes
4. **Check status often**: Use `make status` to monitor services
5. **Use clean-dry-run**: Test cleanup with `make clean-dry-run` before running `make clean`

## Troubleshooting

### Deployment Failed

```bash
# Check what went wrong
make logs

# Clean and try again
make clean
make deploy
```

### Services Not Starting

```bash
# Check status
make status

# Restart services
make restart

# Check health
make check
```

### Permission Errors

```bash
# Fix permissions
make fix-permissions

# Redeploy
make deploy
```

### Complete Reset

```bash
# Nuclear option - clean and redeploy
make redeploy
```

## Getting Help

```bash
# Show all available commands
make help

# Show system information
make info

# Validate scripts are working
make validate
```

## Next Steps

After deployment:

1. Access TeamCity and set up your first project
2. Configure Netdata alerts
3. Set up artifact retention policies
4. Configure SSL certificates (if desired)
5. Set up backup schedules

## Support

For issues:
1. Check `make logs`
2. Run `make check`
3. Try `make redeploy`
4. Check GitHub issues
