FROM code.forgejo.org/forgejo/runner:9.1.1
# https://code.forgejo.org/forgejo/runner/src/branch/main/Dockerfile

USER root
RUN apk add --no-cache ca-certificates
RUN mkdir -p /usr/local/share/ca-certificates/
# Add the self-signed CA certificate to the runner image.
# This is required for the runner to register with a remote Forgejo service over TLS.
# Without this CA certificate, registration will fail due to certificate validation errors.
# The forgejo-runner does not support disabling TLS certificate validation during registration.
COPY my-ca.crt /usr/local/share/ca-certificates/my-ca.crt
RUN update-ca-certificates

# USER 1000:1000