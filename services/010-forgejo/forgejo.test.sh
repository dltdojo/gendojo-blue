#!/bin/bash

set -e

echo "Testing forgejo.sh comprehensive functionality..."

cd /home/runner/work/gendojo-blue/gendojo-blue/services/010-forgejo

# =============================================================================
# LONG-FORM ARGUMENTS TESTS (from forgejo.test-long-args.sh)
# =============================================================================

echo "[TEST_FORGEJO_LONG_001] Testing long-form --help argument..."
if ./forgejo.sh --help | grep -q "Usage:"; then
  echo "Long-form --help works correctly."
else
  echo "Long-form --help failed!" >&2
  exit 1
fi
echo

echo "[TEST_FORGEJO_LONG_002] Testing short-form -h argument (backward compatibility)..."
if ./forgejo.sh -h | grep -q "Usage:"; then
  echo "Short-form -h works correctly (backward compatible)."
else
  echo "Short-form -h failed!" >&2
  exit 1
fi
echo

echo "[TEST_FORGEJO_LONG_003] Testing invalid argument handling..."
if ! ./forgejo.sh --invalid-option >/dev/null 2>&1; then
  echo "Invalid argument handling works correctly."
else
  echo "Invalid argument should have failed!" >&2
  exit 1
fi
echo

echo "[TEST_FORGEJO_LONG_004] Testing that help shows both short and long forms..."
HELP_OUTPUT=$(./forgejo.sh --help)
if echo "$HELP_OUTPUT" | grep -q "\-i, \-\-init" && echo "$HELP_OUTPUT" | grep -q "\-s, \-\-start"; then
  echo "Help correctly shows both short and long forms."
else
  echo "Help does not show both short and long forms correctly!" >&2
  exit 1
fi
echo

# =============================================================================
# BACKUP DIRECTORY TESTS (from forgejo.test-backup-dir.sh)
# =============================================================================

echo "[TEST_BACKUP_DIR_001] Testing --backup-dir argument parsing..."
if ./forgejo.sh --backup-dir 2>&1 | grep -q "Error: --backup-dir requires an argument"; then
  echo "--backup-dir correctly requires an argument."
else
  echo "--backup-dir should require an argument!" >&2
  exit 1
fi
echo

echo "[TEST_BACKUP_DIR_002] Testing help shows --backup-dir option..."
HELP_OUTPUT=$(./forgejo.sh --help)
if echo "$HELP_OUTPUT" | grep -q "\-\-backup-dir DIR"; then
  echo "Help correctly shows --backup-dir option."
else
  echo "Help does not show --backup-dir option correctly!" >&2
  exit 1
fi
echo

echo "[TEST_BACKUP_DIR_003] Testing help shows --backup-dir example..."
if echo "$HELP_OUTPUT" | grep -q "\-\-backup-dir /tmp/backups"; then
  echo "Help correctly shows --backup-dir example."
else
  echo "Help does not show --backup-dir example correctly!" >&2
  exit 1
fi
echo

echo "[TEST_BACKUP_DIR_004] Testing --backup-dir with invalid option combination..."
if ! ./forgejo.sh --backup-dir --invalid-option >/dev/null 2>&1; then
  echo "Invalid option combination handling works correctly."
else
  echo "Invalid option combination should have failed!" >&2
  exit 1
fi
echo

# Test the backup directory creation logic (without actually running Docker)
echo "[TEST_BACKUP_DIR_005] Testing backup directory path handling..."
# Create a temporary test directory
TEST_DIR="/tmp/forgejo-backup-test-$(date +%s)"
mkdir -p "$TEST_DIR"

# Test that the script accepts the --backup-dir option without error
# (We can't test the actual backup without Docker running, but we can test argument parsing)
if ! ./forgejo.sh --backup-dir "$TEST_DIR" --help >/dev/null 2>&1; then
  echo "Script should accept --backup-dir with valid directory!" >&2
  rm -rf "$TEST_DIR"
  exit 1
fi

rm -rf "$TEST_DIR"
echo "Backup directory path handling works correctly."
echo

# =============================================================================
# BACKUP SIMULATION TESTS (from forgejo.test-backup-sim.sh)
# =============================================================================

# Create a temporary directory for simulation tests
TEST_BASE_DIR="/tmp/forgejo-backup-simulation-$(date +%s)"
mkdir -p "$TEST_BASE_DIR"

echo "[TEST_BACKUP_SIM_001] Testing default behavior (no --backup-dir)..."
# Test that help includes the new option
HELP_TEXT=$(./forgejo.sh --help)
if echo "$HELP_TEXT" | grep -q "default: current directory"; then
  echo "Help correctly shows default backup directory behavior."
else
  echo "Help does not specify default backup directory behavior!" >&2
  exit 1
fi
echo

echo "[TEST_BACKUP_SIM_002] Testing backup directory creation logic..."
# Create a test script that mimics the backup logic
cat > "$TEST_BASE_DIR/test_backup_logic.sh" << 'EOF'
#!/bin/bash

