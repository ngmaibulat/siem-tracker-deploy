# Upgrading to a new image version

Since the `migrate` service lost its profile gate, `docker compose up -d` runs
the one-shot schema migration to completion **before** starting the app (the
app has a `depends_on: service_completed_successfully` on it), so the plain
pull-and-up sequence below is a complete upgrade — pending Prisma migrations
for both planes are applied automatically. The job is idempotent; when the
schema is already current it exits immediately.

For a full deploy with a pre-upgrade database backup, use
`scripts/deploy_app.sh` instead.

```bash
# Check what is currently running
docker compose ps

# Pull newer images
docker compose pull

# Recreate containers using the new images.
# This first runs the one-shot `migrate` service (prisma migrate deploy on
# both planes), then starts the app — new code never boots on a stale schema.
docker compose up -d

# Check status
docker compose ps

# Check logs (the app also logs a prominent warning at startup if it ever
# detects pending, unapplied migrations)
docker compose logs -f
```

To apply migrations by hand without touching the running stack:

```bash
docker compose run --rm migrate
```
