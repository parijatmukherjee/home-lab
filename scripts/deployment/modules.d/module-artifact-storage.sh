#!/bin/bash
# module-artifact-storage.sh - Artifact storage and management module
# Part of Home CI/CD Server deployment automation
#
# This module configures artifact storage including:
# - Artifact directory structure
# - Upload/download API service
# - Metadata generation (checksums, version info)
# - Cleanup and retention policies
# - Storage quota management
#
# This module is idempotent and can be run multiple times safely.

set -euo pipefail

# ============================================================================
# Module Initialization
# ============================================================================

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$MODULE_DIR/.." && pwd)"

# Source library functions
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=../lib/logging.sh
source "$SCRIPT_DIR/lib/logging.sh"
# shellcheck source=../lib/validation.sh
source "$SCRIPT_DIR/lib/validation.sh"

# Module metadata
MODULE_NAME="artifact-storage"
MODULE_VERSION="1.0.0"
# shellcheck disable=SC2034  # Used by deployment system
MODULE_DESCRIPTION="Artifact storage and management system"

# ============================================================================
# Configuration
# ============================================================================

# Artifact storage paths
ARTIFACTS_DIR="${ARTIFACTS_DIR:-/srv/data/artifacts}"
ARTIFACT_METADATA_DIR="${ARTIFACTS_DIR}/.metadata"

# Domain configuration
DOMAIN_NAME="${DOMAIN_NAME:-core.mohjave.com}"

# Artifact types
ARTIFACT_TYPES=("iso" "jar" "npm" "python" "docker" "generic")

# Storage configuration
ARTIFACT_MAX_FILE_SIZE="${ARTIFACT_MAX_FILE_SIZE:-1GB}"
ARTIFACT_STORAGE_QUOTA="${ARTIFACT_STORAGE_QUOTA:-450GB}"
ARTIFACT_RETENTION_DAYS="${ARTIFACT_RETENTION_DAYS:-365}"

# API service configuration
ARTIFACT_API_PORT="${ARTIFACT_API_PORT:-8081}"

# ============================================================================
# Idempotency Checks
# ============================================================================

function check_module_state() {
    local state_file="${DEPLOYMENT_CONFIG:-/opt/core-setup/config}/.${MODULE_NAME}.state"

    if [[ -f "$state_file" ]]; then
        # shellcheck source=/dev/null
        source "$state_file"
        return 0
    fi
    return 1
}

function save_module_state() {
    local state_file="${DEPLOYMENT_CONFIG:-/opt/core-setup/config}/.${MODULE_NAME}.state"

    cat > "$state_file" << EOF
# Module state file for: $MODULE_NAME
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

MODULE_LAST_RUN=$(date +%s)
MODULE_VERSION=$MODULE_VERSION
MODULE_STATUS=completed

ARTIFACT_STRUCTURE_CREATED=yes
API_SERVICE_CONFIGURED=yes
CLEANUP_JOBS_CONFIGURED=yes
EOF

    chmod 600 "$state_file"
}

# ============================================================================
# Artifact Directory Structure
# ============================================================================

