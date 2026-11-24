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
5. Open Mailpit to inspect development emails:
   `http://127.0.0.1:8025`

### Shared SMTP configuration

Vaultwarden, Penpot, Support Tools test email, and the Frappe HR leave notifier use the same `SMTP_*` settings. Configure SMTP once in the environment file instead of adding application-specific SMTP variables.

For implicit TLS on port 465:

```dotenv
SMTP_HOST=smtp.example.com
SMTP_PORT=465
SMTP_SECURITY=force_tls
SMTP_SECURE=true
SMTP_STARTTLS=false
SMTP_USER=mailer@example.com
SMTP_PASS=replace-with-smtp-password
SMTP_FROM=no-reply@example.com
```

For STARTTLS on port 587, use `SMTP_SECURITY=starttls`, `SMTP_SECURE=false`, and `SMTP_STARTTLS=true`. Local development uses `mailpit:1025` with `SMTP_SECURITY=off`, `SMTP_SECURE=false`, and `SMTP_STARTTLS=false`.

### Frappe HR leave notifications

The `frappe-hr-leave-notifier` service sends scheduled summaries of submitted, approved leave without modifying Frappe HR. It uses a dedicated database account with `SELECT` access only, discovers the single schema granted to that account, and also marks its session read-only. The existing `orangehrm-leave-notifier-data` volume is intentionally reused during cutover so previously delivered summaries are not resent.

The Support Tools web app is the authoritative configuration store. PostgreSQL keeps rules, templates, and immutable revisions; `config/frappe-hr/leave-notifications.json` and `config/frappe-hr/email-templates/` are imported only when the database is empty. Every accepted change publishes an atomic snapshot to the shared `support-tools-runtime` volume, which the notifier reloads before each scheduler cycle.

Open `https://<SUPPORT_HOST>/automations` through the existing portal login. Access is limited to members of the Keycloak `support-admin` group; authentication alone is not sufficient. The first version supports listing, creating, editing, enabling/disabling, previewing, sending a test email, viewing revision history, and restoring a revision. SMTP credentials remain environment-only and are never stored in the database. See `docs/support_tools_operations.md` for membership, deployment, and verification procedures.

Start the local services independently of the full stack:

```bash
docker compose --env-file .env --profile development up -d mailpit support-tools-db support-tools frappe-hr-leave-notifier
docker compose --env-file .env logs -f support-tools frappe-hr-leave-notifier
```

`SUPPORT_TOOLS_ALLOWED_GROUP` defaults to `support-admin`. The realm template and Keycloak sync script create this group, its matching realm role, and the `groups` claim mapper for `support-portal`. Users must sign out and back in after membership changes. `SUPPORT_TOOLS_DEV_AUTH_BYPASS` stays `false` by default because nginx supplies the authenticated Keycloak identity. Set it to `true` only for deliberate direct-container UI debugging; production preflight rejects it when enabled.

Each rule supports:

1. `schedule.days` and `schedule.time` in the configured `TZ`.
2. `start_offset_days` and `days` to select today, tomorrow, or a future date range.
3. `recipients` for one or more email addresses.
4. `filters.subunits`, `filters.locations`, and `filters.employee_emails`. In Frappe HR these map to employee department, branch, and email. Empty lists include everyone.
5. `statuses`: `Approved`; only submitted (`docstatus=1`) leave applications are eligible. Legacy OrangeHRM values `2` and `3` are migrated automatically.
6. `send_when_empty` to optionally send a message when nobody matches.
7. `include_leave_type` to disclose the leave category. It defaults to `false` in the supplied rule to avoid exposing sensitive leave reasons.

Email presentation uses sandboxed Jinja templates stored with each database rule revision, with strict variables and HTML auto-escaping. The following files provide the initial templates:

1. `config/frappe-hr/email-templates/daily-absence-summary.html.j2`
2. `config/frappe-hr/email-templates/daily-absence-summary.txt.j2`

Select templates per rule with `templates.html` and `templates.text`. The `subject` field is also a Jinja template. Available values are:

1. `period.start`, `period.end`, and `period_label`.
2. `count` and `generated_at`.
3. `rule.id`.
4. `absences`, with `date`, `date_label`, `employee_id`, `employee_name`, `employee_email`, `type_label`, `duration`, `subunit`, `locations`, `locations_label`, and `status`.

Raw database rows are never passed to templates. When `include_leave_type` is false, `type_label` contains only `Leave`.

Development SMTP points to Mailpit by default. Test a rule without sending:

```bash
docker compose --env-file .env run --rm frappe-hr-leave-notifier \
  --run-now --rule daily-absence-summary --dry-run --force
```

Send a test even when no leave records match, then inspect it at `http://127.0.0.1:8025`:

