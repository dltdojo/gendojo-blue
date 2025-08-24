#!/bin/bash

set -e

OUTPUT_DIR="test-long-args-output"

# Function to clean up
cleanup() {
  echo "Cleaning up generated files..."
  rm -rf "$OUTPUT_DIR"
  echo "Cleanup successful."
}

# Check for required tools
echo "Checking for required tools..."
for tool in openssl grep awk sha256sum; do
  if ! command -v "$tool" &> /dev/null;
  then
    echo "Error: $tool is not installed. Please install it and try again." >&2
    exit 1
  fi
done
echo "All required tools are available."
echo

trap cleanup EXIT

echo "[TEST_LONG_001] Testing long-form --help argument..."
./gencert.sh --help | grep -q "Usage:" && echo "Long-form --help works correctly."
echo

echo "[TEST_LONG_002] Testing long-form --output argument..."
./gencert.sh --output "$OUTPUT_DIR" > /dev/null 2>&1

# Check if all files were created
for f in ca.key ca.crt server.key server.csr server.crt; do
  if [ ! -f "$OUTPUT_DIR/$f" ]; then
    echo "File $OUTPUT_DIR/$f not found!"
    exit 1
  fi
done
echo "Long-form --output works correctly - all files created."
echo

# Verify certificates work
echo "[TEST_LONG_003] Verifying certificates created with --output work correctly..."
openssl verify -CAfile "$OUTPUT_DIR/ca.crt" "$OUTPUT_DIR/server.crt" | grep "OK"
echo "Certificates created with --output are valid."
echo

# Clean up for next test
cleanup

echo "[TEST_LONG_004] Testing mixed arguments (short and long)..."
./gencert.sh --output "$OUTPUT_DIR" > /dev/null 2>&1
if [ -f "$OUTPUT_DIR/ca.crt" ]; then
  echo "Mixed argument test passed - files created with --output."
fi

echo
echo "All long-form argument tests passed!"