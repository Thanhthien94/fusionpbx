# FusionPBX Production Deployment Guide

## Overview

This guide covers the production deployment of FusionPBX using Docker with host network mode for optimal SIP/RTP performance.

## Features

- **Bridge Network Mode**: Port mapping for compatibility with existing services
- **Auto-Installation**: Automated setup with admin user creation
- **Persistent Storage**: Data stored in `/opt/fusionpbx/`
- **Security**: Fail2Ban integration and HTTPS support
- **Backup/Restore**: Automated backup and restore scripts
- **Monitoring**: Health checks and logging

## Prerequisites

- Linux server (Ubuntu 20.04+ or CentOS 8+ recommended)
- Docker and Docker Compose installed
- Root access
- Firewall configured (UFW or firewalld)

## Quick Start

### 1. Clone Repository

```bash
git clone <repository-url>
cd fusionpbx-docker
```

### 2. Configure Environment

```bash
# Edit environment file
nano .env

# For development, uncomment the development override section at the bottom
```

### 3. Deploy Production

```bash
# Standard deployment (firewall configuration disabled by default)
sudo ./deploy.sh

# Clean deployment (removes all data)
sudo CLEAN_DEPLOY=true ./deploy.sh

# Build custom image and deploy
sudo BUILD_IMAGE=true ./deploy.sh

# Deploy with automatic firewall configuration (may conflict with existing iptables)
sudo CONFIGURE_FIREWALL=true ./deploy.sh
```

## Configuration

### Environment Variables (.env)

```bash
# FusionPBX Configuration
FUSIONPBX_DOMAIN=pbx.finstar.vn
FUSIONPBX_ADMIN_USER=admin
FUSIONPBX_ADMIN_PASSWORD=Finstar@2025

# Installation Mode
AUTO_INSTALL=true
FUSIONPBX_SETUP_WIZARD=false

# Security
ENABLE_HTTPS=true
ENABLE_FAIL2BAN=true

# For development, uncomment the development override section:
# FUSIONPBX_DOMAIN=localhost
# FUSIONPBX_ADMIN_USER=finstar_admin
# DB_NAME=finstar_pbx
# DB_USER=finstar_user
# DB_PASSWORD=Finstar@DB2025
# ENVIRONMENT=development
```

### Port Mapping

| Service | Host Port | Container Port | Protocol | Description |
|---------|-----------|----------------|----------|-------------|
| HTTP | 8080 | 80 | TCP | Web Interface |
| HTTPS | 8443 | 443 | TCP | Secure Web Interface |
| SIP | 5060 | 5060 | TCP/UDP | SIP Signaling |
| SIP Alt | 5080 | 5080 | TCP/UDP | Alternative SIP |
| Event Socket | 8021 | 8021 | TCP | FreeSWITCH Control |
| RTP | 10000-10100 | 10000-10100 | UDP | Media Streams |

## Backup and Restore

### Create Backup

```bash
# Manual backup
sudo ./backup-production.sh

# Automated backup (add to crontab)
0 2 * * * /path/to/backup-production.sh
```

### Restore from Backup

```bash
# List available backups
ls -lh /opt/fusionpbx/backups/

# Restore specific backup
sudo ./restore-production.sh /opt/fusionpbx/backups/fusionpbx_backup_20250820_020000.tar.gz
```

## Monitoring

### Check Status

```bash
# Container status
docker ps --filter name=fusionpbx

# Health check
docker inspect --format='{{.State.Health.Status}}' fusionpbx

# View logs
docker logs fusionpbx -f
```

### Performance Monitoring

```bash
# Resource usage
docker stats fusionpbx

# Network connections
netstat -tulpn | grep -E "(80|443|5060|8021)"
```

## Maintenance

### Update FusionPBX

```bash
# Pull latest image and redeploy
sudo ./deploy.sh
```

### Restart Services

```bash
# Restart container
docker-compose restart

# Full restart
docker-compose down && docker-compose up -d
```

### Database Maintenance

```bash
# Access database
docker exec -it fusionpbx psql -U postgres -d fusionpbx

# Database backup
docker exec fusionpbx pg_dumpall -U postgres > backup.sql
```

## Firewall Management

### Important Notice

⚠️ **The deploy.sh script does NOT automatically configure firewall by default** to avoid conflicts with existing iptables configurations.

### Firewall Options

1. **Manual Configuration (Recommended)**
   ```bash
   # Check current firewall status
   sudo ./check-firewall.sh

   # Configure firewall manually for required ports:
   # 80, 443, 5060, 5080, 8021, 10000-10100
   ```

2. **Automatic Configuration (Use with caution)**
   ```bash
   # Enable automatic firewall configuration
   sudo CONFIGURE_FIREWALL=true ./deploy.sh
   ```

3. **Restore iptables Service**
   ```bash
   # If iptables service was lost, restore it
   sudo ./restore-iptables.sh
   ```

### Required Ports

| Port | Protocol | Service | Description |
|------|----------|---------|-------------|
| 80 | TCP | HTTP | Web Interface |
| 443 | TCP | HTTPS | Secure Web Interface |
| 5060 | TCP/UDP | SIP | SIP Signaling |
| 5080 | TCP/UDP | SIP Alt | Alternative SIP |
| 8021 | TCP | Event Socket | FreeSWITCH Control |
| 10000-10100 | UDP | RTP | Media Streams |

## Troubleshooting

### Common Issues

1. **Container won't start**
   ```bash
   # Check logs
   docker logs fusionpbx
   
   # Check permissions
   ls -la /opt/fusionpbx/
   ```

2. **SIP registration issues**
   ```bash
   # Check firewall
   ufw status
   
   # Check SIP ports
   netstat -tulpn | grep 5060
   ```

3. **Web interface not accessible**
   ```bash
   # Check nginx status
   docker exec fusionpbx supervisorctl status nginx

   # Check port 80/443
   netstat -tulpn | grep -E "(80|443)"
   ```

4. **iptables service missing after deployment**
   ```bash
   # Check firewall status
   sudo ./check-firewall.sh

   # Restore iptables service
   sudo ./restore-iptables.sh

   # Verify iptables is working
   sudo systemctl status iptables
   ```

5. **Firewall conflicts**
   ```bash
   # Check for conflicts between UFW, firewalld, and iptables
   sudo ./check-firewall.sh

   # Disable conflicting services (example)
   sudo systemctl stop ufw
   sudo systemctl disable ufw
   ```

### Log Locations

- Container logs: `docker logs fusionpbx`
- FusionPBX logs: `/opt/fusionpbx/logs/`
- FreeSWITCH logs: `/opt/fusionpbx/logs/freeswitch/`

## Security Considerations

1. **Firewall Configuration**
   - Only open required ports
   - Use fail2ban for intrusion prevention
   - Regular security updates

2. **SSL/TLS**
   - Use valid SSL certificates
   - Configure HTTPS redirects
   - Strong cipher suites

3. **Access Control**
   - Strong admin passwords
   - Regular password rotation
   - User access auditing

## Production Checklist

- [ ] Server hardening completed
- [ ] Firewall configured
- [ ] SSL certificates installed
- [ ] Backup strategy implemented
- [ ] Monitoring configured
- [ ] Documentation updated
- [ ] Team training completed

## Support

For issues and support:
- Check logs first
- Review troubleshooting section
- Contact Finstar team

## License

Copyright © 2025 Finstar Team. All rights reserved.
