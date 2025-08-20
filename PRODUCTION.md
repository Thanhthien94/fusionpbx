# FusionPBX Production Deployment Guide

## Overview

This guide covers the production deployment of FusionPBX using Docker with host network mode for optimal SIP/RTP performance.

## Features

- **Host Network Mode**: Direct port access for optimal SIP/RTP performance
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
# Copy and edit production environment file
cp .env.production.example .env.production
nano .env.production
```

### 3. Deploy Production

```bash
# Standard deployment
sudo ./deploy.sh

# Clean deployment (removes all data)
sudo CLEAN_DEPLOY=true ./deploy.sh

# Build custom image and deploy
sudo BUILD_IMAGE=true ./deploy.sh
```

## Configuration

### Environment Variables (.env.production)

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
```

### Host Network Ports

| Service | Port | Protocol | Description |
|---------|------|----------|-------------|
| HTTP | 80 | TCP | Web Interface |
| HTTPS | 443 | TCP | Secure Web Interface |
| SIP | 5060 | TCP/UDP | SIP Signaling |
| SIP Alt | 5080 | TCP/UDP | Alternative SIP |
| Event Socket | 8021 | TCP | FreeSWITCH Control |
| RTP | 10000-10100 | UDP | Media Streams |

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
