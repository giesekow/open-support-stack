# Support Tools Operations

## Purpose

Support Tools hosts internal automation configuration at `/automations`. Its first module manages Frappe HR leave-email rules, templates, previews, test messages, revision history, and publication to the notifier runtime.

## Access Control

Access requires both of the following:

1. A valid Keycloak session through the `support-portal` OIDC client.
2. Membership in the Keycloak group `support-admin`.

The group owns the realm role with the same name. The `support-portal` client emits memberships in the `groups` claim, oauth2-proxy returns them in `X-Auth-Request-Groups`, nginx replaces any browser-supplied identity headers, and Support Tools independently checks the required group.

Authentication without `support-admin` membership returns HTTP `403`. A missing authenticated identity returns HTTP `401`. The Docker health check uses the private `/internal/healthz` endpoint; the public `/automations/healthz` endpoint remains authorization-protected.

`platform-admin` and `support-admin` are deliberately separate. Platform administration does not automatically grant ongoing access to automation configuration. During the first production migration, existing `platform-admin` members may be copied once into `support-admin` to prevent lockout; later membership is managed independently.

## Grant Or Revoke Access

In the Keycloak Admin Console:

1. Select the `support` realm.
2. Open `Users`, select the user, and open `Groups`.
3. Join or leave the `support-admin` group.
4. Run `./scripts/harden_keycloak.sh .env.production` after granting membership so users without OTP are required to enroll at their next login.

The realm import keeps `CONFIGURE_TOTP` enabled but not realm-wide by default. The hardening script assigns it to members of `platform-admin`, `support-engineer`, and `support-admin`, and removes a pending TOTP action from ordinary `employees`. If a user belongs to both categories, the privileged-group requirement takes precedence.
5. Have the user sign out of the support portal and sign in again.

Existing oauth2-proxy sessions do not gain a newly assigned group until a new OIDC session is issued. The same applies after revocation, although administrators may also terminate the user's Keycloak sessions for immediate enforcement.

Do not assign the `support-admin` role directly to individual users. Group-based assignment keeps access review and removal consistent. `support-admin` is an MFA-protected group even when the same user is also in `employees`.

## Deployment And Reconciliation

Fresh realm imports receive the role, group, role mapping, and `support-portal` groups mapper from `config/keycloak/realm-support.template.json`.

Existing realms are reconciled idempotently with:

```bash
./scripts/render_keycloak_realm.sh .env.production
./scripts/sync_keycloak_redirects.sh .env.production
docker compose --env-file .env.production up -d --build support-tools oauth2-proxy-portal nginx
```

The sync script creates missing access-control objects but does not add users to `support-admin`. This prevents later deployments from silently granting access.

Production must keep:

```dotenv
SUPPORT_TOOLS_ALLOWED_GROUP=support-admin
SUPPORT_TOOLS_DEV_AUTH_BYPASS=false
```

Provisioning retention policy is configured in days:

```dotenv
PROVISIONING_JIT_REVIEW_AFTER_DAYS=7
PROVISIONING_AUDIT_RETENTION_DAYS=730
PROVISIONING_OPERATIONAL_LOG_RETENTION_DAYS=90
PROVISIONING_CLOSED_REVIEW_RETENTION_DAYS=730
```

All four values must be positive integers. `/internal/readyz` reports the active
JIT threshold as `jit_review_after_days` and retention values under `retention`;
startup fails on invalid configuration. The JIT threshold moves an unchanged
`awaiting_first_login` action to `manual_review` after the configured period. It
does not disable the user, revoke eligibility, or delete/create a target account.
The retention values
define the approved policy but do not currently delete database rows or rotate the
container runtime's logs. Cleanup remains manual until a separately tested and
audited cleanup process is approved. Configure host/container log rotation to honor
the operational-log period.

Run `./scripts/preflight_production.sh .env.production` before deployment. It rejects a different or missing group and rejects the development authentication bypass.

## Verification

Validate the application authorization from inside the Docker network:

