# FusionPBX Docker Makefile
.PHONY: help build build-multiarch push-multiarch push-multiarch-nocache up down logs shell clean backup restore test

# Default target
help: ## Show this help message
	@echo "FusionPBX Docker Management"
	@echo "=========================="
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# Build and deployment
build: ## Build the FusionPBX Docker image
	@echo "Building FusionPBX Docker image..."
	docker-compose build --no-cache

build-quick: ## Quick build (with cache)
	@echo "Quick building FusionPBX Docker image..."
	docker-compose build

build-multiarch: ## Build multi-architecture image (AMD64/ARM64)
	@echo "Building multi-architecture FusionPBX image..."
	@if [ -z "$(USERNAME)" ]; then echo "Usage: make build-multiarch USERNAME=your-dockerhub-username"; exit 1; fi
	./scripts/rebuild-and-push.sh -u $(USERNAME) --build-only

push-multiarch: ## Build and push multi-architecture image to Docker Hub
	@echo "Building and pushing multi-architecture FusionPBX image..."
	@if [ -z "$(USERNAME)" ]; then echo "Usage: make push-multiarch USERNAME=your-dockerhub-username"; exit 1; fi
	./scripts/rebuild-and-push.sh -u $(USERNAME)

push-multiarch-nocache: ## Build and push multi-architecture image without cache
	@echo "Building and pushing multi-architecture FusionPBX image (no cache)..."
	@if [ -z "$(USERNAME)" ]; then echo "Usage: make push-multiarch-nocache USERNAME=your-dockerhub-username"; exit 1; fi
	./scripts/rebuild-and-push.sh -u $(USERNAME) --no-cache

# Development environment
dev-up: ## Start development environment (MacOS compatible)
	@echo "Starting FusionPBX development environment..."
	./deploy-dev.sh

dev-down: ## Stop development environment
	@echo "Stopping FusionPBX development environment..."
	docker-compose -f docker-compose.dev.yml down

dev-logs: ## View development environment logs
	@echo "Viewing FusionPBX development logs..."
	docker logs fusionpbx-dev -f

dev-shell: ## Access development container shell
	@echo "Accessing FusionPBX development container shell..."
	docker exec -it fusionpbx-dev bash

dev-restart: ## Restart development environment
	@echo "Restarting FusionPBX development environment..."
	docker-compose -f docker-compose.dev.yml restart

dev-clean: ## Clean development environment and data
	@echo "Cleaning FusionPBX development environment..."
	docker-compose -f docker-compose.dev.yml down -v
	docker system prune -f
	rm -rf ./dev-data
	@echo "Development environment cleaned!"

up: ## Start FusionPBX services
	@echo "Starting FusionPBX services..."
	docker-compose up -d

down: ## Stop FusionPBX services
	@echo "Stopping FusionPBX services..."
	docker-compose down

restart: ## Restart FusionPBX services
	@echo "Restarting FusionPBX services..."
	docker-compose restart

# Monitoring and debugging
logs: ## Show container logs
	docker-compose logs -f

logs-tail: ## Show last 100 lines of logs
	docker-compose logs --tail=100

status: ## Show service status
	@echo "Container status:"
	docker-compose ps
	@echo ""
	@echo "Service status inside container:"
	docker-compose exec fusionpbx supervisorctl status

shell: ## Access container shell
	docker-compose exec fusionpbx bash

fs-cli: ## Access FreeSWITCH CLI
	docker-compose exec fusionpbx /usr/local/freeswitch/bin/fs_cli

# Database operations
db-shell: ## Access PostgreSQL shell
	docker-compose exec fusionpbx su - postgres -c "psql -d fusionpbx"

db-backup: ## Backup database
	@echo "Creating database backup..."
	mkdir -p ./backups
	docker-compose exec fusionpbx pg_dump -U fusionpbx fusionpbx > ./backups/fusionpbx-$(shell date +%Y%m%d-%H%M%S).sql
	@echo "Database backup created in ./backups/"

