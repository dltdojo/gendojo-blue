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

# Clean up the generated files
echo "All tests passed!"