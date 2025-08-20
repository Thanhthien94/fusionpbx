#!/bin/bash

# FusionPBX - Restore iptables Service Script
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

log "FusionPBX - Restoring iptables service..."

# Detect OS
if [ -f /etc/debian_version ]; then
    OS="debian"
elif [ -f /etc/redhat-release ]; then
    OS="redhat"
else
    OS="unknown"
fi

log "Detected OS: $OS"

# Function to restore iptables on Debian/Ubuntu
restore_debian_iptables() {
    log "Restoring iptables on Debian/Ubuntu..."
    
    # Install iptables-persistent if not installed
    if ! dpkg -l | grep -q iptables-persistent; then
        log "Installing iptables-persistent..."
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent
    fi
    
    # Stop and disable ufw if it's running (may conflict)
    if systemctl is-active --quiet ufw; then
        log "Stopping UFW to avoid conflicts..."
        systemctl stop ufw
        systemctl disable ufw
    fi
    
    # Enable and start iptables services
    log "Enabling iptables services..."
    systemctl enable netfilter-persistent
    systemctl start netfilter-persistent
    
    # Create basic iptables rules for FusionPBX
    log "Creating basic iptables rules for FusionPBX..."
    
    # Flush existing rules
    iptables -F
    iptables -X
    iptables -t nat -F
    iptables -t nat -X
    iptables -t mangle -F
    iptables -t mangle -X
    
    # Set default policies
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    
    # Allow loopback
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A OUTPUT -o lo -j ACCEPT
    
    # Allow established connections
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    
    # Allow SSH (be careful not to lock yourself out)
    iptables -A INPUT -p tcp --dport 22 -j ACCEPT
    
    # Allow FusionPBX ports
    iptables -A INPUT -p tcp --dport 80 -j ACCEPT    # HTTP
    iptables -A INPUT -p tcp --dport 443 -j ACCEPT   # HTTPS
    iptables -A INPUT -p tcp --dport 5060 -j ACCEPT  # SIP TCP
    iptables -A INPUT -p udp --dport 5060 -j ACCEPT  # SIP UDP
    iptables -A INPUT -p tcp --dport 5080 -j ACCEPT  # SIP Alt TCP
    iptables -A INPUT -p udp --dport 5080 -j ACCEPT  # SIP Alt UDP
    iptables -A INPUT -p tcp --dport 8021 -j ACCEPT  # FreeSWITCH Event Socket
    iptables -A INPUT -p udp --dport 10000:10100 -j ACCEPT  # RTP Media
    
    # Save rules
    log "Saving iptables rules..."
    iptables-save > /etc/iptables/rules.v4
    
    log "✅ iptables restored on Debian/Ubuntu"
}

# Function to restore iptables on RedHat/CentOS
restore_redhat_iptables() {
    log "Restoring iptables on RedHat/CentOS..."
    
    # Install iptables-services if not installed
    if ! rpm -q iptables-services &>/dev/null; then
        log "Installing iptables-services..."
        yum install -y iptables-services
    fi
    
    # Stop and disable firewalld if it's running (may conflict)
    if systemctl is-active --quiet firewalld; then
        log "Stopping firewalld to avoid conflicts..."
        systemctl stop firewalld
        systemctl disable firewalld
    fi
    
    # Enable and start iptables services
    log "Enabling iptables services..."
    systemctl enable iptables
    systemctl start iptables
    
    # Create basic iptables rules for FusionPBX
    log "Creating basic iptables rules for FusionPBX..."
    
    # Flush existing rules
    iptables -F
    iptables -X
    iptables -t nat -F
    iptables -t nat -X
    iptables -t mangle -F
    iptables -t mangle -X
    
    # Set default policies
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    
    # Allow loopback
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A OUTPUT -o lo -j ACCEPT
    
    # Allow established connections
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    
    # Allow SSH (be careful not to lock yourself out)
    iptables -A INPUT -p tcp --dport 22 -j ACCEPT
    
    # Allow FusionPBX ports
    iptables -A INPUT -p tcp --dport 80 -j ACCEPT    # HTTP
    iptables -A INPUT -p tcp --dport 443 -j ACCEPT   # HTTPS
    iptables -A INPUT -p tcp --dport 5060 -j ACCEPT  # SIP TCP
    iptables -A INPUT -p udp --dport 5060 -j ACCEPT  # SIP UDP
    iptables -A INPUT -p tcp --dport 5080 -j ACCEPT  # SIP Alt TCP
    iptables -A INPUT -p udp --dport 5080 -j ACCEPT  # SIP Alt UDP
    iptables -A INPUT -p tcp --dport 8021 -j ACCEPT  # FreeSWITCH Event Socket
    iptables -A INPUT -p udp --dport 10000:10100 -j ACCEPT  # RTP Media
    
    # Save rules
    log "Saving iptables rules..."
    service iptables save
    
    log "✅ iptables restored on RedHat/CentOS"
}

# Main restoration logic
case $OS in
    debian)
        restore_debian_iptables
        ;;
    redhat)
        restore_redhat_iptables
        ;;
    *)
        error "Unsupported OS. Please configure iptables manually."
        ;;
esac

# Display current iptables rules
log "Current iptables rules:"
iptables -L -n

log "🎉 iptables service restoration completed!"
log "📋 FusionPBX ports configured: 80, 443, 5060, 5080, 8021, 10000-10100"
log "⚠️  Make sure SSH port 22 is accessible before disconnecting!"
