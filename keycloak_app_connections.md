# Keycloak App Connections

This document describes how to connect the main support apps to Keycloak OIDC, including redirect URI setup and user attribute/field mapping behavior.

## Common Prerequisites

1. Keycloak realm exists (for this stack: `support`).
2. App hostname is reachable from browser and from containers.
3. Keycloak client exists with correct redirect URI and web origin.
4. If using local/dev TLS with custom CA, app containers must trust that CA.

---

## osTicket

### Keycloak Client

1. `clientId`: `osticket` (or your configured `OSTICKET_OIDC_CLIENT_ID`)
2. Login eligibility: users must belong to both `employees` and
   `app-osticket-agent`; `sync_keycloak_redirects.sh` binds the client to the
   `osticket-agent-eligible-browser` flow.
3. `Client authentication`: `On` (confidential client)
4. `Valid redirect URIs`:
   - `https://<TICKETS_HOST>/api/auth/oauth2`
5. `Web origins`:
   - `https://<TICKETS_HOST>`

### osTicket Plugin Configuration

1. `Authorization URL`:
   - `https://<SSO_HOST>/realms/<REALM>/protocol/openid-connect/auth`
2. `Token URL`:
   - `https://<SSO_HOST>/realms/<REALM>/protocol/openid-connect/token`
3. `UserInfo URL`:
   - `https://<SSO_HOST>/realms/<REALM>/protocol/openid-connect/userinfo`
4. `Client ID`/`Client Secret`: must match Keycloak client.
5. Scope:
   - `openid profile email`

### Mapping Notes

1. Typical mapping:
   - `email` -> agent email
   - `preferred_username` or `name` -> display/login fields (plugin-dependent)
2. If login works but account is not found, verify plugin-side claim mapping and existing agent records.

---

## Frappe HR / ERPNext

Frappe HR is installed in the existing ERPNext site and uses the existing `erpnext` Keycloak client. Do not create a separate HR client.

1. `clientId`: `erpnext` (or `ERPNEXT_OIDC_CLIENT_ID`).
2. Valid callback: `https://<ERP_HOST>/api/method/frappe.integrations.oauth2_logins.login_via_keycloak`.
3. Web origin: `https://<ERP_HOST>`.
4. Eligibility: membership in the Keycloak `employees` group.
5. Keycloak login creates or matches the Frappe `User`; it does not create an HR `Employee` record.
6. Link reviewed employee master data with `scripts/onboard_frappe_hr_employee.sh --env-file <ENV_FILE> ...` after the user has logged in once.

The former `hr.<domain>` hostname redirects permanently to `ERP_HOST`, and the synchronization script disables the retired `orangehrm` client when it exists. Keep the old OrangeHRM database volume only for the approved migration/rollback retention period.

---

## EspoCRM

### Keycloak Client

1. `clientId`: `espocrm` (or `ESPOCRM_OIDC_CLIENT_ID`)
2. `Client authentication`: `On`
3. `Valid redirect URIs`:
   - `https://<CRM_HOST>/oauth-callback.php`
   - optionally `https://<CRM_HOST>/*`
4. `Web origins`:
   - `https://<CRM_HOST>`

### EspoCRM OIDC Configuration

1. Issuer:
   - `https://<SSO_HOST>/realms/<REALM>`
2. Authorization endpoint:
   - `https://<SSO_HOST>/realms/<REALM>/protocol/openid-connect/auth`
3. Token endpoint:
   - `https://<SSO_HOST>/realms/<REALM>/protocol/openid-connect/token`
4. UserInfo endpoint:
   - `https://<SSO_HOST>/realms/<REALM>/protocol/openid-connect/userinfo`
5. JWKS endpoint:
   - `https://<SSO_HOST>/realms/<REALM>/protocol/openid-connect/certs`

### Mapping Notes

Typical mapping:

1. `email` -> Espo email
2. `given_name` -> first name
3. `family_name` -> last name
4. `sub` -> username and immutable external-identity link

The stack configures these controls through supported `ESPOCRM_CONFIG_*`
environment variables:

1. JIT user creation and profile synchronization are enabled.
2. Team synchronization is disabled.
3. New identities are regular users with no roles or teams.
4. Keycloak requires `employees` before issuing the authorization code.
5. Local fallback is restricted to the break-glass administrator; regular users
   cannot bypass Keycloak.

If callback URL appears wrong in Espo UI, verify Espo base URL/site URL setting and restart container.

---

## Guacamole

### Keycloak Client

1. `clientId`: `guacamole` (or `GUACAMOLE_OPENID_CLIENT_ID`)
2. Client type can be public or confidential based on your Guacamole extension config.
3. `Valid redirect URIs`:
   - `https://<REMOTE_HOST>/guacamole/*`
