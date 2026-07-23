# default

Production / manual-QA deployment lab for **SIEM Source Onboarding Tracker** (app source lives in the separate `siem-tracker` repo; see the [repo-root README](../README.md) for the full list of labs). The app runs from the published Docker image `ngmaibulat/usiem-tracker:latest` — nothing is built on the host. Topology mirrors the app repo's `containers/default` dev lab (MariaDB master + 2 slaves for the domain plane, Postgres for the control plane, MinIO for rich-text image uploads), but every service here is a pulled registry image rather than built from source. This is the only lab with nginx/TLS/squid — it's the prod-shaped one; the other labs are DB-topology-focused QA exploration environments. Unlike the dev repo's own lab, there's **no MailHog here** (no lab in this repo runs one) — a fake mail catcher has no place in a stack meant for real deployment, so outbound mail must be a real SMTP server configured via the wizard or `/admin/smtp`.

## Deploy

From this directory:

```bash
cd default
cp example.env .env          # fill in APP_SECRET, APP_URL, TARGET_DATE, ...
chmod 600 .env               # it holds secrets — keep it owner-readable only

docker compose pull                # fetch the published image
docker compose up -d               # bring the stack up (runs pending DB migrations first, automatically)
```

Then, on the first deploy:

1. Wait until the app is online — `docker compose ps` shows the `app` service as `healthy` (the image ships a HEALTHCHECK).
2. Open `APP_URL` in a browser and follow the initial configuration wizard.
3. The app restarts when the wizard completes; once it is back online, consider restoring a DB backup from the UI (backups are managed in the app).

The same two compose commands are also the update procedure — re-run them to roll out a new image. To apply migrations by hand without touching the running stack, run `docker compose run --rm migrate` (idempotent).

## Manual QA

- **Email**: no lab in this repo runs MailHog — outbound mail (invites, password resets, notifications) needs a real SMTP server configured via the wizard or `/admin/smtp`.
- **MariaDB replication**: the domain plane is MariaDB (1 master + 2 async binlog/GTID replicas). Inspect it with `docker compose exec mariadb-master mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" -e '...'` (or `mariadb-slave1`/`mariadb-slave2`); no ports are published to the host, matching this repo's "only nginx is externally reachable" convention.

## Architecture

- **Domain plane (MariaDB, by wizard default)**: `mariadb-master` + `mariadb-slave1`/`mariadb-slave2`, classic async binlog/GTID replication. The app's `DB_MARIADB_URL` points only at the master — no read/write splitting. Which plane actually ends up on MariaDB at runtime is a choice made once in the Initial Configuration Wizard (stored in the connection registry, never re-derived from env at runtime — see the app repo's CLAUDE.md, Connection registry section); `DB_PROVIDER=mariadb` on the `app`/`migrate` services only picks the Prisma CLI's own pre-migration target.
- **Control plane (Postgres, by wizard default)**: the `postgres` service hosts a base `siem_source_tracker` database (identity/auth lives in its own `control` schema within it once the wizard assigns it there) — it does not double as the domain-plane database. `CONTROL_DB_PROVIDER=postgres` on the `app`/`migrate` services picks the Prisma CLI's pre-migration target for it, matching the intent that this compose file's default topology is domain=MariaDB / control=Postgres — but, as above, the wizard is what actually decides at runtime. It also doubles as the FR-42 restore-helper (`RESTORE_PG_URL`) for staging legacy pg_dump restores.
- **Volume contracts**: `app_data` (SQLite connection registry with encrypted creds, FR-31) and `app_backups` must survive recreation; they're deliberately on separate volumes from `proxy_conf`/`proxy_certs` so nginx never mounts anything containing secrets. `squid` is the app's egress proxy (FR-32) — all outbound HTTP/HTTPS goes through it via `HTTP_PROXY`/`HTTPS_PROXY`; the app degrades gracefully if squid is down.
- **MinIO (S3-compatible storage)**: backs the rich-text editor's pasted-image uploads (`S3_ENDPOINT`/`S3_ACCESS_KEY_ID`/`S3_SECRET_ACCESS_KEY`/`S3_BUCKET` on `app`). Internal-only, never published; the app auto-creates the `siem-files` bucket on first upload — no init sidecar. Optional accelerator, same posture as squid/meilisearch: the app degrades gracefully if MinIO is down (image paste-upload just stays disabled, nothing else breaks).
- **Scheduler (FR-46, scheduled report delivery)**: the `scheduler` service runs the `ngmaibulat/usiem-scheduler` image (versioned in lockstep with the app image) — a thin Bun trigger that polls the app's `/api/scheduler/config` and fires due jobs via `/api/scheduler/run`; all real work (rendering PDFs, sending mail) happens inside the app. Requires `SCHEDULER_TOKEN` in `.env`; without it the container exits on start (comment the service out if unused).

### Gotchas

- **Postgres major upgrades** (image tag bump) do not work on an existing `postgres_data` volume — a dump/restore migration is required; see the warning in `docker-compose.yml` and `../scripts/DEPLOY.md` §6. The volume mounts `/var/lib/postgresql` (parent dir), the PG 18+ convention.
- **`POSTGRES_DB` doesn't retrofit an existing volume.** The `postgres` service's `POSTGRES_DB` points at `siem_source_tracker`. That env var is only honored on a *fresh* `postgres_data` volume — on an already-initialized one it has no effect; a volume from an older release is still there under the old `siem_source_tracker_control` name. Start from a fresh volume, or rename the DB by hand (`ALTER DATABASE ... RENAME TO ...`).
- **MariaDB replication is async, not synchronous** — a slave can briefly lag the master. This only matters if you're inspecting slave state directly (`SHOW SLAVE STATUS`) right after a write.

## TLS

Certificates are **not** taken from files in this repo: the wizard's TLS step writes `cert.pem` + `key.pem` into the `proxy_certs` volume shared with nginx (on first boot the app seeds a bootstrap HTTP-only config so the wizard is reachable on port 80 before any cert exists). To use an existing certificate instead, copy it into the running `app` container and reload nginx:

```bash
docker compose cp your-fullchain.pem app:/app/tls/cert.pem
docker compose cp your-privkey.pem  app:/app/tls/key.pem
docker compose exec nginx nginx -s reload
```

`nginx/certs/` and `../scripts/generate-self-signed.sh` are legacy — for manual setups that mount `./nginx/certs` themselves (the shipped compose file does not).

## Contents

| Path | Purpose |
|---|---|
| `docker-compose.yml` | Compose stack: nginx → app → mariadb (domain) / postgres (control) / redis / squid / minio / scheduler |
| `example.env` | Template for the prod `.env` (`cp example.env .env`) |
| `mariadb/replication.cnf` | Config mounted into all three MariaDB nodes |
| `mariadb/init-master/01-init.sh` | One-time master init: control-plane sandbox DB + `repl` replication user |
| `nginx/conf.d/app.conf` | Reference nginx reverse-proxy config |
| `nginx/certs/` | Legacy TLS cert location for manual setups — not mounted by the compose file (see its README; `*.pem` are gitignored) |
| `squid/squid.conf` | Egress-proxy config (FR-32) |

The legacy scripted deploy tooling lives at the repo root, [`../scripts/`](../scripts) — see there.

## Secrets

This repo is public. `.env` and `nginx/certs/*.pem` are **gitignored** — real values live only on the machines that need them. The legacy docs/scripts use placeholders (`<prod-host>`, `<prod-user>`) for the same reason.
