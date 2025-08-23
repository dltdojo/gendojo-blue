#!/bin/bash

init_pki() {
  PKI_DIR="pki"
  CA_CERT="$PKI_DIR/ca.crt"
  if [ ! -d "$PKI_DIR" ] || [ ! -f "$CA_CERT" ]; then
    echo "PKI directory or CA certificate not found. Initializing PKI..."
    mkdir -p "$PKI_DIR"
    "$(dirname "$0")/../../scripts/010-gencert/gencert.sh" -o "$PKI_DIR"
    echo "PKI initialized."
  else
    echo "PKI directory and CA certificate already exist."
  fi
}

check_commands_exist() {
  # Ensure each provided command is available in PATH
  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "Error: '$cmd' is not installed or not in PATH. Please install it and try again." >&2
      return 1
    fi
  done
  return 0
}

start_forgejo_docker() {
  echo "Starting Forgejo with Docker Compose..."
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  if ! check_commands_exist docker; then
    return 1
  fi

  # Change to the service directory (where docker compose file lives) and start containers
  if (cd "$SCRIPT_DIR" && docker compose up -d); then
    echo "Forgejo services started."
    echo "Open your browser at: http://localhost:3000/"
  else
    echo "Failed to start Forgejo services. Check Docker output with: (cd \"$SCRIPT_DIR\" && docker compose logs -f)" >&2
    return 1
  fi
}

stop_forgejo_docker() {
  echo "Stopping Forgejo and removing containers/volumes..."
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  if ! check_commands_exist docker; then
    return 1
  fi

  # Change to the service directory and stop containers, remove anonymous volumes
  if (cd "$SCRIPT_DIR" && docker compose down); then
    echo "Forgejo services stopped and volumes removed."
  else
    echo "Failed to stop Forgejo services. Check Docker output with: (cd \"$SCRIPT_DIR\" && docker compose logs -f)" >&2
    return 1
  fi
}

show_help() {
  cat <<'EOF'
Usage: $(basename "$0") [OPTIONS]

Options:
  -i    Initialize PKI (create pki directory and CA certificate)
  -s    Start Forgejo with Docker Compose (docker compose up -d)
  -x    Stop Forgejo and remove containers + volumes (docker compose down -v)
  -h    Show this help message

Examples:
  $(basename "$0") -i    # initialize PKI
  $(basename "$0") -s    # start Forgejo with docker compose
  $(basename "$0") -x    # stop Forgejo and remove volumes
  $(basename "$0") -h    # show this help
EOF
}

# Parse command line options: -i invokes init_pki, -s starts forgejo, -x stops forgejo, -h shows help
if [ "$#" -eq 0 ]; then
  show_help
  exit 0
fi

while getopts "ihsx" opt; do
  case "$opt" in
    i) init_pki ;; 
    s) start_forgejo_docker ;;
    x) stop_forgejo_docker ;;
    h) show_help; exit 0 ;;
    *) show_help; exit 1 ;;
  esac
done
