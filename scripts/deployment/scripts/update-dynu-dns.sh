#!/bin/bash
# update-dynu-dns.sh - Update Dynu DNS records with current public IP
# Part of Home CI/CD Server deployment automation

set -euo pipefail

# Configuration
DEPLOYMENT_CONFIG="${DEPLOYMENT_CONFIG:-/opt/core-setup/config}"
API_KEY_FILE="${DEPLOYMENT_CONFIG}/.dynu-api-key"
DOMAIN="core.mohjave.com"
API_BASE="https://api.dynu.com/v2"

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
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

# Function to make API requests
api_request() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"

    if [[ -n "$data" ]]; then
        curl -s -X "$method" "${API_BASE}${endpoint}" \
            -H "API-Key: ${DYNU_API_KEY}" \
            -H "Content-Type: application/json" \
            -d "$data"
    else
        curl -s -X "$method" "${API_BASE}${endpoint}" \
            -H "API-Key: ${DYNU_API_KEY}"
    fi
}

# Get current public IPv4 address
log "Getting current public IPv4 address..."
CURRENT_IPV4=$(curl -4 -s ifconfig.me)

if [[ -z "$CURRENT_IPV4" ]]; then
    log "ERROR: Failed to get current public IPv4 address"
    exit 1
fi

log "Current public IPv4: $CURRENT_IPV4"

# Get current public IPv6 address
log "Getting current public IPv6 address..."
CURRENT_IPV6=$(curl -6 -s ifconfig.me 2>/dev/null || echo "")

if [[ -z "$CURRENT_IPV6" ]]; then
    log "WARNING: No IPv6 address available"
else
    log "Current public IPv6: $CURRENT_IPV6"
fi

# Get current DNS records from DNS
log "Checking current DNS records for $DOMAIN..."
DNS_IPV4=$(dig +short "$DOMAIN" A | head -1)
log "Current DNS IPv4: $DNS_IPV4"

DNS_IPV6=$(dig +short "$DOMAIN" AAAA | head -1)
if [[ -n "$DNS_IPV6" ]]; then
    log "Current DNS IPv6: $DNS_IPV6"
else
    log "Current DNS IPv6: (none)"
fi

# Check if update is needed
UPDATE_NEEDED=false
if [[ "$CURRENT_IPV4" != "$DNS_IPV4" ]]; then
    log "IPv4 update required: $DNS_IPV4 -> $CURRENT_IPV4"
    UPDATE_NEEDED=true
fi

if [[ -n "$CURRENT_IPV6" ]] && [[ "$CURRENT_IPV6" != "$DNS_IPV6" ]]; then
    log "IPv6 update required: $DNS_IPV6 -> $CURRENT_IPV6"
    UPDATE_NEEDED=true
fi

if [[ "$UPDATE_NEEDED" == "false" ]]; then
    log "DNS records are already up to date. No update needed."
    exit 0
fi

# Get domain ID from API
log "Getting domain information from Dynu API..."
DOMAINS_RESPONSE=$(api_request "GET" "/dns")

# Extract domain ID using grep and sed (avoiding jq dependency)
DOMAIN_ID=$(echo "$DOMAINS_RESPONSE" | grep -o "\"id\":[0-9]*" | head -1 | grep -o "[0-9]*")

if [[ -z "$DOMAIN_ID" ]]; then
    log "ERROR: Could not find domain ID for $DOMAIN"
    log "API Response: $DOMAINS_RESPONSE"
    exit 1
fi

log "Domain ID: $DOMAIN_ID"

# Check if IPv6 is enabled for the domain
log "Checking if IPv6 is enabled..."
IPV6_ENABLED=$(echo "$DOMAINS_RESPONSE" | grep -o '"ipv6":\(true\|false\)' | cut -d':' -f2)

if [[ -n "$CURRENT_IPV6" ]] && [[ "$IPV6_ENABLED" == "false" ]]; then
    log "IPv6 is disabled for domain. Enabling IPv6..."
    ENABLE_IPV6_JSON="{\"name\":\"${DOMAIN}\",\"ipv6\":true,\"ipv6Address\":\"${CURRENT_IPV6}\"}"
    ENABLE_RESPONSE=$(api_request "POST" "/dns/${DOMAIN_ID}" "$ENABLE_IPV6_JSON")
    log "Enable IPv6 response: ${ENABLE_RESPONSE:0:100}"
