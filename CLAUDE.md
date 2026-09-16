# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Docker Compose stacks for two hosts, one directory per stack, grouped by host. It's mostly infra config, not a code project. The only buildable code is the nested `cloud/terminal-portfolio/leonardom011-terminal-portfolio/`, which has its own git repo (github.com/LeonardoM011/leonardom011-terminal-portfolio) and is ignored by this one.

| Directory | Host | Stacks |
|---|---|---|
| `local/` | Laptop `arch-leonardo` | `jellyfin`, `jackett`, `flaresolverr` |
| `cloud/` | VPS `debian-lok-server` | `actual`, `borgmatic`, `obsidian`, `ofelia`, `paperless`, `prometheus`, `radicale`, `terminal-portfolio`, `vikunja` |

On the VPS there's no `cloud/` level: each stack lives at `~/<stack>/`. That placement matters because borgmatic backs up only `/home` (see Backups below). `cloud/backup.sh` is a VPS script.

## Secrets and personal data: `.gitignore` is an allowlist

Live data and secrets sit next to the compose files (paths relative to `cloud/`, except jellyfin and jackett, which are under `local/`):

- **Secrets:** `borgmatic/ssh/hetzner_borg` (private key), `borgmatic/config/borg-passphrase`, `*/.env` (paperless's holds `PAPERLESS_SECRET_KEY` and does double duty: compose interpolation and the webserver's `env_file`), `radicale/config/users`, `obsidian/couchdb-etc/` (CouchDB writes the admin hash here).
- **Personal data:** `paperless/{data,media,export,consume}` (scanned personal documents), `actual/data`, `radicale/data`, `obsidian/couchdb-data`, `vikunja/{files,backups}`, `jellyfin/{config,cache}`, `jackett/config`, `borgmatic/{cache,state,backup.log}`.

`.gitignore` ignores every top-level directory except `cloud/` and `local/`, and everything inside a stack directory unless a `!` rule re-includes it. When adding a stack under `cloud/` or `local/`, its compose file is tracked automatically. Any other config file needs its own `!` line. Never re-include a whole stack directory. Don't print the contents of secret files; read key names only if you need them.

**This repo is public.** Put identifying or secret values (passwords, account names such as the Storage Box user) in the stack's gitignored `.env`. Reference them in tracked files as `${VAR:?set VAR in .env}`, so a missing value stops `docker compose up` instead of starting with an empty value. The tailnet name `tail81798e` is already public through Tailscale's Certificate Transparency entries, so it's fine to keep.

Every gitignored env file has a committed example next to it with the same keys and placeholder values: `example.env` for each `.env`. When you add or rename a variable, update the example in the same change.

## Commands

Run compose from inside the stack directory (`cloud/<stack>` or `local/<stack>`). `./` bind mounts and `.env` interpolation resolve relative to it, and the directory name becomes the compose project name.

```sh
docker compose config -q                        # validate (the "lint" for this repo)
docker compose pull && docker compose up -d     # update / apply changes
docker compose logs -f <service>
```

- `local/flaresolverr/` uses `docker-compose.yaml`. Compose picks it up automatically.
- Prometheus has `--web.enable-lifecycle`, so after editing `prometheus.yml` run `curl -X POST http://127.0.0.1:9090/-/reload` on the VPS. No restart is needed.
- `cloud/backup.sh` (VPS) runs the same two dumps as the nightly ofelia jobs (paperless `document_exporter`, vikunja `pg-dump.sh`), then `borgmatic create --stats`. It uses `set -e`, so if either dump fails, the borg run is skipped.

### terminal-portfolio (Angular 22, Tailwind 4, Vitest)

From `cloud/terminal-portfolio/leonardom011-terminal-portfolio/` (no `node_modules` yet, so `npm ci` first):

```sh
npm start                                   # ng serve on :4200
npm run build                               # -> dist/leonardom011-terminal-portfolio/browser
npm test                                    # Vitest via @angular/build:unit-test
npx ng test --include src/app/app.spec.ts   # single spec
```

Prettier settings: `printWidth: 100`, single quotes.

The whole site is one `Terminal` component (`src/app/terminal/`):
- `commands.ts` holds a `runCommand` switch that returns `TerminalLine[]`.
- `lang` is intercepted in `terminal.ts` before it reaches `runCommand`.
- All user-facing text lives in `i18n.ts` as `TRANSLATIONS: Record<'en'|'hr', Translations>`, with `hr` as the default. A new command needs a translation key in both languages plus an entry in `getCommandDescriptions` so it shows up in `help`.

Deploy: the compose file uses `image: leonardom011-terminal-portfolio` with `pull_policy: never`, so the image must be built on the VPS itself:
`docker build -t leonardom011-terminal-portfolio ./leonardom011-terminal-portfolio && docker compose up -d`.
The container serves on `127.0.0.1:4200`, and host nginx proxies `leonardom011.com` to it. The image has a `/healthz` endpoint.

## Cross-stack wiring (change both sides together)

