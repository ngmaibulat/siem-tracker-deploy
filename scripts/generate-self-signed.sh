#!/usr/bin/env bash
#
# Generate a self-signed TLS certificate for the nginx reverse proxy.
#
# NOTE: the primary path is now the setup wizard, which generates cert.pem +
# key.pem into the proxy_certs volume shared with nginx (see
# docker-compose.yml in this repo). This script remains for manual/legacy setups that
# mount ./nginx/certs themselves.
#
# Writes privkey.pem + fullchain.pem into nginx/certs/ at the repo root —
# the filenames the reference nginx/conf.d/app.conf expects. Both are
# gitignored (nginx/certs/*.pem) — they're secrets.
#
# Unlike a bare `-subj "/CN=..."` one-liner, this sets a subjectAltName so modern
# browsers (and `curl` without -k) accept the cert for localhost. Browsers still
# warn that the issuer is untrusted — this is for testing, not a real CA cert.
#
# Usage:
#   ./generate-self-signed.sh [common-name]   # default common-name: localhost
#
# Env:
#   DAYS=365   validity in days (default 365)
#   FORCE=1    overwrite existing privkey.pem / fullchain.pem
#
# After regenerating, reload nginx:
#   docker compose exec nginx nginx -s reload
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERT_DIR="$SCRIPT_DIR/../nginx/certs"
mkdir -p "$CERT_DIR"
KEY_FILE="$CERT_DIR/privkey.pem"
CERT_FILE="$CERT_DIR/fullchain.pem"

CN="${1:-localhost}"
DAYS="${DAYS:-365}"

# SAN: always cover localhost loopback; add the requested CN host when it's not
# already localhost (as a DNS name).
SAN="DNS:localhost,IP:127.0.0.1,IP:::1"
if [ "$CN" != "localhost" ]; then
  SAN="DNS:$CN,$SAN"
fi

if { [ -f "$KEY_FILE" ] || [ -f "$CERT_FILE" ]; } && [ "${FORCE:-}" != "1" ]; then
  echo "Refusing to overwrite existing certificate in $CERT_DIR" >&2
  echo "  $KEY_FILE" >&2
  echo "  $CERT_FILE" >&2
  echo "Set FORCE=1 to regenerate." >&2
  exit 1
fi

echo "==> Generating self-signed certificate"
echo "    CN:   $CN"
echo "    SAN:  $SAN"
echo "    days: $DAYS"

openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$KEY_FILE" -out "$CERT_FILE" \
  -days "$DAYS" -subj "/CN=$CN" \
  -addext "subjectAltName=$SAN"

chmod 600 "$KEY_FILE"

echo "==> Wrote:"
echo "    $KEY_FILE"
echo "    $CERT_FILE"
echo "Reload nginx to pick it up:"
echo "    docker compose exec nginx nginx -s reload"
