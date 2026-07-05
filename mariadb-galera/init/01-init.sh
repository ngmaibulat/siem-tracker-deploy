#!/bin/sh
set -e

# Runs ONCE on node1's fresh data volume (docker-entrypoint-initdb.d, the
# bootstrap node) and replicates to the other nodes when they join via Galera.
# After the official mariadb image's own env-var bootstrap (MARIADB_DATABASE /
# MARIADB_USER / MARIADB_PASSWORD on the mariadb-node1 service in
# docker-compose.yml) has already created siem_source_tracker and granted the
# `siem` user full rights on it, this script adds:
#
#   - a control-plane database (`<base>_control`, derived from DB_MARIADB_URL
#     — this lab sets no DB_POSTGRES_URL, so the control plane's containerized
#     candidate is this same MariaDB backend; this is that database)
#   - the maxscale monitor/router account (galeramon + readwritesplit
#     authentication, see maxscale.cnf)
#   - a generic sandbox database for a quick manual check that writes
#     propagate across the cluster (see README.md)
#
# No `repl` user needed — Galera has no traditional master/slave replication
# account.
#
# The maxscale password below is a plain literal, matching maxscale.cnf
# (not a docker-compose environment: block, so there's no clean way to
# parameterize either file from the same .env value without extra tooling —
# fine for a QA/exploration lab; change both files together if you need to).
mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" <<-EOSQL
	CREATE DATABASE IF NOT EXISTS siem_source_tracker_control;
	GRANT ALL PRIVILEGES ON siem_source_tracker_control.* TO 'siem'@'%';

	CREATE USER IF NOT EXISTS 'maxscale'@'%' IDENTIFIED BY 'maxscale_password';
	GRANT SELECT ON mysql.* TO 'maxscale'@'%';
	GRANT SHOW DATABASES, REPLICATION CLIENT, PROCESS ON *.* TO 'maxscale'@'%';

	FLUSH PRIVILEGES;

	CREATE DATABASE IF NOT EXISTS lab_demo;
	CREATE TABLE IF NOT EXISTS lab_demo.demo_events (
	  id INT AUTO_INCREMENT PRIMARY KEY,
	  message VARCHAR(255) NOT NULL,
	  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
	);
EOSQL
