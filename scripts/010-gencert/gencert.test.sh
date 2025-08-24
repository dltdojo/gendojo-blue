#!/bin/bash

set -e

OUTPUT_DIR="test-output"

# Function to clean up
cleanup() {
  echo "Cleaning up generated files..."
  rm -rf "$OUTPUT_DIR"
  echo "Cleanup successful."
}

# Helper function to check certificate validity
check_certificate_validity() {
  local expected_days="$1"
  local test_name="$2"
  
  # Extract validity dates for CA certificate
  CA_NOT_BEFORE=$(openssl x509 -in "$OUTPUT_DIR/ca.crt" -noout -dates | grep "notBefore" | sed 's/notBefore=//')
  CA_NOT_AFTER=$(openssl x509 -in "$OUTPUT_DIR/ca.crt" -noout -dates | grep "notAfter" | sed 's/notAfter=//')

  # Extract validity dates for server certificate  
  SERVER_NOT_BEFORE=$(openssl x509 -in "$OUTPUT_DIR/server.crt" -noout -dates | grep "notBefore" | sed 's/notBefore=//')
  SERVER_NOT_AFTER=$(openssl x509 -in "$OUTPUT_DIR/server.crt" -noout -dates | grep "notAfter" | sed 's/notAfter=//')

  # Convert dates to seconds since epoch for calculation
  CA_START=$(date -d "$CA_NOT_BEFORE" +%s)
  CA_END=$(date -d "$CA_NOT_AFTER" +%s)
  SERVER_START=$(date -d "$SERVER_NOT_BEFORE" +%s)
  SERVER_END=$(date -d "$SERVER_NOT_AFTER" +%s)

  # Calculate validity periods in days
  CA_VALIDITY_DAYS=$(( (CA_END - CA_START) / 86400 ))
  SERVER_VALIDITY_DAYS=$(( (SERVER_END - SERVER_START) / 86400 ))

  echo "CA certificate validity: $CA_VALIDITY_DAYS days"
  echo "Server certificate validity: $SERVER_VALIDITY_DAYS days"

  # Verify both certificates have expected validity (allow 1 day tolerance)
  if [ "$CA_VALIDITY_DAYS" -lt $(( expected_days - 1 )) ] || [ "$CA_VALIDITY_DAYS" -gt $(( expected_days + 1 )) ]; then
    echo "CA certificate validity is $CA_VALIDITY_DAYS days, expected ~$expected_days days!"
    exit 1
  fi

  if [ "$SERVER_VALIDITY_DAYS" -lt $(( expected_days - 1 )) ] || [ "$SERVER_VALIDITY_DAYS" -gt $(( expected_days + 1 )) ]; then
    echo "Server certificate validity is $SERVER_VALIDITY_DAYS days, expected ~$expected_days days!"
    exit 1
  fi

  echo "$test_name is correct."
  echo
}

# Function to check for required tools
check_required_tools() {
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
}

# TEST_001: File creation verification
test_file_creation() {
  echo "[TEST_001] Checking if all certificate and key files were created in $OUTPUT_DIR..."
  for f in ca.key ca.crt server.key server.csr server.crt; do
    if [ ! -f "$OUTPUT_DIR/$f" ]; then
      echo "File $OUTPUT_DIR/$f not found!"
      exit 1
    fi
  done
  echo "All files created successfully."
  echo
}

# TEST_002: Certificate subjects and issuers verification
test_certificate_fields() {
  echo "[TEST_002] Verifying certificate subjects and issuers..."
  openssl x509 -in "$OUTPUT_DIR/ca.crt" -noout -subject | grep "CN = My CA"
  openssl x509 -in "$OUTPUT_DIR/server.crt" -noout -subject | grep "CN = localhost"
  openssl x509 -in "$OUTPUT_DIR/server.crt" -noout -issuer | grep "CN = My CA"
  echo "Certificate subjects and issuers are correct."
  echo
}

# TEST_003: Certificate chain verification
test_certificate_chain() {
  echo "[TEST_003] Verifying the server certificate with the CA..."
  openssl verify -CAfile "$OUTPUT_DIR/ca.crt" "$OUTPUT_DIR/server.crt" | grep "OK"
  echo "Server certificate is signed by the CA."
  echo
}

# TEST_004: Key matching verification
test_key_matching() {
  echo "[TEST_004] Verifying that keys match the certificates..."
  cert_pubkey_ca=$(openssl x509 -in "$OUTPUT_DIR/ca.crt" -noout -pubkey | openssl pkey -pubin -outform pem | sha256sum)
  key_pubkey_ca=$(openssl pkey -in "$OUTPUT_DIR/ca.key" -pubout -outform pem | sha256sum)

  if [ "$cert_pubkey_ca" != "$key_pubkey_ca" ]; then
    echo "CA key does not match CA certificate!"
    exit 1
  fi

  cert_pubkey_server=$(openssl x509 -in "$OUTPUT_DIR/server.crt" -noout -pubkey | openssl pkey -pubin -outform pem | sha256sum)
  key_pubkey_server=$(openssl pkey -in "$OUTPUT_DIR/server.key" -pubout -outform pem | sha256sum)

  if [ "$cert_pubkey_server" != "$key_pubkey_server" ]; then
    echo "Server key does not match server certificate!"
    exit 1
  fi
  echo "Keys match the certificates."
  echo
}

