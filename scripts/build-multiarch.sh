#!/bin/bash

# FusionPBX Multi-Architecture Docker Build Script
# This script builds and pushes multi-architecture images (AMD64/ARM64) to Docker Hub

set -e

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
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Configuration
DOCKER_HUB_USERNAME=""
DOCKER_HUB_REPO="fusionpbx"
VERSION="5.4"
PLATFORMS="linux/amd64,linux/arm64"
BUILDER_NAME="fusionpbx-multiarch"

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -u, --username USERNAME    Docker Hub username (required)"
    echo "  -r, --repo REPO           Repository name (default: fusionpbx)"
    echo "  -v, --version VERSION     Version tag (default: 5.4)"
    echo "  -p, --platforms PLATFORMS Platforms to build for (default: linux/amd64,linux/arm64)"
    echo "  --push                    Push to Docker Hub after build"
    echo "  --no-cache                Build without cache"
    echo "  -h, --help               Show this help message"
    echo ""
    echo "Example:"
    echo "  $0 -u myusername -r fusionpbx -v 5.4 --push"
}

# Parse command line arguments
PUSH_TO_HUB=false
NO_CACHE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -u|--username)
            DOCKER_HUB_USERNAME="$2"
            shift 2
            ;;
        -r|--repo)
            DOCKER_HUB_REPO="$2"
            shift 2
            ;;
        -v|--version)
            VERSION="$2"
            shift 2
            ;;
        -p|--platforms)
            PLATFORMS="$2"
            shift 2
            ;;
        --push)
            PUSH_TO_HUB=true
            shift
            ;;
        --no-cache)
            NO_CACHE="--no-cache"
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Validate required parameters
if [ -z "$DOCKER_HUB_USERNAME" ]; then
    error "Docker Hub username is required"
    show_usage
    exit 1
fi

# Set image names
DOCKER_HUB_IMAGE="$DOCKER_HUB_USERNAME/$DOCKER_HUB_REPO"
LATEST_TAG="$DOCKER_HUB_IMAGE:latest"
VERSION_TAG="$DOCKER_HUB_IMAGE:$VERSION"

log "=============================================="
log "FusionPBX Multi-Architecture Build Started"
log "=============================================="

info "Configuration:"
info "  Docker Hub username: $DOCKER_HUB_USERNAME"
info "  Repository: $DOCKER_HUB_REPO"
info "  Version: $VERSION"
info "  Platforms: $PLATFORMS"
info "  Latest tag: $LATEST_TAG"
info "  Version tag: $VERSION_TAG"
info "  Push to Hub: $PUSH_TO_HUB"
info "  No cache: $([ -n "$NO_CACHE" ] && echo "Yes" || echo "No")"

# 1. Check Docker login if pushing
if [ "$PUSH_TO_HUB" = true ]; then
    log "Checking Docker Hub authentication..."
    if ! docker info | grep -q "Username:"; then
        warn "Not logged in to Docker Hub"
        log "Please login to Docker Hub..."
        if ! docker login; then
            error "Failed to login to Docker Hub"
            exit 1
        fi
    fi
    info "✓ Docker Hub authentication verified"
fi

# 2. Create or use existing buildx builder
log "Setting up Docker Buildx builder..."
if docker buildx inspect $BUILDER_NAME >/dev/null 2>&1; then
    info "Using existing builder: $BUILDER_NAME"
    docker buildx use $BUILDER_NAME
else
    info "Creating new builder: $BUILDER_NAME"
    docker buildx create --name $BUILDER_NAME --driver docker-container --bootstrap
    docker buildx use $BUILDER_NAME
fi

# 3. Inspect builder capabilities
log "Inspecting builder capabilities..."
docker buildx inspect --bootstrap
info "✓ Builder ready for multi-platform builds"

# 4. Build multi-architecture image
log "Building multi-architecture image..."
info "This may take a while as we're building for multiple architectures..."

BUILD_ARGS=""
if [ "$PUSH_TO_HUB" = true ]; then
    BUILD_ARGS="--push"
else
    BUILD_ARGS="--load"
    warn "Building without push - only AMD64 will be loaded locally"
fi

# Build command
DOCKER_BUILDX_CMD="docker buildx build \
    --platform $PLATFORMS \
    --tag $LATEST_TAG \
    --tag $VERSION_TAG \
    $NO_CACHE \
    $BUILD_ARGS \
    ."

info "Executing: $DOCKER_BUILDX_CMD"

if eval $DOCKER_BUILDX_CMD; then
    info "✓ Multi-architecture build completed successfully"
else
    error "✗ Multi-architecture build failed"
    exit 1
fi

# 5. Verify build results
if [ "$PUSH_TO_HUB" = true ]; then
    log "Verifying push to Docker Hub..."
    info "Images pushed successfully to Docker Hub:"
    info "  - $LATEST_TAG"
    info "  - $VERSION_TAG"
    info "  - Platforms: $PLATFORMS"
    info ""
    info "You can verify the push at: https://hub.docker.com/r/$DOCKER_HUB_USERNAME/$DOCKER_HUB_REPO"
    
    # Check manifest for multi-arch support
    log "Checking manifest for multi-architecture support..."
    docker buildx imagetools inspect $LATEST_TAG
else
    log "Build completed without push"
    info "To push to Docker Hub, run with --push flag"
    info "Local image loaded for current architecture only"
fi

# 6. Generate usage instructions
if [ "$PUSH_TO_HUB" = true ]; then
    cat > multiarch-build-results.txt << EOF
Multi-Architecture Build Completed Successfully!

Your FusionPBX image is now available at:
- Latest: $LATEST_TAG
- Version: $VERSION_TAG
- Platforms: $PLATFORMS

To use the image on different architectures:

1. Pull the image (Docker will automatically select the right architecture):
   docker pull $LATEST_TAG

2. Run on AMD64:
   docker run -d --name fusionpbx -p 80:80 -p 443:443 -p 5060:5060/udp $LATEST_TAG

3. Run on ARM64 (Raspberry Pi, Apple Silicon, etc.):
   docker run -d --name fusionpbx -p 80:80 -p 443:443 -p 5060:5060/udp $LATEST_TAG

4. Verify architecture:
   docker run --rm $LATEST_TAG uname -m

The image will automatically run on the correct architecture without any changes needed.

Build Details:
- Build time: $(date)
- Platforms: $PLATFORMS
- Builder: $BUILDER_NAME
- Tags: $LATEST_TAG, $VERSION_TAG
EOF

    log "Results saved to: multiarch-build-results.txt"
fi

log "=============================================="
log "FusionPBX Multi-Architecture Build Complete!"
log "=============================================="

if [ "$PUSH_TO_HUB" = true ]; then
    log "✓ Images built and pushed for: $PLATFORMS"
    log "✓ Available at: https://hub.docker.com/r/$DOCKER_HUB_USERNAME/$DOCKER_HUB_REPO"
else
    log "✓ Images built for: $PLATFORMS"
    log "  Run with --push to upload to Docker Hub"
fi
