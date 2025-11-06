#!/bin/bash
# Restart TeamCity services

set -euo pipefail

TEAMCITY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Restarting TeamCity services..."
cd "$TEAMCITY_DIR"
docker compose restart

echo ""
echo "Waiting for services to restart..."
sleep 10

echo ""
echo "Service status:"
docker ps | grep teamcity

echo ""
echo "TeamCity restarted successfully!"
echo ""
echo "Access TeamCity at: https://teamcity.core.mohjave.com"
