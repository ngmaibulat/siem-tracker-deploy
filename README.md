# siem-tracker-deploy

Production deployment stack for **SIEM Source Onboarding Tracker** (app source lives in the separate `siem-tracker` repo). The app runs from the published Docker image `ngmaibulat/usiem-tracker:latest` — nothing is built on the prod host.

## Deploy

On the prod host, from a copy of this repo:

```bash
cp example.env .env          # fill in APP_SECRET, APP_URL, TARGET_DATE, ...
# place your TLS cert in nginx/certs/ (fullchain.pem + privkey.pem),
# or generate a self-signed pair for testing: ./scripts/generate-self-signed.sh

docker compose pull                # fetch the published image
docker compose run --rm migrate    # apply DB migrations (idempotent)
docker compose up -d               # bring the stack up
```

Then, on the first deploy:

1. Wait until the app is online — `docker compose ps` shows the `app` service as `healthy` (the image ships a HEALTHCHECK).
2. Open `APP_URL` in a browser and follow the initial configuration wizard.
3. The app restarts when the wizard completes; once it is back online, consider restoring a DB backup from the UI (backups are managed in the app).

The same three compose commands are also the update procedure — re-run them to roll out a new image.

## Contents

| Path | Purpose |
|---|---|
| `docker-compose.yml` | Prod compose stack: nginx → app → postgres / redis / squid |
| `example.env` | Template for the prod `.env` (`cp example.env .env`) |
| `nginx/conf.d/app.conf` | Reference nginx reverse-proxy config |
| `nginx/certs/` | TLS cert location (see its README; `*.pem` are gitignored) |
| `squid/squid.conf` | Egress-proxy config (FR-32) |
| `scripts/` | **Legacy** scripted deploy — kept for now, see below |

## Secrets

This repo is public. `.env` and `nginx/certs/*.pem` are **gitignored** — real values live only on the machines that need them. The legacy docs/scripts use placeholders (`<prod-host>`, `<prod-user>`) for the same reason.

## Legacy scripted deploy (`scripts/`)

The previous workflow — build + push the image from a dev machine, then deploy over SSH — still works and is documented in [`scripts/DEPLOY.md`](scripts/DEPLOY.md):

- `scripts/deploy-prod.ps1` — dev-side driver (builds from the app repo, defaults to a `siem-tracker` checkout next to this repo; override with `-AppRepo`). Prod host/user are passed via `-ProdHost`/`-ProdUser` — they are not stored in the repo.
- `scripts/deploy_app.sh` — prod-side script (backup → pull → migrate → up), copied to `/opt/siem-source-tracker/deploy_app.sh`.
- `scripts/generate-self-signed.sh`, `scripts/remove-all-images.sh` — helpers.
