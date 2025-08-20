# FusionPBX Docker Image

Một Docker image tùy chỉnh cho FusionPBX dựa trên Debian 12 (bookworm), được thiết kế để tái sử dụng với cấu hình ports và volumes linh hoạt.

## Tính Năng

- ✅ **Base OS**: Debian 12 (bookworm) - recommended bởi FusionPBX
- ✅ **Multi-stage build**: Tối ưu image size
- ✅ **Host network**: Tránh NAT issues với VoIP traffic
- ✅ **Flexible configuration**: Custom ports và volumes
- ✅ **Auto-generated passwords**: Bảo mật tự động
- ✅ **SSL support**: HTTPS với self-signed certificates
- ✅ **All-in-one**: NGINX, PHP, PostgreSQL, FreeSWITCH

## Components

- **Web Server**: NGINX với SSL/TLS
- **Database**: PostgreSQL 15
- **PHP**: Version 8.2 với FPM
- **VoIP Engine**: FreeSWITCH (stable branch)
- **Security**: Fail2Ban, SNMP monitoring
- **Process Manager**: Supervisor

## Ports Sử Dụng

Với `network_mode: host`, các services sẽ bind trực tiếp vào host:

```
80/tcp      - HTTP (redirect to HTTPS)
443/tcp     - HTTPS web interface
5060/tcp    - SIP signaling
5060/udp    - SIP signaling
5061/tcp    - SIP TLS
5080/tcp    - SIP alternative
5080/udp    - SIP alternative
16384-32768/udp - RTP media streams
```

## Quick Start

### 1. Clone và Setup

```bash
git clone <repository>
cd fusionpbx-docker

# Copy và customize environment file
cp .env.example .env
nano .env
```

### 2. Build và Run

```bash
# Build image
docker-compose build

# Start services
docker-compose up -d

# Xem logs
docker-compose logs -f
```

### 3. Truy Cập Web Interface

```bash
# HTTP (sẽ redirect to HTTPS)
http://your-server-ip

# HTTPS
https://your-server-ip
```

**Default credentials** (nếu không set trong .env):
- Username: `admin`
- Password: Xem trong logs `docker-compose logs fusionpbx`

## Customization

### Environment Variables

Chỉnh sửa file `.env`:

```bash
# Domain configuration
FUSIONPBX_DOMAIN=pbx.yourcompany.com

# Admin credentials
FUSIONPBX_ADMIN_USER=admin
FUSIONPBX_ADMIN_PASSWORD=your-secure-password

# Database credentials
DB_PASSWORD=your-db-password

# Resource limits
MEMORY_LIMIT=4G
CPU_LIMIT=4.0
```

### Volume Mapping

```bash
# Data persistence
CONFIG_VOLUME=./data/config
DB_VOLUME=./data/postgresql
BACKUP_VOLUME=./data/backups
RECORDINGS_VOLUME=./data/recordings
LOGS_VOLUME=./data/logs

# Custom sounds
SOUNDS_VOLUME=./data/sounds

# Custom SSL certificates
SSL_VOLUME=./data/ssl
```

### Custom SSL Certificates

```bash
# Tạo thư mục SSL
mkdir -p ./data/ssl

# Copy certificates
cp your-cert.crt ./data/ssl/nginx-selfsigned.crt
cp your-key.key ./data/ssl/nginx-selfsigned.key

# Restart container
docker-compose restart
```

## Production Deployment

### 1. Security Hardening

```bash
# Set strong passwords
FUSIONPBX_ADMIN_PASSWORD=$(openssl rand -base64 32)
DB_PASSWORD=$(openssl rand -base64 32)

# Enable Fail2Ban
ENABLE_FAIL2BAN=true

# Use real SSL certificates
SSL_VOLUME=./ssl-certs
```

### 2. Resource Optimization

```bash
# Adjust based on concurrent calls
MEMORY_LIMIT=8G
CPU_LIMIT=4.0

# RTP port range (1000 concurrent calls ≈ 2000 ports)
RTP_START_PORT=16384
RTP_END_PORT=32768
```

