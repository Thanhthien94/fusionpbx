#!/bin/bash

# FusionPBX Production Deployment Script
# Author: Finstar Team
# Version: 2.0
# Environment: Production Linux Server
# Features: Pull + Deploy + Auto-install
#
# Usage:
#   ./deploy-prod.sh                    # Full production deploy + auto-install
#   BUILD_IMAGE=true ./deploy-prod.sh   # Build image locally (for testing)
#   CLEAN_DEPLOY=false ./deploy-prod.sh # Incremental deploy (keep data)
#   AUTO_INSTALL=false ./deploy-prod.sh # Skip auto-install, manual setup
#
# Environment Variables:
#   BUILD_IMAGE=false|true    - Pull from registry vs build locally
#   CLEAN_DEPLOY=true|false   - Clean deploy (remove volumes) vs incremental
#   AUTO_INSTALL=true|false   - Auto-install FusionPBX vs manual setup

set -e

# Script options (production defaults)
BUILD_IMAGE=${BUILD_IMAGE:-false}
CLEAN_DEPLOY=${CLEAN_DEPLOY:-true}
AUTO_INSTALL=${AUTO_INSTALL:-true}
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
    *)          error "Production deployment only supports Linux servers"
esac

log "Detected OS: ${MACHINE}"

# Load environment variables
if [ -f .env.prod ]; then
    source .env.prod
    log "Production environment variables loaded"
elif [ -f .env ]; then
    source .env
    log "Environment variables loaded"
else
    warn ".env file not found, using defaults"
fi

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    error "Docker is not installed. Please install Docker first."
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
    docker build -t skytruongdev/fusionpbx:latest . || error "Failed to build image"
    log "✅ Image built successfully"
elif [ "$SKIP_PULL" = "false" ]; then
    log "Pulling latest FusionPBX image..."
    docker pull skytruongdev/fusionpbx:latest || error "Failed to pull image"
    log "✅ Image pulled successfully"
else
    log "Skipping image pull/build as requested"
fi

# Clean deployment based on configuration
if [ "$CLEAN_DEPLOY" = "true" ]; then
    log "Performing clean production deployment..."
    
    # Stop and remove everything including volumes
    ${DOCKER_COMPOSE} -f docker-compose.yml down -v 2>/dev/null || true
    
    # Clean up any orphaned containers
    docker rm -f fusionpbx-prod 2>/dev/null || true
    
    log "✅ Clean deployment prepared"
else
    log "Performing incremental deployment..."
    
    # Stop existing container if running
    if [ "$(docker ps -q -f name=fusionpbx-prod)" ]; then
        log "Stopping existing FusionPBX production container..."
        ${DOCKER_COMPOSE} -f docker-compose.yml down
    fi
fi

# Start services
log "Starting FusionPBX production services..."
${DOCKER_COMPOSE} -f docker-compose.yml up -d

# Wait for services to be ready
log "Waiting for services to initialize..."
sleep 30

# Check container health
log "Checking container health..."
for i in {1..12}; do
    if [ "$(docker inspect --format='{{.State.Health.Status}}' fusionpbx-prod 2>/dev/null)" = "healthy" ]; then
        log "✅ FusionPBX Production is healthy and ready!"
        break
    fi
    if [ $i -eq 12 ]; then
        error "❌ FusionPBX Production failed to become healthy"
    fi
    log "Waiting for health check... ($i/12)"
    sleep 10
done

# Auto-install FusionPBX if enabled
if [ "$AUTO_INSTALL" = "true" ]; then
    log "Checking FusionPBX installation status..."
    
    # Wait a bit more for auto-installation to complete
    sleep 20
    
    # Check if installation completed
    for i in {1..10}; do
        INSTALL_STATUS=$(curl -s -k https://localhost/core/install/install.php 2>/dev/null | grep -i "already installed" || echo "")
        if [ -n "$INSTALL_STATUS" ]; then
            log "✅ FusionPBX auto-installation completed successfully!"
            break
        fi
        if [ $i -eq 10 ]; then
            warn "⚠️ FusionPBX auto-installation may need manual completion"
            log "Please access https://your-domain/core/install/install.php to complete setup"
        fi
        log "Waiting for auto-installation... ($i/10)"
        sleep 10
    done
else
    log "Auto-installation disabled, manual setup required"
fi

# Get container IP
CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' fusionpbx-prod 2>/dev/null || echo "N/A")

# Display status
log "Production deployment completed successfully!"
echo
echo -e "${BLUE}=== FusionPBX Production Deployment Status ===${NC}"
echo -e "${GREEN}✅ Container Status:${NC} $(docker ps --format 'table {{.Names}}\t{{.Status}}' --filter name=fusionpbx-prod)"
echo -e "${GREEN}✅ Container IP:${NC} ${CONTAINER_IP}"
echo -e "${GREEN}✅ HTTP Interface:${NC} http://localhost (or your domain)"
echo -e "${GREEN}✅ HTTPS Interface:${NC} https://localhost (or your domain)"
echo -e "${GREEN}✅ Admin Login:${NC} ${FUSIONPBX_ADMIN_USER:-admin} / ${FUSIONPBX_ADMIN_PASSWORD:-admin123}"
echo -e "${GREEN}✅ Database:${NC} ${DB_NAME:-fusionpbx} (${DB_USER:-fusionpbx})"
echo -e "${GREEN}✅ SIP Server:${NC} localhost:5060"
echo -e "${GREEN}✅ Logs:${NC} docker logs fusionpbx-prod"
echo

log "🎉 FusionPBX production deployment completed successfully!"
