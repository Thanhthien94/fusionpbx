#!/bin/bash

# FusionPBX Development Deployment Script
# Author: Finstar Team
# Version: 2.0
# Environment: MacOS/Linux Development
# Features: Build + Deploy + Auto-install
#
# Usage:
#   ./deploy-dev.sh                    # Full build + clean deploy + auto-install
#   BUILD_IMAGE=false ./deploy-dev.sh  # Skip build, use existing image
#   CLEAN_DEPLOY=false ./deploy-dev.sh # Incremental deploy (keep data)
#   AUTO_INSTALL=false ./deploy-dev.sh # Skip auto-install, manual setup
#
# Environment Variables:
#   BUILD_IMAGE=true|false    - Build image locally vs pull from registry
#   CLEAN_DEPLOY=true|false   - Clean deploy (remove volumes) vs incremental
#   AUTO_INSTALL=true|false   - Auto-install FusionPBX vs manual setup
#   SKIP_PULL=true|false      - Skip pulling image when BUILD_IMAGE=false

set -e

# Script options
BUILD_IMAGE=${BUILD_IMAGE:-true}
CLEAN_DEPLOY=${CLEAN_DEPLOY:-true}
AUTO_INSTALL=${AUTO_INSTALL:-true}
SETUP_WIZARD=${SETUP_WIZARD:-true}  # Enable setup wizard by default
SKIP_PULL=${SKIP_PULL:-false}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
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

# Detect OS
OS="$(uname -s)"
case "${OS}" in
    Linux*)     MACHINE=Linux;;
    Darwin*)    MACHINE=Mac;;
    CYGWIN*)    MACHINE=Cygwin;;
    MINGW*)     MACHINE=MinGw;;
    *)          MACHINE="UNKNOWN:${OS}"
esac

log "Detected OS: ${MACHINE}"

# Load environment variables
if [ -f .env ]; then
    source .env
    log "Environment variables loaded"
    log "Admin credentials: ${FUSIONPBX_ADMIN_USER:-admin} / ${FUSIONPBX_ADMIN_PASSWORD:-admin123}"
else
    warn ".env file not found, using defaults"
    export FUSIONPBX_ADMIN_USER="admin"
    export FUSIONPBX_ADMIN_PASSWORD="admin123"
fi

# Export setup wizard configuration
export FUSIONPBX_SETUP_WIZARD="$SETUP_WIZARD"

# Create required directories for development
log "Creating required directories for development..."
mkdir -p ./dev-data/{data,config,recordings,logs,sounds,storage}

# Set proper permissions for development
log "Setting proper permissions for development environment..."
if [ "${MACHINE}" = "Mac" ]; then
    # MacOS specific permissions
    chmod 755 ./dev-data
    chmod 700 ./dev-data/data
    chmod 755 ./dev-data/{config,recordings,logs,sounds,storage}
    
    # Get current user ID for MacOS
    CURRENT_UID=$(id -u)
    CURRENT_GID=$(id -g)
    
    # Set ownership to current user for MacOS development
    chown -R ${CURRENT_UID}:${CURRENT_GID} ./dev-data
    
    # For PostgreSQL data directory, we need to ensure it's accessible
    # PostgreSQL in container runs as UID 999, but we'll handle this in entrypoint
    if [ -d "./dev-data/data" ]; then
        chmod 777 ./dev-data/data  # Temporary for MacOS development
    fi
else
    # Linux permissions
    chmod 755 ./dev-data
    chmod 700 ./dev-data/data
    chmod 755 ./dev-data/{config,recordings,logs,sounds,storage}
    
    # Set ownership to current user for Linux development
    chown -R $(id -u):$(id -g) ./dev-data
fi

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    error "Docker is not installed. Please install Docker Desktop first."
fi

# Check if Docker Compose is installed
if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    error "Docker Compose is not installed. Please install Docker Compose first."
fi

# Determine docker-compose command
if command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
else
    DOCKER_COMPOSE="docker compose"
fi

log "Using Docker Compose command: ${DOCKER_COMPOSE}"