### 3. Backup Strategy

```bash
# Database backup
docker-compose exec fusionpbx pg_dump -U fusionpbx fusionpbx > backup.sql

# Full backup
tar -czf fusionpbx-backup-$(date +%Y%m%d).tar.gz ./data/
```

## Troubleshooting

### Check Services Status

```bash
# All services
docker-compose exec fusionpbx supervisorctl status

# Specific service
docker-compose exec fusionpbx supervisorctl status freeswitch
```

### View Logs

```bash
# Container logs
docker-compose logs fusionpbx

# Service logs
docker-compose exec fusionpbx tail -f /var/log/supervisor/freeswitch.log
docker-compose exec fusionpbx tail -f /var/log/nginx/fusionpbx_error.log
```

### FreeSWITCH CLI

```bash
# Access FreeSWITCH console
docker-compose exec fusionpbx /usr/local/freeswitch/bin/fs_cli

# Check registrations
fs_cli -x "show registrations"

# Check calls
fs_cli -x "show calls"
```

### Network Issues

```bash
# Check if ports are listening
docker-compose exec fusionpbx netstat -tulpn | grep -E "(80|443|5060)"

# Test SIP connectivity
docker-compose exec fusionpbx nmap -sU -p 5060 localhost
```

## Development

### Build Custom Image

```bash
# Build with custom tag
docker build -t fusionpbx:custom .

# Build with build args
docker build --build-arg FUSIONPBX_VERSION=master -t fusionpbx:master .
```

### Debug Mode

```bash
# Run with debug
docker-compose run --rm fusionpbx bash

# Check configuration
docker-compose exec fusionpbx cat /var/www/fusionpbx/resources/config.php
```

## Multi-Architecture Build & Push

Project này hỗ trợ build và push multi-architecture Docker images (AMD64/ARM64) lên Docker Hub:

### Build Multi-Architecture Image

```bash
# Build multi-architecture image locally (AMD64/ARM64)
make build-multiarch USERNAME=your-dockerhub-username

# Hoặc sử dụng script trực tiếp
./scripts/rebuild-and-push.sh -u your-dockerhub-username --build-only
```

### Push to Docker Hub

```bash
# Build và push lên Docker Hub
make push-multiarch USERNAME=your-dockerhub-username

# Build và push không dùng cache
make push-multiarch-nocache USERNAME=your-dockerhub-username

# Hoặc sử dụng script trực tiếp
./scripts/rebuild-and-push.sh -u your-dockerhub-username
./scripts/rebuild-and-push.sh -u your-dockerhub-username --no-cache
```

### Script Options

Script `rebuild-and-push.sh` hỗ trợ nhiều tùy chọn:

```bash
# Hiển thị help
./scripts/rebuild-and-push.sh --help

# Chỉ build (không push)
./scripts/rebuild-and-push.sh -u username --build-only

# Chỉ push image có sẵn
./scripts/rebuild-and-push.sh -u username --push-only

# Custom repository và version
./scripts/rebuild-and-push.sh -u username -r myrepo -v 1.0

# Custom platforms
./scripts/rebuild-and-push.sh -u username -p linux/amd64,linux/arm64,linux/arm/v7
```

### Ví dụ sử dụng

```bash
# Build và push với username skytruongdev
make push-multiarch USERNAME=skytruongdev

# Build và push với custom settings
./scripts/rebuild-and-push.sh -u skytruongdev -r fusionpbx -v 5.4

# Chỉ build để test
./scripts/rebuild-and-push.sh -u skytruongdev --build-only --no-cache
```

## Support

- **Official Docs**: https://docs.fusionpbx.com/
- **FusionPBX Forums**: https://www.pbxforums.com/
- **GitHub Issues**: [Create issue for this Docker image]

## License

Dựa trên FusionPBX (Mozilla Public License) và các components open source khác.
