# Forgejo (local service)

This folder contains a small wrapper script and a Docker Compose setup to run a local Forgejo instance for development or testing.

Prerequisites
- Docker (and Docker Compose plugin) installed and available in PATH.

Files
- `forgejo.sh` — helper script to initialize PKI and start the service.
- `compose.yaml` — Docker Compose service definition.
- `forgejo-data/` — persistent data volume mounted into the container.

Quick usage

1. Initialize PKI (creates `pki/` and a CA certificate):

   ./forgejo.sh -i

2. Start Forgejo with Docker Compose (runs `docker compose up -d` from the service directory):

   ./forgejo.sh -s

3. If you run the script with no arguments it prints the help:

   ./forgejo.sh

Access the web UI
- After the service is started, open your browser at: https://forgejo.localtest.me
- On first run you will be prompted by Forgejo to create the initial admin account and configure the instance.

Useful commands
- Follow logs:

  cd "$(dirname "$0")" && docker compose logs -f

- Stop the service:

  cd "$(dirname "$0")" && docker compose down

Data and persistence
- Repository data, DB and uploaded files are stored in the `forgejo-data/` directory in this service folder. Back this directory up if you need to preserve data.

Notes
- If Docker is not found the script will print an error asking you to install Docker.
- The compose file maps port `3000` on the host to `3000` in the container.

Troubleshooting
- If the browser cannot connect, ensure Docker is running and that the container is healthy:

  docker ps
  docker compose ps

- Check container logs for errors (see "Follow logs" above).

License
- This README inherits the repository license (see top-level `LICENSE`).
