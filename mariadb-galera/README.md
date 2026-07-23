# mariadb-galera

Manual-QA / exploration lab: 3-node MariaDB Galera cluster (synchronous multi-master via certification-based replication). App source lives in the separate `siem-tracker` repo; see the [repo-root README](../README.md) for the full list of labs.

Mirrors the app repo's `containers/mariadb-galera` dev lab in topology (minus its MaxScale proxy — removed here; the app connects to the cluster directly), but every service here is a **pulled registry image** (`ngmaibulat/usiem-tracker:latest` for the app) — this lab never builds anything. nginx fronts the app on host 80/443 as the only web entry point (wizard-generated config/TLS, same volume wiring as [`../default`](../default)); no squid here (DB-topology-focused, not fully prod-shaped — see [`../default`](../default)). No MailHog either — real SMTP only, configured via the wizard or `/admin/smtp`; a MinIO service backs rich-text image uploads. Every lab's nginx binds 80/443, so only one lab can be up at a time.

The app talks only to node1 (any node would do — Galera is multi-master); node2/3 are cluster peers it never contacts directly, reachable on their own host ports for manual QA.

```
   app ────► mariadb-node1 ◄──► mariadb-node2 ◄──► mariadb-node3
                (Galera synchronous multi-master replication)
```

## Deploy

```bash
cd mariadb-galera
mkdir -p data/mariadb-logs
cp example.env .env
docker compose pull
docker compose up -d
docker compose ps        # wait for all three nodes and the app to report healthy
```

The app applies its own pending migrations at startup (FR-47) once it can reach the cluster. On a very first boot, if the Galera cluster is still settling, the app's own retry/reconnect logic (plus `restart: unless-stopped`) handles it — just give it a few seconds and re-check `docker compose ps` / `docker compose logs app`.

App: http://localhost (first load goes to the setup wizard; https://localhost works after the wizard's TLS step — apply the generated config with `docker compose exec nginx nginx -s reload`).

## Verify the cluster

```bash
docker compose exec mariadb-node1 mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" \
  -e "INSERT INTO lab_demo.demo_events (message) VALUES ('hello from node1')"

# Read it back from a different physical node — proves synchronous
# replication, not just "the app's queries happen to land on one node".
docker compose exec mariadb-node2 mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" \
  -e "SELECT * FROM lab_demo.demo_events"
docker compose exec mariadb-node3 mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" \
  -e "SELECT * FROM lab_demo.demo_events"
```

## Bootstrap / recovery

node1 bootstraps the cluster when its `grastate.dat` is absent (fresh volume) or marked `safe_to_bootstrap` — node2/3 depend on node1, so a graceful `down` stops node1 last and leaves it safe to bootstrap. After an **ungraceful** full-stack kill, all nodes may hold `safe_to_bootstrap: 0`; recover by starting node1 once with the flag forced:

```bash
docker compose run --rm mariadb-node1 sh -c \
  "sed -i 's/safe_to_bootstrap: 0/safe_to_bootstrap: 1/' /var/lib/mysql/grastate.dat" \
&& docker compose up -d
```

## Reset

```bash
docker compose down -v   # wipes all three node volumes together and re-bootstraps
```

## Ports

| Port | Service |
|---|---|
| 80 / 443 | nginx — the only web entry point (proxies to the internal `app:3000`) |
| 3346 / 3347 / 3348 | mariadb-node1 / node2 / node3 |
| 5445 | postgres (FR-42 restore-helper only) |

## Notes

- The cluster runs `mariadb:13.0.1-rc`, not the 13.1 preview the other labs use: no current 13.1 build (preview or rolling, any variant) ships a working Galera provider library. Re-pin to 13.1 once a Galera-capable build exists.
- No `DB_POSTGRES_URL` is set: the control plane, if the wizard assigns it MariaDB, derives from the same backend as `siem_source_tracker_control`, keeping this lab focused on its own cluster topology (unlike `../default`, which offers a separate Postgres candidate).
- `postgres` is not part of the cluster/routing topology — it exists solely as the FR-42 restore-helper for staging legacy pg_dump restores.
- No MailHog: outbound mail needs a real SMTP server, configured via the wizard or `/admin/smtp`.
- `minio` backs the rich-text editor's pasted-image uploads (`S3_*` env vars on `app`); internal-only, never published — the app degrades gracefully if it's down.
- `scheduler` backs FR-46 scheduled report delivery — a thin Bun trigger (`ngmaibulat/usiem-scheduler` image) that polls the app's `/api/scheduler/config` and fires due jobs via `/api/scheduler/run`; no business logic, DB access, or SMTP credentials live in it. Requires `SCHEDULER_TOKEN` in `.env`; without it the container exits on start (comment the service out if unused).
- The healthcheck on all three nodes uses **root credentials**, not the MariaDB image's built-in `healthcheck.sh`: SST (State Snapshot Transfer, used when a node joins/rejoins) overwrites the joiner's `mysql.user` table with the donor's, orphaning its locally-generated `healthcheck@localhost` password. Root's password is identical cluster-wide and survives SST; a non-synced Galera node also rejects queries, so `SELECT 1` doubles as a synced-check.