4. `Web origins`:
   - `https://<REMOTE_HOST>`

### Guacamole OIDC/OpenID Settings

Common fields:

1. Authorization endpoint:
   - `https://<SSO_HOST>/realms/<REALM>/protocol/openid-connect/auth`
2. Token endpoint:
   - `https://<SSO_HOST>/realms/<REALM>/protocol/openid-connect/token`
3. JWKS endpoint:
   - `https://<SSO_HOST>/realms/<REALM>/protocol/openid-connect/certs`
4. Logout endpoint:
   - `https://<SSO_HOST>/realms/<REALM>/protocol/openid-connect/logout`
5. Redirect URI:
   - `https://<REMOTE_HOST>/guacamole/`

### Mapping Notes

1. Username claim usually `preferred_username`.
2. If forcing fresh login each time is desired, append prompt behavior at auth request level (`prompt=login`) where supported.
3. The PostgreSQL-backed Guacamole user must have exactly the same username as the `preferred_username` claim. Otherwise OIDC authentication succeeds, but database connections and administrative permissions are not attached to the session.
4. To grant an existing Keycloak identity Guacamole administrator access without using the local `guacadmin` login:
   ```bash
   ./scripts/grant_guacamole_admin.sh \
     --env-file .env.production \
     --username '<preferred_username>'
   ```

---

## BookStack

### Keycloak Client

1. `clientId`: `bookstack` (or `BOOKSTACK_OIDC_CLIENT_ID`)
2. `Client authentication`: `On`
3. `Valid redirect URIs`:
   - `https://<DOCS_HOST>/oidc/callback`
   - optionally `https://<DOCS_HOST>/*`
4. `Web origins`:
   - `https://<DOCS_HOST>`

### BookStack OIDC Environment

1. `AUTH_METHOD=oidc`
2. `OIDC_ISSUER=https://<SSO_HOST>/realms/<REALM>`
3. `OIDC_CLIENT_ID=<bookstack-client-id>`
4. `OIDC_CLIENT_SECRET=<bookstack-client-secret>`
5. `OIDC_ISSUER_DISCOVER=true` (recommended)

If discovery is disabled, configure all endpoints manually and set `OIDC_PUBLIC_KEY` if required by your mode.

When TLS is terminated by an upstream reverse proxy, set `BOOKSTACK_OIDC_HOST_IP` to that proxy's reachable IP. The BookStack-only host override keeps the public HTTPS issuer name and certificate validation intact while avoiding Docker's internal nginx alias, which may listen only on HTTP in this mode.

### Mapping Notes

1. `OIDC_DISPLAY_NAME_CLAIMS=name` is a good default.
2. Email claim is used for account linkage/creation behavior based on BookStack auth settings.
3. Error `Missing required configuration "keys"` usually indicates incorrect discovery/manual key setup.

---

## ERPNext

### Keycloak Client

1. `clientId`: `erpnext` (or `ERPNEXT_OIDC_CLIENT_ID`)
2. `Client authentication`: `On`
3. `Valid redirect URIs`:
   - `https://<ERP_HOST>/*`
4. `Web origins`:
   - `https://<ERP_HOST>`

### ERPNext Provider Configuration

Run the idempotent helper after the ERPNext site has been bootstrapped:

```bash
./scripts/configure_erpnext_oidc.sh .env.production
```

The helper configures Frappe's native Keycloak provider with `openid profile email` and enables social signup. It deliberately splits the endpoints:

1. Browser authorization: `https://<SSO_HOST>/realms/<REALM>/protocol/openid-connect/auth`
2. Container token exchange: `http://keycloak:8080/realms/<REALM>/protocol/openid-connect/token`
3. Container user info: `http://keycloak:8080/realms/<REALM>/protocol/openid-connect/userinfo`

This keeps browser authentication on public HTTPS while avoiding reverse-proxy TLS hairpin and certificate-chain failures for server-side requests inside Docker.

### Mapping Notes

1. The immutable Keycloak `sub` claim is the provider user identifier. Existing
   legacy links that stored `preferred_username` require reviewed migration and
   are never reassigned automatically.
2. `email`, `given_name`, and `family_name` populate the Frappe user profile.
3. New Keycloak users are created in ERPNext because the provider's `sign_ups` setting is `Allow`.

---

## NetBird

NetBird uses its embedded local identity provider for a break-glass owner, while Keycloak is configured as the primary external identity provider.

### Keycloak Client

1. `clientId`: `netbird` (or `NETBIRD_OIDC_CLIENT_ID`)
2. `Client authentication`: `On`
3. `Standard flow`: `On`
4. Valid redirect URI: the exact value of `NETBIRD_OIDC_REDIRECT_URI`: `https://<NETBIRD_HOST>/oauth2/callback`
5. Valid post-logout redirect URI: `https://<NETBIRD_HOST>/oauth2/logout/callback`
6. Web origin: `https://<NETBIRD_HOST>`

