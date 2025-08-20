#!/bin/bash

# FusionPBX Production Deployment Script
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

# Detect OS
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="Linux"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    OS="Mac"
    error "Production deployment is not supported on macOS. Use deploy-dev.sh for development."
else
    OS="Unknown"
    warn "Unknown OS detected: $OSTYPE"
fi

log "Detected OS: $OS"

# Load environment variables
if [ -f .env.production ]; then
    source .env.production
    log "Production environment variables loaded"
elif [ -f .env ]; then
    source .env
    log "Environment variables loaded"
else
    warn ".env file not found, using defaults"
fi

# Display admin credentials
log "Admin credentials: ${FUSIONPBX_ADMIN_USER:-admin} / ${FUSIONPBX_ADMIN_PASSWORD:-Finstar@2025}"

# Create required directories
log "Creating required directories..."
mkdir -p /opt/fusionpbx/{data,config,recordings,logs,sounds,storage}
chmod 755 /opt/fusionpbx

# Set proper permissions for PostgreSQL data directory
log "Setting proper permissions for PostgreSQL data directory..."
chmod 700 /opt/fusionpbx/data
chmod 755 /opt/fusionpbx/config
chmod 755 /opt/fusionpbx/recordings
chmod 755 /opt/fusionpbx/logs
chmod 755 /opt/fusionpbx/sounds
chmod 755 /opt/fusionpbx/storage

# Ensure PostgreSQL data subdirectories have correct permissions
if [ -d "/opt/fusionpbx/data/15" ]; then
    log "Fixing existing PostgreSQL data permissions..."
    chmod 700 /opt/fusionpbx/data/15
    if [ -d "/opt/fusionpbx/data/15/main" ]; then
        chmod 700 /opt/fusionpbx/data/15/main
    fi
fi

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    error "Docker is not installed. Please install Docker first."
fi

# Determine Docker Compose command
if command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker-compose"
elif docker compose version &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker compose"
else
    error "Docker Compose is not installed. Please install Docker Compose first."
fi

log "Using Docker Compose command: $DOCKER_COMPOSE_CMD"

# Handle image building or pulling
if [ "${BUILD_IMAGE:-false}" = "true" ]; then
    log "Building FusionPBX image locally..."
    docker build -t fusionpbx-custom:latest .

    # Update docker-compose to use local image
    export FUSIONPBX_IMAGE="fusionpbx-custom:latest"
    log "✅ Image built successfully"
else
    log "Pulling latest FusionPBX image..."
    docker pull ${FUSIONPBX_IMAGE:-skytruongdev/fusionpbx:latest}
fi

# Stop existing container if running
if [ "$(docker ps -q -f name=fusionpbx)" ]; then
    log "Stopping existing FusionPBX container..."
    $DOCKER_COMPOSE_CMD down
fi

