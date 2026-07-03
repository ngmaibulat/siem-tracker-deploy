#!/usr/bin/env bash
#
# DANGER: force-removes ALL Docker images on this host — not just this
# project's. Every stack on the machine will need its images re-pulled.
# Dev-machine cleanup helper; never run on prod.
set -euo pipefail

read -r -p "Force-remove ALL Docker images on this host? [y/N] " answer
case "$answer" in
  [yY]|[yY][eE][sS]) ;;
  *) echo "Aborted."; exit 1 ;;
esac

docker rmi -f $(docker images -aq)