fi

# Get existing DNS records
log "Fetching DNS records..."
RECORDS_RESPONSE=$(api_request "GET" "/dns/${DOMAIN_ID}/record")

# Find A record ID
A_RECORD_ID=$(echo "$RECORDS_RESPONSE" | grep -o '"id":[0-9]*[^}]*"recordType":"A"' | grep -o '"id":[0-9]*' | grep -o '[0-9]*' | head -1)

# Find AAAA record ID
AAAA_RECORD_ID=$(echo "$RECORDS_RESPONSE" | grep -o '"id":[0-9]*[^}]*"recordType":"AAAA"' | grep -o '"id":[0-9]*' | grep -o '[0-9]*' | head -1)

# Update or create A record for IPv4
if [[ "$CURRENT_IPV4" != "$DNS_IPV4" ]]; then
    if [[ -n "$A_RECORD_ID" ]]; then
        log "Updating existing A record (ID: $A_RECORD_ID) with IPv4: $CURRENT_IPV4"
        _DELETE_RESPONSE=$(api_request "DELETE" "/dns/${DOMAIN_ID}/record/${A_RECORD_ID}")
    else
        log "Creating new A record with IPv4: $CURRENT_IPV4"
    fi

    # Create A record
    A_RECORD_JSON="{\"nodeName\":\"\",\"recordType\":\"A\",\"ttl\":90,\"state\":true,\"ipv4Address\":\"${CURRENT_IPV4}\"}"
    A_RESPONSE=$(api_request "POST" "/dns/${DOMAIN_ID}/record" "$A_RECORD_JSON")
    log "A record response: ${A_RESPONSE:0:100}"
fi

# Update or create AAAA record for IPv6
if [[ -n "$CURRENT_IPV6" ]] && [[ "$CURRENT_IPV6" != "$DNS_IPV6" ]]; then
    if [[ -n "$AAAA_RECORD_ID" ]]; then
        log "Updating existing AAAA record (ID: $AAAA_RECORD_ID) with IPv6: $CURRENT_IPV6"
        _DELETE_RESPONSE=$(api_request "DELETE" "/dns/${DOMAIN_ID}/record/${AAAA_RECORD_ID}")
    else
        log "Creating new AAAA record with IPv6: $CURRENT_IPV6"
    fi

    # Create AAAA record
    AAAA_RECORD_JSON="{\"nodeName\":\"\",\"recordType\":\"AAAA\",\"ttl\":90,\"state\":true,\"ipv6Address\":\"${CURRENT_IPV6}\"}"
    AAAA_RESPONSE=$(api_request "POST" "/dns/${DOMAIN_ID}/record" "$AAAA_RECORD_JSON")
    log "AAAA record response: ${AAAA_RESPONSE:0:100}"
fi

# Verify the updates worked
log "Verifying DNS updates..."
sleep 10  # DNS updates may take a bit longer with REST API
# Use Cloudflare DNS to avoid caching issues
NEW_DNS_IPV4=$(dig +short "$DOMAIN" A @1.1.1.1 | head -1)
NEW_DNS_IPV6=$(dig +short "$DOMAIN" AAAA @1.1.1.1 | head -1)

IPV4_UPDATED=false
IPV6_UPDATED=false

if [[ "$NEW_DNS_IPV4" == "$CURRENT_IPV4" ]]; then
    log "SUCCESS: IPv4 DNS record verified: $CURRENT_IPV4"
    IPV4_UPDATED=true
else
    log "ERROR: IPv4 DNS verification failed. Expected: $CURRENT_IPV4, Got: $NEW_DNS_IPV4"
fi

if [[ -n "$CURRENT_IPV6" ]]; then
    if [[ "$NEW_DNS_IPV6" == "$CURRENT_IPV6" ]]; then
        log "SUCCESS: IPv6 DNS record verified: $CURRENT_IPV6"
        IPV6_UPDATED=true
    else
        log "ERROR: IPv6 DNS verification failed. Expected: $CURRENT_IPV6, Got: $NEW_DNS_IPV6"
    fi
else
    IPV6_UPDATED=true  # No IPv6 to update
fi

if [[ "$IPV4_UPDATED" == "true" ]] && [[ "$IPV6_UPDATED" == "true" ]]; then
    log "All DNS records successfully updated and verified"
    exit 0
else
    log "DNS update verification failed"
    exit 1
fi