# Handle clean deployment
if [ "${CLEAN_DEPLOY:-false}" = "true" ]; then
    log "Performing clean deployment..."

    # Clean up any existing containers
    if [ "$(docker ps -aq -f name=fusionpbx)" ]; then
        log "Removing existing FusionPBX container..."
        docker rm -f fusionpbx 2>/dev/null || true
    fi

    # Clean data directories if requested
    log "Cleaning production data directories..."
    rm -rf /opt/fusionpbx/data/*
    rm -rf /opt/fusionpbx/config/*
    log "✅ Production data directories cleaned"

    # Remove Docker volumes
    log "Removing Docker volumes..."
    docker volume prune -f
    log "✅ Clean deployment prepared - all data and volumes removed"
else
    # Clean up any existing containers
    if [ "$(docker ps -aq -f name=fusionpbx)" ]; then
        log "Removing existing FusionPBX container..."
        docker rm -f fusionpbx 2>/dev/null || true
    fi
fi

# Reset PostgreSQL data permissions after container stop
log "Resetting PostgreSQL data permissions..."
if [ -d "/opt/fusionpbx/data" ]; then
    chmod 700 /opt/fusionpbx/data
    # Set ownership to postgres user (UID 999 in container)
    chown -R 999:999 /opt/fusionpbx/data
    if [ -d "/opt/fusionpbx/data/15" ]; then
        chmod 700 /opt/fusionpbx/data/15
        if [ -d "/opt/fusionpbx/data/15/main" ]; then
            chmod 700 /opt/fusionpbx/data/15/main
            # Fix all subdirectories permissions
            find /opt/fusionpbx/data/15/main -type d -exec chmod 700 {} \;
        fi
    fi
fi

# Configure firewall for FusionPBX ports (Bridge Network Mode) - OPTIONAL
if [ "${CONFIGURE_FIREWALL:-false}" = "true" ]; then
    log "Configuring firewall rules for FusionPBX (Bridge Network Mode)..."
    if command -v ufw &> /dev/null; then
        ufw allow 8080/tcp      # HTTP Web Interface (bridge network)
        ufw allow 8443/tcp      # HTTPS Web Interface (bridge network)
        ufw allow 5060/tcp      # SIP TCP
        ufw allow 5060/udp      # SIP UDP
        ufw allow 5080/tcp      # SIP Alternative TCP
        ufw allow 5080/udp      # SIP Alternative UDP
        ufw allow 8021/tcp      # FreeSWITCH Event Socket (bridge network)
        ufw allow 10000:10100/udp  # RTP Media
        log "UFW firewall rules configured for bridge network"
    elif command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-port=8080/tcp
        firewall-cmd --permanent --add-port=8443/tcp
        firewall-cmd --permanent --add-port=5060/tcp
        firewall-cmd --permanent --add-port=5060/udp
        firewall-cmd --permanent --add-port=5080/tcp
        firewall-cmd --permanent --add-port=5080/udp
        firewall-cmd --permanent --add-port=8021/tcp
        firewall-cmd --permanent --add-port=10000-10100/udp
        firewall-cmd --reload
        log "Firewalld rules configured for bridge network"
    else
        warn "No firewall detected. Please configure manually."
    fi
else
    warn "Firewall configuration skipped. Set CONFIGURE_FIREWALL=true to enable automatic firewall configuration."
    warn "Required ports: 8080, 8443, 5060, 5080, 8021, 10000-10100"
fi

# Start services
log "Starting FusionPBX production services with host network..."
$DOCKER_COMPOSE_CMD up -d

# Wait for services to be ready
log "Waiting for services to initialize..."
sleep 60  # Increased wait time for auto-install

# Check container health
log "Checking container health..."
for i in {1..20}; do  # Increased retries for auto-install
    if [ "$(docker inspect --format='{{.State.Health.Status}}' fusionpbx 2>/dev/null)" = "healthy" ]; then
        log "✅ FusionPBX Production is healthy and ready!"
        break
    fi
    if [ $i -eq 20 ]; then
        error "❌ FusionPBX failed to become healthy"
    fi
    log "Waiting for health check... ($i/20)"
    sleep 15
done

# Check FusionPBX installation status
log "Checking FusionPBX installation status..."

# Function to check if FusionPBX is installed
check_installation() {
    local table_count=$(docker exec fusionpbx bash -c "PGPASSWORD='fusionpbx' psql -h localhost -U fusionpbx -d fusionpbx -t -c \"SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_name IN ('v_domains', 'v_users', 'v_groups');\" 2>/dev/null | tr -d ' '")

    if [ "$table_count" = "3" ]; then
        return 0  # installed
    fi
    return 1  # not installed
}

# Wait for auto-installation to complete
if [ "${AUTO_INSTALL:-true}" = "true" ]; then
    for i in {1..15}; do  # Wait up to 15 minutes for auto-install
        if check_installation; then
            log "✅ FusionPBX auto-installation completed successfully!"

            # Check if admin user exists
            local admin_exists=$(docker exec fusionpbx bash -c "PGPASSWORD='fusionpbx' psql -h localhost -U fusionpbx -d fusionpbx -t -c \"SELECT COUNT(*) FROM v_users WHERE username = '${FUSIONPBX_ADMIN_USER:-admin}' AND user_enabled = 'true';\" 2>/dev/null | tr -d ' '")

            if [ "$admin_exists" = "1" ]; then
                log "✅ Admin user '${FUSIONPBX_ADMIN_USER:-admin}' is ready"
            else
                warn "⚠️ Admin user may need manual verification"
            fi
            break
        fi

        if [ $i -eq 15 ]; then
            warn "⚠️ FusionPBX auto-installation may need manual completion"
            warn "Please access http://$(hostname -I | awk '{print $1}')/core/install/install.php to complete setup"
        fi

        log "Waiting for auto-installation... ($i/15)"
        sleep 60
    done
else
    log "Manual installation mode - please complete setup via web interface"
fi

# Get server IP
SERVER_IP=$(hostname -I | awk '{print $1}')

# Display status
log "Production deployment completed successfully!"
echo
echo -e "${BLUE}=== FusionPBX Production Deployment Status ===${NC}"
echo -e "${GREEN}✅ Container Status:${NC} $(docker ps --format 'table {{.Names}}\t{{.Status}}' --filter name=fusionpbx)"
echo -e "${GREEN}✅ Network Mode:${NC} Bridge Network (Port Mapping)"
echo -e "${GREEN}✅ HTTP Interface:${NC} http://${SERVER_IP}:8080"
echo -e "${GREEN}✅ HTTPS Interface:${NC} https://${SERVER_IP}:8443"
echo -e "${GREEN}✅ Admin Login:${NC} ${FUSIONPBX_ADMIN_USER:-admin} / ${FUSIONPBX_ADMIN_PASSWORD:-Finstar@2025}"
echo -e "${GREEN}✅ Database:${NC} ${DB_NAME:-fusionpbx} (${DB_USER:-fusionpbx})"
echo -e "${GREEN}✅ SIP Server:${NC} ${SERVER_IP}:5060"
echo -e "${GREEN}✅ Logs:${NC} docker logs fusionpbx"
echo
echo -e "${YELLOW}📋 Port Mapping:${NC}"
echo "• HTTP: 8080 → 80 (Web Interface)"
echo "• HTTPS: 8443 → 443 (Secure Web Interface)"
echo "• SIP: 5060 → 5060 (TCP/UDP)"
echo "• SIP Alt: 5080 → 5080 (TCP/UDP)"
echo "• Event Socket: 8021 → 8021"
echo "• RTP: 10000-10100 → 10000-10100 (UDP)"
echo
echo -e "${YELLOW}📋 Production Features:${NC}"
echo "• Bridge Network (Compatible with existing services)"
echo "• Auto-Installation: ${AUTO_INSTALL:-true}"
echo "• HTTPS: ${ENABLE_HTTPS:-true}"
echo "• Fail2Ban: ${ENABLE_FAIL2BAN:-true}"
echo "• Persistent Data Storage: /opt/fusionpbx/"
echo
echo -e "${YELLOW}📋 Next Steps:${NC}"
echo "1. Access http://${SERVER_IP}:8080 or https://${SERVER_IP}:8443"
echo "2. Configure Nginx Proxy Manager to proxy ${FUSIONPBX_DOMAIN:-pbx.finstar.vn} → ${SERVER_IP}:8080"
echo "3. Set up extensions and dial plans"
echo "4. Test SIP connectivity on ${SERVER_IP}:5060"
echo "5. Check logs: docker logs fusionpbx -f"
echo
echo -e "${YELLOW}📋 Useful Commands:${NC}"
echo "• View logs: docker logs fusionpbx -f"
echo "• Stop: $DOCKER_COMPOSE_CMD down"
echo "• Restart: $DOCKER_COMPOSE_CMD restart"
echo "• Shell access: docker exec -it fusionpbx bash"
echo

log "🎉 FusionPBX production deployment completed successfully!"
