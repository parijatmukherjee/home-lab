# SSL/HTTPS Certificate Setup

This directory contains scripts for obtaining and managing free SSL certificates from Let's Encrypt.

## Quick Start

### Setup HTTPS (Production)

```bash
make ssl
```

This will:
- ✓ Install certbot (if not already installed)
- ✓ Check DNS resolution for all domains
- ✓ Obtain SSL certificates from Let's Encrypt
- ✓ Configure nginx for HTTPS with automatic HTTP→HTTPS redirect
- ✓ Setup automatic certificate renewal

### Test Setup (Staging)

Before running in production, you can test with Let's Encrypt's staging environment:

```bash
make ssl-staging
```

**Note:** Staging certificates won't be trusted by browsers, but this is useful for testing without hitting rate limits.

## Prerequisites

Before running SSL setup:

1. **Deploy the system first:**
   ```bash
   make deploy
   ```

2. **Ensure DNS is configured:**
   All domains must resolve to your server's IP:
   - core.mohjave.com
   - jenkins.core.mohjave.com
   - artifacts.core.mohjave.com
   - monitoring.core.mohjave.com

3. **Port 80 must be accessible from the internet**
   Let's Encrypt validates domain ownership via HTTP

4. **Firewall must allow HTTP/HTTPS:**
   ```bash
   sudo ufw allow 80/tcp
   sudo ufw allow 443/tcp
   ```

## Available Commands

### Setup & Configuration

```bash
make ssl              # Setup HTTPS certificates (production)
make ssl-staging      # Test with staging certificates
```

### Management

```bash
make ssl-status       # Show certificate status and expiration dates
make ssl-renew        # Manually renew certificates
make ssl-renew-test   # Test renewal (dry-run)
make ssl-revoke       # Revoke certificates (CAUTION!)
```

## How It Works

### Certificate Obtainment

The script uses `certbot` with the nginx plugin to:

1. Request certificates from Let's Encrypt for all configured domains
2. Validate domain ownership via HTTP-01 challenge
3. Download certificates to `/etc/letsencrypt/live/core.mohjave.com/`
4. Automatically configure nginx to use the certificates

### Auto-Renewal

Certbot automatically sets up a systemd timer that:
- Runs twice daily to check if certificates need renewal
- Renews certificates 30 days before expiration
- Reloads nginx automatically after renewal

Check renewal timer status:
```bash
systemctl status certbot.timer
```

Test renewal process:
```bash
sudo certbot renew --dry-run
```

## Domains Covered

By default, certificates are obtained for:

- `core.mohjave.com` - Main landing page
- `jenkins.core.mohjave.com` - Jenkins CI/CD
- `artifacts.core.mohjave.com` - Artifact repository
- `monitoring.core.mohjave.com` - Netdata monitoring

All domains are covered by a single certificate.

## Certificate Locations

```
/etc/letsencrypt/
├── live/
│   └── core.mohjave.com/
│       ├── fullchain.pem    # Certificate + chain
│       ├── privkey.pem      # Private key
│       ├── cert.pem         # Certificate only
│       └── chain.pem        # Chain only
├── renewal/
│   └── core.mohjave.com.conf
└── archive/
    └── core.mohjave.com/
```

## Custom Configuration

### Custom Email

```bash
sudo scripts/ssl/setup-ssl.sh --email your@email.com
```

### Custom Domains

```bash
sudo scripts/ssl/setup-ssl.sh --domains "example.com,www.example.com"
```

### Staging Environment

```bash
sudo scripts/ssl/setup-ssl.sh --staging
```

## Troubleshooting

### DNS Not Resolving

**Problem:** `Domain does not resolve to an IP address`

**Solution:**
1. Check DNS records are properly configured
2. Wait for DNS propagation (can take up to 48 hours)
3. Verify with: `host core.mohjave.com`

### Port 80 Not Accessible

**Problem:** `Failed to obtain certificates`

**Solution:**
1. Check firewall: `sudo ufw status`
2. Ensure nginx is running: `systemctl status nginx`
3. Test from outside: `curl http://core.mohjave.com`

### Rate Limit Reached

**Problem:** `too many certificates already issued`

**Solution:**
1. Let's Encrypt has rate limits (50 certs per domain per week)
2. Use `--staging` for testing
3. Wait for rate limit to reset
4. See: https://letsencrypt.org/docs/rate-limits/

### Certificate Already Exists

**Problem:** `Certificate already exists`

**Solution:**
```bash
# Force renewal
sudo certbot renew --force-renewal

# Or revoke and re-issue
sudo certbot revoke --cert-name core.mohjave.com
make ssl
```

### Nginx Configuration Errors

**Problem:** `nginx configuration test failed`

**Solution:**
```bash
# Check nginx configuration
sudo nginx -t

# View nginx logs
sudo journalctl -u nginx -n 50

# Fix configuration and retry
make ssl
```

## Security Best Practices

1. **Keep certificates renewed**
   - Certbot auto-renewal is enabled by default
   - Monitor with: `systemctl status certbot.timer`

2. **Use strong SSL configuration**
   - Certbot configures modern SSL settings automatically
   - HTTP automatically redirects to HTTPS

3. **Monitor certificate expiration**
   ```bash
   make ssl-status
   ```

4. **Backup certificates**
   ```bash
   sudo tar -czf letsencrypt-backup.tar.gz /etc/letsencrypt
   ```

## Let's Encrypt Information

- **Issuer:** Let's Encrypt (Free, Automated, Open CA)
- **Certificate Validity:** 90 days
- **Renewal:** Automatic (30 days before expiration)
- **Rate Limits:** 50 certificates per domain per week
- **Cost:** Free forever

**Official Documentation:**
- https://letsencrypt.org/
- https://certbot.eff.org/
- https://letsencrypt.org/docs/

## Integration with Deployment

SSL setup is **separate** from the main deployment process:

1. **Deploy the system:**
   ```bash
   make deploy
   ```

2. **Setup SSL (manually, when ready):**
   ```bash
   make ssl
   ```

This separation allows you to:
- Deploy and test without HTTPS first
- Configure DNS properly before requesting certificates
- Avoid rate limits during testing

## Files

```
scripts/ssl/
├── setup-ssl.sh    # Main SSL setup script
└── README.md       # This file
```

## Support

For issues or questions:
- GitHub Issues: https://github.com/parijatmukherjee/home-lab/issues
- Let's Encrypt Community: https://community.letsencrypt.org/

## License

Same as parent project.
