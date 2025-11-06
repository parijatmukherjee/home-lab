#!/bin/bash
# Fix TeamCity agent directory permissions

set -euo pipefail

AGENT_CONF_DIR="/srv/data/teamcity/agent"

echo "Fixing TeamCity agent directory permissions..."
sudo chown -R 1000:1000 "$AGENT_CONF_DIR"
sudo chmod 755 "$AGENT_CONF_DIR"

echo "Restarting agent..."
docker restart teamcity-agent-1

echo ""
echo "Waiting for agent to restart..."
sleep 10

echo "Agent status:"
docker ps | grep teamcity-agent-1

echo ""
echo "Agent permissions fixed!"
echo ""
echo "Check agent logs with: docker logs teamcity-agent-1"
