#!/bin/bash

# Podman ARK Server Setup Script
# Optimized for Podman with rootless containers

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

timestamp() {
    date +"%Y-%m-%d %H:%M:%S"
}

log() {
    echo -e "${GREEN}[$(timestamp)]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(timestamp)]${NC} WARNING: $1"
}

error() {
    echo -e "${RED}[$(timestamp)]${NC} ERROR: $1"
}

info() {
    echo -e "${BLUE}[$(timestamp)]${NC} INFO: $1"
}

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    warn "This script is designed to run as a non-root user with rootless Podman"
    warn "Running as root is not recommended for security reasons"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Function to check if podman is installed
check_podman() {
    if ! command -v podman &> /dev/null; then
        error "Podman is not installed. Please install Podman first."
        echo "On Ubuntu/Debian: sudo apt-get install podman"
        echo "On RHEL/CentOS/Fedora: sudo dnf install podman"
        exit 1
    fi
    
    log "Podman version: $(podman --version)"
}

# Function to check if podman-compose is available
check_compose() {
    if command -v podman-compose &> /dev/null; then
        COMPOSE_CMD="podman-compose"
        log "Using podman-compose: $(podman-compose --version)"
    elif command -v docker-compose &> /dev/null; then
        COMPOSE_CMD="docker-compose"
        warn "Using docker-compose with podman (may have limitations)"
    else
        error "Neither podman-compose nor docker-compose found"
        echo "Install podman-compose: pip3 install --user podman-compose"
        exit 1
    fi
}

# Function to setup rootless Podman
setup_rootless() {
    log "Setting up rootless Podman configuration"
    
    # Enable lingering for user (allows user services to run without login)
    if ! systemctl --user status | grep -q "Linger: yes"; then
        log "Enabling user lingering"
        sudo loginctl enable-linger "$USER"
    fi
    
    # Start and enable user services
    systemctl --user enable --now podman.socket || warn "Could not enable podman.socket"
    
    # Check if user namespaces are properly configured
    if [ ! -f /etc/subuid ] || ! grep -q "^$USER:" /etc/subuid; then
        error "User namespaces not properly configured"
        echo "Run: sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $USER"
        exit 1
    fi
    
    # Create Podman directories
    mkdir -p ~/.config/containers
    mkdir -p ~/.local/share/containers
    
    log "Rootless Podman setup completed"
}

# Function to configure Podman for ARK servers
configure_podman() {
    log "Configuring Podman for ARK servers"
    
    # Create containers.conf if it doesn't exist
    if [ ! -f ~/.config/containers/containers.conf ]; then
        cat > ~/.config/containers/containers.conf << EOF
[containers]
# Increase default ulimits for ARK servers
default_ulimits = [
    "nofile=65536:65536",
]

# Set default timezone
tz = "America/Toronto"

# Enable cgroups v2
cgroups = "enabled"

[engine]
# Optimize for gaming servers
events_logger = "file"
runtime = "crun"
EOF
        log "Created containers.conf with ARK server optimizations"
    fi
    
    # Set SELinux context if SELinux is enabled
    if command -v getenforce &> /dev/null && [ "$(getenforce)" = "Enforcing" ]; then
        log "Configuring SELinux for container volumes"
        setsebool -P container_manage_cgroup 1 2>/dev/null || warn "Could not set SELinux boolean"
    fi
}

# Function to create network for cluster
create_network() {
    log "Creating ARK cluster network"
    
    if ! podman network exists ark-cluster-network 2>/dev/null; then
        podman network create ark-cluster-network
        log "Created ark-cluster-network"
    else
        info "Network ark-cluster-network already exists"
    fi
}

# Function to create volumes for cluster
create_volumes() {
    log "Creating persistent volumes for ARK cluster"
    
    local volumes=(
        "ark-island-data"
        "ark-ragnarok-data" 
        "ark-scorchedearth-data"
        "ark-aberration-data"
        "ark-cluster-data"
    )
    
    for volume in "${volumes[@]}"; do
        if ! podman volume exists "$volume" 2>/dev/null; then
            podman volume create "$volume"
            log "Created volume: $volume"
        else
            info "Volume $volume already exists"
        fi
    done
}

# Function to build ARK server image
build_image() {
    log "Building ARK Ascended server image"
    
    cd "$(dirname "$0")/container" || exit 1
    
    podman build \
        --tag ark-ascended-server:latest \
        --file Containerfile \
        --format docker \
        .
    
    log "ARK server image built successfully"
}

# Function to create systemd service files for auto-start
create_systemd_services() {
    log "Creating systemd user services for ARK cluster"
    
    local services_dir="$HOME/.config/systemd/user"
    mkdir -p "$services_dir"
    
    # Create service for core cluster
    cat > "$services_dir/ark-cluster.service" << EOF
[Unit]
Description=ARK Ascended Cluster (Island + Ragnarok)
Requires=network-online.target
After=network-online.target
RequiresMountsFor=%t/containers

[Service]
Type=notify
NotifyAccess=all
Environment=PODMAN_SYSTEMD_UNIT=%n
Restart=on-failure
TimeoutStartSec=900
TimeoutStopSec=120
ExecStart=/usr/bin/podman-compose -f %h/ark-ascended-server/container/compose-cluster.yaml up
ExecStop=/usr/bin/podman-compose -f %h/ark-ascended-server/container/compose-cluster.yaml down
SyslogIdentifier=%n
KillMode=mixed

[Install]
WantedBy=default.target
EOF
    
    # Reload systemd and enable service
    systemctl --user daemon-reload
    log "Created ark-cluster.service (not enabled by default)"
    info "To enable auto-start: systemctl --user enable ark-cluster.service"
}