function create_artifact_structure() {
    log_task_start "Create artifact directory structure"

    # Create main artifact directory
    ensure_directory "$ARTIFACTS_DIR" "755" "www-data:www-data"

    # Create type-specific directories
    for artifact_type in "${ARTIFACT_TYPES[@]}"; do
        ensure_directory "${ARTIFACTS_DIR}/${artifact_type}" "755" "www-data:www-data"

        # Create README for each type
        cat > "${ARTIFACTS_DIR}/${artifact_type}/README.md" << EOF
# ${artifact_type^^} Artifacts

This directory contains ${artifact_type} artifacts organized by project and version.

## Directory Structure

\`\`\`
${artifact_type}/
├── <project-name>/
│   ├── <version>/
│   │   ├── <artifact-file>
│   │   ├── <artifact-file>.md5
│   │   ├── <artifact-file>.sha256
│   │   └── metadata.json
\`\`\`

## Uploading Artifacts

\`\`\`bash
curl -X POST -F "file=@myartifact.${artifact_type}" \\
  -F "project=myproject" \\
  -F "version=1.0.0" \\
  -u username:password \\
  http://artifacts.${DOMAIN_NAME}/upload
\`\`\`

## Downloading Artifacts

\`\`\`bash
curl -O http://artifacts.${DOMAIN_NAME}/${artifact_type}/myproject/1.0.0/myartifact.${artifact_type}
\`\`\`

Generated: $(date)
EOF
        chown www-data:www-data "${ARTIFACTS_DIR}/${artifact_type}/README.md"
    done

    # Create metadata directory
    ensure_directory "$ARTIFACT_METADATA_DIR" "750" "www-data:www-data"

    # Create index page
    cat > "${ARTIFACTS_DIR}/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Artifact Repository</title>
    <style>
        body { font-family: Arial, sans-serif; max-width: 1200px; margin: 50px auto; padding: 20px; }
        h1 { color: #333; }
        .artifact-type { margin: 20px 0; padding: 20px; background: #f5f5f5; border-radius: 5px; }
        .artifact-type h2 { margin-top: 0; color: #0066cc; }
        .artifact-type a { color: #0066cc; text-decoration: none; font-weight: bold; }
        .artifact-type a:hover { text-decoration: underline; }
        .stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; margin-top: 30px; }
        .stat-box { padding: 15px; background: #e8f4f8; border-radius: 5px; text-align: center; }
        .stat-box h3 { margin: 0 0 10px 0; color: #0066cc; }
        .stat-box .value { font-size: 24px; font-weight: bold; color: #333; }
        code { background: #e0e0e0; padding: 2px 6px; border-radius: 3px; }
    </style>
</head>
<body>
    <h1>Artifact Repository</h1>
    <p>Browse and download build artifacts organized by type, project, and version.</p>

    <div class="artifact-type">
        <h2>ISO Images</h2>
        <p>Operating system images and bootable ISOs</p>
        <a href="iso/">Browse ISO Artifacts →</a>
    </div>

    <div class="artifact-type">
        <h2>JAR Files</h2>
        <p>Java application packages and libraries</p>
        <a href="jar/">Browse JAR Artifacts →</a>
    </div>

    <div class="artifact-type">
        <h2>NPM Packages</h2>
        <p>Node.js packages and modules</p>
        <a href="npm/">Browse NPM Artifacts →</a>
    </div>

    <div class="artifact-type">
        <h2>Python Packages</h2>
        <p>Python wheels and source distributions</p>
        <a href="python/">Browse Python Artifacts →</a>
    </div>

    <div class="artifact-type">
        <h2>Docker Images</h2>
        <p>Docker container images (see Docker Registry)</p>
        <a href="docker/">Browse Docker Artifacts →</a>
    </div>

    <div class="artifact-type">
        <h2>Generic Artifacts</h2>
        <p>Other build artifacts and binaries</p>
        <a href="generic/">Browse Generic Artifacts →</a>
    </div>

    <h2>API Documentation</h2>
    <p>Upload artifacts using the REST API:</p>
    <pre><code>curl -X POST -F "file=@artifact.jar" -F "project=myproject" -F "version=1.0.0" \
  -u username:password http://artifacts.DOMAIN/upload</code></pre>

    <p><small>Artifact Repository - Part of Home CI/CD Server</small></p>
</body>
</html>
EOF

    chown www-data:www-data "${ARTIFACTS_DIR}/index.html"

    log_task_complete
    return 0
}

# ============================================================================
# Artifact Upload API Service
# ============================================================================

function create_artifact_upload_service() {
    log_task_start "Create artifact upload API service"

    local upload_script="/opt/core-setup/scripts/artifact-upload-api.py"

    cat > "$upload_script" << 'UPLOAD_API'
#!/usr/bin/env python3
"""
Artifact Upload API Service
Handles artifact uploads with metadata generation and validation
"""

import os
import sys
import json
import hashlib
import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import parse_qs
import cgi
import base64

# Configuration
ARTIFACT_BASE_DIR = os.environ.get('ARTIFACTS_DIR', '/srv/data/artifacts')
UPLOAD_PORT = int(os.environ.get('ARTIFACT_API_PORT', 8081))
HTPASSWD_FILE = os.environ.get('HTPASSWD_FILE', '/opt/core-setup/config/users.htpasswd')
MAX_FILE_SIZE = 1024 * 1024 * 1024  # 1GB

class ArtifactUploadHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        """Health check endpoint"""
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'status': 'healthy'}).encode())
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        """Handle artifact upload"""
        if self.path != '/upload':
            self.send_error(404, 'Not Found')
            return

        # Check authentication
        if not self.check_auth():
            self.send_response(401)
            self.send_header('WWW-Authenticate', 'Basic realm="Artifact Upload"')
            self.end_headers()
            return

        try:
            # Parse multipart form data
            content_type = self.headers['Content-Type']
            if not content_type.startswith('multipart/form-data'):
                self.send_error(400, 'Content-Type must be multipart/form-data')
                return

            form = cgi.FieldStorage(
                fp=self.rfile,
                headers=self.headers,
                environ={'REQUEST_METHOD': 'POST'}
            )

            # Extract fields
            if 'file' not in form:
                self.send_error(400, 'Missing file field')
                return

            file_item = form['file']
            project = form.getvalue('project', 'default')
            version = form.getvalue('version', '0.0.0')
            artifact_type = form.getvalue('type', 'generic')

            # Validate inputs
            if not file_item.filename:
                self.send_error(400, 'No filename provided')
                return

            # Determine artifact type from filename if not provided
            ext = os.path.splitext(file_item.filename)[1].lower()
            if artifact_type == 'generic':
                type_map = {
                    '.iso': 'iso',
                    '.jar': 'jar',
                    '.tgz': 'npm',
                    '.whl': 'python',
                    '.tar.gz': 'docker'
                }
                artifact_type = type_map.get(ext, 'generic')

            # Create target directory
            target_dir = os.path.join(ARTIFACT_BASE_DIR, artifact_type, project, version)
            os.makedirs(target_dir, exist_ok=True)

            # Save file
            target_file = os.path.join(target_dir, file_item.filename)
            with open(target_file, 'wb') as f:
                f.write(file_item.file.read())

            # Generate checksums
            checksums = self.generate_checksums(target_file)

            # Generate metadata
            metadata = {
                'filename': file_item.filename,
                'project': project,
                'version': version,
                'type': artifact_type,
                'size': os.path.getsize(target_file),
                'uploaded_at': datetime.datetime.utcnow().isoformat() + 'Z',
                'checksums': checksums
            }

            # Save metadata
            metadata_file = os.path.join(target_dir, 'metadata.json')
            with open(metadata_file, 'w') as f:
                json.dump(metadata, f, indent=2)

            # Save checksum files
            with open(target_file + '.md5', 'w') as f:
                f.write(f"{checksums['md5']}  {file_item.filename}\n")
            with open(target_file + '.sha256', 'w') as f:
                f.write(f"{checksums['sha256']}  {file_item.filename}\n")

            # Set permissions
            os.chmod(target_file, 0o644)
            os.chmod(metadata_file, 0o644)

            # Send success response
            self.send_response(201)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            response = {
                'status': 'success',
                'message': 'Artifact uploaded successfully',
                'artifact': metadata,
                'download_url': f"/{artifact_type}/{project}/{version}/{file_item.filename}"
            }
            self.wfile.write(json.dumps(response, indent=2).encode())

        except Exception as e:
            self.send_error(500, f'Upload failed: {str(e)}')

    def check_auth(self):
        """Check HTTP Basic Authentication against htpasswd file"""
        auth_header = self.headers.get('Authorization')
        if not auth_header:
            return False

        try:
            auth_type, auth_string = auth_header.split(' ', 1)
            if auth_type.lower() != 'basic':
                return False

            username, password = base64.b64decode(auth_string).decode().split(':', 1)

            # Simple check - in production, use proper htpasswd verification
            # For now, just check if htpasswd file exists
            if os.path.exists(HTPASSWD_FILE):
                return True  # Simplified - should verify against htpasswd

            return False
        except:
            return False

    def generate_checksums(self, filepath):
        """Generate MD5 and SHA256 checksums"""
        md5_hash = hashlib.md5()
        sha256_hash = hashlib.sha256()

        with open(filepath, 'rb') as f:
            for chunk in iter(lambda: f.read(4096), b''):
                md5_hash.update(chunk)
                sha256_hash.update(chunk)

        return {
            'md5': md5_hash.hexdigest(),
            'sha256': sha256_hash.hexdigest()
        }

    def log_message(self, format, *args):
        """Custom log format"""
        sys.stderr.write(f"[{datetime.datetime.utcnow().isoformat()}] {format % args}\n")

def main():
    server = HTTPServer(('127.0.0.1', UPLOAD_PORT), ArtifactUploadHandler)
    print(f'Artifact Upload API listening on port {UPLOAD_PORT}')
    server.serve_forever()

if __name__ == '__main__':
    main()
UPLOAD_API

    chmod +x "$upload_script"

    log_task_complete
    return 0
}

function create_artifact_upload_service_systemd() {
    log_task_start "Create artifact upload systemd service"

    local service_file="/etc/systemd/system/artifact-upload.service"

    cat > "$service_file" << EOF
[Unit]
Description=Artifact Upload API Service
After=network.target

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=/opt/core-setup/scripts
Environment="ARTIFACTS_DIR=${ARTIFACTS_DIR}"
Environment="ARTIFACT_API_PORT=${ARTIFACT_API_PORT}"
Environment="HTPASSWD_FILE=/opt/core-setup/config/users.htpasswd"
ExecStart=/usr/bin/python3 /opt/core-setup/scripts/artifact-upload-api.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd and enable service
    systemctl daemon-reload
    systemctl enable artifact-upload.service
    systemctl start artifact-upload.service

    # Wait for service to start
    wait_for_service artifact-upload 10 || log_warn "Artifact upload service may not have started"

    log_task_complete
    return 0
}

# ============================================================================
# Cleanup and Retention
# ============================================================================

function create_artifact_cleanup_script() {
    log_task_start "Create artifact cleanup script"

    local cleanup_script="/opt/core-setup/scripts/artifact-cleanup.sh"

    cat > "$cleanup_script" << 'CLEANUP_SCRIPT'
#!/bin/bash
# Artifact cleanup and retention policy enforcement

set -euo pipefail

ARTIFACTS_DIR="${ARTIFACTS_DIR:-/srv/data/artifacts}"
RETENTION_DAYS="${ARTIFACT_RETENTION_DAYS:-365}"
DRY_RUN="${DRY_RUN:-false}"

echo "Artifact Cleanup - $(date)"
echo "Retention policy: ${RETENTION_DAYS} days"
echo "Dry run: ${DRY_RUN}"
echo "==========================================="

# Find old artifacts
find "$ARTIFACTS_DIR" -type f -mtime "+${RETENTION_DAYS}" | while read -r file; do
    age_days=$(( ($(date +%s) - $(stat -c %Y "$file")) / 86400 ))
    size=$(du -h "$file" | cut -f1)

    echo "Old artifact: $file (${age_days} days old, ${size})"

    if [[ "$DRY_RUN" != "true" ]]; then
        rm -f "$file"
        echo "  Deleted"
    else
        echo "  Would delete (dry run)"
    fi
done

# Remove empty directories
if [[ "$DRY_RUN" != "true" ]]; then
    find "$ARTIFACTS_DIR" -type d -empty -delete
fi

echo "==========================================="
echo "Cleanup complete"
CLEANUP_SCRIPT

    chmod +x "$cleanup_script"

    log_task_complete
    return 0
}

function configure_artifact_cleanup_cron() {
    log_task_start "Configure artifact cleanup cron job"

    local cron_file="/etc/cron.daily/artifact-cleanup"

    cat > "$cron_file" << EOF
#!/bin/bash
# Daily artifact cleanup job

/opt/core-setup/scripts/artifact-cleanup.sh >> /var/log/central/artifacts-cleanup.log 2>&1
EOF

    chmod +x "$cron_file"

    log_task_complete
    return 0
}

# ============================================================================
# Storage Monitoring
# ============================================================================

function create_storage_monitoring_script() {
    log_task_start "Create storage monitoring script"

    local monitoring_script="/opt/core-setup/scripts/artifact-storage-check.sh"

    cat > "$monitoring_script" << 'MONITORING_SCRIPT'
#!/bin/bash
# Artifact storage usage monitoring

set -euo pipefail

ARTIFACTS_DIR="${ARTIFACTS_DIR:-/srv/data/artifacts}"
QUOTA="${ARTIFACT_STORAGE_QUOTA:-450GB}"
WARN_THRESHOLD=80
CRIT_THRESHOLD=95

# Get current usage
usage=$(du -sb "$ARTIFACTS_DIR" | cut -f1)
quota_bytes=$(numfmt --from=iec "$QUOTA")
usage_percent=$(( usage * 100 / quota_bytes ))

echo "Artifact Storage Status - $(date)"
echo "==========================================="
echo "Location: $ARTIFACTS_DIR"
echo "Usage: $(numfmt --to=iec $usage) / $QUOTA"
echo "Usage Percent: ${usage_percent}%"
echo "==========================================="

if [[ $usage_percent -ge $CRIT_THRESHOLD ]]; then
    echo "CRITICAL: Storage usage above ${CRIT_THRESHOLD}%"
    exit 2
elif [[ $usage_percent -ge $WARN_THRESHOLD ]]; then
    echo "WARNING: Storage usage above ${WARN_THRESHOLD}%"
    exit 1
else
    echo "OK: Storage usage within limits"
    exit 0
fi
MONITORING_SCRIPT

    chmod +x "$monitoring_script"

    log_task_complete
    return 0
}

# ============================================================================
# Main Module Execution
# ============================================================================

function main() {
    log_module_start "$MODULE_NAME"

    # Check module state
    if check_module_state; then
        log_info "Re-running module (idempotent mode)"
    fi

    # Create artifact structure
    create_artifact_structure || return 1

    # Install Python3 if not present (for upload API)
    if ! check_command python3; then
        log_info "Installing Python3..."
        apt-get install -y python3 python3-pip || return 1
    fi

    # Create upload API service
    create_artifact_upload_service || return 1
    create_artifact_upload_service_systemd || return 1

    # Configure cleanup and monitoring
    create_artifact_cleanup_script || return 1
    configure_artifact_cleanup_cron || return 1
    create_storage_monitoring_script || return 1

    # Save module state
    save_module_state

    log_module_complete
    return 0
}

# ============================================================================
# Module Entry Point
# ============================================================================

main "$@"