```bash
# Expected: 401
curl -i http://support-tools:8000/automations/healthz

# Expected: 403
curl -i \
  -H 'X-Auth-Request-Email: engineer@example.com' \
  -H 'X-Auth-Request-Groups: support-engineer' \
  http://support-tools:8000/automations/healthz

# Expected: 200
curl -i \
  -H 'X-Auth-Request-Email: admin@example.com' \
  -H 'X-Auth-Request-Groups: support-admin' \
  http://support-tools:8000/automations/healthz
```

These synthetic headers are suitable only for container-internal verification. The service has no published host port, and external traffic must pass through nginx and oauth2-proxy.

For an end-to-end check, sign in as one user in `support-admin` and one authenticated user outside it. The first must reach `/automations`; the second must receive `403`.

## Troubleshooting

1. `403` immediately after access was granted: sign out and back in so the OIDC token contains the new group.
2. Every authenticated user receives `403`: rerun `scripts/sync_keycloak_redirects.sh`, recreate oauth2-proxy, and verify the `support-portal` client has the `groups` mapper.
3. Container is unhealthy: check `docker compose logs support-tools support-tools-db`; Docker checks `/internal/healthz`, so Keycloak is not involved.
4. `401` from an external request: verify nginx auth subrequests and oauth2-proxy, not group membership.
5. Never enable `SUPPORT_TOOLS_DEV_AUTH_BYPASS` in production.

## Identity Provisioning

The provisioning control plane is available to `support-admin` users at `/automations/provisioning`. It stores source identities by the immutable OIDC `(issuer, sub)` pair, target links, reconciliation runs, reviewable actions, and append-only audit events.

Restricted targets require both `employees` and their application group: `app-erpnext`, `app-netbird`, `app-guacamole`, `app-osticket-agent`, or `app-vaultwarden`. These groups are created empty; synchronization never assigns users.

All targets are seeded **disabled** and **dry-run only**. The two independent write controls are:

```dotenv
PROVISIONING_ALLOW_WRITES=false
```

and each target's `Dry-run only` switch. An action can execute only when the global gate is `true`, the target dry-run switch is off, the source snapshot is still current, the user remains eligible, and an administrator supplies an approval reason. Keep the global gate `false` until validation is approved. Scheduled scans additionally require `PROVISIONING_ENABLED=true`; manual reconciliation remains available for controlled testing.

The initial adapters are:

- BookStack: verifies JIT-created users and can safely link one unique existing email to the Keycloak subject. It does not create users.
- EspoCRM: verifies native OIDC JIT users by immutable Keycloak subject and supports
  guarded disable/reactivate with exact auth-token invalidation. It never changes
  CRM roles, teams, records, assignments, or ownership.
- ERPNext: verifies native JIT-created Website Users, links legacy username-based
  social-login records only after an exact reviewed match, and supports guarded
  disable/reactivate with MariaDB and Redis session revocation. It does not create
  users or grant ERPNext roles.
- Seafile: verifies native OAuth JIT users linked by Keycloak subject and supports
  guarded disable/reactivate. It does not create users, groups, organizations,
  libraries, shares, or permissions.
- Penpot: verifies native OIDC JIT profiles by immutable Keycloak subject, supports
  guarded verified-email/name migration and disable/reactivate, and never changes
  shared teams, projects, files, invitations, roles, or ownership.
- NetBird: verifies external-IdP JIT users by the Keycloak subject encoded in the
  NetBird user ID and supports guarded block/reactivate. It preserves synchronized
  groups and peer ownership and never creates routes, policies, setup keys, or peers.
- Vaultwarden: creates one native organization User invitation for an exact verified
  email with no groups, collections, custom permissions, or access-all flag. The user
  accepts and an owner/admin confirms the membership in Vaultwarden; automation never
  receives a master password or performs client-side encryption. Offboarding deletes
  only the exact organization membership and preserves the personal vault.
- Frappe HR / ERPNext: discovers and safely links the Keycloak JIT-created Frappe user. HR master-data creation is performed with `scripts/onboard_frappe_hr_employee.sh` because employee number, company, gender, date of birth, and joining date require reviewed HR values.
- Guacamole: creates a PostgreSQL identity with random unusable credential material,
  grants no permissions, and supports guarded disable/reactivate while protecting
  `guacadmin` and every identity with `ADMINISTER`.