```bash
docker compose --env-file .env --profile development up -d mailpit erpnext-db support-tools-db support-tools
docker compose --env-file .env run --rm frappe-hr-leave-notifier \
  --run-now --rule daily-absence-summary --send-empty --force
```

Start the continuous scheduler:

```bash
docker compose --env-file .env up -d frappe-hr-leave-notifier
docker compose --env-file .env logs -f frappe-hr-leave-notifier
```

Use `--date YYYY-MM-DD` to preview another date. `--force` intentionally bypasses duplicate protection and should only be used for testing or an approved resend.
The source JSON and template files are fallback seed material, not a deployment mechanism for later edits. Use the web app after initialization so PostgreSQL, revision history, and the runtime snapshot remain consistent.

Validate the production query and templates without printing employee details or sending email:

```bash
docker compose --env-file .env run --rm frappe-hr-leave-notifier \
  --run-now --rule daily-absence-summary --send-empty --validate-only --force
```

### Useful dev commands

1. Restart stack:
```bash
docker compose --profile development down && docker compose --profile development up -d
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

### NetBird

NetBird uses:

1. `netbird-server` for management, signal, relay, embedded authentication, and STUN.
2. `netbird-dashboard` for administration.
3. `netbird-data` for the SQLite stores and identity data.
4. Direct host UDP `${NETBIRD_STUN_PORT:-3478}` for STUN; HTTP, WebSocket, relay, and gRPC use `https://<NETBIRD_HOST>` through nginx.

Both NetBird images are pinned by immutable digest. Upgrade by reviewing a new release, replacing the two image digests, and testing the migration against a volume backup before production rollout.

Render and start NetBird:

```bash
./scripts/render_netbird_config.sh .env
docker compose --env-file .env up -d netbird-server netbird-dashboard
```

The first local owner is bootstrapped from `NETBIRD_ADMIN_EMAIL` and the bcrypt hash in `NETBIRD_ADMIN_PASSWORD_HASH_B64`. Keep `NETBIRD_ADMIN_PASSWORD` as the corresponding break-glass password. The hash is base64-encoded so Docker Compose does not interpolate bcrypt's `$` characters. After the services are reachable, configure the supported API and Keycloak integration idempotently:

```bash
./scripts/bootstrap_netbird_provisioning.sh .env
docker compose --env-file .env up -d --force-recreate support-tools
./scripts/sync_keycloak_redirects.sh .env
./scripts/configure_netbird_oidc.sh .env
```

The NetBird client requires both `employees` and `app-netbird`. Its token mapper emits only the hardcoded `app-netbird` group, preventing unrelated Keycloak groups from becoming NetBird policy groups. The OIDC configuration permits automatic JIT because this dual gate runs before registration. See [`docs/identity-provisioning-netbird-validation.md`](docs/identity-provisioning-netbird-validation.md) for the tested lifecycle and limitations.

Production prerequisites for NetBird:

1. Create an `A` record for `NETBIRD_HOST`. The default convention is `mesh.<BASE_DOMAIN>`. Add `AAAA` only when the host's IPv6 path is fully working.
2. Forward TCP `443` to nginx and UDP `3478` directly to the Docker host.
3. Add `NETBIRD_HOST` to `LETSENCRYPT_DOMAINS`. The certbot service uses `--expand` to add new SANs to the existing certificate.
4. Back up `netbird-data` and the source environment file containing `NETBIRD_DATASTORE_ENCRYPTION_KEY`; losing that key makes encrypted data unrecoverable. The generated `config/netbird/config.yaml` alone is not a substitute for the protected environment backup.
5. Validate Windows enrollment, direct peer connectivity, relay fallback, customer subnet routing, DNS, and least-privilege policies before onboarding customer systems.

When nginx runs in HTTP mode behind a separate TLS proxy, set `NETBIRD_SSO_HOST_IP` to that proxy's reachable IP. This container-only mapping lets NetBird perform Keycloak discovery and token exchange while retaining the public HTTPS issuer and certificate hostname.

Useful checks:

```bash
docker compose --env-file .env ps netbird-server netbird-dashboard
docker inspect support-netbird-dashboard --format '{{.State.Health.Status}}'
docker compose --env-file .env logs --tail=120 netbird-server netbird-dashboard
curl -fsS https://<NETBIRD_HOST>/api/instance
```

For the pfSense HAProxy h2c/WebSocket requirements, regression tests, failure
signatures, and the difference between TCP/22 and NetBird SSH policies, see
[`docs/netbird_proxy_and_ssh_runbook.md`](docs/netbird_proxy_and_ssh_runbook.md).

## 2. Production

### Step 1: Prepare production env

