#!/bin/bash


set -e

# Parse arguments
OUTPUT_DIR="."

show_help() {
  echo "Usage: $0 [-o|--output output_dir] [-h|--help]"
  echo "  -o, --output output_dir   Specify output directory (default: .)"
  echo "  -h, --help                Show this help message"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    -o|--output)
      if [ "$#" -lt 2 ]; then
        echo "Error: --output requires an argument" >&2
        show_help >&2
        exit 1
      fi
      OUTPUT_DIR="$2"
      shift 2
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      show_help >&2
      exit 1
      ;;
  esac
done

# Ensure output directory exists
mkdir -p "$OUTPUT_DIR"

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

cat > "$OUTPUT_DIR/ca.cnf" <<EOF
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

openssl ecparam -name prime256v1 -genkey -noout -out "$OUTPUT_DIR/ca.key"
openssl req -x509 -new -nodes -key "$OUTPUT_DIR/ca.key" -out "$OUTPUT_DIR/ca.crt" -days "$CERT_DAYS" -extensions v3_ca -config "$OUTPUT_DIR/ca.cnf"

openssl ecparam -name prime256v1 -genkey -noout -out "$OUTPUT_DIR/server.key"

cat > "$OUTPUT_DIR/server.cnf" <<EOF
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

openssl req -new -key "$OUTPUT_DIR/server.key" -out "$OUTPUT_DIR/server.csr" -config "$OUTPUT_DIR/server.cnf"

echo 1000 > "$OUTPUT_DIR/ca.srl"
openssl x509 -req -in "$OUTPUT_DIR/server.csr" -CA "$OUTPUT_DIR/ca.crt" -CAkey "$OUTPUT_DIR/ca.key" -CAserial "$OUTPUT_DIR/ca.srl" -out "$OUTPUT_DIR/server.crt" -days "$CERT_DAYS" -sha256 -extensions v3_req -extfile "$OUTPUT_DIR/server.cnf"

rm "$OUTPUT_DIR/ca.cnf" "$OUTPUT_DIR/server.cnf" "$OUTPUT_DIR/ca.srl"
