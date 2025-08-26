#!/bin/bash

# Global variables
BACKUP_DIR=""
PLAKAR_BACKUP_DIR="$HOME/test/forgejo-backup" # global path for plakar backups (default set here)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

init_pki() {
  PKI_DIR="pki"
  CA_CERT="$PKI_DIR/ca.crt"
  if [ ! -d "$PKI_DIR" ] || [ ! -f "$CA_CERT" ]; then
    echo "PKI directory or CA certificate not found. Initializing PKI..."
    mkdir -p "$PKI_DIR"
    "$SCRIPT_DIR/../../scripts/010-gencert/gencert.sh" -o "$PKI_DIR"
    echo "PKI initialized."
  else
    echo "PKI directory and CA certificate already exist."
  fi
}

# Backup this whole dir into plakar backup
backup_plakar(){
  if ! check_commands_exist plakar; then
    return 1
  fi

  # you need to create a plakar backup directory for this project.
  if [ ! -d "$PLAKAR_BACKUP_DIR" ]; then
    echo "Plakar backup directory $PLAKAR_BACKUP_DIR does not exist. Please create it first." >&2
    # plakar at $PLAKAR_BACKUP_DIR create -plaintext
    return 1
  fi
  stop_forgejo_docker
  plakar at "$PLAKAR_BACKUP_DIR" backup .
  start_forgejo_docker
}

restore_plakar(){
  if ! check_commands_exist plakar; then
    return 1
  fi

  # you need to create a plakar backup directory for this project.
  if [ ! -d "$PLAKAR_BACKUP_DIR" ]; then
    echo "Plakar backup directory $PLAKAR_BACKUP_DIR does not exist. Please create it first." >&2
    # plakar at $PLAKAR_BACKUP_DIR create -plaintext
    return 1
  fi
  stop_forgejo_docker
  plakar at "$PLAKAR_BACKUP_DIR" restore -to .
  start_forgejo_docker
}

# Backup Forgejo data 
backup_forgejo() {
  echo "Creating Forgejo backup..."
  if ! check_commands_exist docker; then
    return 1
  fi

  # Generate timestamp in format YYYYMMDD-HHMMSS
  TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
  BACKUP_FILENAME="forgejo-backup-${TIMESTAMP}.tgz"
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
  echo "Step 1: Starting backup process..." | tee -a "$LOG_FILE"

  stop_forgejo_docker
  
  # using docker run busybox to mounut ./forgejo-data then tar czf to host's $BACKUP_DEST
  # change ownership of backup files to current user in docker
  if (cd "$SCRIPT_DIR" && docker run --rm -v "$BACKUP_DEST:/backup" -v "$(pwd)/forgejo-data:/data" busybox sh -c "cd /data && tar czf /backup/$BACKUP_FILENAME . && chown 1000:1000 /backup/$BACKUP_FILENAME"); then
    echo "Step 2: Backup created successfully" | tee -a "$LOG_FILE"
  else
    echo "Step 2 FAILED: Failed to create backup" | tee -a "$LOG_FILE"
    return 1
  fi
}

