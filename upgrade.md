# Upgrading to a new image version

The app applies its own pending migrations at every start (FR-47): it targets
whichever connection the SQLite registry actually resolves for each plane
(domain + control), not env vars, is advisory-lock protected against
concurrent container starts, and writes Prisma-CLI-compatible ledger rows.
This means the plain pull-and-up sequence below is already a complete
upgrade — no separate migrate step or container is needed. The migration
runs before the app reports healthy/starts serving traffic; when the schema
is already current it's a no-op. Opt out with `AUTO_MIGRATE=off` (the app
then only logs a warning about pending migrations instead of applying them).

For a full deploy with a pre-upgrade database backup, use
`scripts/deploy_app.sh` instead.

```bash
# Check what is currently running
docker compose ps

# Pull newer images
docker compose pull

# Recreate containers using the new images — the app migrates itself on
# start, before serving traffic, so new code never runs against a stale
# schema.
docker compose up -d

# Check status
docker compose ps

# Check logs (the app also logs a prominent warning at startup if it ever
# detects pending, unapplied migrations)
docker compose logs -f
```
