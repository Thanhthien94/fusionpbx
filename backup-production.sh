#!/bin/bash

# FusionPBX Production Backup Script
# Author: Finstar Team
# Version: 1.0

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
BACKUP_DIR="/opt/fusionpbx/backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_NAME="fusionpbx_backup_${TIMESTAMP}"
RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-30}

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root"
fi

# Create backup directory
log "Creating backup directory..."
mkdir -p "$BACKUP_DIR"

# Check if container is running
if ! docker ps | grep -q fusionpbx; then
    error "FusionPBX container is not running"
fi

log "Starting FusionPBX backup: $BACKUP_NAME"

# Create backup subdirectory
BACKUP_PATH="$BACKUP_DIR/$BACKUP_NAME"
mkdir -p "$BACKUP_PATH"

# Backup database
log "Backing up PostgreSQL database..."
docker exec fusionpbx pg_dumpall -U postgres > "$BACKUP_PATH/database.sql"

# Backup configuration files
log "Backing up configuration files..."
cp -r /opt/fusionpbx/config "$BACKUP_PATH/" 2>/dev/null || warn "Config directory not found or empty"

# Backup recordings
log "Backing up recordings..."
if [ -d "/opt/fusionpbx/recordings" ] && [ "$(ls -A /opt/fusionpbx/recordings)" ]; then
    cp -r /opt/fusionpbx/recordings "$BACKUP_PATH/"
else
    warn "Recordings directory not found or empty"
fi

# Backup sounds (custom sounds only)
log "Backing up custom sounds..."
if [ -d "/opt/fusionpbx/sounds" ] && [ "$(ls -A /opt/fusionpbx/sounds)" ]; then
    cp -r /opt/fusionpbx/sounds "$BACKUP_PATH/"
else
    warn "Custom sounds directory not found or empty"
fi

# Backup storage
log "Backing up storage..."
if [ -d "/opt/fusionpbx/storage" ] && [ "$(ls -A /opt/fusionpbx/storage)" ]; then
    cp -r /opt/fusionpbx/storage "$BACKUP_PATH/"
else
    warn "Storage directory not found or empty"
fi

# Create backup info file
log "Creating backup info file..."
cat > "$BACKUP_PATH/backup_info.txt" << EOF
FusionPBX Backup Information
===========================
Backup Date: $(date)
Backup Name: $BACKUP_NAME
Server: $(hostname)
Server IP: $(hostname -I | awk '{print $1}')
Container Status: $(docker ps --format 'table {{.Names}}\t{{.Status}}' --filter name=fusionpbx)

Backup Contents:
- Database dump (database.sql)
- Configuration files (config/)
- Recordings (recordings/)
- Custom sounds (sounds/)
- Storage files (storage/)

Restore Instructions:
1. Stop FusionPBX container
2. Restore database: docker exec -i fusionpbx psql -U postgres < database.sql
3. Restore files to /opt/fusionpbx/
4. Start FusionPBX container
EOF

# Compress backup
log "Compressing backup..."
cd "$BACKUP_DIR"
tar -czf "${BACKUP_NAME}.tar.gz" "$BACKUP_NAME"
rm -rf "$BACKUP_NAME"

# Set proper permissions
chmod 600 "${BACKUP_NAME}.tar.gz"

# Calculate backup size
BACKUP_SIZE=$(du -h "${BACKUP_NAME}.tar.gz" | cut -f1)

log "✅ Backup completed successfully!"
log "📁 Backup file: $BACKUP_DIR/${BACKUP_NAME}.tar.gz"
log "📊 Backup size: $BACKUP_SIZE"

# Clean up old backups
log "Cleaning up old backups (retention: $RETENTION_DAYS days)..."
find "$BACKUP_DIR" -name "fusionpbx_backup_*.tar.gz" -mtime +$RETENTION_DAYS -delete

# List current backups
log "Current backups:"
ls -lh "$BACKUP_DIR"/fusionpbx_backup_*.tar.gz 2>/dev/null || log "No backups found"

log "🎉 FusionPBX backup process completed!"
