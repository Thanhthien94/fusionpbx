#!/bin/bash

# FusionPBX Production Restore Script
# Author: Finstar Team
# Version: 1.0

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Check parameters
if [ $# -eq 0 ]; then
    echo "Usage: $0 <backup_file.tar.gz>"
    echo
    echo "Available backups:"
    ls -lh /opt/fusionpbx/backups/fusionpbx_backup_*.tar.gz 2>/dev/null || echo "No backups found"
    exit 1
fi

BACKUP_FILE="$1"

# Check if backup file exists
if [ ! -f "$BACKUP_FILE" ]; then
    error "Backup file not found: $BACKUP_FILE"
fi

# Extract backup name
BACKUP_NAME=$(basename "$BACKUP_FILE" .tar.gz)
RESTORE_DIR="/tmp/fusionpbx_restore_$$"

log "Starting FusionPBX restore from: $BACKUP_FILE"

# Create temporary restore directory
mkdir -p "$RESTORE_DIR"

# Extract backup
log "Extracting backup..."
cd "$(dirname "$BACKUP_FILE")"
tar -xzf "$BACKUP_FILE" -C "$RESTORE_DIR"

# Check backup contents
BACKUP_CONTENT_DIR="$RESTORE_DIR/$BACKUP_NAME"
if [ ! -d "$BACKUP_CONTENT_DIR" ]; then
    error "Invalid backup structure"
fi

# Display backup info
if [ -f "$BACKUP_CONTENT_DIR/backup_info.txt" ]; then
    log "Backup information:"
    cat "$BACKUP_CONTENT_DIR/backup_info.txt"
    echo
fi

# Confirmation
read -p "Are you sure you want to restore this backup? This will overwrite current data. (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log "Restore cancelled"
    rm -rf "$RESTORE_DIR"
    exit 0
fi

# Stop FusionPBX container
log "Stopping FusionPBX container..."
if docker ps | grep -q fusionpbx; then
    docker-compose down
fi

# Backup current data (safety)
SAFETY_BACKUP="/opt/fusionpbx/backups/pre_restore_$(date +%Y%m%d_%H%M%S)"
log "Creating safety backup: $SAFETY_BACKUP"
mkdir -p "$SAFETY_BACKUP"
cp -r /opt/fusionpbx/data "$SAFETY_BACKUP/" 2>/dev/null || true
cp -r /opt/fusionpbx/config "$SAFETY_BACKUP/" 2>/dev/null || true

# Restore database data
if [ -f "$BACKUP_CONTENT_DIR/database.sql" ]; then
    log "Restoring database..."
    
    # Clear existing data
    rm -rf /opt/fusionpbx/data/*
    
    # Start container temporarily for database restore
    docker-compose up -d
    
    # Wait for PostgreSQL to be ready
    log "Waiting for PostgreSQL to be ready..."
    sleep 30
    
    # Restore database
    docker exec -i fusionpbx psql -U postgres < "$BACKUP_CONTENT_DIR/database.sql"
    
    # Stop container
    docker-compose down
else
    warn "Database backup not found in backup file"
fi

# Restore configuration files
if [ -d "$BACKUP_CONTENT_DIR/config" ]; then
    log "Restoring configuration files..."
    rm -rf /opt/fusionpbx/config/*
    cp -r "$BACKUP_CONTENT_DIR/config"/* /opt/fusionpbx/config/
else
    warn "Configuration backup not found in backup file"
fi

# Restore recordings
if [ -d "$BACKUP_CONTENT_DIR/recordings" ]; then
    log "Restoring recordings..."
    rm -rf /opt/fusionpbx/recordings/*
    cp -r "$BACKUP_CONTENT_DIR/recordings"/* /opt/fusionpbx/recordings/
else
    warn "Recordings backup not found in backup file"
fi

# Restore sounds
if [ -d "$BACKUP_CONTENT_DIR/sounds" ]; then
    log "Restoring custom sounds..."
    rm -rf /opt/fusionpbx/sounds/*
    cp -r "$BACKUP_CONTENT_DIR/sounds"/* /opt/fusionpbx/sounds/
else
    warn "Sounds backup not found in backup file"
fi

# Restore storage
if [ -d "$BACKUP_CONTENT_DIR/storage" ]; then
    log "Restoring storage..."
    rm -rf /opt/fusionpbx/storage/*
    cp -r "$BACKUP_CONTENT_DIR/storage"/* /opt/fusionpbx/storage/
else
    warn "Storage backup not found in backup file"
fi

# Fix permissions
log "Fixing permissions..."
chmod 700 /opt/fusionpbx/data
chown -R 999:999 /opt/fusionpbx/data
chmod 755 /opt/fusionpbx/config
chmod 755 /opt/fusionpbx/recordings
chmod 755 /opt/fusionpbx/sounds
chmod 755 /opt/fusionpbx/storage

# Start FusionPBX container
log "Starting FusionPBX container..."
docker-compose up -d

# Wait for services to be ready
log "Waiting for services to initialize..."
sleep 60

# Check container health
log "Checking container health..."
for i in {1..12}; do
    if [ "$(docker inspect --format='{{.State.Health.Status}}' fusionpbx 2>/dev/null)" = "healthy" ]; then
        log "✅ FusionPBX is healthy and ready!"
        break
    fi
    if [ $i -eq 12 ]; then
        error "❌ FusionPBX failed to become healthy after restore"
    fi
    log "Waiting for health check... ($i/12)"
    sleep 10
done

# Clean up
log "Cleaning up temporary files..."
rm -rf "$RESTORE_DIR"

# Get server IP
SERVER_IP=$(hostname -I | awk '{print $1}')

log "✅ FusionPBX restore completed successfully!"
log "🌐 Access FusionPBX at: http://${SERVER_IP}/"
log "📁 Safety backup created at: $SAFETY_BACKUP"

log "🎉 FusionPBX restore process completed!"
