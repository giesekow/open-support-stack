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
4. Set nginx mode:
   - `NGINX_MODE=https` to serve HTTPS directly from nginx.
   - `NGINX_MODE=http` if TLS is terminated upstream (for example HAProxy/pfSense).
5. For automatic TLS via Let's Encrypt set (only when `NGINX_MODE=https`):
   - `ENABLE_LETSENCRYPT=true`
   - `LETSENCRYPT_EMAIL=<your-email>`
   - `LETSENCRYPT_DOMAINS=<comma-separated domains>`
   - `LETSENCRYPT_PRIMARY_DOMAIN=<one domain from list>`
6. If `NGINX_MODE=http` (TLS terminated upstream), oauth2-proxy uses split OIDC endpoints by design:
   - Login URL via public HTTPS (`https://<SSO_HOST>/.../auth`)
   - Redeem/JWKS via internal Keycloak HTTP (`http://keycloak:8080/...`)
   This prevents callback `500` errors during code exchange.
7. Keep dedicated OIDC clients:
   - `MESHWEB_OIDC_CLIENT_ID` for mesh-web auth only.
   - `SUPPORT_PORTAL_OIDC_CLIENT_ID` for portal auth only (recommended: `support-portal`).

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
4. Recreate oauth2-proxy services after any OIDC/env changes:
```bash
docker compose --env-file .env.production up -d oauth2-proxy-portal oauth2-proxy-meshweb
```
5. If `NGINX_MODE=https` and `ENABLE_LETSENCRYPT=true`, wait for initial cert issuance and check logs:
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
   - `https://<FILES_HOST>`
   - `https://<STATUS_HOST>`

### Headscale UI API URL

When configuring Headscale UI settings in the browser:

1. Use `https://<MESH_WEB_HOST>` as the API URL.
2. Do not use `https://<MESH_HOST>` for the UI API setting.

Reason: `MESH_WEB_HOST` is the nginx + oauth2-proxy protected endpoint expected by the UI flow.

### Step 5: Optional env switching workflow

1. If you prefer using plain `docker compose` without `--env-file`, you can activate production env into `.env`:
```bash
./scripts/switch_env.sh prod
```
2. After operations, restore previous `.env`:
```bash
./scripts/switch_env.sh restore
```

## 3. Scripts Reference

### Environment and rendering

1. `./scripts/switch_env.sh <dev|prod|restore>`
   Switch active `.env` between dev/prod presets and restore previous state.
2. `./scripts/harden_env_production.sh .env.production`
   Generate strong production secrets and harden env defaults.
3. `./scripts/render_headscale_config.sh <env-file>`
   Render `config/headscale/config.yaml` from env values.
4. `./scripts/render_keycloak_realm.sh <env-file>`
   Render `config/keycloak/realm-support.json` from template/env values.
5. `./scripts/render_portal_index.sh <env-file>`
   Render `nginx/html/index.html` portal links from env values.

### Keycloak and SSO

1. `./scripts/sync_keycloak_redirects.sh <env-file>`
   Sync Keycloak client redirect URIs/web origins for mesh-web, portal, guacamole, BookStack, osTicket, and EspoCRM.
2. `./scripts/check_osticket_keycloak.sh`
   Preflight check for osTicket OAuth2 plugin and Keycloak endpoint reachability.
3. `./scripts/install_osticket_oauth2_plugin.sh`
   Install osTicket OAuth2 plugin files into the expected path.

### Certificates and TLS

1. `./scripts/regenerate_nginx_cert.sh <env-file>`
   Regenerate local/self-signed cert assets for nginx (dev/lab use).
2. `./scripts/check_active_cert.sh <hostname>`
   Show the currently served TLS cert details for a hostname.

### Seeding and bootstrap

1. `./scripts/seed_admin_accounts.sh`
   Seed admin/bootstrap accounts across integrated services.
2. `./scripts/post_seed_vaultwarden_org.sh`
   Post-seed helper for Vaultwarden organization setup.
3. `./scripts/seed_uptime_kuma_monitors.sh <env-file>`
   Seed Uptime Kuma monitors for stack services.
4. `./scripts/headscale_api_key.sh <create|list|expire> [options]`
   Manage Headscale API keys for mesh-web and API access.

### Production validation

1. `./scripts/preflight_production.sh .env.production`
   Run production readiness checks before deployment.
2. `./scripts/check_osticket_languages.sh`
   Verify expected osTicket language packs are available.
