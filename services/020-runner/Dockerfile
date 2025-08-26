FROM code.forgejo.org/forgejo/runner:9.1.1
# https://code.forgejo.org/forgejo/runner/src/branch/main/Dockerfile

USER root
RUN apk add --no-cache ca-certificates
RUN mkdir -p /usr/local/share/ca-certificates/
COPY my-ca.crt /usr/local/share/ca-certificates/my-ca.crt
RUN update-ca-certificates

# USER 1000:1000