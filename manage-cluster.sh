#!/bin/bash

# ARK Cluster Management Script
# This script helps manage ARK: Survival Ascended cluster servers

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/compose-cluster.yaml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

usage() {
    echo "ARK Cluster Management Script"
    echo ""
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  start [SERVICE]     Start all cluster services or specific service"
    echo "  stop [SERVICE]      Stop all cluster services or specific service"
    echo "  restart [SERVICE]   Restart all cluster services or specific service"
    echo "  status              Show status of all cluster services"
    echo "  logs [SERVICE]      Show logs for all services or specific service"
    echo "  update              Update all server images and restart"
    echo "  backup              Backup all cluster data"
    echo "  rcon SERVICE CMD    Execute RCON command on specific service"
    echo "  build               Build custom container image"
    echo "  init                Initialize cluster configuration"
    echo ""
    echo "Services:"
    echo "  ark-island         The Island server"
    echo "  ark-ragnarok       Ragnarok server"
    echo "  ark-scorchedearth  Scorched Earth server (optional)"
    echo "  ark-aberration     Aberration server (optional)"
    echo ""
    echo "Examples:"
    echo "  $0 start                    # Start core cluster (Island + Ragnarok)"
    echo "  $0 start ark-ragnarok       # Start only Ragnarok server"
    echo "  $0 rcon ark-island Saveworld # Save The Island server"
    echo "  $0 logs ark-ragnarok        # Show Ragnarok server logs"
    echo ""
}

check_dependencies() {
    if ! command -v podman &> /dev/null && ! command -v docker &> /dev/null; then
        error "Neither podman nor docker is installed"
        exit 1
    fi
    
    if command -v podman &> /dev/null; then
        CONTAINER_CMD="podman"
        COMPOSE_CMD="podman-compose"
        if ! command -v podman-compose &> /dev/null; then
            if command -v docker-compose &> /dev/null; then
                COMPOSE_CMD="docker-compose"
            else
                error "podman-compose or docker-compose is required"
                exit 1
            fi
        fi
    else
        CONTAINER_CMD="docker"
        COMPOSE_CMD="docker-compose"
        if ! command -v docker-compose &> /dev/null; then
            COMPOSE_CMD="docker compose"
        fi
    fi
    
    log "Using container runtime: ${CONTAINER_CMD}"
    log "Using compose command: ${COMPOSE_CMD}"
}

start_cluster() {
    local service="$1"
    if [ -n "$service" ]; then
        log "Starting ARK cluster service: $service"
        $COMPOSE_CMD -f "$COMPOSE_FILE" up -d "$service"
    else
        log "Starting ARK cluster (core services: Island + Ragnarok)"
        $COMPOSE_CMD -f "$COMPOSE_FILE" up -d ark-island ark-ragnarok
    fi
}

start_full_cluster() {
    log "Starting full ARK cluster (all maps)"
    $COMPOSE_CMD -f "$COMPOSE_FILE" --profile full-cluster up -d
}

stop_cluster() {
    local service="$1"
    if [ -n "$service" ]; then
        log "Stopping ARK cluster service: $service"
        $COMPOSE_CMD -f "$COMPOSE_FILE" stop "$service"
    else
        log "Stopping ARK cluster"
        $COMPOSE_CMD -f "$COMPOSE_FILE" down
    fi
}

restart_cluster() {
    local service="$1"
    if [ -n "$service" ]; then
        log "Restarting ARK cluster service: $service"
        $COMPOSE_CMD -f "$COMPOSE_FILE" restart "$service"
    else
        log "Restarting ARK cluster"
        $COMPOSE_CMD -f "$COMPOSE_FILE" restart
    fi
}

cluster_status() {
    log "ARK Cluster Status:"
    $COMPOSE_CMD -f "$COMPOSE_FILE" ps
}

