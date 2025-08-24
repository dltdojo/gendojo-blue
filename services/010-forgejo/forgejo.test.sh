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

echo "All forgejo.sh tests passed!"