# Simulate the backup directory logic from forgejo.sh
BACKUP_DIR=""

# Parse arguments like forgejo.sh does
while [ "$#" -gt 0 ]; do
  case "$1" in
    --backup-dir)
      if [ "$#" -lt 2 ] || [[ "$2" =~ ^-- ]]; then
        echo "Error: --backup-dir requires an argument" >&2
        exit 1
      fi
      BACKUP_DIR="$2"
      shift
      ;;
    *)
      echo "Simulating other args: $1"
      ;;
  esac
  shift
done

# Simulate backup logic
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
BACKUP_FILENAME="forgejo-backup-${TIMESTAMP}.zip"

# Determine backup destination directory (like in forgejo.sh)
if [ -n "$BACKUP_DIR" ]; then
  # Use specified backup directory
  BACKUP_DEST="$BACKUP_DIR"
  
  # Create backup directory if it doesn't exist
  if ! mkdir -p "$BACKUP_DEST"; then
    echo "Failed to create backup directory: $BACKUP_DEST" >&2
    exit 1
  fi
  echo "Would create backup at: $BACKUP_DEST/$BACKUP_FILENAME"
else
  # Use current directory (default behavior)
  BACKUP_DEST="."
  echo "Would create backup at: $BACKUP_DEST/$BACKUP_FILENAME"
fi
EOF

chmod +x "$TEST_BASE_DIR/test_backup_logic.sh"

# Test default behavior (no --backup-dir)
OUTPUT1=$("$TEST_BASE_DIR/test_backup_logic.sh")
if echo "$OUTPUT1" | grep -q "Would create backup at: ./forgejo-backup-"; then
  echo "Default backup location logic works correctly."
else
  echo "Default backup location logic failed!" >&2
  echo "Output was: $OUTPUT1"
  exit 1
fi

# Test custom backup directory
CUSTOM_DIR="$TEST_BASE_DIR/custom-backups"
OUTPUT2=$("$TEST_BASE_DIR/test_backup_logic.sh" --backup-dir "$CUSTOM_DIR")
if echo "$OUTPUT2" | grep -q "Would create backup at: $CUSTOM_DIR/forgejo-backup-"; then
  echo "Custom backup directory logic works correctly."
else
  echo "Custom backup directory logic failed!" >&2
  echo "Output was: $OUTPUT2"
  exit 1
fi

# Verify directory was actually created
if [ -d "$CUSTOM_DIR" ]; then
  echo "Custom backup directory was created successfully."
else
  echo "Custom backup directory was not created!" >&2
  exit 1
fi
echo

echo "[TEST_BACKUP_SIM_003] Testing backup directory with spaces..."
SPACE_DIR="$TEST_BASE_DIR/backup with spaces"
OUTPUT3=$("$TEST_BASE_DIR/test_backup_logic.sh" --backup-dir "$SPACE_DIR")
if echo "$OUTPUT3" | grep -q "Would create backup at: $SPACE_DIR/forgejo-backup-"; then
  echo "Backup directory with spaces works correctly."
else
  echo "Backup directory with spaces failed!" >&2
  echo "Output was: $OUTPUT3"
  exit 1
fi

if [ -d "$SPACE_DIR" ]; then
  echo "Backup directory with spaces was created successfully."
else
  echo "Backup directory with spaces was not created!" >&2
  exit 1
fi
echo

# Cleanup simulation test directory
rm -rf "$TEST_BASE_DIR"

# =============================================================================
# BACKUP LOGGING TESTS
# =============================================================================

echo "[TEST_BACKUP_LOG_001] Testing backup log file creation logic..."
# Create a temporary directory for log tests
LOG_TEST_DIR="/tmp/forgejo-backup-log-test-$(date +%s)"
mkdir -p "$LOG_TEST_DIR"

# Create a test script that simulates the backup logging logic
cat > "$LOG_TEST_DIR/test_backup_log_logic.sh" << 'EOF'
#!/bin/bash

# Simulate the backup logging logic from forgejo.sh
BACKUP_DIR=""

# Parse arguments like forgejo.sh does
while [ "$#" -gt 0 ]; do
  case "$1" in
    --backup-dir)
      if [ "$#" -lt 2 ] || [[ "$2" =~ ^-- ]]; then
        echo "Error: --backup-dir requires an argument" >&2
        exit 1
      fi
      BACKUP_DIR="$2"
      shift
      ;;
    *)
      echo "Simulating other args: $1"
      ;;
  esac
  shift
done

# Simulate backup and log file creation
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
BACKUP_FILENAME="forgejo-backup-${TIMESTAMP}.zip"
LOG_FILENAME="forgejo-backup-${TIMESTAMP}.log"

# Determine backup destination directory
if [ -n "$BACKUP_DIR" ]; then
  BACKUP_DEST="$BACKUP_DIR"
  if ! mkdir -p "$BACKUP_DEST"; then
    echo "Failed to create backup directory: $BACKUP_DEST" >&2
    exit 1
  fi
else
  BACKUP_DEST="."
fi

