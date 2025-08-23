#!/bin/bash

set -e

# Function to clean up
cleanup() {
  echo "Cleaning up generated files..."
  rm -f ca.key ca.crt server.key server.csr server.crt
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

# Run the script to generate the certs
./gencert.sh
trap cleanup EXIT

# --- Test File Creation ---
echo "[TEST_001] Checking if all certificate and key files were created..."
for f in ca.key ca.crt server.key server.csr server.crt; do
  if [ ! -f "$f" ]; then
    echo "File $f not found!"
    exit 1
  fi
done
echo "All files created successfully."
echo

# --- Test Certificate Fields ---
echo "[TEST_002] Verifying certificate subjects and issuers..."
openssl x509 -in ca.crt -noout -subject | grep "CN = My CA"
openssl x509 -in server.crt -noout -subject | grep "CN = localhost"
openssl x509 -in server.crt -noout -issuer | grep "CN = My CA"
echo "Certificate subjects and issuers are correct."
echo

# --- Test Certificate Chain ---
echo "[TEST_003] Verifying the server certificate with the CA..."
openssl verify -CAfile ca.crt server.crt | grep "OK"
echo "Server certificate is signed by the CA."
echo

# --- Test Key Matching ---
echo "[TEST_004] Verifying that keys match the certificates..."
cert_pubkey_ca=$(openssl x509 -in ca.crt -noout -pubkey | openssl pkey -pubin -outform pem | sha256sum)
key_pubkey_ca=$(openssl pkey -in ca.key -pubout -outform pem | sha256sum)

if [ "$cert_pubkey_ca" != "$key_pubkey_ca" ]; then
  echo "CA key does not match CA certificate!"
  exit 1
fi

cert_pubkey_server=$(openssl x509 -in server.crt -noout -pubkey | openssl pkey -pubin -outform pem | sha256sum)
key_pubkey_server=$(openssl pkey -in server.key -pubout -outform pem | sha256sum)

if [ "$cert_pubkey_server" != "$key_pubkey_server" ]; then
  echo "Server key does not match server certificate!"
  exit 1
fi
echo "Keys match the certificates."
echo

# --- Test Certificate Extensions ---
echo "[TEST_005] Verifying SANs..."
openssl x509 -in server.crt -noout -text | awk '/DNS:/' | grep "localhost" | grep "\\*.localtest.me"
echo "SANs are correct."
echo


echo "[TEST_006] Verifying CA Key Usage..."
openssl x509 -in ca.crt -noout -text | grep "Certificate Sign, CRL Sign"
echo "CA Key Usage is correct."
echo

echo "[TEST_007] Verifying server certificate signature algorithm is ECDSA-SHA256..."
SIGN_ALG=$(openssl x509 -in server.crt -noout -text | grep "Signature Algorithm" | head -n 1 | awk '{print $3}' | tr -d '\n')
echo "DEBUG: SIGN_ALG='${SIGN_ALG}'"
if [ "$SIGN_ALG" != "ecdsa-with-SHA256" ]; then
  echo "Server certificate signature algorithm is '$SIGN_ALG', expected 'ecdsa-with-SHA256'!"
  exit 1
fi
echo "Server certificate signature algorithm is correct."
echo

echo "[TEST_008] Testing default certificate validity (365 days)..."
# Test default behavior - certificates should be valid for 365 days
EXPECTED_DAYS=365

# Extract validity dates for CA certificate
CA_NOT_BEFORE=$(openssl x509 -in ca.crt -noout -dates | grep "notBefore" | sed 's/notBefore=//')
CA_NOT_AFTER=$(openssl x509 -in ca.crt -noout -dates | grep "notAfter" | sed 's/notAfter=//')

# Extract validity dates for server certificate  
SERVER_NOT_BEFORE=$(openssl x509 -in server.crt -noout -dates | grep "notBefore" | sed 's/notBefore=//')
SERVER_NOT_AFTER=$(openssl x509 -in server.crt -noout -dates | grep "notAfter" | sed 's/notAfter=//')

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
if [ "$CA_VALIDITY_DAYS" -lt $(( EXPECTED_DAYS - 1 )) ] || [ "$CA_VALIDITY_DAYS" -gt $(( EXPECTED_DAYS + 1 )) ]; then
  echo "CA certificate validity is $CA_VALIDITY_DAYS days, expected ~$EXPECTED_DAYS days!"
  exit 1
fi

if [ "$SERVER_VALIDITY_DAYS" -lt $(( EXPECTED_DAYS - 1 )) ] || [ "$SERVER_VALIDITY_DAYS" -gt $(( EXPECTED_DAYS + 1 )) ]; then
  echo "Server certificate validity is $SERVER_VALIDITY_DAYS days, expected ~$EXPECTED_DAYS days!"
  exit 1
fi

echo "Default certificate validity is correct."
echo

# Clean up current certificates before next test
cleanup

echo "[TEST_009] Testing custom certificate validity (30 days)..."
# Test custom CERT_DAYS value
EXPECTED_DAYS=30
CERT_DAYS=$EXPECTED_DAYS ./gencert.sh > /dev/null 2>&1

# Extract validity dates for CA certificate
CA_NOT_BEFORE=$(openssl x509 -in ca.crt -noout -dates | grep "notBefore" | sed 's/notBefore=//')
CA_NOT_AFTER=$(openssl x509 -in ca.crt -noout -dates | grep "notAfter" | sed 's/notAfter=//')

# Extract validity dates for server certificate  
SERVER_NOT_BEFORE=$(openssl x509 -in server.crt -noout -dates | grep "notBefore" | sed 's/notBefore=//')
SERVER_NOT_AFTER=$(openssl x509 -in server.crt -noout -dates | grep "notAfter" | sed 's/notAfter=//')

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
if [ "$CA_VALIDITY_DAYS" -lt $(( EXPECTED_DAYS - 1 )) ] || [ "$CA_VALIDITY_DAYS" -gt $(( EXPECTED_DAYS + 1 )) ]; then
  echo "CA certificate validity is $CA_VALIDITY_DAYS days, expected ~$EXPECTED_DAYS days!"
  exit 1
fi

if [ "$SERVER_VALIDITY_DAYS" -lt $(( EXPECTED_DAYS - 1 )) ] || [ "$SERVER_VALIDITY_DAYS" -gt $(( EXPECTED_DAYS + 1 )) ]; then
  echo "Server certificate validity is $SERVER_VALIDITY_DAYS days, expected ~$EXPECTED_DAYS days!"
  exit 1
fi

echo "Custom certificate validity (30 days) is correct."
echo

# Clean up current certificates before next test
cleanup

echo "[TEST_010] Testing custom certificate validity (730 days)..."
# Test another custom CERT_DAYS value
EXPECTED_DAYS=730
CERT_DAYS=$EXPECTED_DAYS ./gencert.sh > /dev/null 2>&1

# Extract validity dates for CA certificate
CA_NOT_BEFORE=$(openssl x509 -in ca.crt -noout -dates | grep "notBefore" | sed 's/notBefore=//')
CA_NOT_AFTER=$(openssl x509 -in ca.crt -noout -dates | grep "notAfter" | sed 's/notAfter=//')

# Extract validity dates for server certificate  
SERVER_NOT_BEFORE=$(openssl x509 -in server.crt -noout -dates | grep "notBefore" | sed 's/notBefore=//')
SERVER_NOT_AFTER=$(openssl x509 -in server.crt -noout -dates | grep "notAfter" | sed 's/notAfter=//')

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
if [ "$CA_VALIDITY_DAYS" -lt $(( EXPECTED_DAYS - 1 )) ] || [ "$CA_VALIDITY_DAYS" -gt $(( EXPECTED_DAYS + 1 )) ]; then
  echo "CA certificate validity is $CA_VALIDITY_DAYS days, expected ~$EXPECTED_DAYS days!"
  exit 1
fi

if [ "$SERVER_VALIDITY_DAYS" -lt $(( EXPECTED_DAYS - 1 )) ] || [ "$SERVER_VALIDITY_DAYS" -gt $(( EXPECTED_DAYS + 1 )) ]; then
  echo "Server certificate validity is $SERVER_VALIDITY_DAYS days, expected ~$EXPECTED_DAYS days!"
  exit 1
fi

echo "Custom certificate validity (730 days) is correct."
echo

# Clean up the generated files
echo "All tests passed!"