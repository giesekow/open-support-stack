# Support Stack

## 1. Development

### Prerequisites

1. Install Docker and Docker Compose plugin.
2. Add local host entries from [`hostnames.txt`](/media/datahouse/projects/support-stack/hostnames.txt) into `/etc/hosts`.
3. Ensure local TLS certs exist in `nginx/certs/` (for local HTTPS testing):
```bash
./scripts/regenerate_nginx_cert.sh .env
```

### Setup

1. Copy environment template:
```bash
cp .env.example .env
```
2. Edit `.env` and set your values (at minimum passwords/secrets).
3. Start the stack:
```bash
./start-dev.sh
```
4. Open the portal:
   `https://<SUPPORT_HOST from .env>`

### Useful dev commands

1. Restart stack:
```bash
docker compose down && docker compose up -d
```
2. Check logs:
```bash
docker compose logs -f nginx keycloak
```
3. Run osTicket + Keycloak preflight:
```bash
./scripts/check_osticket_keycloak.sh
```
4. If you change hostnames in `.env`, re-sync Keycloak redirect URIs:
```bash
./scripts/sync_keycloak_redirects.sh .env
```

## 2. Production

### Step 1: Prepare production env

1. Use `.env.production` as source of truth.
2. Generate/refresh strong secrets:
```bash
./scripts/harden_env_production.sh .env.production
```
3. Review `.env.production` and adjust domain-specific values.
4. For automatic TLS via Let's Encrypt set:
   - `ENABLE_LETSENCRYPT=true`
   - `LETSENCRYPT_EMAIL=<your-email>`
   - `LETSENCRYPT_DOMAINS=<comma-separated domains>`
   - `LETSENCRYPT_PRIMARY_DOMAIN=<one domain from list>`

### Step 2: Preflight checks

1. Run production preflight:
```bash
./scripts/preflight_production.sh .env.production
```
2. Resolve any reported failures before continuing.

### Step 3: Deploy

1. Render generated configs from production env:
```bash
./scripts/render_headscale_config.sh .env.production
./scripts/render_keycloak_realm.sh .env.production
```
2. Pull images:
```bash
docker compose --env-file .env.production pull
```
3. Start services:
```bash
docker compose --env-file .env.production up -d
```
4. If `ENABLE_LETSENCRYPT=true`, wait for initial cert issuance and check logs:
```bash
docker compose --env-file .env.production logs --tail=120 certbot nginx
```

### Step 4: Verify

1. Check container health/logs:
```bash
docker compose --env-file .env.production ps
docker compose --env-file .env.production logs --tail=120
```
2. Check active TLS cert in nginx:
```bash
./scripts/check_active_cert.sh <SUPPORT_HOST>
```
3. Verify key URLs:
   - `https://<SUPPORT_HOST>`
   - `https://<SSO_HOST>`
   - `https://<VAULT_HOST>`
   - `https://<DOCS_HOST>`
   - `https://<REMOTE_HOST>`
   - `https://<MESH_HOST>`
   - `https://<MESH_WEB_HOST>`
   - `https://<TICKETS_HOST>`
   - `https://<CRM_HOST>`
   - `https://<STATUS_HOST>`

### Step 5: Optional env switching workflow

1. If you prefer using plain `docker compose` without `--env-file`, you can activate production env into `.env`:
```bash
./scripts/switch_env.sh prod
```
2. After operations, restore previous `.env`:
```bash
./scripts/switch_env.sh restore
```
