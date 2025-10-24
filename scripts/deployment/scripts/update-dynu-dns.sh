#!/bin/bash
# update-dynu-dns.sh - Update Dynu DNS records with current public IP
# Part of Home CI/CD Server deployment automation

set -euo pipefail

# Configuration
DEPLOYMENT_CONFIG="${DEPLOYMENT_CONFIG:-/opt/core-setup/config}"
API_KEY_FILE="${DEPLOYMENT_CONFIG}/.dynu-api-key"
LOG_FILE="/var/log/dynu-dns-update.log"
DOMAIN="core.mohjave.com"

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Check if API key file exists
if [[ ! -f "$API_KEY_FILE" ]]; then
    log "ERROR: API key file not found: $API_KEY_FILE"
    exit 1
fi

# Load API key
DYNU_API_KEY=$(cat "$API_KEY_FILE")

if [[ -z "$DYNU_API_KEY" ]]; then
    log "ERROR: API key is empty"
    exit 1
fi

# Get current public IPv4 address
log "Getting current public IPv4 address..."
CURRENT_IPV4=$(curl -s https://api.ipify.org)

if [[ -z "$CURRENT_IPV4" ]]; then
    log "ERROR: Failed to get current public IPv4 address"
    exit 1
fi

log "Current public IPv4: $CURRENT_IPV4"

# Get current DNS record
log "Checking current DNS record for $DOMAIN..."
DNS_IPV4=$(dig +short "$DOMAIN" A | head -1)

log "Current DNS IPv4: $DNS_IPV4"

# Check if update is needed
if [[ "$CURRENT_IPV4" == "$DNS_IPV4" ]]; then
    log "DNS record is already up to date. No update needed."
    exit 0
fi

log "DNS update required: $DNS_IPV4 -> $CURRENT_IPV4"

# Update DNS using Dynu API
# Dynu API v2 endpoint for updating IP address
log "Updating DNS record via Dynu API..."

# Using Dynu's IP update API (compatible with DynDNS protocol)
RESPONSE=$(curl -s -k "https://api.dynu.com/nic/update?hostname=${DOMAIN}&myip=${CURRENT_IPV4}" \
    -H "Authorization: Bearer ${DYNU_API_KEY}")

log "API Response: $RESPONSE"

# Check response
if echo "$RESPONSE" | grep -qi "good\|nochg"; then
    log "SUCCESS: DNS record updated successfully"
    log "New IP: $CURRENT_IPV4"
    exit 0
elif echo "$RESPONSE" | grep -qi "badauth"; then
    log "ERROR: Authentication failed - check API key"
    exit 1
else
    log "WARNING: Unexpected API response: $RESPONSE"
    # Verify the update worked
    sleep 5
    NEW_DNS_IPV4=$(dig +short "$DOMAIN" A | head -1)
    if [[ "$NEW_DNS_IPV4" == "$CURRENT_IPV4" ]]; then
        log "SUCCESS: DNS record verified updated to $CURRENT_IPV4"
        exit 0
    else
        log "ERROR: DNS update may have failed. Current DNS: $NEW_DNS_IPV4"
        exit 1
    fi
fi
