#!/bin/bash

set -e

# Check for required tools
echo "Checking for required tools..."
for tool in openssl; do
  if ! command -v "$tool" &> /dev/null; then
    echo "Error: $tool is not installed. Please install it and try again." >&2
    exit 1
  fi
done
echo "All required tools are available."
echo

# Configure certificate validity period (default: 365 days)
CERT_DAYS=${CERT_DAYS:-365}
echo "Certificate validity period: $CERT_DAYS days"
echo

# Create a config file for the CA certificate
cat > ca.cnf <<EOF
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_ca
prompt = no

[req_distinguished_name]
CN = My CA

[v3_ca]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical,CA:true
keyUsage = critical,digitalSignature,cRLSign,keyCertSign
EOF

# CA
openssl ecparam -name prime256v1 -genkey -noout -out ca.key
openssl req -x509 -new -nodes -key ca.key -out ca.crt -days "$CERT_DAYS" -extensions v3_ca -config ca.cnf

# Server
openssl ecparam -name prime256v1 -genkey -noout -out server.key

# Create a config file for the server certificate
cat > server.cnf <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = localhost

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = localhost
DNS.2 = *.localtest.me
DNS.3 = *.nip.io
DNS.4 = *.xip.io
EOF

openssl req -new -key server.key -out server.csr -config server.cnf

echo 1000 > ca.srl
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAserial ca.srl -out server.crt -days "$CERT_DAYS" -sha256 -extensions v3_req -extfile server.cnf

rm ca.cnf server.cnf ca.srl