- osTicket: creates only a non-admin Support Agent in the Support department with
  the approved reply-only role and no local password, team, or extra department.

### Keycloak Service Account

Generate/render configuration and reconcile the realm:

```bash
./scripts/render_keycloak_realm.sh .env
./scripts/configure_provisioning_keycloak_client.sh .env
./scripts/sync_keycloak_redirects.sh .env
```

The `support-tools-provisioning` confidential client receives only `view-users`, `query-users`, and `query-groups` from Keycloak's `realm-management` client. It has no user, credential, group, role, or client mutation permission. The dedicated configuration script fails if it observes any additional realm-management role. Rotate `PROVISIONING_KEYCLOAK_CLIENT_SECRET` by changing the environment value, rerunning the provisioning-client configuration script, and recreating Support Tools.

### Safe Local Test

```bash
docker compose up -d --build support-tools
./scripts/sync_keycloak_redirects.sh .env
docker compose up -d --force-recreate support-tools
```

1. Keep `PROVISIONING_ALLOW_WRITES=false`.
2. Open `/automations/provisioning` as a `support-admin` user.
3. Enable only one validated adapter target and retain `Dry-run only`.
4. Select `Reconcile now`.
5. Review identities, plans, conflicts, adapter errors, and the run summary.
6. Do not open the write gate until schema compatibility, backup, and action output have been approved.

### Vaultwarden Invitation Controls

1. Create a dedicated Vaultwarden account that is not assigned to Keycloak
   provisioning groups. Confirm it as an organization Admin, not an Owner unless the
   deployment has a separately approved reason.
2. In that account, open `Settings > Security > Keys`, select `View API key`, and
   place its `client_id` and `client_secret` in the environment. A personal API key
   bypasses Vaultwarden 2FA, so store it as a secret, never print it, and rotate it
   immediately if exposed.
3. Set `PROVISIONING_VAULTWARDEN_ORGANIZATION_ID` to the organization UUID and
   `PROVISIONING_VAULTWARDEN_DEVICE_IDENTIFIER` to one persistent generated UUID.
   Add the service account email to `PROVISIONING_VAULTWARDEN_PROTECTED_EMAILS`.
4. Recreate Support Tools and confirm `/internal/readyz` reports the Vaultwarden
   adapter ready. Keep the target disabled and dry-run until the lifecycle checklist
   in `identity-provisioning-vaultwarden-validation.md` passes.
5. The adapter stores only the short-lived bearer token in memory. Vaultwarden's
   token response also contains encrypted account material, which is discarded and
   covered by audit redaction.
6. Invitation acceptance, master-password setup/unlock, and membership confirmation
   remain in the Vaultwarden clients. Confirmation requires client-generated encrypted
   organization-key material and is deliberately outside this automation.

### Repeatable Lifecycle Test

Run the unit and disposable-PostgreSQL reconciliation suite with:

```bash
./scripts/test_identity_provisioning.sh .env
```

The script creates a temporary `support_tools_reconciliation_test` database, migrates it from empty, runs all lifecycle tests, and removes the database through an exit trap. It never enables application writes or contacts production.

### Failure Safety

- An unavailable Keycloak source fails the run before source tombstones are created.
- A target failure is isolated and recorded without stopping other targets.
- Repeated source and target state deduplicates currently actionable work. A later
  lifecycle cycle may create the same semantic action again after the prior action
  becomes terminal; historical actions remain immutable audit evidence.
- Changed source state or target configuration makes an earlier action stale.
- Reconcile again after changing dry-run, eligibility, adapter, or target settings; configuration changes generate a new plan.
- An action is marked `executing` before its adapter runs and cannot be executed twice.
- Failed writes become `retryable` until the target retry limit is reached, then move to `manual_review`.
- JIT actions still awaiting first login after the configured period move once to
`manual_review` and emit `jit.first_login_review_required`; subsequent scans do
  not duplicate the event. Eligibility loss supersedes the waiting action instead.
