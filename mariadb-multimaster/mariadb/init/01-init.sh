#!/bin/sh
set -e

# Runs ONCE on node1's fresh data volume (docker-entrypoint-initdb.d), after
# the official mariadb image's own env-var bootstrap (MARIADB_DATABASE /
# MARIADB_USER / MARIADB_PASSWORD on the mariadb-node1 service in
# docker-compose.yml) has already created siem_source_tracker and granted the
# `siem` user full rights on it. This script adds:
#
#   - a control-plane database (`<base>_control`, derived from DB_MARIADB_URL
#     — this lab sets no DB_POSTGRES_URL, so the control plane's containerized
#     candidate is this same MariaDB backend; this is that database)
#   - the replication account each node's entrypoint authenticates with
#     against the OTHER node
#
# node2 gets NO init script of its own: once the node2<-node1 replication link
# comes up, this database and the `repl` user itself both arrive on node2 via
# ordinary replication (DDL/DCL replicates like any other statement) — which
# is what then lets node1 authenticate back to node2 and close the circle.
mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" <<-EOSQL
	CREATE DATABASE IF NOT EXISTS siem_source_tracker_control;
	GRANT ALL PRIVILEGES ON siem_source_tracker_control.* TO 'siem'@'%';

	CREATE USER IF NOT EXISTS 'repl'@'%' IDENTIFIED BY '$MARIADB_REPL_PASSWORD';
	GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';

	FLUSH PRIVILEGES;

	-- Generic sandbox database, independent of the app, for a quick manual
	-- replication check in both directions (see README.md). origin_server_id
	-- self-reports which physical node wrote a given row.
	CREATE DATABASE IF NOT EXISTS lab_demo;
	CREATE TABLE lab_demo.demo_events (
	  id INT AUTO_INCREMENT PRIMARY KEY,
	  message VARCHAR(255) NOT NULL,
	  origin_server_id INT NOT NULL DEFAULT (@@server_id),
	  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
	);
EOSQL
