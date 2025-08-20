#!/bin/bash

# FusionPBX - Check Firewall Status Script
# Author: Finstar Team
# Version: 1.0

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
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

log "🔍 FusionPBX - Checking Firewall Status..."

echo -e "${BLUE}=== Firewall Status Check ===${NC}"

# Check iptables service
echo -e "\n${YELLOW}📋 iptables Service Status:${NC}"
if systemctl is-active --quiet iptables 2>/dev/null; then
    echo -e "${GREEN}✅ iptables service: ACTIVE${NC}"
    systemctl status iptables --no-pager -l
elif systemctl is-active --quiet netfilter-persistent 2>/dev/null; then
    echo -e "${GREEN}✅ netfilter-persistent service: ACTIVE${NC}"
    systemctl status netfilter-persistent --no-pager -l
else
    echo -e "${RED}❌ iptables service: INACTIVE${NC}"
fi

# Check UFW status
echo -e "\n${YELLOW}📋 UFW Status:${NC}"
if command -v ufw &> /dev/null; then
    if systemctl is-active --quiet ufw 2>/dev/null; then
        echo -e "${GREEN}✅ UFW service: ACTIVE${NC}"
        ufw status verbose
    else
        echo -e "${YELLOW}⚠️ UFW service: INACTIVE${NC}"
    fi
else
    echo -e "${BLUE}ℹ️ UFW: NOT INSTALLED${NC}"
fi

# Check firewalld status
echo -e "\n${YELLOW}📋 firewalld Status:${NC}"
if command -v firewall-cmd &> /dev/null; then
    if systemctl is-active --quiet firewalld 2>/dev/null; then
        echo -e "${GREEN}✅ firewalld service: ACTIVE${NC}"
        firewall-cmd --list-all
    else
        echo -e "${YELLOW}⚠️ firewalld service: INACTIVE${NC}"
    fi
else
    echo -e "${BLUE}ℹ️ firewalld: NOT INSTALLED${NC}"
fi

# Check current iptables rules
echo -e "\n${YELLOW}📋 Current iptables Rules:${NC}"
if command -v iptables &> /dev/null; then
    echo -e "${BLUE}Filter table:${NC}"
    iptables -L -n --line-numbers
    
    echo -e "\n${BLUE}NAT table:${NC}"
    iptables -t nat -L -n --line-numbers 2>/dev/null || echo "NAT table not accessible"
else
    echo -e "${RED}❌ iptables command not found${NC}"
fi

# Check FusionPBX required ports
echo -e "\n${YELLOW}📋 FusionPBX Port Status:${NC}"
FUSIONPBX_PORTS=(80 443 5060 5080 8021)

for port in "${FUSIONPBX_PORTS[@]}"; do
    if netstat -tlnp 2>/dev/null | grep -q ":$port "; then
        echo -e "${GREEN}✅ Port $port: LISTENING${NC}"
    else
        echo -e "${RED}❌ Port $port: NOT LISTENING${NC}"
    fi
done

# Check RTP port range
echo -e "\n${YELLOW}📋 RTP Port Range (10000-10100):${NC}"
RTP_LISTENING=$(netstat -ulnp 2>/dev/null | grep -E ":10[0-9]{3} " | wc -l)
if [ "$RTP_LISTENING" -gt 0 ]; then
    echo -e "${GREEN}✅ RTP ports: $RTP_LISTENING ports listening${NC}"
else
    echo -e "${RED}❌ RTP ports: NO ports listening${NC}"
fi

# Check Docker network mode
echo -e "\n${YELLOW}📋 Docker Network Status:${NC}"
if docker ps --format "table {{.Names}}\t{{.Ports}}" | grep -q fusionpbx; then
    echo -e "${GREEN}✅ FusionPBX container: RUNNING${NC}"
    docker ps --format "table {{.Names}}\t{{.Ports}}" | grep fusionpbx
    
    # Check if using host network
    NETWORK_MODE=$(docker inspect fusionpbx --format '{{.HostConfig.NetworkMode}}' 2>/dev/null)
    if [ "$NETWORK_MODE" = "host" ]; then
        echo -e "${GREEN}✅ Network mode: HOST (Direct port access)${NC}"
    else
        echo -e "${BLUE}ℹ️ Network mode: $NETWORK_MODE${NC}"
    fi
else
    echo -e "${RED}❌ FusionPBX container: NOT RUNNING${NC}"
fi

# Recommendations
echo -e "\n${BLUE}=== Recommendations ===${NC}"

# Check for conflicts
CONFLICTS=0

if systemctl is-active --quiet ufw 2>/dev/null && systemctl is-active --quiet firewalld 2>/dev/null; then
    warn "UFW and firewalld are both active - this may cause conflicts"
    CONFLICTS=$((CONFLICTS + 1))
fi

if systemctl is-active --quiet ufw 2>/dev/null && (systemctl is-active --quiet iptables 2>/dev/null || systemctl is-active --quiet netfilter-persistent 2>/dev/null); then
    warn "UFW and iptables service are both active - this may cause conflicts"
    CONFLICTS=$((CONFLICTS + 1))
fi

if systemctl is-active --quiet firewalld 2>/dev/null && (systemctl is-active --quiet iptables 2>/dev/null || systemctl is-active --quiet netfilter-persistent 2>/dev/null); then
    warn "firewalld and iptables service are both active - this may cause conflicts"
    CONFLICTS=$((CONFLICTS + 1))
fi

if [ $CONFLICTS -eq 0 ]; then
    echo -e "${GREEN}✅ No firewall conflicts detected${NC}"
else
    echo -e "${RED}⚠️ $CONFLICTS potential firewall conflicts detected${NC}"
    echo -e "${YELLOW}💡 Consider using only one firewall solution:${NC}"
    echo "   • For iptables: sudo ./restore-iptables.sh"
    echo "   • For UFW: sudo ufw enable && sudo CONFIGURE_FIREWALL=true ./deploy.sh"
    echo "   • For firewalld: sudo systemctl enable firewalld && sudo CONFIGURE_FIREWALL=true ./deploy.sh"
fi

# Final status
echo -e "\n${BLUE}=== Summary ===${NC}"
if systemctl is-active --quiet iptables 2>/dev/null || systemctl is-active --quiet netfilter-persistent 2>/dev/null; then
    echo -e "${GREEN}✅ iptables: ACTIVE${NC}"
elif systemctl is-active --quiet ufw 2>/dev/null; then
    echo -e "${GREEN}✅ UFW: ACTIVE${NC}"
elif systemctl is-active --quiet firewalld 2>/dev/null; then
    echo -e "${GREEN}✅ firewalld: ACTIVE${NC}"
else
    echo -e "${RED}❌ No active firewall detected${NC}"
    echo -e "${YELLOW}💡 Run: sudo ./restore-iptables.sh to restore iptables${NC}"
fi

log "🔍 Firewall status check completed!"