# Build or pull image based on configuration
if [ "$BUILD_IMAGE" = "true" ]; then
    log "Building FusionPBX image locally..."
    docker build -t fusionpbx-custom:latest . || error "Failed to build image"
    log "✅ Image built successfully"
elif [ "$SKIP_PULL" = "false" ]; then
    log "Pulling latest FusionPBX image..."
    docker pull skytruongdev/fusionpbx:latest || error "Failed to pull image"
    # Tag the pulled image as fusionpbx-custom:latest for consistency
    docker tag skytruongdev/fusionpbx:latest fusionpbx-custom:latest
    log "✅ Image pulled and tagged successfully"
else
    log "Skipping image pull/build as requested"
fi

# Always stop existing containers first
log "Stopping existing containers..."
${DOCKER_COMPOSE} -f docker-compose.dev.yml down 2>/dev/null || true

# Clean deployment based on configuration
if [ "$CLEAN_DEPLOY" = "true" ]; then
    log "Performing clean deployment..."

    # Stop and remove everything including volumes
    ${DOCKER_COMPOSE} -f docker-compose.dev.yml down -v 2>/dev/null || true

    # Clean up any orphaned containers
    docker rm -f fusionpbx-dev 2>/dev/null || true

    # Clean up any existing networks
    docker network rm test_fusionpbx-network 2>/dev/null || true

    # Clean up local data directories
    log "Cleaning local data directories..."
    if [ -d "./dev-data" ]; then
        rm -rf ./dev-data
        log "✅ Local data directories cleaned"
    fi

    # Remove any existing volumes
    log "Removing Docker volumes..."
    docker volume rm test_fusionpbx-data 2>/dev/null || true
    docker volume rm test_fusionpbx-config 2>/dev/null || true
    docker volume rm test_fusionpbx-recordings 2>/dev/null || true
    docker volume rm test_fusionpbx-logs 2>/dev/null || true
    docker volume rm test_fusionpbx-sounds 2>/dev/null || true
    docker volume rm test_fusionpbx-storage 2>/dev/null || true

    log "✅ Clean deployment prepared - all data and volumes removed"

    # Recreate required directories after clean
    log "Recreating required directories after clean..."
    mkdir -p ./dev-data/{data,config,recordings,logs,sounds,storage}
else
    log "Performing incremental deployment..."
fi

# Reset data permissions for container compatibility
log "Preparing data directory for container..."
if [ -d "./dev-data/data" ]; then
    if [ "${MACHINE}" = "Mac" ]; then
        # For MacOS, ensure the directory is writable by container
        chmod 777 ./dev-data/data
        # Create a marker file to indicate fresh setup
        touch ./dev-data/data/.dev-setup
    else
        # For Linux, set proper PostgreSQL permissions
        chmod 700 ./dev-data/data
        # Set ownership to postgres user (UID 999 in container)
        if command -v sudo &> /dev/null; then
            sudo chown -R 999:999 ./dev-data/data 2>/dev/null || true
        fi
    fi
fi

# Start services
log "Starting FusionPBX development services with bridge network..."
${DOCKER_COMPOSE} -f docker-compose.dev.yml up -d

# Wait for services to be ready
log "Waiting for services to initialize..."
sleep 30

# Check container health
log "Checking container health..."
for i in {1..12}; do
    if [ "$(docker inspect --format='{{.State.Health.Status}}' fusionpbx-dev 2>/dev/null)" = "healthy" ]; then
        log "✅ FusionPBX Development is healthy and ready!"
        break
    fi
    if [ $i -eq 12 ]; then
        error "❌ FusionPBX Development failed to become healthy"
    fi
    log "Waiting for health check... ($i/12)"
    sleep 10
done