show_logs() {
    local service="$1"
    if [ -n "$service" ]; then
        log "Showing logs for ARK service: $service"
        $COMPOSE_CMD -f "$COMPOSE_FILE" logs -f "$service"
    else
        log "Showing logs for all ARK cluster services"
        $COMPOSE_CMD -f "$COMPOSE_FILE" logs -f
    fi
}

update_cluster() {
    log "Updating ARK cluster images and restarting services"
    
    # Pull latest images
    $COMPOSE_CMD -f "$COMPOSE_FILE" pull
    
    # Restart services with new images
    $COMPOSE_CMD -f "$COMPOSE_FILE" up -d --force-recreate
    
    log "Cluster update completed"
}

backup_cluster() {
    log "Creating backup of ARK cluster data"
    
    local backup_dir="./backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    # Get volume paths and backup
    for volume in ark-island-data ark-ragnarok-data ark-scorchedearth-data ark-aberration-data ark-cluster-data; do
        if $CONTAINER_CMD volume inspect "$volume" &>/dev/null; then
            log "Backing up volume: $volume"
            $CONTAINER_CMD run --rm -v "$volume":/source -v "$(pwd)/$backup_dir":/backup alpine tar czf "/backup/${volume}.tar.gz" -C /source .
        fi
    done
    
    log "Backup completed in: $backup_dir"
}

rcon_command() {
    local service="$1"
    local command="$2"
    
    if [ -z "$service" ] || [ -z "$command" ]; then
        error "Both service and command are required for RCON"
        usage
        exit 1
    fi
    
    # Get the container name
    local container_name="${service}"
    
    log "Executing RCON command '$command' on $service"
    
    # Execute RCON command inside the container
    $CONTAINER_CMD exec "$container_name" rcon -a 127.0.0.1:27020 -p "${SERVER_ADMIN_PASSWORD:-AdminPassword123}" "$command"
}

build_image() {
    log "Building custom ARK Ascended server image"
    cd "$SCRIPT_DIR" || exit 1
    $CONTAINER_CMD build -t ark-ascended-server:latest -f Containerfile .
    log "Image build completed"
}

init_cluster() {
    log "Initializing ARK cluster configuration"
    
    # Create .env file if it doesn't exist
    if [ ! -f "${SCRIPT_DIR}/.env" ]; then
        cat > "${SCRIPT_DIR}/.env" << EOF
# ARK Cluster Configuration
SERVER_PASSWORD=ClusterPassword123
SERVER_ADMIN_PASSWORD=AdminPassword123
CLUSTER_ID=MyARKCluster
TZ=America/Toronto

# Optional: Custom settings
# EXTRA_SETTINGS=?HarvestAmountMultiplier=2.0?XPMultiplier=2.0
# EXTRA_FLAGS=-NoBattlEye
EOF
        log "Created default .env file. Please edit it with your preferences."
    fi
    
    # Create necessary directories
    mkdir -p backups logs
    
    log "Cluster initialization completed"
    info "Edit .env file to configure your cluster settings"
    info "Run '$0 start' to start the core cluster (Island + Ragnarok)"
    info "Run '$0 start-full' to start all available maps"
}

# Main script logic
case "${1:-}" in
    start)
        check_dependencies
        start_cluster "$2"
        ;;
    start-full)
        check_dependencies
        start_full_cluster
        ;;
    stop)
        check_dependencies
        stop_cluster "$2"
        ;;
    restart)
        check_dependencies
        restart_cluster "$2"
        ;;
    status)
        check_dependencies
        cluster_status
        ;;
    logs)
        check_dependencies
        show_logs "$2"
        ;;
    update)
        check_dependencies
        update_cluster
        ;;
    backup)
        check_dependencies
        backup_cluster
        ;;
    rcon)
        check_dependencies
        rcon_command "$2" "$3"
        ;;
    build)
        check_dependencies
        build_image
        ;;
    init)
        init_cluster
        ;;
    ""|help|--help|-h)
        usage
        ;;
    *)
        error "Unknown command: $1"
        usage
        exit 1
        ;;
esac