- **Exposure convention:** every published port binds `127.0.0.1`. On the VPS, services are reached through `tailscale serve` (MagicDNS name only, e.g. `https://debian-lok-server.tail81798e.ts.net:8000`) or through host nginx. There are two exceptions:
  - `jellyfin` also binds `${LAN_IP}:8096`. `LAN_IP` (the laptop's static LAN IP) is defined only in `local/.env`. Compose reads `.env` only from the stack's own directory, so each local stack that needs it has a `.env -> ../.env` symlink. Both are gitignored. Keep the `${LAN_IP:?...}` form on port bindings: an empty value would publish on every interface.
  - VPS `node-exporter` is `network_mode: host`, so it listens on `*:9100`.

  Docker-published ports bypass ufw (they go through Docker's FORWARD-chain rules), so for jellyfin the host-IP binding is the real access control. Call out any new non-loopback binding as widening exposure.
- **Prometheus to node-exporter:** Prometheus scrapes `172.30.0.1:9100`. That address is the gateway of the `monitoring` network's pinned subnet `172.30.0.0/24` in `cloud/prometheus/docker-compose.yml`. If you change the subnet, change `prometheus.yml` too. cAdvisor and docker-state-exporter are scraped by service name over that network.
- **Timezone:** defined once per host.
  - Laptop stacks interpolate `${TZ:?...}` from `local/.env`, through the same `.env -> ../.env` symlinks as `LAN_IP`.
  - Cloud stacks load `env_file: ../common.env`. It's tracked as `cloud/common.env`; on the VPS it's `~/common.env`. It also sets `VIKUNJA_SERVICE_TIMEZONE`. If it's missing, `docker compose up` fails, so it has to be on the VPS before any compose file that references it. It's public, so never put secrets in it.
  - Paperless is the exception: `PAPERLESS_TIME_ZONE` in its own `.env`.
- **`torrent-network`:** an external network that jackett and flaresolverr both join. It must already exist (`docker network create torrent-network`). Jackett reaches FlareSolverr at `http://flaresolverr:8191`.
- **Container names other files depend on:** renaming either of these silently breaks the nightly dumps.
  - `paperless-webserver-1` comes from `COMPOSE_PROJECT_NAME` in `cloud/paperless/.env`. It's used by `cloud/backup.sh` and `cloud/ofelia/config.ini`.
  - `vikunja-db` is a fixed `container_name`. It's used by `cloud/backup.sh` and `cloud/ofelia/config.ini`.

### Backups

- borgmatic mounts `/home:ro` and backs up to a Hetzner Storage Box. The Storage Box user is `STORAGEBOX_USER` in `cloud/borgmatic/.env`. Compose passes it into the container, and borgmatic expands `${STORAGEBOX_USER}` in `config.yaml`. Cron jobs see it too: the image starts `crond` with the container environment. Schedule: `cloud/borgmatic/config/crontab.txt`. `BACKUP_CRON` in the compose file is commented out. Retention and checks: `cloud/borgmatic/config/config.yaml`.
- Bind-mounted data under `~/<stack>/` is covered. **Named volumes are not:** `pgdata`/`redisdata` (paperless), `prometheus_data`, `vikunja-pgdata`. Two dumps stand in for the databases that matter:
  - paperless: `document_exporter`, writing to `paperless/export/`
  - vikunja: `vikunja/backup/pg-dump.sh`, writing to `vikunja/backups/` (keeps the newest 7). It must run as `1000:1000`, which owns `~/vikunja/backups` on the VPS. As `postgres` (uid 999) the write fails with `Permission denied`; that's why no dumps existed before 2026-09-14.

  Both run from the single shared ofelia in `cloud/ofelia/`, using 6-field cron with seconds (`0 30 1 * * *`, 01:30 Europe/Zagreb).
- **Ofelia jobs live in `cloud/ofelia/config.ini`, not in container labels.** Ofelia runs without `--docker`, so any `ofelia.*` labels on containers are ignored. The reason (tested with `0.3.21` and `:latest`): label discovery exits when no labelled container exists yet, and it doesn't register containers that start later. A boot could therefore silently lose a job.

  Static `[job-exec]` sections register at startup and look up `container = <name>` on every run. While the container is missing, runs fail with `No such container` and are logged; a recreated container is picked up automatically. To add a job, add a section to `config.ini`, then `docker compose restart` in `cloud/ofelia`. Ofelia doesn't watch the file.
- `cloud/borgmatic/backup.log` is stale. It shows a failing before-hook (`cd ~/paperless && ...`) that no longer exists in `config.yaml`.

## Notes

- **Every container has a healthcheck.** Some ship one in the image and are not repeated in the compose file: `jellyfin`, `radicale`, `actual`, `audiobookshelf`, paperless `webserver`, `cadvisor`, `terminal-portfolio`. Check with `docker inspect -f '{{json .Config.Healthcheck}}' <container>` before writing one. A new stack needs one too — prefer the app's own endpoint or CLI. Three images constrain how it's written: `vikunja` has no shell (exec-form `CMD` with `/app/vikunja/vikunja healthcheck`), `tika` has neither curl nor wget (bash `/dev/tcp`), and CouchDB wants credentials even on `/_up` (`$$VAR` so compose leaves the expansion to the container's shell).
- `jellyfin` uses `runtime: nvidia` for NVENC, so the NVIDIA container toolkit has to be present on the laptop.
- `radicale` (tomsquest image) runs as uid/gid 2999, and `./config` is mounted `:ro`, so the entrypoint doesn't chown it. On the VPS, `~/radicale/config/` and both files in it must be group `2999` (dir `0750`, files `0640`). The laptop copies are `1000:1000`, so copying them over with ownership preserved (`rsync -a`, `cp -a`) crashloops the container with `Permission denied: '/config/config'`. Fix: `sudo chgrp 2999 ~/radicale/config/{config,users}`.
