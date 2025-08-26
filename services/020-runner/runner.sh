#!/bin/bash

# Unified runner script that combines setup, registration, and permission fixes
# for the Forgejo runner service

# Configuration variables
PKI_CA_PATH="../010-forgejo/pki/ca.crt"
RUNNER_IMAGE="my-forgejo-runner:9.1.1"

# Function to show help message
show_help() {
    cat << EOF
Usage: $0 [OPTION]

Unified Forgejo runner management script

OPTIONS:
    --build     Setup CA certificate and build Docker image
    --register  Register the runner with Forgejo instance
    --fix-perm  Fix permissions for runner data directory
    --start     Start services with docker compose (uses compose.yaml)
    --stop      Stop services with docker compose (uses compose.yaml)
    --help      Show this help message

EXAMPLES:
    $0 --build      # Setup CA cert and build runner image
    $0 --register   # Register runner with Forgejo
    $0 --fix-perm   # Fix permissions for runner-data directory

EOF
}

# Function to setup CA certificate and build Docker image
setup_ca_cert_and_build() {
    echo "Setting up CA certificate and building Docker image..."
    
    # Remove existing my-ca.crt if it exists
    [ -f my-ca.crt ] && rm my-ca.crt
    
    # Copy CA certificate
    if [ ! -f "$PKI_CA_PATH" ]; then
        echo "Error: CA certificate not found at $PKI_CA_PATH"
        exit 1
    fi
    
    cp "$PKI_CA_PATH" my-ca.crt
    echo "Copied CA certificate from $PKI_CA_PATH"
    
    # Build the Docker image
    echo "Building Docker image: $RUNNER_IMAGE"
    docker build -t "$RUNNER_IMAGE" .
    
    echo "Docker image build completed successfully!"
}

# Function to register runner with Forgejo
register_runner() {
    echo "Registering runner with Forgejo instance..."

    # Check if Docker image exists
    if ! docker image inspect "$RUNNER_IMAGE" > /dev/null 2>&1; then
        echo "Error: Docker image $RUNNER_IMAGE not found. Please run '$0 --build' first."
        exit 1
    fi

    # read TOKEN from env variable FORGEJO_RUNNER_TOKEN, if not exist, then exit and warring user.
    TOKEN="${FORGEJO_RUNNER_TOKEN:-}"
    if [ -z "$TOKEN" ]; then
        echo "Error: FORGEJO_RUNNER_TOKEN environment variable is not set."
        exit 1
    fi
    
    # Register the runner
    docker compose run --rm --entrypoint sh runner -c "forgejo-runner register --no-interactive --instance https://forgejo.localtest.me --name runner101 --labels ubuntu-22.04:docker://node:20-bookworm --token $TOKEN"
    
    echo "Runner registration completed!"
}

# Function to fix permissions for runner data
fix_data_permission() {
    echo "Fixing permissions for runner data directory..."
    
    # Fix permissions using busybox container
    docker run --rm -v "$(pwd)/runner-data:/data" busybox chown -R 1000:1000 /data
    
    echo "Permissions fixed successfully!"
}

# Start services using docker compose (explicit compose file)
start_services() {
    echo "Starting services with docker compose (compose.yaml)..."
    docker compose up -d
    echo "Services started."
}

# Stop services using docker compose (explicit compose file)
stop_services() {
    echo "Stopping services with docker compose (compose.yaml)..."
    docker compose down
    echo "Services stopped."
}

# Main script logic
case "${1:-}" in
    --build)
        setup_ca_cert_and_build
        ;;
    --register)
        register_runner
        ;;
    --fix-perm)
        fix_data_permission
        ;;
    --start)
        start_services
        ;;
    --stop)
        stop_services
        ;;
    --help)
        show_help
        ;;
    "")
        echo "Error: No option specified."
        echo ""
        show_help
        exit 1
        ;;
    *)
        echo "Error: Unknown option '$1'"
        echo ""
        show_help
        exit 1
        ;;
esac