# Auto-install FusionPBX if enabled
if [ "$AUTO_INSTALL" = "true" ]; then
    log "Checking FusionPBX installation status..."

    # Wait a bit more for auto-installation to complete
    sleep 20

    # Check if installation completed by checking database
    for i in {1..10}; do
        # Check if admin user exists in database
        ADMIN_EXISTS=$(docker exec fusionpbx-dev bash -c "PGPASSWORD=\$DB_PASSWORD psql -h localhost -U \$DB_USER -d \$DB_NAME -t -c \"SELECT username FROM v_users WHERE username = '\$FUSIONPBX_ADMIN_USER';\" 2>/dev/null | tr -d ' '" || echo "")

        if [ -n "$ADMIN_EXISTS" ]; then
            log "✅ FusionPBX auto-installation completed successfully!"
            log "✅ Admin user '$FUSIONPBX_ADMIN_USER' is ready"
            break
        fi
        if [ $i -eq 10 ]; then
            warn "⚠️ FusionPBX auto-installation may need manual completion"
            log "Please access https://localhost:8443/core/install/install.php to complete setup"
        fi
        log "Waiting for auto-installation... ($i/10)"
        sleep 10
    done
else
    log "Auto-installation disabled, manual setup required"
fi

# Get container IP
CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' fusionpbx-dev 2>/dev/null || echo "N/A")

# Display status
log "Development deployment completed successfully!"
echo
echo -e "${BLUE}=== FusionPBX Development Deployment Status ===${NC}"
echo -e "${GREEN}✅ Container Status:${NC} $(docker ps --format 'table {{.Names}}\t{{.Status}}' --filter name=fusionpbx-dev)"
echo -e "${GREEN}✅ Network Mode:${NC} Bridge Network"
echo -e "${GREEN}✅ Container IP:${NC} ${CONTAINER_IP}"
echo -e "${GREEN}✅ HTTP Interface:${NC} http://localhost:8080"
echo -e "${GREEN}✅ HTTPS Interface:${NC} https://localhost:8443"
echo -e "${GREEN}✅ Admin Login:${NC} ${FUSIONPBX_ADMIN_USER:-admin} / ${FUSIONPBX_ADMIN_PASSWORD:-admin123}"
echo -e "${GREEN}✅ Database:${NC} ${DB_NAME:-fusionpbx} (${DB_USER:-fusionpbx})"
echo -e "${GREEN}✅ SIP Server:${NC} localhost:5060"
echo -e "${GREEN}✅ Logs:${NC} docker logs fusionpbx-dev"
echo
echo -e "${YELLOW}📋 Port Mapping:${NC}"
echo "• HTTP: 8080 → 80 (Web Interface)"
echo "• HTTPS: 8443 → 443 (Secure Web Interface)"
echo "• SIP: 5060 → 5060 (TCP/UDP)"
echo "• SIP Alt: 5080 → 5080 (TCP/UDP)"
echo "• Event Socket: 8022 → 8021"
echo "• RTP: 10000-10100 → 10000-10100 (UDP)"
echo
echo -e "${YELLOW}📋 Development Features:${NC}"
echo "• Bridge Network (MacOS Compatible)"
echo "• Local Data Storage: ./dev-data/"
echo "• Debug Mode: Enabled"
echo "• Fail2Ban: Disabled"
echo "• Development Credentials"
echo
echo -e "${YELLOW}📋 Next Steps:${NC}"
echo "1. Access http://localhost:8080 or https://localhost:8443"
echo "2. Login with ${FUSIONPBX_ADMIN_USER:-admin} / ${FUSIONPBX_ADMIN_PASSWORD:-admin123}"
echo "3. Configure extensions and dial plans"
echo "4. Test SIP connectivity on localhost:5060"
echo "5. Check logs: docker logs fusionpbx-dev -f"
echo
echo -e "${YELLOW}📋 Useful Commands:${NC}"
echo "• View logs: docker logs fusionpbx-dev -f"
echo "• Stop: ${DOCKER_COMPOSE} -f docker-compose.dev.yml down"
echo "• Restart: ${DOCKER_COMPOSE} -f docker-compose.dev.yml restart"
echo "• Shell access: docker exec -it fusionpbx-dev bash"
echo

log "🎉 FusionPBX development deployment completed successfully!"
