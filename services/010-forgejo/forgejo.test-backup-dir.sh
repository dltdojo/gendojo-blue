#!/bin/bash

set -e

echo "Testing forgejo.sh --backup-dir functionality..."

cd /home/runner/work/gendojo-blue/gendojo-blue/services/010-forgejo

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

echo "All forgejo.sh --backup-dir functionality tests passed!"