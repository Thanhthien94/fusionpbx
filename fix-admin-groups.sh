#!/bin/bash

# FusionPBX - Fix Admin User Groups Script
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

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

log "🔧 FusionPBX - Fixing Admin User Groups..."

# Check if container is running
if ! docker ps | grep -q fusionpbx; then
    error "FusionPBX container is not running"
fi

# Load environment variables
if [ -f .env ]; then
    source .env
    log "Environment variables loaded from .env"
else
    warn ".env file not found, using defaults"
fi

# Get admin credentials
ADMIN_USER=${FUSIONPBX_ADMIN_USER:-admin}
ADMIN_DOMAIN=${FUSIONPBX_DOMAIN:-pbx.finstar.vn}

log "Admin User: $ADMIN_USER@$ADMIN_DOMAIN"

# Step 1: Debug current state
log "Step 1: Debugging current user groups..."
docker exec fusionpbx php /debug-user-groups.php

# Step 2: Run upgrade permissions
log "Step 2: Running upgrade permissions..."
docker exec fusionpbx php /var/www/fusionpbx/core/upgrade/upgrade.php --permissions

# Step 3: Run upgrade menu
log "Step 3: Running upgrade menu..."
docker exec fusionpbx php /var/www/fusionpbx/core/upgrade/upgrade.php --menu

# Step 4: Force create admin user and assign groups
log "Step 4: Force creating admin user and assigning groups..."
docker exec fusionpbx php /create-admin.php

# Step 5: Manual group assignment if needed
log "Step 5: Manual group assignment check..."

# Get user UUID
USER_UUID=$(docker exec fusionpbx bash -c "
PGPASSWORD='${DB_PASSWORD:-fusionpbx}' psql -h localhost -U ${DB_USER:-fusionpbx} -d ${DB_NAME:-fusionpbx} -t -c \"
SELECT user_uuid FROM v_users u 
JOIN v_domains d ON u.domain_uuid = d.domain_uuid 
WHERE u.username = '$ADMIN_USER' AND d.domain_name = '$ADMIN_DOMAIN';
\" | tr -d ' '
")

if [ -z "$USER_UUID" ] || [ "$USER_UUID" = "" ]; then
    error "Could not find admin user UUID"
fi

log "Admin User UUID: $USER_UUID"

# Check if user has superadmin group
HAS_SUPERADMIN=$(docker exec fusionpbx bash -c "
PGPASSWORD='${DB_PASSWORD:-fusionpbx}' psql -h localhost -U ${DB_USER:-fusionpbx} -d ${DB_NAME:-fusionpbx} -t -c \"
SELECT COUNT(*) FROM v_user_groups WHERE user_uuid = '$USER_UUID' AND group_name = 'superadmin';
\" | tr -d ' '
")

log "Current superadmin assignments: $HAS_SUPERADMIN"

if [ "$HAS_SUPERADMIN" = "0" ]; then
    warn "Admin user has no superadmin group, assigning manually..."
    
    # Get domain UUID
    DOMAIN_UUID=$(docker exec fusionpbx bash -c "
    PGPASSWORD='${DB_PASSWORD:-fusionpbx}' psql -h localhost -U ${DB_USER:-fusionpbx} -d ${DB_NAME:-fusionpbx} -t -c \"
    SELECT domain_uuid FROM v_domains WHERE domain_name = '$ADMIN_DOMAIN';
    \" | tr -d ' '
    ")
    
    # Get superadmin group UUID
    GROUP_UUID=$(docker exec fusionpbx bash -c "
    PGPASSWORD='${DB_PASSWORD:-fusionpbx}' psql -h localhost -U ${DB_USER:-fusionpbx} -d ${DB_NAME:-fusionpbx} -t -c \"
    SELECT group_uuid FROM v_groups WHERE group_name = 'superadmin' LIMIT 1;
    \" | tr -d ' '
    ")
    
    if [ -n "$GROUP_UUID" ] && [ "$GROUP_UUID" != "" ]; then
        log "Assigning superadmin group manually..."
        
        # Generate UUID for user_group
        USER_GROUP_UUID=$(docker exec fusionpbx bash -c "
        PGPASSWORD='${DB_PASSWORD:-fusionpbx}' psql -h localhost -U ${DB_USER:-fusionpbx} -d ${DB_NAME:-fusionpbx} -t -c \"
        SELECT gen_random_uuid();
        \" | tr -d ' '
        ")
        
        # Insert user group assignment
        docker exec fusionpbx bash -c "
        PGPASSWORD='${DB_PASSWORD:-fusionpbx}' psql -h localhost -U ${DB_USER:-fusionpbx} -d ${DB_NAME:-fusionpbx} -c \"
        INSERT INTO v_user_groups (user_group_uuid, domain_uuid, group_name, group_uuid, user_uuid) 
        VALUES ('$USER_GROUP_UUID', '$DOMAIN_UUID', 'superadmin', '$GROUP_UUID', '$USER_UUID')
        ON CONFLICT DO NOTHING;
        \"
        "
        
        log "✅ Superadmin group assigned manually"
    else
        error "Could not find superadmin group UUID"
    fi
else
    log "✅ Admin user already has superadmin group"
fi

# Step 6: Final verification
log "Step 6: Final verification..."
docker exec fusionpbx php /debug-user-groups.php

# Step 7: Clear cache
log "Step 7: Clearing cache..."
docker exec fusionpbx bash -c "
rm -rf /var/cache/fusionpbx/* 2>/dev/null || true
rm -rf /tmp/fusionpbx_cache/* 2>/dev/null || true
"

# Step 8: Restart PHP-FPM
log "Step 8: Restarting PHP-FPM..."
docker exec fusionpbx bash -c "
pkill -f php-fpm || true
sleep 2
/usr/sbin/php-fpm8.2 -D
"

log "✅ Admin user groups fix completed!"
log "🌐 Please try logging in again: http://server-ip:8080"
log "🔑 Login: $ADMIN_USER@$ADMIN_DOMAIN"
log "🔑 Password: ${FUSIONPBX_ADMIN_PASSWORD:-Finstar@2025}"

log "🎉 Fix process completed!"