restore_forgejo() {
  # Generate timestamp in format YYYYMMDD-HHMMSS
  TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
  RESTORE_FILENAME="forgejo-backup.tgz"
  LOG_FILE="forgejo-restore-${TIMESTAMP}.log"
  echo "=== Forgejo Restore Log ===" > "$LOG_FILE"
  echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE"
  echo "Restore filename: $RESTORE_FILENAME" >> "$LOG_FILE"
  echo "Log filename: $LOG_FILE" >> "$LOG_FILE"
  echo "" >> "$LOG_FILE"
  echo "=== Restore Process ===" >> "$LOG_FILE"

  echo "Step 1: Checking restore file..." | tee -a "$LOG_FILE"
  if [ ! -f "$RESTORE_FILENAME" ]; then
    echo "Step 1 FAILED: Restore file $RESTORE_FILENAME does not exist" | tee -a "$LOG_FILE"
    echo "Restore failed." | tee -a "$LOG_FILE"
    return 1
  fi

  echo "Step 2: Stopping Forgejo Docker..." | tee -a "$LOG_FILE"
  if stop_forgejo_docker; then
    echo "Step 2: Forgejo Docker stopped." | tee -a "$LOG_FILE"
  else
    echo "Step 2 FAILED: Could not stop Forgejo Docker." | tee -a "$LOG_FILE"
    echo "Restore failed." | tee -a "$LOG_FILE"
    return 1
  fi

  echo "Step 3: Checking ./forgejo-data directory..." | tee -a "$LOG_FILE"
  if [ ! -d "./forgejo-data" ]; then
    echo "Step 3 FAILED: ./forgejo-data directory does not exist" | tee -a "$LOG_FILE"
    echo "Restore failed." | tee -a "$LOG_FILE"
    return 1
  fi

  echo "Step 4: Changing ownership to current user..." | tee -a "$LOG_FILE"
  cd "$SCRIPT_DIR" || return 1
  if docker run --rm -v "$(pwd)/forgejo-data:/data" busybox sh -c "chown -R 1000:1000 /data"; then
    echo "Step 4: Ownership changed to current user" | tee -a "$LOG_FILE"
  else
    echo "Step 4 FAILED: Failed to change ownership" | tee -a "$LOG_FILE"
    echo "Restore failed." | tee -a "$LOG_FILE"
    return 1
  fi

  echo "Step 5: Moving ./forgejo-data to ./forgejo-data-old..." | tee -a "$LOG_FILE"
  if mv ./forgejo-data ./forgejo-data-old; then
    echo "Step 5: forgejo-data moved to forgejo-data-old" | tee -a "$LOG_FILE"
  else
    echo "Step 5 FAILED: Could not move forgejo-data" | tee -a "$LOG_FILE"
    echo "Restore failed." | tee -a "$LOG_FILE"
    return 1
  fi

  echo "Step 6: Extracting backup to ./forgejo-data..." | tee -a "$LOG_FILE"
  mkdir -p ./forgejo-data
  if tar xzf "$RESTORE_FILENAME" -C ./forgejo-data; then
    echo "Step 6: Backup extracted successfully" | tee -a "$LOG_FILE"
  else
    echo "Step 6 FAILED: Failed to extract backup" | tee -a "$LOG_FILE"
    echo "Restore failed." | tee -a "$LOG_FILE"
    return 1
  fi

  echo "Step 7: Restoring ownership to current user..." | tee -a "$LOG_FILE"
  cd "$SCRIPT_DIR" || return 1
  if docker run --rm -v "$(pwd)/forgejo-data:/data" busybox sh -c "chown -R 1000:1000 /data"; then
    echo "Step 7: Ownership restored to current user" | tee -a "$LOG_FILE"
  else
    echo "Step 7 WARNING: Failed to restore ownership after extraction" | tee -a "$LOG_FILE"
  fi

  echo "Step 8: Optional - Starting Forgejo Docker..." | tee -a "$LOG_FILE"
  if start_forgejo_docker; then
    echo "Step 8: Forgejo Docker started." | tee -a "$LOG_FILE"
  else
    echo "Step 8 WARNING: Could not start Forgejo Docker automatically. Please start manually." | tee -a "$LOG_FILE"
  fi

  echo "" | tee -a "$LOG_FILE"
  echo "=== Restore Summary ===" | tee -a "$LOG_FILE"
  echo "Restore completed at $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG_FILE"
  echo "Backup file: $RESTORE_FILENAME" | tee -a "$LOG_FILE"
  echo "Log file: $LOG_FILE" | tee -a "$LOG_FILE"
  echo "forgejo-data restored and ready." | tee -a "$LOG_FILE"
  return 0
}

# Function to fix permissions for forgejo data
fix_data_permission() {
    echo "Fixing permissions for forgejo data directory..."
    # Fix permissions using busybox container
    docker run --rm -v "$(pwd)/forgejo-data:/data" busybox chown -R 1000:1000 /data
    echo "Permissions fixed successfully!"
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
    echo "Failed to start Forgejo services. Check Docker output with: \(cd '$SCRIPT_DIR' && docker compose logs -f\)" >&2
    return 1
  fi
}

stop_forgejo_docker() {
  echo "Stopping Forgejo and removing containers/volumes..."
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  if ! check_commands_exist docker; then
    return 1
  fi

  # Change to the service directory and stop containers
  if (cd "$SCRIPT_DIR" && docker compose down); then
    echo "Forgejo services stopped"
  else
    echo "Failed to stop Forgejo services."
    return 1
  fi
}

show_help() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  -i, --init                    Initialize PKI (create pki directory and CA certificate)
  -s, --start                   Start Forgejo with Docker Compose (docker compose up -d)
  -x, --stop                    Stop Forgejo and remove containers + volumes (docker compose down -v)
  -b, --backup                  Create timestamped backup of Forgejo data (forgejo-backup-YYYYMMDD-HHMMSS.zip)
      --backup-plakar           Create Plakar backup (uses plakar at configured backup location)
      --backup-dir DIR          Specify directory for backup files (default: current directory)
  -P, --plakar-backup-dir DIR   Specify Plakar backup directory (overrides default PLAKAR_BACKUP_DIR)
      --fix-perm                Fix permissions for forgejo data directory
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
  $(basename "$0") --backup-plakar               # create a plakar-managed backup
  $(basename "$0") --plakar-backup-dir /tmp/plakar --backup-plakar  # use custom plakar backup dir for this run
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
    --backup-plakar)
      backup_plakar
      exit $?
      ;;
    -r|--restore)
      restore_forgejo
      exit $?
      ;;
    --fix-perm)
      fix_data_permission
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
    -P|--plakar-backup-dir)
      if [ "$#" -lt 2 ] || [[ "$2" =~ ^-- ]]; then
        echo "Error: --plakar-backup-dir requires an argument" >&2
        show_help >&2
        exit 1
      fi
      PLAKAR_BACKUP_DIR="$2"
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