`scripts/sync_keycloak_redirects.sh` creates or updates this client and adds a group-membership mapper named `groups`. Keep `NETBIRD_OIDC_REDIRECT_URI` on the stable `/oauth2/callback` endpoint sent by the current self-hosted NetBird login flow. Wildcards and connector-specific callback suffixes are not used.

### NetBird Provider Configuration

1. Sign in using `NETBIRD_ADMIN_EMAIL` and `NETBIRD_ADMIN_PASSWORD`.
2. Open `Settings → Identity Providers → Add Identity Provider`.
3. Select `Keycloak` or `Generic OIDC`.
4. Name: `Keycloak`.
5. Client ID: value of `NETBIRD_OIDC_CLIENT_ID`.
6. Client secret: value of `NETBIRD_OIDC_CLIENT_SECRET`.
7. Issuer URL: `https://<SSO_HOST>/realms/<KEYCLOAK_REALM>`.
8. Save, log out, and verify the Keycloak login button.

### Claim Mapping

1. Keycloak `sub` becomes the stable external identity.
2. Keycloak `email`, `name`, and `preferred_username` populate the NetBird user.
3. Keycloak group membership is emitted as the `groups` claim.
4. Optional NetBird JWT group sync uses claim name `groups`.
5. Configure a JWT allow-group before broad user onboarding if only selected Keycloak users should access NetBird.

Do not remove the local owner until Keycloak login, account ownership, and recovery procedures have all been tested. Retaining one protected local owner is recommended.

---

## Quick Validation Commands

1. Sync configured redirect URIs for stack clients:
```bash
./scripts/sync_keycloak_redirects.sh .env
```

2. Render Keycloak realm from template:
```bash
./scripts/render_keycloak_realm.sh .env
```

3. Check Keycloak client existence:
```bash
docker compose --env-file .env exec -T keycloak \
  /opt/keycloak/bin/kcadm.sh get clients -r support -q clientId=<client-id>
```

4. For Frappe HR / ERPNext OIDC errors:
```bash
docker compose --env-file .env logs --tail=120 erpnext-backend
docker compose --env-file .env exec -T erpnext-backend \
  bench --site "$ERPNEXT_SITE_NAME" list-apps
```

---

## Support Portal And Support Tools

### Keycloak Client

1. `clientId`: `support-portal` (or `SUPPORT_PORTAL_OIDC_CLIENT_ID`).
2. Client authentication: `On`.
3. Valid redirect URI: `https://<SUPPORT_HOST>/oauth2/callback`.
4. Web origin: `https://<SUPPORT_HOST>`.
5. Protocol mapper `groups`: group-membership mapper with full group paths disabled and the claim included in ID, access, and user-info tokens.

### Authorization Model

The portal accepts any authenticated account for its general landing page, but `/automations` additionally requires the `support-admin` group. This separation prevents ordinary Keycloak users and support engineers from changing automation recipients, schedules, or email content.

`scripts/sync_keycloak_redirects.sh` idempotently creates:

1. Realm role `support-admin`.
2. Group `support-admin`.
3. The realm-role assignment on that group.
4. The `groups` claim mapper on `support-portal`.

The sync script intentionally does not assign users. Manage access in `Users -> <user> -> Groups` in the Keycloak Admin Console. After joining or leaving the group, the user must sign out of the support portal and sign in again so oauth2-proxy receives a fresh token. Terminate the user's Keycloak sessions when a revocation must take effect immediately.

Keep `SUPPORT_TOOLS_ALLOWED_GROUP=support-admin` and `SUPPORT_TOOLS_DEV_AUTH_BYPASS=false` in production. Detailed deployment, verification, and troubleshooting steps are in `docs/support_tools_operations.md`.


### Realm Group MFA Policy

The managed support realm uses group-scoped TOTP rather than realm-wide enrollment:

1. `platform-admin`, `support-engineer`, and `support-admin` require TOTP.
2. Members of `employees` alone do not require TOTP.
3. If a user belongs to `employees` and any protected group, the protected group takes precedence.
4. Existing OTP credentials are never removed from employees; the policy only avoids mandatory enrollment for employees-only accounts.
5. Run `./scripts/sync_keycloak_redirects.sh <env-file>` before `./scripts/harden_keycloak.sh <env-file>` on fresh deployments and after protected-group membership changes.

The realm template includes both managed groups, the sync script creates them idempotently in existing realms, and the hardening script disables global default TOTP enrollment before applying `CONFIGURE_TOTP` to protected-group members.
