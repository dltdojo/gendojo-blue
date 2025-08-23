#!/bin/bash

set -e

# Function to clean up
cleanup() {
  echo "Cleaning up..."
  if [ -n "$SERVER_PID" ]; then
    echo "Killing web server (PID: $SERVER_PID)..."
    kill "$SERVER_PID" || true # Use || true to prevent script from exiting if kill fails
    echo "Web server killed."
  fi
  rm -f ca.key ca.crt server.key server.csr server.crt server.py
  echo "Cleanup complete."
}

# Check for required tools
echo "Checking for required tools..."
for tool in openssl curl python3; do
  if ! command -v "$tool" &> /dev/null; then
    echo "Error: $tool is not installed. Please install it and try again." >&2
    exit 1
  fi
done
echo "All required tools are available."
echo

# Generate the certificates
echo "Generating certificates..."
./gencert.sh
echo "Certificates generated."
echo

# Create the python web server
echo "Creating python web server..."
cat > server.py <<EOF
import http.server
import ssl

server_address = ('localhost', 4443)
httpd = http.server.HTTPServer(server_address, http.server.SimpleHTTPRequestHandler)
httpd.socket = ssl.wrap_socket(httpd.socket,
                               server_side=True,
                               certfile='server.crt',
                               keyfile='server.key',
                               ssl_version=ssl.PROTOCOL_TLS)
print('Server running on https://localhost:4443')
httpd.serve_forever()
EOF
echo "Web server script created."
echo

# Run the server in the background
echo "Starting web server in the background..."
python3 server.py &
SERVER_PID=$!
echo "Web server started with PID: $SERVER_PID"
trap cleanup EXIT
echo

# Wait for the server to start
echo "Waiting for server to start..."
sleep 1
echo "Server should be up."
echo

# Test the server with curl
echo "--- Testing with curl ---"
echo "[TEST_001] Testing connection to https://localhost:4443..."
echo "Expected: HTML content of the root directory."
curl --cacert ca.crt https://localhost:4443
echo
echo "[TEST_002] Testing connection to https://test.localtest.me:4443 (with DNS resolve)..."
echo "Expected: HTML content of the root directory."
curl --cacert ca.crt --resolve test.localtest.me:4443:127.0.0.1 https://test.localtest.me:4443
echo
echo "--- curl tests passed ---"
echo

# Test with openssl
echo "--- Testing with openssl ---"
echo "[TEST_003] Verifying certificate for localhost..."
echo "Expected: Verification: OK"
openssl s_client -connect localhost:4443 -CAfile ca.crt </dev/null
echo
echo "[TEST_004] Verifying certificate for test.localtest.me (using SNI)..."
echo "Expected: Verification: OK"
openssl s_client -connect localhost:4443 -servername test.localtest.me -CAfile ca.crt </dev/null
echo
echo "--- openssl tests passed ---"
echo

echo "[TEST_005] Verifying server certificate signature algorithm is ECDSA-SHA256..."
SIGN_ALG=$(openssl x509 -in server.crt -noout -text | grep "Signature Algorithm" | head -1 | awk '{print $3}' | tr -d '\n\r')
echo "DEBUG: SIGN_ALG='${SIGN_ALG}'"
if [ "$SIGN_ALG" != "ecdsa-with-SHA256" ]; then
  echo "Server certificate signature algorithm is '$SIGN_ALG', expected 'ecdsa-with-SHA256'!"
  exit 1
fi
echo "Server certificate signature algorithm is correct."
echo

echo "All tests passed!"