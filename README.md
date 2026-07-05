# siem-tracker-deploy

Production / manual-QA deployment stack for **SIEM Source Onboarding Tracker** (app source lives in the separate `siem-tracker` repo). Organized as several independent **labs**, mirroring the app repo's `containers/` directory — each self-contained, running the published Docker image `ngmaibulat/usiem-tracker:latest` plus stock upstream images for every dependency. Nothing is built anywhere in this repo.

## Labs

| Lab | Mirrors (app repo) | Topology | App URL |
|---|---|---|---|
| [`default/`](default/README.md) | `containers/default` | nginx (TLS) → app → MariaDB master+2 slaves (domain) + Postgres (control) + Redis + MailHog + Squid | https://localhost |
| [`mariadb-multimaster/`](mariadb-multimaster/README.md) | `containers/mariadb-multimaster` | app → 2-node circular MariaDB replication (binlog/GTID) | http://localhost:3004 |
| [`mariadb-galera/`](mariadb-galera/README.md) | `containers/mariadb-galera` | app → MaxScale → 3-node Galera cluster | http://localhost:3005 |

`default/` is the prod-shaped lab — the only one with nginx/TLS/squid, and the one to use for an actual deployment. `mariadb-multimaster/` and `mariadb-galera/` are DB-topology-focused QA/exploration labs (no nginx/squid/TLS, app reachable directly on its own port) — bring them up to poke at a specific replication/clustering behavior without touching your `default/` deployment. Each lab has its own ports, own volumes, own `.env`, and can run independently or side-by-side with the others.

## Deploy a lab

From inside the lab's own directory (there is no root-level compose file):

```bash
cd default   # or mariadb-multimaster / mariadb-galera
cp example.env .env
chmod 600 .env               # it holds secrets — keep it owner-readable only

docker compose pull                # fetch the published image
docker compose run --rm migrate    # apply DB migrations (idempotent)
docker compose up -d               # bring the stack up
```

Then open the lab's App URL and follow the initial configuration wizard. The same three commands are also the update procedure. See each lab's own README for lab-specific notes (verify commands, recovery procedures, port tables).

## Legacy scripted deploy (`scripts/`)

A previous workflow — build + push the image from a dev machine, then deploy over SSH — still works, is specific to the `default` lab, and is documented in [`scripts/DEPLOY.md`](scripts/DEPLOY.md). Superseded by the plain `docker compose pull && run --rm migrate && up -d` workflow above; kept for now.

## Secrets

This repo is public. Each lab's `.env` (and `default/nginx/certs/*.pem`) are **gitignored** — real values live only on the machines that need them. Docs use placeholders (`<prod-host>`, `<prod-user>`) for the same reason.