- Every attempt records actor, correlation ID, redacted result/error, and timestamps.
- `/internal/healthz` proves process/database liveness; `/internal/readyz` separately reports scheduler, write gate, adapters, and the latest run.
- Database writes use exact-column schema guards, transactions, and read-back discovery.
- Built-in administrators and break-glass accounts must remain outside eligibility groups and automated matching.
- Frappe HR/ERPNext, BookStack, Seafile, Penpot, NetBird and osTicket also enforce role-based protected-account checks during
  discovery and execution. Additional stable IDs, usernames and emails can be
  supplied with the `PROVISIONING_<TARGET>_PROTECTED_*` variables documented in
  [Identity Provisioning Technical Inventory](identity_provisioning_technical_inventory.md).

### osTicket Agent Controls

- Run `./scripts/bootstrap_osticket_provisioning.sh <env-file>` before enabling
  osTicket reconciliation. It backs up the database, validates the pinned schema,
  and creates or validates the `Support Agent` role with only `ticket.reply`.
- The adapter creates staff agents only. It never writes customer users, teams,
  extra department access, administrator flags, API keys, or local passwords.
- Login requires both `employees` and `app-osticket-agent` through the
  client-specific Keycloak browser flow.
- Existing agents are linked only by exact `preferred_username` plus verified
  email. Email-only matches and authorization drift stop for manual review.
- Disable preserves tickets and assignments, marks only the exact agent inactive,
  and removes only sessions for that staff ID.
- Any schema signature change blocks adapter operations until revalidation.

### BookStack JIT Controls

- `BOOKSTACK_DEFAULT_REGISTRATION_ROLE=Viewer` is resolved by role name at startup;
  the container fails closed if the role is absent or ambiguous.
- `BOOKSTACK_SESSION_DRIVER=database` makes per-user session revocation possible.
- `sync_keycloak_redirects.sh` maps the `employees` group to its eligibility role
  and binds BookStack to an employees-only browser flow. Ineligible users are
  denied by Keycloak before BookStack can create an account.
- BookStack links OIDC users by `users.external_auth_id = Keycloak sub`. It does
  not synchronize changed name/email values on later login in the pinned version.
- Offboarding preserves the BookStack account, roles, content, and immutable link;
  it blocks new login through Keycloak and removes only that user's BookStack
  database sessions.

### EspoCRM JIT Controls

- EspoCRM access requires `employees`. The client-specific Keycloak browser flow
  denies users without that role before EspoCRM can exchange an authorization code
  or create a user.
- EspoCRM's supported `ESPOCRM_CONFIG_*` startup settings enable OIDC JIT, use
  Keycloak `sub` as `oidcUsernameClaim`, and synchronize verified email/name.
- JIT creates only a `regular` user. Team synchronization is disabled, so no role,
  team, record permission, assignment, or ownership is granted automatically.
- Local fallback remains enabled for break-glass administration, but regular users
  cannot use it and OIDC login to administrator accounts is disabled.
- The adapter matches only `user.user_name = Keycloak sub`. A unique email without
  that subject is a conflict and is never linked automatically.
- Offboarding sets only `user.is_active=false` and invalidates active `auth_token`
  rows for that exact user. Roles, teams, records, assignments, and ownership are
  preserved. Reactivation does not restore old tokens; a fresh OIDC login is needed.
- Before and after lifecycle writes, role and team ID sets must be identical. Any
  drift rolls back the transaction and requires manual review.

### ERPNext JIT Controls

- ERPNext access requires both `employees` and `app-erpnext`. The synchronization
  script binds the client to two fail-closed Keycloak role gates after password and
  conditional OTP, so either missing role denies login before JIT creation.
- The Social Login Key stores `Keycloak sub`, not username. Exact legacy links that
  stored `preferred_username` can be migrated only when username and verified email
  both match; ambiguous links stop for review.
- JIT creates a standard `Website User` with no automatic ERPNext business roles.
  `Administrator`, `Guest`, and any user with `Administrator` or `System Manager`
  are excluded from automation.
- A source email change for an existing subject returns `manual_review`. Administrators
  must review the target email migration before permitting another login, preventing
  an unintended duplicate account.