Back up both the `support-tools-db-data` PostgreSQL volume and the `support-tools-runtime` volume before upgrades. The database is authoritative; the runtime volume is a reproducible notifier snapshot, but retaining both simplifies rollback.

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
7. Keep `SUPPORT_PORTAL_OIDC_CLIENT_ID` dedicated to portal authentication (recommended: `support-portal`).

### Step 2: Preflight checks

1. Run production preflight:
```bash
./scripts/preflight_production.sh .env.production
```
2. Resolve any reported failures before continuing.

### Step 3: Deploy

1. Render generated configs from production env:
```bash
./scripts/render_netbird_config.sh .env.production
./scripts/render_keycloak_realm.sh .env.production
./scripts/render_portal_index.sh .env.production
```
2. Pull images:
```bash
docker compose --env-file .env.production pull
```
3. Start services:
```bash
docker compose --env-file .env.production up -d
```
4. Synchronize and harden Keycloak after it is ready. Existing realms are not overwritten by startup imports, so both idempotent scripts are required:
```bash
./scripts/sync_keycloak_redirects.sh .env.production
./scripts/harden_keycloak.sh .env.production
```
The hardening script enables the approved brute-force controls, requires TOTP enrollment for `platform-admin`, `support-engineer`, and `support-admin`, and assigns reviewed delegated roles to `platform-admin`. Members of `employees` alone are not required to enroll TOTP. Protected-group membership takes precedence when a user belongs to both group types, and the hardening script must be rerun after protected-group membership changes.
5. ERPNext/HRMS bootstrap is explicit. Stop the notifier before rerunning bootstrap during upgrades because bootstrap recreates its least-privilege database account:
```bash
docker compose --env-file .env.production stop frappe-hr-leave-notifier
docker compose --env-file .env.production --profile bootstrap up -d erpnext-configurator erpnext-create-site
docker compose --env-file .env.production logs -f erpnext-create-site
```
6. Start or refresh ERPNext runtime services:
```bash
docker compose --env-file .env.production up -d erpnext-backend erpnext-websocket erpnext-queue-short erpnext-queue-long erpnext-scheduler erpnext-frontend frappe-hr-leave-notifier
```
7. If bootstrap reports duplicate module errors but `bench list-apps` already shows `erpnext`, run recovery migrate:
```bash
docker compose --env-file .env.production exec -T erpnext-backend sh -lc \
'cd /home/frappe/frappe-bench && bench --site "<ERP_HOST>" migrate'
```
8. Verify ERPNext services are up:
```bash
docker compose --env-file .env.production ps erpnext-db erpnext-frontend erpnext-backend erpnext-websocket erpnext-queue-short erpnext-queue-long erpnext-scheduler
```
9. Recreate oauth2-proxy services after any OIDC/env changes:
```bash
docker compose --env-file .env.production up -d oauth2-proxy-portal
```
10. Recreate Seafile after first start or hostname/OIDC changes. The mounted init
    hook idempotently applies HTTPS service URLs, trusted origins, and Keycloak OAuth:
```bash
docker compose --env-file .env.production up -d --force-recreate seafile
```
11. If `NGINX_MODE=https` and `ENABLE_LETSENCRYPT=true`, wait for initial cert issuance and check logs:
```bash
docker compose --env-file .env.production logs --tail=120 certbot nginx
```

### Step 4: Verify

1. Check container health/logs:
```bash
docker compose --env-file .env.production ps
docker compose --env-file .env.production logs --tail=120
docker inspect support-netbird-dashboard --format '{{.State.Health.Status}}'
curl -fsS https://<NETBIRD_HOST>/api/instance
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
   - `https://<NETBIRD_HOST>`
   - `https://<TICKETS_HOST>`
   - `https://<CRM_HOST>`
   - `https://<HR_HOST>`
   - `https://<ERP_HOST>`
   - `https://<FILES_HOST>`
   - `https://<PENPOT_HOST>`
   - `https://<STATUS_HOST>`

### Keycloak upgrades and rollback

1. Pin `KEYCLOAK_IMAGE` to the reviewed immutable digest; do not deploy a mutable major/minor tag.
2. Before an upgrade, create protected backups of the Keycloak PostgreSQL database and the matching stack configuration/environment. Verify archive/database integrity and restrict permissions.
3. Rehearse the target image against an isolated restore with no published ports. Verify schema migration, OIDC discovery, realm access, and a controlled login.
4. Stop Keycloak, start the reviewed image, then run `scripts/sync_keycloak_redirects.sh` and `scripts/harden_keycloak.sh`. Recheck discovery, production profile, exact callback boundaries, privileged MFA state, and relying-application login entrypoints.
5. A migrated Keycloak database is not safely rolled back by selecting the old image. To roll back, stop Keycloak and restore both the pre-upgrade database and its matching configuration before starting the previous pinned image.

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
3. `./scripts/render_netbird_config.sh <env-file>`
   Render secret-bearing `config/netbird/config.yaml` and dashboard environment from the selected environment file.
