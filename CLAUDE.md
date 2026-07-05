# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Production / manual-QA **deployment stack** for the SIEM Source Onboarding Tracker, organized as several independent **labs** — mirroring the app repo's `containers/` directory (`containers/default`, `containers/mariadb-multimaster`, `containers/mariadb-galera`) — but with every service in every lab a **pulled registry image**, never built from source: the app always runs the published public image `ngmaibulat/usiem-tracker:latest` (versioned `vX.Y.Z` / timestamp tags exist for rollback), and every dependency (MariaDB, Postgres, Redis, MailHog, Squid, MaxScale, Meilisearch) is a stock upstream image. There is no application code, no package manager, no test suite.

Each lab is a **fully self-contained Compose project** in its own subdirectory — own `docker-compose.yml`, own `example.env`, own README, own DB config/init files, own compose project name and host ports, so they don't collide if run side-by-side. `cd` into a lab before running any `docker compose` command; there is no root-level compose file.

| Lab | Mirrors | Topology | Ports |
|---|---|---|---|
| [`default/`](default/README.md) | `containers/default` | nginx (TLS) → app → MariaDB master+2 slaves (domain) + Postgres (control) + Redis + MailHog + Squid | 80, 443, 8025 |
| [`mariadb-multimaster/`](mariadb-multimaster/README.md) | `containers/mariadb-multimaster` | app → 2-node circular MariaDB replication (binlog/GTID) + Postgres (restore-helper only) | 3004, 3336-3337, 5443, 8029 |
| [`mariadb-galera/`](mariadb-galera/README.md) | `containers/mariadb-galera` | app → MaxScale → 3-node Galera cluster + Postgres (restore-helper only) | 3005, 3346-3348, 14006, 18989, 5445, 8030 |

`default/` is the only prod-shaped lab (nginx/TLS/squid, control plane pinned to a separate Postgres). The other two are DB-topology-focused QA/exploration labs (no nginx/squid/TLS, app reachable directly on its own port, control plane derives from the same MariaDB backend) — see each lab's own README for full detail, architecture notes, and gotchas specific to it.

**This repo is public.** Each lab's `.env` (and `default/nginx/certs/*.pem`) are gitignored secrets; docs use placeholders (`<prod-host>`, `<prod-user>`). Never commit real hostnames, credentials, or certs.

## Commands

Every lab follows the same three-command pattern, run from inside the lab's own directory:

```bash
cd <lab>                           # default | mariadb-multimaster | mariadb-galera
cp example.env .env
docker compose pull                # fetch the published image
docker compose run --rm migrate    # one-shot Prisma migrations, idempotent (profile keeps it out of `up`)
docker compose up -d               # bring the stack up
```

The same three commands are both first deploy and update procedure. On schema changes, always `migrate` **before** `up -d`. See each lab's README for lab-specific verify/bring-up notes (e.g. `mariadb-galera` needs `mkdir -p data/mariadb-logs data/maxscale-logs` first, and its `migrate` may need a retry if run before the cluster settles).

Never run on a lab you care about: `docker compose down -v`, `docker volume rm <project>_*_data`, `docker system prune --volumes` — these destroy the database.

## Shared gotchas (apply to every lab)

- **Rollback** = re-point `latest` at a previous tag in the registry (`docker buildx imagetools create -t ...:latest ...:<tag>`), then pull + up in the affected lab. Rolling back the image does not roll back migrations.
- **MariaDB passwords are set-once.** Every lab parameterizes MariaDB/Postgres passwords via `.env`, but the official images only honor them on a *fresh* data volume — changing a password in `.env` later has no effect on an already-initialized volume.
- **Provider is a wizard choice, not an env mode.** Every lab sets `DB_MARIADB_URL` (and `default` also sets `DB_POSTGRES_URL`) — the only two DB-connection env vars the app reads (see the app repo's CLAUDE.md, Environment section). Neither decides which plane uses which provider at runtime; that's a one-time choice made in the Initial Configuration Wizard and stored in the connection registry. `DB_PROVIDER`/`CONTROL_DB_PROVIDER` on the `app`/`migrate` services only pick the Prisma CLI's own pre-migration target per plane (the CLI can't read the registry, so it needs an explicit flag where the old `mysql://` URL-sniffing used to suffice).

## Legacy scripted deploy (`scripts/`)

Repo-root `scripts/` — kept but superseded by the plain compose workflow above, and specific to the `default` lab (the only prod-shaped one) even though the scripts live at the repo root rather than under `default/`. `scripts/DEPLOY.md` (in Russian) documents it fully: `deploy-prod.ps1` builds/pushes from a Windows dev machine (app repo checkout expected next to this **deploy** repo, override with `-AppRepo`; the script derives that sibling path from its own location, so it must stay at `scripts/` off the repo root) and SSHes to run `deploy_app.sh` on prod at `/opt/siem-source-tracker/` (backup → pull → migrate → up). The `[image_tag]` argument to `deploy_app.sh` is a label for the backup filename only — the stack always runs `latest`. `generate-self-signed.sh` writes `privkey.pem`/`fullchain.pem` into `default/nginx/certs/` for manual (non-wizard) setups.

Note: `DEPLOY.md` predates the multi-lab split and in places still describes `docker-compose.yml`/`nginx/` as sitting at the repo root — they're under `default/` now. The `scripts/` location and invocation examples in it are correct as-is; the prose describing what gets copied to prod is the stale part.
