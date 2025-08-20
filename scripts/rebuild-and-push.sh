#!/bin/bash

# FusionPBX Rebuild and Push Script
# This script rebuilds the multi-architecture image and pushes to Docker Hub

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
    echo "  --no-cache                Build without cache"
    echo "  --build-only              Build only, don't push to Docker Hub"
    echo "  --push-only               Skip build, only push existing image"
    echo "  -h, --help               Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 -u skytruongdev                    # Build and push with default settings"
    echo "  $0 -u skytruongdev --no-cache         # Build without cache and push"
    echo "  $0 -u skytruongdev --build-only       # Build only, don't push"
    echo "  $0 -u skytruongdev --push-only        # Push existing image only"
}

# Parse command line arguments
BUILD_ONLY=false
PUSH_ONLY=false
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
        --no-cache)
            NO_CACHE="--no-cache"
            shift
            ;;
        --build-only)
            BUILD_ONLY=true
            shift
            ;;
        --push-only)
            PUSH_ONLY=true
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

# Validate conflicting options
if [ "$BUILD_ONLY" = true ] && [ "$PUSH_ONLY" = true ]; then
    error "Cannot use --build-only and --push-only together"
    exit 1
fi

# Set image names
DOCKER_HUB_IMAGE="$DOCKER_HUB_USERNAME/$DOCKER_HUB_REPO"
LATEST_TAG="$DOCKER_HUB_IMAGE:latest"
VERSION_TAG="$DOCKER_HUB_IMAGE:$VERSION"

log "=============================================="
log "FusionPBX Rebuild and Push Started"
log "=============================================="

info "Configuration:"
info "  Docker Hub username: $DOCKER_HUB_USERNAME"
info "  Repository: $DOCKER_HUB_REPO"
info "  Version: $VERSION"
info "  Platforms: $PLATFORMS"
info "  Latest tag: $LATEST_TAG"
info "  Version tag: $VERSION_TAG"
info "  Build only: $BUILD_ONLY"
info "  Push only: $PUSH_ONLY"
info "  No cache: $([ -n "$NO_CACHE" ] && echo "Yes" || echo "No")"

# 1. Check Docker login if pushing
if [ "$BUILD_ONLY" = false ]; then
    log "Checking Docker Hub authentication..."
    if ! docker info | grep -q "Username:" 2>/dev/null; then
        warn "Not logged in to Docker Hub"
        log "Please login to Docker Hub..."
        if ! docker login; then
            error "Failed to login to Docker Hub"
            exit 1
        fi
    fi
    info "✓ Docker Hub authentication verified"
fi

# 2. Setup Docker Buildx builder (skip if push-only)
if [ "$PUSH_ONLY" = false ]; then
    log "Setting up Docker Buildx builder..."
    if docker buildx inspect $BUILDER_NAME >/dev/null 2>&1; then
        info "Using existing builder: $BUILDER_NAME"
        docker buildx use $BUILDER_NAME
    else
        info "Creating new builder: $BUILDER_NAME"
        docker buildx create --name $BUILDER_NAME --driver docker-container --bootstrap
        docker buildx use $BUILDER_NAME
    fi

    # Inspect builder capabilities
    log "Inspecting builder capabilities..."
    docker buildx inspect --bootstrap
    info "✓ Builder ready for multi-platform builds"
fi

# 3. Build multi-architecture image (skip if push-only)
if [ "$PUSH_ONLY" = false ]; then
    log "Building multi-architecture image..."
    info "This may take a while as we're building for multiple architectures..."

    BUILD_ARGS=""
    if [ "$BUILD_ONLY" = true ]; then
        BUILD_ARGS="--load"
        warn "Building without push - only AMD64 will be loaded locally"
    else
        BUILD_ARGS="--push"
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
fi

# 4. Push existing image (only if push-only mode)
if [ "$PUSH_ONLY" = true ]; then
    log "Pushing existing images to Docker Hub..."
    
    # Check if images exist locally
    if ! docker images | grep -q "$DOCKER_HUB_USERNAME/$DOCKER_HUB_REPO"; then
        error "No local images found for $DOCKER_HUB_USERNAME/$DOCKER_HUB_REPO"
        error "Please build the image first or use without --push-only flag"
        exit 1
    fi

    # Push latest tag
    log "Pushing latest tag..."
    if docker push $LATEST_TAG; then
        info "✓ Latest tag pushed successfully"
    else
        error "✗ Failed to push latest tag"
        exit 1
    fi

    # Push version tag
    log "Pushing version tag..."
    if docker push $VERSION_TAG; then
        info "✓ Version tag pushed successfully"
    else
        error "✗ Failed to push version tag"
        exit 1
    fi
fi

# 5. Verify results
if [ "$BUILD_ONLY" = false ]; then
    log "Verifying push to Docker Hub..."
    info "Images pushed successfully to Docker Hub:"
    info "  - $LATEST_TAG"
    info "  - $VERSION_TAG"
    info "  - Platforms: $PLATFORMS"
    info ""
    info "You can verify the push at: https://hub.docker.com/r/$DOCKER_HUB_USERNAME/$DOCKER_HUB_REPO"
    
    # Check manifest for multi-arch support (skip if push-only)
    if [ "$PUSH_ONLY" = false ]; then
        log "Checking manifest for multi-architecture support..."
        docker buildx imagetools inspect $LATEST_TAG
    fi
else
    log "Build completed without push"
    info "To push to Docker Hub, run without --build-only flag"
    info "Local image loaded for current architecture only"
fi

# 6. Generate usage instructions
if [ "$BUILD_ONLY" = false ]; then
    cat > rebuild-push-results.txt << EOF
Rebuild and Push Completed Successfully!

Your FusionPBX image is now available at:
- Latest: $LATEST_TAG
- Version: $VERSION_TAG
- Platforms: $PLATFORMS

To use the image on different architectures:

1. Pull the image (Docker will automatically select the right architecture):
   docker pull $LATEST_TAG

2. Run on any supported platform:
   docker run -d --name fusionpbx -p 80:80 -p 443:443 -p 5060:5060/udp $LATEST_TAG

3. Verify architecture:
   docker run --rm $LATEST_TAG uname -m

The image will automatically run on the correct architecture without any changes needed.

Build Details:
- Build time: $(date)
- Platforms: $PLATFORMS
- Builder: $BUILDER_NAME
- Tags: $LATEST_TAG, $VERSION_TAG
EOF

    log "Results saved to: rebuild-push-results.txt"
fi

log "=============================================="
log "FusionPBX Rebuild and Push Complete!"
log "=============================================="

if [ "$BUILD_ONLY" = true ]; then
    log "✓ Images built for: $PLATFORMS"
    log "  Run without --build-only to push to Docker Hub"
elif [ "$PUSH_ONLY" = true ]; then
    log "✓ Images pushed to: https://hub.docker.com/r/$DOCKER_HUB_USERNAME/$DOCKER_HUB_REPO"
else
    log "✓ Images built and pushed for: $PLATFORMS"
    log "✓ Available at: https://hub.docker.com/r/$DOCKER_HUB_USERNAME/$DOCKER_HUB_REPO"
fi
