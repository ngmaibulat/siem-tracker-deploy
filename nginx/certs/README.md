# TLS certificates for nginx

`docker-compose.yml` (repo root) mounts this directory read-only into the nginx
container at `/etc/nginx/certs`. The proxy config (`nginx/conf.d/app.conf`)
expects exactly two files here:

| File            | Contents                                              |
|-----------------|-------------------------------------------------------|
| `fullchain.pem` | Server certificate + any intermediate CA chain        |
| `privkey.pem`   | Private key for that certificate                       |

These files are **not** committed (see `.gitignore`) — they are secrets. Place
the real certificate issued for your host here on the prod machine.

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

Reload nginx after changing certs:

```bash
docker compose exec nginx nginx -s reload   # from the repo root
```
