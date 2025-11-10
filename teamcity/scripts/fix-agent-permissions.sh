#!/bin/bash
# Fix TeamCity agent directory permissions
# This script ensures proper permissions for:
# - Agent configuration directories
# - Artifact storage directory (for build outputs)

set -euo pipefail

AGENT_CONF_DIR="/srv/data/teamcity/agent"
ARTIFACTS_DIR="/srv/data/artifacts"

echo "=================================="
echo "TeamCity Agent Permissions Fix"
echo "=================================="
echo ""

# Fix agent configuration directories
echo "Fixing TeamCity agent directory permissions..."
for i in 1 2 3; do
    AGENT_DIR="${AGENT_CONF_DIR}${i}"
    if [ -d "$AGENT_DIR" ]; then
        echo "  - Fixing $AGENT_DIR"
        sudo chown -R 1000:1000 "$AGENT_DIR"
        sudo chmod 755 "$AGENT_DIR"
    else
        echo "  - Creating $AGENT_DIR"
        sudo mkdir -p "$AGENT_DIR"
        sudo chown -R 1000:1000 "$AGENT_DIR"
        sudo chmod 755 "$AGENT_DIR"
    fi
done

# Fix artifacts directory
echo ""
echo "Setting up artifacts directory..."
if [ ! -d "$ARTIFACTS_DIR" ]; then
    echo "  - Creating $ARTIFACTS_DIR"
    sudo mkdir -p "$ARTIFACTS_DIR"
fi

# Create subdirectories for different artifact types
for artifact_type in iso jar npm python docker generic; do
    if [ ! -d "$ARTIFACTS_DIR/$artifact_type" ]; then
        echo "  - Creating $ARTIFACTS_DIR/$artifact_type"
        sudo mkdir -p "$ARTIFACTS_DIR/$artifact_type"
    fi
done

# Set ownership (buildagent UID:GID is 1000:1000)
echo "  - Setting ownership to buildagent (1000:1000)"
sudo chown -R 1000:1000 "$ARTIFACTS_DIR"

# Set permissions (755 allows read/execute for web server)
echo "  - Setting permissions (755)"
sudo chmod -R 755 "$ARTIFACTS_DIR"

# Restart all agents
echo ""
echo "Restarting agents..."
for i in 1 2 3; do
    AGENT_NAME="teamcity-agent-$i"
    if docker ps -a --format '{{.Names}}' | grep -q "^${AGENT_NAME}$"; then
        echo "  - Restarting $AGENT_NAME"
        docker restart "$AGENT_NAME"
    fi
done

echo ""
echo "Waiting for agents to restart..."
sleep 10

echo ""
echo "Agent status:"
docker ps | grep teamcity-agent || echo "No agents running"

echo ""
echo "=================================="
echo "Permissions fixed successfully!"
echo "=================================="
echo ""
echo "Verification:"
echo "  - Agent configs: ls -la /srv/data/teamcity/agent*"
echo "  - Artifacts dir: ls -la $ARTIFACTS_DIR"
echo "  - Agent logs: docker logs teamcity-agent-1"
echo ""
