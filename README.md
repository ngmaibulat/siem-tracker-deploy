# siem-tracker-deploy

Production / manual-QA deployment stack for **SIEM Source Onboarding Tracker** (app source lives in the separate `siem-tracker` repo). Organized as several independent **labs**, mirroring the app repo's `containers/` directory — each self-contained, running the published Docker image `ngmaibulat/usiem-tracker:latest` plus stock upstream images for every dependency. Nothing is built anywhere in this repo.

## Labs

| Lab | Mirrors (app repo) | Topology | App URL |
|---|---|---|---|
| [`default/`](default/README.md) | `containers/default` | nginx (TLS) → app → MariaDB master+2 slaves (domain) + Postgres (control) + Redis + Squid + Meilisearch + MinIO | https://localhost |
| [`mariadb-multimaster/`](mariadb-multimaster/README.md) | `containers/mariadb-multimaster` | nginx (TLS) → app → 2-node circular MariaDB replication (binlog/GTID) + MinIO | https://localhost |
| [`mariadb-galera/`](mariadb-galera/README.md) | `containers/mariadb-galera` | nginx (TLS) → app → 3-node Galera cluster + MinIO | https://localhost |

`default/` is the prod-shaped lab — the only one with nginx/TLS/squid/Meilisearch, and the one to use for an actual deployment. `mariadb-multimaster/` and `mariadb-galera/` are DB-topology-focused QA/exploration labs (no squid/Meilisearch/control-plane Postgres candidate) — bring them up to poke at a specific replication/clustering behavior without touching your `default/` deployment. No lab runs MailHog — a fake mail catcher has no place here; every lab needs a real SMTP server, configured via the wizard or `/admin/smtp`. Every lab does run MinIO, backing the rich-text editor's pasted-image uploads. Every lab fronts the app with its own nginx on host ports **80/443** (the only web entry point — the app publishes no ports; first load serves the setup wizard over HTTP, HTTPS works after the wizard's TLS step), so **only one lab can be up at a time**; every other published port (DB nodes) is distinct per lab.

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