4. `./scripts/render_keycloak_realm.sh <env-file>`
   Render `config/keycloak/realm-support.json` from template/env values.
5. `./scripts/render_portal_index.sh <env-file>`
   Render `nginx/html/index.html` portal links from env values and optional additions from `config/portal-links.json` (validated at render time).

### Keycloak and SSO

1. `./scripts/sync_keycloak_redirects.sh <env-file>`
   Sync exact HTTPS Keycloak client redirect URIs/web origins for NetBird, portal, Guacamole, BookStack, osTicket, EspoCRM, Frappe HR/ERPNext, Seafile, and Penpot. It also disables the retired OrangeHRM client when present and reconciles the `support-admin` role/group, the `employees` group, the portal `groups` claim mapper, and client-specific login gates without assigning users.
2. `./scripts/harden_keycloak.sh <env-file>`
   Apply approved brute-force protection, group-scoped TOTP for `platform-admin`, `support-engineer`, and `support-admin`, the `employees` exception, and delegated `platform-admin` controls idempotently.
3. `./scripts/check_osticket_keycloak.sh`
   Preflight check for osTicket OAuth2 plugin and Keycloak endpoint reachability.
4. `./scripts/install_osticket_oauth2_plugin.sh`
   Install osTicket OAuth2 plugin files into the expected path.
5. `./scripts/bootstrap_osticket_provisioning.sh <env-file>`
   Back up osTicket, validate the pinned schema, and create or validate the
   least-privilege `Support Agent` role before enabling agent provisioning.
6. `./scripts/configure_seafile_csrf.sh <env-file>`
   Recovery helper for Seafile URL/CSRF values. Normal deployments use the
   idempotent container startup hook, which also configures Keycloak OAuth.
7. `./scripts/bootstrap_netbird_provisioning.sh <env-file>`
   Create or reuse the dedicated NetBird provisioning service user and generate an
   expiring PAT in the selected environment file.
8. `./scripts/configure_netbird_oidc.sh <env-file>`
   Reconcile NetBird's Keycloak identity provider, restricted JWT group sync, and
   user-approval setting through the supported API.

### Certificates and TLS

1. `./scripts/regenerate_nginx_cert.sh <env-file>`
   Regenerate local/self-signed cert assets for nginx (dev/lab use).
2. `./scripts/check_active_cert.sh <hostname>`
   Show the currently served TLS cert details for a hostname.

### Seeding and bootstrap

1. `./scripts/seed_admin_accounts.sh`
   Seed admin/bootstrap accounts across integrated services.
2. `./scripts/grant_guacamole_admin.sh --env-file <env-file> --username <preferred_username>`
   Grant Guacamole administrator permissions to an existing Keycloak/OIDC identity. The username must exactly match the Keycloak `preferred_username` claim.
3. `./scripts/post_seed_vaultwarden_org.sh`
   Post-seed helper for Vaultwarden organization setup.
   See `docs/vaultwarden_operations.md` for approved sharing, recovery, offboarding, backup, and update instructions.
4. `./scripts/seed_uptime_kuma_monitors.sh <env-file>`
   Seed Uptime Kuma monitors for stack services.
### Production validation

1. `./scripts/preflight_production.sh .env.production`
   Run production readiness checks before deployment.
2. `./scripts/check_osticket_languages.sh`
   Verify expected osTicket language packs are available.

## 4. Portal Links JSON

Use [`config/portal-links.json`](/media/datahouse/projects/support-stack/config/portal-links.json) to add extra cards to the portal without changing existing built-in links.
Start by copying the example:

```bash
cp config/portal-links.example.json config/portal-links.json
```

Behavior:

1. Existing portal links remain unchanged.
2. JSON links are appended to matching sections (`Operations`, `Core Services`, `Identity & Mesh`).
3. If a JSON `section` does not exist, a new section is created automatically.
4. `enabled: false` hides a link.

Supported formats:

1. Object with `links` array (recommended).
2. Top-level array of links.

Each link supports:

1. `title` (required)
2. `url` (required, `http` or `https`)
3. `section` (optional, default: `Additional Links`)
4. `description` (optional)
5. `icon` (optional, up to 3 chars shown)
6. `enabled` (optional boolean, default: true)

Example:

```json
{
  "links": [
    {
      "id": "license-server",
      "section": "Core Services",
      "title": "License Server",
      "description": "License server for issuing and updating customer licenses",
      "url": "https://license.bonescreen.de",
      "icon": "LIC",
      "enabled": true
    }
  ]
}
```
