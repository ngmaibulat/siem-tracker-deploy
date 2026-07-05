# mariadb-galera

Manual-QA / exploration lab: 3-node MariaDB Galera cluster (synchronous multi-master via certification-based replication) fronted by MaxScale's readwritesplit listener. App source lives in the separate `siem-tracker` repo; see the [repo-root README](../README.md) for the full list of labs.

Mirrors the app repo's `containers/mariadb-galera` dev lab exactly in topology, but every service here is a **pulled registry image** (`ngmaibulat/usiem-tracker:latest` for the app) — this lab never builds anything. No nginx/squid/TLS (DB-topology-focused, not prod-shaped — see [`../default`](../default) for that).

Unlike the master-slave/multimaster labs, the app here is **not** pinned to one physical node — MaxScale routes it to whichever node is currently designated for writes.

```
                    ┌──────────┐
   app ───────────► │ maxscale │ (readwritesplit :4006)
                    └────┬─────┘
             ┌───────────┼───────────┐
             ▼           ▼           ▼
      mariadb-node1  mariadb-node2  mariadb-node3
         (Galera synchronous multi-master replication)
```

## Deploy

```bash
cd mariadb-galera
mkdir -p data/mariadb-logs data/maxscale-logs
cp example.env .env
docker compose pull
docker compose run --rm migrate
docker compose up -d
docker compose ps        # wait for all three nodes to report healthy
```

If `migrate` fails on the very first run with a connection error, the cluster/MaxScale may still be settling (there's no MaxScale healthcheck to gate on) — wait a few seconds and re-run `docker compose run --rm migrate`; it's idempotent.

App: http://localhost:3005 (first load goes to the setup wizard). MaxScale's GUI/REST API is at http://localhost:18989 (admin/mariadb, dev-only plain HTTP).

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
| 3005 | app |
| 3346 / 3347 / 3348 | mariadb-node1 / node2 / node3 |
| 14006 | maxscale (readwritesplit SQL listener) |
| 18989 | maxscale GUI/REST (admin/mariadb) |
| 5445 | postgres (FR-42 restore-helper only) |
| 8030 | mailhog web UI |

## Notes

- No `DB_POSTGRES_URL` is set: the control plane, if the wizard assigns it MariaDB, derives from the same backend as `siem_source_tracker_control`, keeping this lab focused on its own cluster topology (unlike `../default`, which offers a separate Postgres candidate).
- `postgres` is not part of the cluster/routing topology — it exists solely as the FR-42 restore-helper for staging legacy pg_dump restores.
- The healthcheck on all three nodes uses **root credentials**, not the MariaDB image's built-in `healthcheck.sh`: SST (State Snapshot Transfer, used when a node joins/rejoins) overwrites the joiner's `mysql.user` table with the donor's, orphaning its locally-generated `healthcheck@localhost` password. Root's password is identical cluster-wide and survives SST; a non-synced Galera node also rejects queries, so `SELECT 1` doubles as a synced-check.
- The `maxscale` monitor/router password is a plain literal in both `maxscale.cnf` and `init/01-init.sh` (not parameterized via `.env` — those files aren't docker-compose `environment:` blocks) — fine for a QA/exploration lab; edit both files together if you need to change it.
