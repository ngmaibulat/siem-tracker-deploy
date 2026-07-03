# TLS certificates for nginx (legacy / manual setups)

**This directory is no longer mounted by `docker-compose.yml`.** The running
stack gets its certificate from the app's setup wizard: the TLS step writes
`cert.pem` + `key.pem` into the `proxy_certs` named volume, which nginx mounts
read-only at `/etc/nginx/certs`. To bring an existing certificate into the
running stack, copy it into the `app` container and reload nginx:

```bash
docker compose cp your-fullchain.pem app:/app/tls/cert.pem
docker compose cp your-privkey.pem  app:/app/tls/key.pem
docker compose exec nginx nginx -s reload
```

This directory is kept for **manual setups** that bind-mount `./nginx/certs`
into nginx themselves, paired with the reference config `nginx/conf.d/app.conf`,
which expects exactly two files here:

| File            | Contents                                              |
|-----------------|-------------------------------------------------------|
| `fullchain.pem` | Server certificate + any intermediate CA chain        |
| `privkey.pem`   | Private key for that certificate                       |

These files are **not** committed (see `.gitignore`) — they are secrets.

## Self-signed pair for testing

Run `scripts/generate-self-signed.sh` — it writes `privkey.pem` + `fullchain.pem`
into this directory with a `subjectAltName` for `localhost` (so modern browsers
and `curl` accept the cert for that host; they still warn that the issuer is
untrusted):

```bash
./scripts/generate-self-signed.sh            # CN=localhost, 365 days
# ./scripts/generate-self-signed.sh siem.local   # different common name
# FORCE=1 ./scripts/generate-self-signed.sh      # overwrite existing pair
# DAYS=30 ./scripts/generate-self-signed.sh      # shorter validity
```

It refuses to overwrite existing `.pem` files unless `FORCE=1` is set. Replace
the pair with a properly issued certificate for production.
