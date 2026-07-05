# mariadb-multimaster

Manual-QA / exploration lab: the siem-tracker app running against a 2-node MariaDB circular ("multi-master") replication topology using classic binlog/GTID replication — NOT Galera (see [`../mariadb-galera`](../mariadb-galera) for the certification-based multi-master lab). App source lives in the separate `siem-tracker` repo; see the [repo-root README](../README.md) for the full list of labs.

Mirrors the app repo's `containers/mariadb-multimaster` dev lab exactly in topology, but every service here is a **pulled registry image** (`ngmaibulat/usiem-tracker:latest` for the app) — this lab never builds anything. No nginx/squid/TLS (DB-topology-focused, not prod-shaped — see [`../default`](../default) for that).

## Deploy

```bash
cd mariadb-multimaster
cp example.env .env
docker compose pull
docker compose run --rm migrate
docker compose up -d
```

App: http://localhost:3004 — follow the initial configuration wizard on first load.

## Topology

```
app (DATABASE_URL) ──► mariadb-node1 ◄──circular replication──► mariadb-node2
```

The app's `DATABASE_URL` points only at `mariadb-node1`; `mariadb-node2` is a replication peer the app never talks to directly. Each node independently retries a `CHANGE MASTER TO` against the *other* node on startup (no `depends_on` between them — that would be a dependency cycle) — correctness comes from the retry loop, not container start order.

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
| 3004 | app |
| 3336 | mariadb-node1 |
| 3337 | mariadb-node2 |
| 5443 | postgres (FR-42 restore-helper only) |
| 8029 | mailhog web UI |

## Notes

- `CONTROL_DATABASE_URL` is left unset: the control plane derives from the same MariaDB backend as `siem_source_tracker_control`, keeping this lab focused on its own replication topology (unlike `../default`, which pins control to a separate Postgres).
- `postgres` is not part of the replication topology — it exists solely as the FR-42 restore-helper for staging legacy pg_dump restores.
- Passwords are parameterized via `.env` (see `example.env`) but default to the same values as the app repo's dev lab, so behavior is unchanged out of the box.
