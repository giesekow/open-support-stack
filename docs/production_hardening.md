# Production Hardening Guide

This guide is for preparing the support stack for production deployment.

## 1) Core environment settings

Use `.env.production` as source of truth and keep `.env` for local/dev.
Set these values:

- `KEYCLOAK_START_CMD=start`
- `KEYCLOAK_HOSTNAME_STRICT=true`
- `MESHWEB_OIDC_SSL_INSECURE_SKIP_VERIFY=false`
- `SUPPORT_PORTAL_OIDC_SSL_INSECURE_SKIP_VERIFY=false`
- `VAULTWARDEN_SIGNUPS_ALLOWED=false`

Replace all placeholder values (`change-this...`, `replace-with...`) with strong secrets.

## 2) TLS

- For automatic public certs, enable:
  - `ENABLE_LETSENCRYPT=true`
  - `LETSENCRYPT_EMAIL=<ops email>`
  - `LETSENCRYPT_DOMAINS=<comma-separated FQDN list>`
  - `LETSENCRYPT_PRIMARY_DOMAIN=<one domain in list>`
- DNS for all `LETSENCRYPT_DOMAINS` must resolve to this host.
- Ports `80` and `443` must be reachable from the internet.
- If Let's Encrypt is disabled, nginx falls back to local certs in `nginx/certs/`.

## 3) Run the production preflight

```bash
./scripts/preflight_production.sh .env.production
```

You should have:

- `0` hard failures
- ideally `0` warnings

## 4) Deploy

```bash
docker compose --env-file .env.production pull
docker compose --env-file .env.production up -d
```

## 5) Post-deploy checks

- Check startup logs:
```bash
docker compose --env-file .env.production logs --tail=120 nginx certbot
```
- Verify active certificate:
```bash
./scripts/check_active_cert.sh example.com
```
- Open:
  - `https://example.com`
  - `https://sso.example.com`
  - `https://vault.example.com`
  - `https://docs.example.com`
  - `https://remote.example.com`
  - `https://tickets.example.com`
  - `https://crm.example.com`
  - `https://status.example.com`
- Confirm Keycloak login flow works for each integrated app.
- Confirm service health in Uptime Kuma.

## 6) Operational recommendations

- Backups:
  - Postgres volumes (`keycloak-db-data`, `guacamole-db-data`)
  - MariaDB volumes (`bookstack-db-data`, `osticket-db-data`, `espocrm-db-data`)
  - App data volumes (`vaultwarden-data`, `bookstack-data`, `espocrm-data`, `headscale-data`, `uptime-kuma-data`, `letsencrypt-data`)
- Update strategy:
  - Pin explicit image tags where possible.
  - Upgrade in staging before production.
- Monitoring:
  - Keep Uptime Kuma checks enabled.