- Offboarding sets only `tabUser.enabled=0`, removes that user's `tabSessions` rows,
  and deletes the same session IDs from the site-prefixed Redis session hashes.
  Business records, roles, ownership, and the immutable social-login link remain.
- Support Tools reads the generated database name and credential from the read-only
  mounted ERPNext `site_config.json`; no database credential is duplicated in its
  environment.

### Seafile JIT Controls

- The Seafile startup hook writes an idempotent managed block to
  `seahub_settings.py`. Browser authorization uses the public HTTPS Keycloak URL;
  token and user-info requests use Keycloak's private Docker-network endpoint.
- Seafile access requires `employees`. The client-specific Keycloak browser flow
  denies users without that role before Seafile's callback can create an account.
- `OAUTH_ATTRIBUTE_MAP` maps Keycloak `sub` to Seafile `uid`. Email and name are
  profile metadata and may update on later login without changing the internal
  account or repository ownership.
- JIT creates a non-staff active account, one personal library, and no automatic
  Seafile group or organization memberships.
- Offboarding sets only `ccnet_db.EmailUser.is_active=0`, deletes exact Django
  sessions belonging to the internal username, and revokes exact user-owned API,
  client-login, SSO, and device tokens. Repositories, shares, groups, organizations,
  and ownership are not changed.
- Support Tools reads Seafile's generated database connection from a read-only
  mount of `seahub_settings.py`; the generated password is not duplicated in its
  environment.

### Penpot JIT Controls

- Penpot access requires `employees`. The client-specific Keycloak browser flow
  denies users without that role before the callback can create a profile.
- Browser authorization uses public HTTPS. Token and user-info requests use
  `keycloak:8080`; Penpot's SSRF allowlist contains only `keycloak` and the public
  SSO hostname.
- Keep `PENPOT_OIDC_USER_INFO_SOURCE=userinfo`. Penpot 2.15.3 stores the returned
  Keycloak subject in `profile.props["~:oidc/sub"]`, which is the adapter's stable
  identity key.
- JIT creates an active OIDC profile plus its personal default team and project.
  It does not add the user to existing shared teams/projects or assign files.
- A changed verified email/name produces a guarded `update` action matched by
  profile UUID and OIDC subject. Apply it before the user's next Penpot login to
  prevent Penpot's native email lookup from creating a duplicate profile.
- Offboarding sets only `profile.is_active=false`, removes exact v1/v2 HTTP
  sessions, and revokes profile access tokens. Teams, projects, files,
  invitations, roles, and ownership remain unchanged.

### NetBird JIT Controls

- NetBird access requires both `employees` and `app-netbird`. The client-specific
  Keycloak browser flow denies users missing either role before the Management API
  can complete JIT registration.
- NetBird receives a hardcoded `groups=["app-netbird"]` claim. Other Keycloak
  groups, including administrative groups, cannot become NetBird policy groups.
- `PROVISIONING_NETBIRD_REQUIRE_USER_APPROVAL=false` permits automatic JIT only
  because Keycloak applies both eligibility gates before registration.
- The adapter matches the immutable Keycloak subject encoded in NetBird's composite
  user ID. NetBird's `idp_id` identifies the connector and is not the user subject.
- NetBird 0.79 does not refresh display email/name on repeat OIDC login. Those fields
  are not matching keys; changes do not create or relink accounts automatically.
- Offboarding sets the supported `is_blocked` flag. Existing bearer tokens are
  retained but return `403` while blocked. Reactivation re-enables the same account.
- Before and after block/reactivate, synchronized group IDs and owned peer IDs must
  be identical. Any drift fails closed and requires manual review.
- Create the dedicated service user and PAT, then configure OIDC idempotently:

```bash
./scripts/bootstrap_netbird_provisioning.sh .env
docker compose --env-file .env up -d --force-recreate support-tools
./scripts/sync_keycloak_redirects.sh .env
./scripts/configure_netbird_oidc.sh .env
```

- PAT lifetime is configured by `PROVISIONING_NETBIRD_TOKEN_DAYS` and cannot exceed
  365 days. Re-running the bootstrap leaves a valid PAT unchanged; rotate it under
  change control before expiry and recreate Support Tools after rotation.