db-restore: ## Restore database (usage: make db-restore FILE=backup.sql)
	@if [ -z "$(FILE)" ]; then echo "Usage: make db-restore FILE=backup.sql"; exit 1; fi
	@echo "Restoring database from $(FILE)..."
	docker-compose exec -T fusionpbx psql -U fusionpbx -d fusionpbx < $(FILE)

# Backup and restore
backup: ## Full backup of all data
	@echo "Creating full backup..."
	mkdir -p ./backups
	tar -czf ./backups/fusionpbx-full-$(shell date +%Y%m%d-%H%M%S).tar.gz ./data/
	@echo "Full backup created in ./backups/"

restore: ## Restore from backup (usage: make restore FILE=backup.tar.gz)
	@if [ -z "$(FILE)" ]; then echo "Usage: make restore FILE=backup.tar.gz"; exit 1; fi
	@echo "Restoring from $(FILE)..."
	@echo "WARNING: This will overwrite existing data. Continue? [y/N]"
	@read -r REPLY; if [ "$$REPLY" != "y" ] && [ "$$REPLY" != "Y" ]; then echo "Aborted."; exit 1; fi
	docker-compose down
	rm -rf ./data/
	tar -xzf $(FILE)
	docker-compose up -d

# Maintenance
clean: ## Clean up containers and images
	@echo "Cleaning up..."
	docker-compose down -v
	docker system prune -f
	docker volume prune -f

clean-all: ## Clean everything including images
	@echo "Cleaning everything..."
	docker-compose down -v --rmi all
	docker system prune -af
	docker volume prune -f

update: ## Update FusionPBX to latest version
	@echo "Updating FusionPBX..."
	docker-compose down
	docker-compose build --no-cache
	docker-compose up -d

# Testing and validation
test: ## Run basic tests
	@echo "Running basic tests..."
	@echo "1. Checking if container is running..."
	docker-compose ps | grep -q "Up" || (echo "Container not running" && exit 1)
	@echo "2. Checking web interface..."
	curl -k -s -o /dev/null -w "%{http_code}" https://localhost/ | grep -q "200\|302" || (echo "Web interface not responding" && exit 1)
	@echo "3. Checking FreeSWITCH..."
	docker-compose exec fusionpbx /usr/local/freeswitch/bin/fs_cli -x "status" | grep -q "UP" || (echo "FreeSWITCH not running" && exit 1)
	@echo "All tests passed!"

health: ## Check service health
	@echo "Checking service health..."
	@echo "Container health:"
	docker-compose exec fusionpbx supervisorctl status
	@echo ""
	@echo "Network ports:"
	docker-compose exec fusionpbx netstat -tulpn | grep -E "(80|443|5060)"
	@echo ""
	@echo "Disk usage:"
	docker-compose exec fusionpbx df -h
	@echo ""
	@echo "Memory usage:"
	docker-compose exec fusionpbx free -h

# Development
dev: ## Start in development mode with live logs
	docker-compose up --build

dev-rebuild: ## Rebuild and start in development mode
	docker-compose down
	docker-compose build --no-cache
	docker-compose up

# SSL certificate management
ssl-generate: ## Generate self-signed SSL certificates
	@echo "Generating self-signed SSL certificates..."
	mkdir -p ./data/ssl
	openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
		-keyout ./data/ssl/nginx-selfsigned.key \
		-out ./data/ssl/nginx-selfsigned.crt \
		-subj "/C=US/ST=State/L=City/O=Organization/CN=fusionpbx.local"
	docker-compose restart

ssl-info: ## Show SSL certificate information
	@if [ -f ./data/ssl/nginx-selfsigned.crt ]; then \
		openssl x509 -in ./data/ssl/nginx-selfsigned.crt -text -noout | grep -E "(Subject|Not Before|Not After)"; \
	else \
		echo "SSL certificate not found"; \
	fi

# Quick setup
setup: ## Quick setup with default configuration
	@echo "Setting up FusionPBX with default configuration..."
	cp .env.example .env
	mkdir -p data/{config,postgresql,backups,recordings,logs,sounds,ssl}
	make build
	make up
	@echo "Setup completed! Access web interface at https://localhost/"
	@echo "Check logs with: make logs"
