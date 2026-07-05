#!/bin/sh
set -e

# Runs ONCE on the master's fresh data volume (docker-entrypoint-initdb.d),
# after the official mariadb image's own env-var bootstrap (MARIADB_DATABASE /
# MARIADB_USER / MARIADB_PASSWORD on the mariadb-master service in
# docker-compose.yml) has already created siem_source_tracker and granted the
# `siem` user full rights on it. This script adds the two things that
# bootstrap can't:
#
#   - a control-plane database on this server (`<base>_control`, derived from
#     DB_MARIADB_URL — unused unless the wizard is pointed at MariaDB for the
#     control plane instead of the companion postgres service; created so
#     that option is available too)
#   - the replication account each slave's entrypoint authenticates with
#
# Replicates down to both slaves automatically once they attach, so they need
# no init script of their own.
mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" <<-EOSQL
	CREATE DATABASE IF NOT EXISTS siem_source_tracker_control;
	GRANT ALL PRIVILEGES ON siem_source_tracker_control.* TO 'siem'@'%';

	CREATE USER IF NOT EXISTS 'repl'@'%' IDENTIFIED BY '$MARIADB_REPL_PASSWORD';
	GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';

	FLUSH PRIVILEGES;
EOSQL