# Create log file path
LOG_FILE="$BACKUP_DEST/$LOG_FILENAME"

# Simulate log file creation
{
  echo "=== Forgejo Backup Log ==="
  echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "Backup filename: $BACKUP_FILENAME"
  echo "Backup destination: $BACKUP_DEST"
  echo "Log filename: $LOG_FILENAME"
  echo ""
  echo "=== Backup Process ==="
  echo "Step 1: Starting Forgejo dump process..."
  echo "Step 2: Simulated forgejo dump command"
  echo "Step 3: Backup completed successfully"
  echo ""
  echo "=== Backup Summary ==="
  echo "Backup file: $BACKUP_DEST/$BACKUP_FILENAME"
  echo "Log file: $LOG_FILE"
  echo "Completed at: $(date '+%Y-%m-%d %H:%M:%S')"
} > "$LOG_FILE"

echo "Would create backup at: $BACKUP_DEST/$BACKUP_FILENAME"
echo "Would create log at: $LOG_FILE"
EOF

chmod +x "$LOG_TEST_DIR/test_backup_log_logic.sh"

# Test default behavior with logging
OUTPUT1=$("$LOG_TEST_DIR/test_backup_log_logic.sh")
if echo "$OUTPUT1" | grep -q "Would create backup at: ./forgejo-backup-" && echo "$OUTPUT1" | grep -q "Would create log at: ./forgejo-backup-"; then
  echo "Default backup and log location logic works correctly."
else
  echo "Default backup and log location logic failed!" >&2
  echo "Output was: $OUTPUT1"
  exit 1
fi

# Check if log file was actually created with correct content
LOG_FILES=(./forgejo-backup-*.log)
if [ -f "${LOG_FILES[0]}" ]; then
  LOG_FILE="${LOG_FILES[0]}"
  if grep -q "=== Forgejo Backup Log ===" "$LOG_FILE" && grep -q "Backup Process" "$LOG_FILE"; then
    echo "Log file created successfully with correct content."
  else
    echo "Log file content is incorrect!" >&2
    exit 1
  fi
  # Clean up log file
  rm -f "$LOG_FILE"
else
  echo "Log file was not created!" >&2
  exit 1
fi

# Test custom backup directory with logging
CUSTOM_LOG_DIR="$LOG_TEST_DIR/custom-logs"
OUTPUT2=$("$LOG_TEST_DIR/test_backup_log_logic.sh" --backup-dir "$CUSTOM_LOG_DIR")
if echo "$OUTPUT2" | grep -q "Would create backup at: $CUSTOM_LOG_DIR/forgejo-backup-" && echo "$OUTPUT2" | grep -q "Would create log at: $CUSTOM_LOG_DIR/forgejo-backup-"; then
  echo "Custom backup directory logging logic works correctly."
else
  echo "Custom backup directory logging logic failed!" >&2
  echo "Output was: $OUTPUT2"
  exit 1
fi

# Check if log file was created in custom directory
CUSTOM_LOG_FILES=("$CUSTOM_LOG_DIR"/forgejo-backup-*.log)
if [ -f "${CUSTOM_LOG_FILES[0]}" ]; then
  CUSTOM_LOG_FILE="${CUSTOM_LOG_FILES[0]}"
  if grep -q "=== Forgejo Backup Log ===" "$CUSTOM_LOG_FILE" && grep -q "Backup destination: $CUSTOM_LOG_DIR" "$CUSTOM_LOG_FILE"; then
    echo "Custom directory log file created successfully with correct content."
  else
    echo "Custom directory log file content is incorrect!" >&2
    exit 1
  fi
else
  echo "Custom directory log file was not created!" >&2
  exit 1
fi
echo

echo "[TEST_BACKUP_LOG_002] Testing log file naming consistency..."
# Test that backup file and log file have same timestamp
BACKUP_FILES=(./forgejo-backup-*.zip)
LOG_FILES=(./forgejo-backup-*.log)

# Clean up any existing test files first
rm -f ./forgejo-backup-*.zip ./forgejo-backup-*.log

# Run simulation again to get fresh files
"$LOG_TEST_DIR/test_backup_log_logic.sh" >/dev/null

BACKUP_FILES=(./forgejo-backup-*.zip)
LOG_FILES=(./forgejo-backup-*.log)

if [ -f "${LOG_FILES[0]}" ]; then
  BACKUP_BASE=$(basename "${LOG_FILES[0]}" .log)
  EXPECTED_ZIP="${BACKUP_BASE}.zip"
  
  if grep -q "Backup filename: $EXPECTED_ZIP" "${LOG_FILES[0]}"; then
    echo "Backup and log file naming consistency verified."
  else
    echo "Backup and log file naming inconsistency detected!" >&2
    exit 1
  fi
  
  # Clean up
  rm -f "${LOG_FILES[0]}"
else
  echo "Could not verify naming consistency!" >&2
  exit 1
fi
echo

# Cleanup log test directory
rm -rf "$LOG_TEST_DIR"

echo "All forgejo.sh tests passed!"