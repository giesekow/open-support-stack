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
2. `Client authentication`: `On` (confidential client)
3. `Valid redirect URIs`:
   - `https://<TICKETS_HOST>/auth/oauth2`
   - optionally `https://<TICKETS_HOST>/*`
4. `Web origins`:
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

## OrangeHRM

### Keycloak Client

1. `clientId`: `orangehrm` (or `ORANGEHRM_OIDC_CLIENT_ID`)
2. `Client authentication`: `On`
3. `Valid redirect URIs`:
   - `https://<HR_HOST>/*`
   - `https://<HR_HOST>/web/index.php/openidauth/*`
   - `https://<HR_HOST>/index.php/openidauth/*`
4. `Web origins`:
   - `https://<HR_HOST>`

### OrangeHRM Provider Configuration

In OrangeHRM `Admin -> Configuration -> Social Media Authentication`:

1. `Name`: e.g. `Keycloak`
2. `Provider URL`:
   - preferred in this stack: `http://<SSO_HOST>/realms/<REALM>` (container-internal reachability)
   - use `https://<SSO_HOST>/realms/<REALM>` only if OrangeHRM container can reach `443` and trusts your cert chain
3. `Client ID`: `orangehrm`
4. `Client Secret`: must match Keycloak

Notes:

1. OrangeHRM performs OIDC discovery server-side from inside the container.
2. Keep the provider URL on the SSO hostname so discovery returns Keycloak's public HTTPS issuer and authorization endpoint.
3. Set `ORANGEHRM_OIDC_INTERNAL_BASE_URI=http://keycloak:8080/realms/<REALM>` in the stack environment. The startup patch uses this internal base only for the token, user-info, and JWKS requests made by OrangeHRM inside Docker.
4. This split is required when the browser can reach public HTTPS but the OrangeHRM container cannot connect back to the reverse proxy on port `443`.
5. The patch is idempotently applied from `config/orangehrm/patch-oidc-internal-endpoints.php` whenever the OrangeHRM container starts.

### Mapping Notes (Important)

OrangeHRM OIDC plugin uses `userinfo.email` as the login lookup value, then matches it against OrangeHRM `username`.

Effective mapping:

1. Keycloak `email` claim -> OrangeHRM `ohrm_user.user_name`

This means OrangeHRM must have a user whose **username equals the Keycloak account email**.

Example:

1. Keycloak user email: `giles.tetteh@tum.de`
2. OrangeHRM username must be: `giles.tetteh@tum.de`

### Common Errors

1. `500` on `/openidauth/openIdCredentials/...`:
   - container cannot reach SSO host or TLS trust issue.
   - the browser redirect may work while the callback fails if OrangeHRM cannot reach the discovered HTTPS token endpoint; verify `ORANGEHRM_OIDC_INTERNAL_BASE_URI` is present in the container.
   - check `/var/www/html/src/log/orangehrm.log`; common errors are:
     - `Failed to connect ... port 443`
     - `SSL certificate problem: unable to get local issuer certificate`
2. `No User Found`:
   - no OrangeHRM username matching Keycloak `email`.

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
4. `preferred_username` -> username

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

1. `preferred_username` is the provider user identifier.
2. `email`, `given_name`, and `family_name` populate the Frappe user profile.
3. New Keycloak users are created in ERPNext because the provider's `sign_ups` setting is `Allow`.

---

## NetBird

NetBird uses its embedded local identity provider for a break-glass owner, while Keycloak is configured as the primary external identity provider.

### Keycloak Client

1. `clientId`: `netbird` (or `NETBIRD_OIDC_CLIENT_ID`)
2. `Client authentication`: `On`
3. `Standard flow`: `On`
4. Valid redirect URI: `https://<NETBIRD_HOST>/oauth2/callback/*`
5. Valid post-logout redirect URI: `https://<NETBIRD_HOST>/oauth2/logout/callback`
6. Web origin: `https://<NETBIRD_HOST>`

`scripts/sync_keycloak_redirects.sh` creates or updates this client and adds a group-membership mapper named `groups`. The wildcard is limited to NetBird's dynamic connector callback path; NetBird assigns the final connector ID when the provider is saved.

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

4. For OrangeHRM OIDC errors:
```bash
docker compose --env-file .env exec -T orangehrm \
  sh -lc 'tail -n 120 /var/www/html/src/log/orangehrm.log'
```
