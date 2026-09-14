# docker-compose-files

Docker Compose stacks for my self-hosted services, split by host:

- `local/`: my laptop (Arch Linux, NVIDIA GPU)
- `cloud/`: a Debian VPS, reached over Tailscale

Each stack is one directory holding its compose file. Data, secrets and `.env` files live next to the compose files on the hosts but are gitignored. Only configuration is committed.

## Stacks

| Stack | What it runs |
|---|---|
| `local/jellyfin` | Jellyfin media server with NVENC hardware transcoding |
| `local/jackett` | Jackett torrent indexer proxy |
| `local/flaresolverr` | FlareSolverr, which solves Cloudflare challenges for Jackett |
| `cloud/actual` | Actual Budget |
| `cloud/borgmatic` | borgmatic: encrypted Borg backups of `/home` to a Hetzner Storage Box |
| `cloud/obsidian` | CouchDB for Obsidian LiveSync |
| `cloud/ofelia` | Ofelia, which schedules the nightly database dumps |
| `cloud/paperless` | Paperless-ngx with PostgreSQL, Redis, Gotenberg and Tika |
| `cloud/prometheus` | Prometheus with node-exporter, cAdvisor and docker-state-exporter |
| `cloud/radicale` | Radicale CalDAV/CardDAV server |
| `cloud/terminal-portfolio` | My personal site, a terminal-style Angular app ([source](https://github.com/LeonardoM011/leonardom011-terminal-portfolio)) |
| `cloud/vikunja` | Vikunja task manager with PostgreSQL |

## Exposure

- Every published port binds to `127.0.0.1`, so by default nothing listens on a public interface.
- On the VPS, services are reached through `tailscale serve` (HTTPS inside the tailnet) or through the host's nginx reverse proxy (for the public site).
- There are two exceptions:
  - Jellyfin also binds the laptop's LAN IP (`LAN_IP`), so devices on the home network can stream. Docker-published ports bypass ufw, so that bind address is what limits access.
  - node-exporter uses host networking to see the host's metrics. Keep port 9100 closed at the firewall.

## Setup

You need Docker with the Compose plugin.

1. Create each stack's env files from the committed examples and fill in the placeholders:

   ```sh
   cp cloud/vikunja/example.env cloud/vikunja/.env
   cp cloud/paperless/example.env cloud/paperless/.env
   cp cloud/paperless/docker-compose.example.env cloud/paperless/docker-compose.env
   # ...and the same for cloud/borgmatic and cloud/obsidian
   ```

   The laptop stacks share one file. Compose only reads `.env` from a stack's own directory, so each stack gets a symlink to it:

   ```sh
   cp local/example.env local/.env
   for s in jellyfin jackett flaresolverr; do ln -s ../.env "local/$s/.env"; done
   ```

2. Some stacks need a little more:
   - **borgmatic**: the repository passphrase in `config/borg-passphrase` and the SSH key in `ssh/hetzner_borg`.
   - **radicale**: an htpasswd file at `config/users` with bcrypt hashes, for example `htpasswd -B -c config/users <user>`. The committed `config/config` already points at it. The container runs as uid 2999, so it must be able to read both files: `chgrp -R 2999 config && chmod 750 config && chmod 640 config/*`.
   - **jackett, flaresolverr**: the shared network, created with `docker network create torrent-network`.
   - **jellyfin**: the NVIDIA Container Toolkit.
   - **terminal-portfolio**: a locally built image. Clone the source repo into `cloud/terminal-portfolio/`, then run `docker build -t leonardom011-terminal-portfolio ./leonardom011-terminal-portfolio`.

3. Start a stack from its directory with `docker compose up -d`.

Required variables are written as `${VAR:?...}`. If one is missing, compose refuses to start and names it, rather than running with an empty value.

### VPS layout

On the VPS, stacks live directly in the home directory (`~/paperless`, `~/vikunja`, and so on) rather than under `cloud/`. The cloud stacks load shared settings, currently the timezone, from `../common.env`, so `cloud/common.env` goes to `~/common.env`.

## Backups

- borgmatic backs up `/home` to an encrypted Borg repository on a Hetzner Storage Box. It runs on the schedule in `cloud/borgmatic/config/crontab.txt` and keeps 7 daily, 4 weekly and 6 monthly archives.
- Bind-mounted data under `~/<stack>/` is included in that backup. Docker named volumes, which hold the PostgreSQL databases, are not. To cover them, Ofelia runs a dump every night at 01:30 into a directory that does get backed up:
  - Paperless: `document_exporter` writes to `paperless/export/`.
  - Vikunja: `pg-dump.sh` writes to `vikunja/backups/` and keeps the last 7 dumps.
- `cloud/backup.sh` runs both dumps and a borgmatic backup on demand.

## Working on this repo

- Validate a stack after editing it: `docker compose config -q`.
- `.gitignore` is an allowlist. Inside a stack directory, only compose files and the example env files are tracked. To commit another config file, add a `!` rule for it.
- Secrets belong in the stack's gitignored `.env`. When you add a variable, add it to the matching example file too.
