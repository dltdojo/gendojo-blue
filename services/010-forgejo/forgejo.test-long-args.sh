#!/bin/bash

set -e

echo "Testing forgejo.sh long-form arguments..."

echo "[TEST_FORGEJO_LONG_001] Testing long-form --help argument..."
cd /home/runner/work/gendojo-blue/gendojo-blue/services/010-forgejo
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

echo "All forgejo.sh long-form argument tests passed!"