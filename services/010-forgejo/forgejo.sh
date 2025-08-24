#!/bin/bash

# Global variables
BACKUP_DIR=""

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

backup_forgejo() {
  echo "Creating Forgejo backup..."
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  if ! check_commands_exist docker; then
    return 1
  fi

  # Generate timestamp in format YYYYMMDD-HHMMSS
  TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
  BACKUP_FILENAME="forgejo-backup-${TIMESTAMP}.zip"
  LOG_FILENAME="forgejo-backup-${TIMESTAMP}.log"
  
  # Determine backup destination directory
  if [ -n "$BACKUP_DIR" ]; then
    # Use specified backup directory
    BACKUP_DEST="$BACKUP_DIR"
    # Create backup directory if it doesn't exist
    if ! mkdir -p "$BACKUP_DEST"; then
      echo "Failed to create backup directory: $BACKUP_DEST" >&2
      return 1
    fi
  else
    # Use current directory (default behavior)
    BACKUP_DEST="."
  fi
  
  # Create log file path
  LOG_FILE="$BACKUP_DEST/$LOG_FILENAME"
  
  # Initialize log file
  {
    echo "=== Forgejo Backup Log ==="
    echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Backup filename: $BACKUP_FILENAME"
    echo "Backup destination: $BACKUP_DEST"
    echo "Log filename: $LOG_FILENAME"
    echo ""
    echo "=== Backup Process ==="
  } > "$LOG_FILE"
  
  # Log step 1: Starting backup process
  echo "Step 1: Starting Forgejo dump process..." | tee -a "$LOG_FILE"
  
  # Change to the service directory and create backup, capturing output
  echo "Step 2: Executing 'docker compose exec -u git -w /data/git forgejo101 forgejo dump --file=$BACKUP_FILENAME'" >> "$LOG_FILE"
  echo "" >> "$LOG_FILE"
  echo "=== Forgejo Dump Command Output ===" >> "$LOG_FILE"
  
  # Create temporary file to capture command output and status
  TEMP_OUTPUT=$(mktemp)
  DUMP_SUCCESS=0
  
  if (cd "$SCRIPT_DIR" && docker compose exec -u git -w /data/git forgejo101 forgejo dump --file="$BACKUP_FILENAME") > "$TEMP_OUTPUT" 2>&1; then
    DUMP_SUCCESS=1
  fi
  
  # Append command output to log file
  cat "$TEMP_OUTPUT" >> "$LOG_FILE"
  # Also display output to user
  cat "$TEMP_OUTPUT"
  rm -f "$TEMP_OUTPUT"
  
  if [ $DUMP_SUCCESS -eq 1 ]; then
    echo "" >> "$LOG_FILE"
    echo "Step 3: Forgejo dump completed successfully" | tee -a "$LOG_FILE"
    
    # Copy backup file from container to host
    echo "Step 4: Copying backup file from container to host..." | tee -a "$LOG_FILE"
    
    # Create temporary file to capture copy command output and status
    TEMP_COPY_OUTPUT=$(mktemp)
    COPY_SUCCESS=0
    
    if (cd "$SCRIPT_DIR" && docker compose cp "forgejo101:/data/git/$BACKUP_FILENAME" "$BACKUP_DEST") > "$TEMP_COPY_OUTPUT" 2>&1; then
      COPY_SUCCESS=1
    fi
    
    # Append copy command output to log file
    cat "$TEMP_COPY_OUTPUT" >> "$LOG_FILE"
    # Also display output to user
    cat "$TEMP_COPY_OUTPUT"
    rm -f "$TEMP_COPY_OUTPUT"
    
    if [ $COPY_SUCCESS -eq 1 ]; then
      echo "Step 5: Backup process completed successfully" | tee -a "$LOG_FILE"
      echo "" >> "$LOG_FILE"
      echo "=== Backup Summary ===" >> "$LOG_FILE"
      echo "Backup file: $BACKUP_DEST/$BACKUP_FILENAME" >> "$LOG_FILE"
      echo "Log file: $LOG_FILE" >> "$LOG_FILE"
      echo "Completed at: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE"
      
      echo "Backup created successfully: $BACKUP_DEST/$BACKUP_FILENAME"
      echo "Backup log created: $LOG_FILE"
      return 0
    else
      echo "Step 4 FAILED: Failed to copy backup file from container" | tee -a "$LOG_FILE"
      echo "Error occurred at: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE"
      echo "Failed to copy backup file from container." >&2
      return 1
    fi
  else
    echo "Step 2 FAILED: Forgejo dump command failed" | tee -a "$LOG_FILE"
    echo "Error occurred at: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE"
    echo "Failed to create Forgejo backup. Make sure Forgejo is running." >&2
    return 1
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
    echo "Open your browser at: https://forgejo.localtest.me"
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
  -i, --init                    Initialize PKI (create pki directory and CA certificate)
  -s, --start                   Start Forgejo with Docker Compose (docker compose up -d)
  -x, --stop                    Stop Forgejo and remove containers + volumes (docker compose down -v)
  -b, --backup                  Create timestamped backup of Forgejo data (forgejo-backup-YYYYMMDD-HHMMSS.zip)
      --backup-dir DIR          Specify directory for backup files (default: current directory)
  -h, --help                    Show this help message

Examples:
  $(basename "$0") -i                           # initialize PKI
  $(basename "$0") --init                       # initialize PKI (long form)
  $(basename "$0") -s                           # start Forgejo with docker compose
  $(basename "$0") --start                      # start Forgejo with docker compose (long form)
  $(basename "$0") -x                           # stop Forgejo and remove volumes
  $(basename "$0") --stop                       # stop Forgejo and remove volumes (long form)
  $(basename "$0") -b                           # create backup with timestamp
  $(basename "$0") --backup                     # create backup with timestamp (long form)
  $(basename "$0") -b --backup-dir /tmp/backups # create backup in specified directory
  $(basename "$0") -h                           # show this help
  $(basename "$0") --help                       # show this help (long form)
EOF
}

# Parse command line options: supports both short and long forms
if [ "$#" -eq 0 ]; then
  show_help
  exit 0
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    -i|--init)
      init_pki
      exit $?
      ;;
    -s|--start)
      start_forgejo_docker
      exit $?
      ;;
    -x|--stop)
      stop_forgejo_docker
      exit $?
      ;;
    -b|--backup)
      backup_forgejo
      exit $?
      ;;
    --backup-dir)
      if [ "$#" -lt 2 ] || [[ "$2" =~ ^-- ]]; then
        echo "Error: --backup-dir requires an argument" >&2
        show_help >&2
        exit 1
      fi
      BACKUP_DIR="$2"
      shift
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      show_help
      exit 1
      ;;
  esac
  shift
done
