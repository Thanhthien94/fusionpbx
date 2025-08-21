#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

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

# Initialize PostgreSQL if needed
init_postgresql() {
    if [ ! -d "/var/lib/postgresql/15/main" ]; then
        log "Initializing PostgreSQL database cluster..."
        su - postgres -c "/usr/lib/postgresql/15/bin/initdb -D /var/lib/postgresql/15/main --encoding=UTF-8 --lc-collate=C --lc-ctype=C"
        log "PostgreSQL initialized successfully"
    else
        log "PostgreSQL already initialized"
    fi
}

# Setup basic permissions
setup_permissions() {
    log "Setting up basic permissions..."

    # Ensure PostgreSQL data directory ownership
    chown -R postgres:postgres /var/lib/postgresql

    # Ensure FusionPBX web directory permissions
    chown -R www-data:www-data /var/www/fusionpbx

    # Ensure FreeSWITCH directory permissions
    chown -R fusionpbx:fusionpbx /usr/local/freeswitch

    # Ensure FreeSWITCH config directory exists and is writable
    mkdir -p /etc/freeswitch
    mkdir -p /etc/freeswitch/autoload_configs
    mkdir -p /etc/freeswitch/sip_profiles
    mkdir -p /var/lib/freeswitch
    mkdir -p /var/lib/freeswitch/db
    mkdir -p /var/lib/freeswitch/storage
    mkdir -p /usr/share/freeswitch/scripts
    chown -R www-data:www-data /etc/freeswitch
    chmod -R 775 /etc/freeswitch

    # Ensure FusionPBX config directory exists and is writable
    mkdir -p /etc/fusionpbx
    chown -R www-data:www-data /etc/fusionpbx
    chmod 755 /etc/fusionpbx

    # Ensure cache directory exists
    mkdir -p /var/cache/fusionpbx
    chown -R www-data:www-data /var/cache/fusionpbx

    # Ensure log directories exist and have proper permissions
    mkdir -p /var/log/supervisor /var/log/nginx /var/log/postgresql /var/log/fusionpbx
    chown -R www-data:www-data /var/log/fusionpbx

    log "Basic permissions set successfully"
}

# Wait for PostgreSQL to be ready
wait_for_postgres() {
    log "Waiting for PostgreSQL to be ready..."
    for i in {1..30}; do
        if su - postgres -c "psql -c 'SELECT 1;'" >/dev/null 2>&1; then
            log "PostgreSQL is ready"
            return 0
        fi
        sleep 2
    done
    error "PostgreSQL failed to start"
}

# Create database and user if they don't exist
setup_database() {
    log "Setting up database..."

    # Set default values
    local db_name="${DB_NAME:-fusionpbx}"
    local db_username="${DB_USER:-fusionpbx}"
    local db_password="${DB_PASSWORD:-fusionpbx}"

    # Create database and user
    su - postgres -c "psql -c \"CREATE DATABASE $db_name;\"" 2>/dev/null || true
    su - postgres -c "psql -c \"CREATE USER $db_username WITH PASSWORD '$db_password';\"" 2>/dev/null || true
    su - postgres -c "psql -c \"GRANT ALL PRIVILEGES ON DATABASE $db_name TO $db_username;\"" 2>/dev/null || true
    su - postgres -c "psql -d $db_name -c \"GRANT CREATE ON SCHEMA public TO $db_username;\"" 2>/dev/null || true

    # Create FusionPBX config.conf (following official pattern)
    log "Creating FusionPBX configuration..."
    mkdir -p /etc/fusionpbx
    cp /fusionpbx-config.conf /etc/fusionpbx/config.conf
    sed -i "s/{database_host}/$DB_HOST/g" /etc/fusionpbx/config.conf
    sed -i "s/{database_name}/$db_name/g" /etc/fusionpbx/config.conf
    sed -i "s/{database_username}/$db_username/g" /etc/fusionpbx/config.conf
    sed -i "s/{database_password}/$db_password/g" /etc/fusionpbx/config.conf

    log "Database setup completed"
}

# Check if FusionPBX is installed by checking database schema
is_fusionpbx_installed() {
    # Check if essential FusionPBX tables exist
    local table_count=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_name IN ('v_domains', 'v_users', 'v_groups');" 2>/dev/null | tr -d ' ')

    if [ "$table_count" = "3" ]; then
        return 0  # installed
    fi
    return 1  # not installed
}

# Check if setup wizard should be used (only if AUTO_INSTALL is not enabled)
should_use_setup_wizard() {
    # If AUTO_INSTALL is enabled, never use setup wizard
    if [ "${AUTO_INSTALL:-false}" = "true" ]; then
        return 1  # false - use auto install
    fi

    # Otherwise check FUSIONPBX_SETUP_WIZARD
    if [ "${FUSIONPBX_SETUP_WIZARD:-false}" = "true" ]; then
        return 0  # true - use setup wizard
    fi

    # Default: use setup wizard for safety
    return 0  # true
}

# Main initialization
main() {
    log "🚀 Starting FusionPBX container initialization..."

    # Basic setup
    init_postgresql
    setup_permissions

    # Start supervisord in background to start services
    log "Starting services..."
    /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf &
    SUPERVISOR_PID=$!

    # Wait a bit for services to start
    sleep 10

    # Setup database
    wait_for_postgres
    setup_database

    # Check installation status and provide guidance
    if is_fusionpbx_installed; then
        log "✅ FusionPBX already installed"
        log "🌐 Access FusionPBX at: http://localhost/"
    else
        if should_use_setup_wizard; then
            log "🎯 Setup Wizard Mode - Manual configuration required"
            log "📋 Access setup wizard at: http://localhost/core/install/install.php"
            log "💾 Database credentials:"
            log "   - Host: ${DB_HOST}"
            log "   - Port: ${DB_PORT}"
            log "   - Database: ${DB_NAME}"
            log "   - Username: ${DB_USER}"
            log "   - Password: ${DB_PASSWORD}"
            log "✅ Setup wizard ready - please open browser to complete installation"
        else
            log "🤖 Auto-Install Mode - Following official installation pattern"

            # Step 1: Create database schema (official: upgrade.php --schema)
            log "Creating database schema..."
            php /var/www/fusionpbx/core/upgrade/upgrade.php --schema

            # Step 2: Create domain and admin user (official pattern)
            log "Creating domain and admin user..."
            php /create-admin.php

            # Step 3: Run app defaults (official: upgrade.php --defaults)
            log "Setting up application defaults..."
            php /var/www/fusionpbx/core/upgrade/upgrade.php --defaults

            # Step 4: Update permissions (official: upgrade.php --permissions)
            log "Updating permissions..."
            php /var/www/fusionpbx/core/upgrade/upgrade.php --permissions

            # Step 5: Debug and verify user groups
            log "Debugging user groups..."
            php /debug-user-groups.php

            # Step 6: Force assign superadmin group if needed
            log "Ensuring admin user has superadmin group..."
            php /create-admin.php

            log "✅ Auto-install completed following official pattern!"
            log "🌐 Access FusionPBX at: http://localhost/"
            log "👤 Login: ${FUSIONPBX_ADMIN_USER:-admin}@${FUSIONPBX_DOMAIN:-localhost}"
            log "🔑 Password: ${FUSIONPBX_ADMIN_PASSWORD:-admin}"
        fi
    fi

    log "✅ Initialization complete"

    # Wait for supervisor
    wait $SUPERVISOR_PID
}

# Run main function
main "$@"