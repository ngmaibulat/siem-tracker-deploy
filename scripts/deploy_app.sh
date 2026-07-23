#!/usr/bin/env bash
#
# Prod-side deploy for SIEM Source Tracker (registry workflow).
#
# Ships as scripts/deploy_app.sh in the siem-tracker-deploy repo and is copied
# to the prod app dir root (/opt/siem-source-tracker/deploy_app.sh).
# Invoked by the dev-side deploy-prod.ps1 over SSH, or run by hand:
#
#   sudo -n /opt/siem-source-tracker/deploy_app.sh [image_tag]
#
# The stack always runs the PUBLISHED image ngmaibulat/usiem-tracker:latest
# (hardcoded in docker-compose.yml); this script pulls the registry's current
# `latest` (no `docker load` of a tar). The image is public, so the prod host
# needs no `docker login`. The optional [image_tag] argument (default: latest)
# is a LABEL only — it names the pre-deploy DB backup and the final report; it
# does not select which image runs. To deploy/roll back to a specific version,
# re-point `latest` at that tag in the registry first (see DEPLOY.md).
# Takes a backup, then brings the stack up (the app applies its own pending
# migrations on start — FR-47). Idempotent — re-running is safe.
set -euo pipefail

APP_DIR="/opt/siem-source-tracker"
BACKUPS_DIR="$APP_DIR/backups"

# Prod stack lives in $APP_DIR/docker-compose.yml (default filename — no -f flag).
COMPOSE="docker compose"

# Optional label for the backup filename / final report (see header comment).
IMAGE_TAG="${1:-latest}"

cd "$APP_DIR"

mkdir -p "$BACKUPS_DIR"

echo "==> Checking postgres container"
$COMPOSE up -d postgres

echo "==> Waiting for PostgreSQL"
for i in {1..30}; do
  if $COMPOSE exec -T postgres pg_isready -U siem -d siem_source_tracker >/dev/null 2>&1; then
    echo "PostgreSQL is ready"
    break
  fi

  if [ "$i" -eq 30 ]; then
    echo "PostgreSQL is not ready"
    exit 1
  fi

  sleep 2
done

BACKUP_FILE="$BACKUPS_DIR/siem_source_tracker_before_${IMAGE_TAG}_$(date +%F_%H-%M-%S).dump"

echo "==> Backing up database to $BACKUP_FILE"
$COMPOSE exec -T postgres pg_dump -U siem -d siem_source_tracker -Fc > "$BACKUP_FILE"

# Pull the registry's current `latest`.
echo "==> Pulling app image from registry"
$COMPOSE pull app

echo "==> Starting stack (app + nginx + redis + meilisearch + postgres)"
$COMPOSE up -d

echo "==> Checking containers"
$COMPOSE ps

echo "==> Last app logs"
$COMPOSE logs --tail=50 app

echo "==> Deploy completed"
echo "Image: ngmaibulat/usiem-tracker:latest (label: $IMAGE_TAG)"
echo "Backup: $BACKUP_FILE"
