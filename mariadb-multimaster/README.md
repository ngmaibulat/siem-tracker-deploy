# mariadb-multimaster

Manual-QA / exploration lab: the siem-tracker app running against a 2-node MariaDB circular ("multi-master") replication topology using classic binlog/GTID replication — NOT Galera (see [`../mariadb-galera`](../mariadb-galera) for the certification-based multi-master lab). App source lives in the separate `siem-tracker` repo; see the [repo-root README](../README.md) for the full list of labs.

Mirrors the app repo's `containers/mariadb-multimaster` dev lab exactly in topology, but every service here is a **pulled registry image** (`ngmaibulat/usiem-tracker:latest` for the app) — this lab never builds anything. nginx fronts the app on host 80/443 as the only web entry point (wizard-generated config/TLS, same volume wiring as [`../default`](../default)); no squid here (DB-topology-focused, not fully prod-shaped — see [`../default`](../default)). No MailHog either — real SMTP only, configured via the wizard or `/admin/smtp`; a MinIO service backs rich-text image uploads. Every lab's nginx binds 80/443, so only one lab can be up at a time.

## Deploy

```bash
cd mariadb-multimaster
cp example.env .env
docker compose pull
docker compose up -d
```

App: http://localhost — follow the initial configuration wizard on first load (https://localhost works after the wizard's TLS step; apply the generated config with `docker compose exec nginx nginx -s reload`).

## Topology

```
app (DB_MARIADB_URL) ──► mariadb-node1 ◄──circular replication──► mariadb-node2
```

The app's `DB_MARIADB_URL` points only at `mariadb-node1`; `mariadb-node2` is a replication peer the app never talks to directly. Each node independently retries a `CHANGE MASTER TO` against the *other* node on startup (no `depends_on` between them — that would be a dependency cycle) — correctness comes from the retry loop, not container start order.

## Verify replication

```bash
docker compose exec mariadb-node1 mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" \
  -e "INSERT INTO lab_demo.demo_events (message) VALUES ('from node1');"
docker compose exec mariadb-node2 mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" \
  -e "SELECT * FROM lab_demo.demo_events;"
```
And the reverse direction (insert on node2, read from node1) to confirm both directions replicate.

## Ports

| Port | Service |
|---|---|
| 80 / 443 | nginx — the only web entry point (proxies to the internal `app:3000`) |
| 3336 | mariadb-node1 |
| 3337 | mariadb-node2 |
| 5443 | postgres (FR-42 restore-helper only) |

## Notes

- No `DB_POSTGRES_URL` is set: the control plane, if the wizard assigns it MariaDB, derives from the same backend as `siem_source_tracker_control`, keeping this lab focused on its own replication topology (unlike `../default`, which offers a separate Postgres candidate).
- `postgres` is not part of the replication topology — it exists solely as the FR-42 restore-helper for staging legacy pg_dump restores.
- No MailHog: outbound mail needs a real SMTP server, configured via the wizard or `/admin/smtp`.
- `minio` backs the rich-text editor's pasted-image uploads (`S3_*` env vars on `app`); internal-only, never published — the app degrades gracefully if it's down.
- `scheduler` backs FR-46 scheduled report delivery — a thin Bun trigger (`ngmaibulat/usiem-scheduler` image) that polls the app's `/api/scheduler/config` and fires due jobs via `/api/scheduler/run`; no business logic, DB access, or SMTP credentials live in it. Requires `SCHEDULER_TOKEN` in `.env`; without it the container exits on start (comment the service out if unused).
- Passwords are parameterized via `.env` (see `example.env`) but default to the same values as the app repo's dev lab, so behavior is unchanged out of the box.