# Function to optimize system for ARK servers
optimize_system() {
    log "Applying system optimizations for ARK servers"
    
    # Create sysctl optimizations file
    if [ ! -f ~/.config/sysctl.conf ]; then
        cat > ~/.config/sysctl.conf << EOF
# Optimizations for ARK servers
vm.max_map_count=262144
net.core.rmem_max=134217728
net.core.wmem_max=134217728
net.ipv4.tcp_rmem=4096 65536 134217728
net.ipv4.tcp_wmem=4096 65536 134217728
net.core.netdev_max_backlog=5000
EOF
        warn "Created sysctl optimizations. You may need to apply them system-wide:"
        echo "sudo sysctl -p ~/.config/sysctl.conf"
    fi
}

# Function to create environment file
create_env_file() {
    local env_file="$(dirname "$0")/container/.env"
    
    if [ ! -f "$env_file" ]; then
        log "Creating environment configuration file"
        
        cat > "$env_file" << EOF
# ARK Cluster Configuration
# Generated on $(date)

# Server Settings
SERVER_PASSWORD=RagnarokServer2024
SERVER_ADMIN_PASSWORD=AdminPassword123
TZ=America/Toronto

# Cluster Settings
CLUSTER_ID=MyARKCluster

# Performance Settings
EXTRA_SETTINGS=?HarvestAmountMultiplier=2.0?XPMultiplier=2.0?TamingSpeedMultiplier=3.0?ResourcesRespawnPeriodMultiplier=0.5?ServerCrosshair=True?MapPlayerLocation=True

# Optional: Disable BattlEye and allow cave flyers
EXTRA_FLAGS=-NoBattlEye -ForceAllowCaveFlyers

# Backup Settings (if using restic)
BACKUP_ENABLED=false
BACKUP_REPOSITORY=
BACKUP_PASSWORD=
BACKUP_SCHEDULE=0 2 * * *

# Update Settings
AUTO_UPDATE_ENABLED=true
AUTO_UPDATE_SCHEDULE=0 4 * * *
EOF
        
        log "Created .env file at $env_file"
        info "Please edit the .env file to customize your server settings"
    else
        info "Environment file already exists at $env_file"
    fi
}

# Function to setup firewall rules
setup_firewall() {
    log "Setting up firewall rules for ARK servers"
    
    # Check if firewall-cmd is available
    if command -v firewall-cmd &> /dev/null; then
        info "Detected firewalld. Adding ARK server ports..."
        
        # Add ports for cluster
        sudo firewall-cmd --permanent --add-port=7777/udp  # Island
        sudo firewall-cmd --permanent --add-port=7778/udp  # Ragnarok
        sudo firewall-cmd --permanent --add-port=7779/udp  # Scorched Earth
        sudo firewall-cmd --permanent --add-port=7780/udp  # Aberration
        sudo firewall-cmd --permanent --add-port=27020-27023/tcp  # RCON ports
        sudo firewall-cmd --reload
        
        log "Firewall rules added"
    elif command -v ufw &> /dev/null; then
        info "Detected UFW. Adding ARK server ports..."
        
        sudo ufw allow 7777:7780/udp
        sudo ufw allow 27020:27023/tcp
        
        log "UFW rules added"
    else
        warn "No supported firewall detected. Please manually open ports:"
        echo "UDP: 7777-7780 (game ports)"
        echo "TCP: 27020-27023 (RCON ports)"
    fi
}

# Main setup function
main() {
    log "Starting Podman ARK Server Setup"
    
    # Check prerequisites
    check_podman
    check_compose
    
    # Setup Podman
    setup_rootless
    configure_podman
    
    # Create resources
    create_network
    create_volumes
    
    # Build and configure
    build_image
    create_env_file
    create_systemd_services
    
    # System optimizations
    optimize_system
    
    # Optional firewall setup
    read -p "Setup firewall rules for ARK servers? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        setup_firewall
    fi
    
    log "Podman ARK Server setup completed!"
    echo
    info "Next steps:"
    echo "1. Edit container/.env file to configure your servers"
    echo "2. Run: ./manage-cluster.sh init"
    echo "3. Start servers: ./manage-cluster.sh start"
    echo "4. Check status: ./manage-cluster.sh status"
    echo
    info "For Ragnarok only server:"
    echo "podman-compose -f container/compose-ragnarok.yaml up -d"
    echo
    info "To enable auto-start on boot:"
    echo "systemctl --user enable ark-cluster.service"
}

# Run main function
main "$@"