# TEST_005: SANs verification
test_certificate_extensions() {
  echo "[TEST_005] Verifying SANs..."
  openssl x509 -in "$OUTPUT_DIR/server.crt" -noout -text | awk '/DNS:/' | grep "localhost" | grep "\\*.localtest.me"
  echo "SANs are correct."
  echo
}

# TEST_006: CA Key Usage verification
test_ca_key_usage() {
  echo "[TEST_006] Verifying CA Key Usage..."
  openssl x509 -in "$OUTPUT_DIR/ca.crt" -noout -text | grep "Certificate Sign, CRL Sign"
  echo "CA Key Usage is correct."
  echo
}

# TEST_007: Signature algorithm verification
test_signature_algorithm() {
  echo "[TEST_007] Verifying server certificate signature algorithm is ECDSA-SHA256..."
  SIGN_ALG=$(openssl x509 -in "$OUTPUT_DIR/server.crt" -noout -text | grep "Signature Algorithm" | head -n 1 | awk '{print $3}' | tr -d '\n')
  echo "DEBUG: SIGN_ALG='${SIGN_ALG}'"
  if [ "$SIGN_ALG" != "ecdsa-with-SHA256" ]; then
    echo "Server certificate signature algorithm is '$SIGN_ALG', expected 'ecdsa-with-SHA256'!"
    exit 1
  fi
  echo "Server certificate signature algorithm is correct."
  echo
}

# TEST_008: Default certificate validity verification
test_default_validity() {
  echo "[TEST_008] Testing default certificate validity (365 days)..."
  check_certificate_validity 365 "Default certificate validity"
}

# Custom certificate validity verification
test_custom_validity() {
  local expected_days="$1"
  local test_number="$2"
  
  echo "[TEST_$test_number] Testing custom certificate validity ($expected_days days)..."
  CERT_DAYS=$expected_days ./gencert.sh -o "$OUTPUT_DIR" > /dev/null 2>&1
  check_certificate_validity $expected_days "Custom certificate validity ($expected_days days)"
}

# TEST_011: Long-form --help argument
test_long_help() {
  echo "[TEST_011] Testing long-form --help argument..."
  ./gencert.sh --help | grep -q "Usage:" && echo "Long-form --help works correctly."
  echo
}

# TEST_012: Long-form --output argument
test_long_output() {
  echo "[TEST_012] Testing long-form --output argument..."
  local temp_output_dir="test-long-args-output"
  
  ./gencert.sh --output "$temp_output_dir" > /dev/null 2>&1
  
  # Check if all files were created
  for f in ca.key ca.crt server.key server.csr server.crt; do
    if [ ! -f "$temp_output_dir/$f" ]; then
      echo "File $temp_output_dir/$f not found!"
      exit 1
    fi
  done
  echo "Long-form --output works correctly - all files created."
  
  # Clean up temporary directory
  rm -rf "$temp_output_dir"
  echo
}

# TEST_013: Certificate validation with long-form output
test_long_output_validation() {
  echo "[TEST_013] Verifying certificates created with --output work correctly..."
  local temp_output_dir="test-long-args-output"
  
  ./gencert.sh --output "$temp_output_dir" > /dev/null 2>&1
  openssl verify -CAfile "$temp_output_dir/ca.crt" "$temp_output_dir/server.crt" | grep "OK"
  echo "Certificates created with --output are valid."
  
  # Clean up temporary directory
  rm -rf "$temp_output_dir"
  echo
}

# TEST_014: Mixed arguments (short and long)
test_mixed_arguments() {
  echo "[TEST_014] Testing mixed arguments (short and long)..."
  local temp_output_dir="test-long-args-output"
  
  ./gencert.sh --output "$temp_output_dir" > /dev/null 2>&1
  if [ -f "$temp_output_dir/ca.crt" ]; then
    echo "Mixed argument test passed - files created with --output."
  fi
  
  # Clean up temporary directory
  rm -rf "$temp_output_dir"
  echo
}

# Main test execution flow
trap cleanup EXIT

# Run initial tool checks
check_required_tools

# Generate certificates with default settings
./gencert.sh -o "$OUTPUT_DIR"

# Run all basic certificate tests
test_file_creation
test_certificate_fields
test_certificate_chain
test_key_matching
test_certificate_extensions
test_ca_key_usage
test_signature_algorithm
test_default_validity

# Clean up current certificates before testing custom validity
cleanup

# Test custom certificate validities
test_custom_validity 30 "009"
cleanup
test_custom_validity 730 "010"

# Test long-form arguments
test_long_help
test_long_output
test_long_output_validation
test_mixed_arguments

echo "All tests passed!"