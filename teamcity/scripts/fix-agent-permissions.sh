#!/bin/bash
# Fix TeamCity agent directory permissions
# This script ensures proper permissions for:
# - Agent configuration directories
# - Artifact storage directory (for build outputs)
#
# Usage:
#   ./fix-agent-permissions.sh           # Just restart agents (for permission fixes)
#   ./fix-agent-permissions.sh --recreate # Recreate agents (for docker-compose.yml changes)

set -euo pipefail

AGENT_CONF_DIR="/srv/data/teamcity/agent"
ARTIFACTS_DIR="/srv/data/artifacts"
RECREATE_AGENTS=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --recreate)
            RECREATE_AGENTS=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --recreate    Recreate agents (needed for docker-compose.yml volume changes)"
            echo "  --help        Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                    # Fix permissions and restart agents"
            echo "  $0 --recreate         # Fix permissions and recreate agents"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Run '$0 --help' for usage"
            exit 1
            ;;
    esac
done

echo "=================================="
echo "TeamCity Agent Permissions Fix"
echo "=================================="
echo ""

if [ "$RECREATE_AGENTS" = true ]; then
    echo "Mode: Recreate agents (picks up docker-compose.yml changes)"
else
    echo "Mode: Restart agents (faster, for permission fixes only)"
fi
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

# Restart or recreate agents
echo ""
if [ "$RECREATE_AGENTS" = true ]; then
    echo "Recreating agents with updated configuration..."
    echo "NOTE: This will pick up docker-compose.yml changes (like new volume mounts)"
    echo "NOTE: TeamCity server will NOT be restarted"
    echo ""

    # Change to teamcity directory where docker-compose.yml is located
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    TEAMCITY_DIR="$(dirname "$SCRIPT_DIR")"

    cd "$TEAMCITY_DIR" || exit 1

    # Recreate ONLY the agents, not the server
    echo "  - Recreating teamcity-agent-1"
    docker compose up -d --force-recreate teamcity-agent-1
    echo "  - Recreating teamcity-agent-2"
    docker compose up -d --force-recreate teamcity-agent-2
    echo "  - Recreating teamcity-agent-3"
    docker compose up -d --force-recreate teamcity-agent-3

    echo ""
    echo "Waiting for agents to start..."
    sleep 15
else
    echo "Restarting agents..."
    echo "NOTE: This is a quick restart, won't pick up docker-compose.yml changes"
    echo "NOTE: Use --recreate flag if you changed docker-compose.yml"
    echo ""

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
fi

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

if [ "$RECREATE_AGENTS" = true ]; then
    echo "✅ Agents recreated with new configuration"
    echo "   Volume mounts and other docker-compose.yml changes are now active"
else
    echo "💡 Tip: If you changed docker-compose.yml (added volumes, etc.),"
    echo "   run with --recreate flag to apply those changes"
fi
echo ""
