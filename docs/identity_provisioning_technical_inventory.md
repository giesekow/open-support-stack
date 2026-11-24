# Identity Provisioning Technical Inventory

## Record

- Inventory date: 2026-11-24
- Local source: Docker Compose configuration and local container inspection
- Deployment source: read-only inspection of the production containers at
  `/home/administrator/open-support-stack`
- Production changes made during inventory: none
- Provisioning writes: locked

This inventory records reproducible versions and currently verified identity
behavior. `Pending` means the target must remain disabled and dry-run; it is not an
assumption that the application lacks the capability.

## Deployed Version Baseline

| Component | Application/build version | Approved image baseline |
| --- | --- | --- |
| Keycloak | 26.7.4 | `quay.io/keycloak/keycloak@sha256:82a77884f3af238beab1e7afd63b5f530e1b5c0590bd7aa60b40a40463e29b2c` |
| Vaultwarden | 1.37.2; Web Vault 2026.7.0 | `vaultwarden/server:1.37.2` |
| BookStack | LinuxServer build v26.03.5-ls262 | `lscr.io/linuxserver/bookstack@sha256:c9eee56c8beb181d8e53ea616be1537f2c65f394d7e7fb19c90e7059dc7670d6` |
| Guacamole | 1.5.5 | `guacamole/guacamole:1.5.5` |
| NetBird | 0.79.0 validated component baseline | `netbirdio/netbird-server@sha256:d1da0c0179c9e6f2ab7b48be54d06341b11037855a9426b9f2536aa79f13360b` |
| EspoCRM | 9.3.7 | `espocrm/espocrm@sha256:8b38e9ec6a7caaee6744ad247a44a0f4f23729c2efe379e68f1203439d3ff319` |
| Frappe HR / ERPNext | Local: HRMS 15.64.3, ERPNext 15.121.6, Frappe 15.122.0; production cutover pending | `ghcr.io/frappe/hrms:v15.64.3@sha256:437cf73e2da0f3e80b400f9fc3ca7fa21e93a7a0620474545140a8698d83812c` |
| Seafile | 11.0.13 | `seafileltd/seafile-mc@sha256:f1e19cc1cdd52ed8ec883de114acaa1e932941515dd6571fce0c0ff02248c4cf` |
| Penpot | 2.15.3 | `penpotapp/backend:2.15.3` |
| osTicket | 1.17.5 | `devinsolutions/osticket@sha256:2098f85341ca71e8ceb7ddfe28c4fee188505789148061819219ec4bcc3a8674` |

The BookStack, EspoCRM, Seafile and osTicket Compose references are pinned to the
repository digests observed in production. Upgrades require an explicit digest
change and target regression test.

## Capability And Stable-Link Inventory

| Target | Verified account mechanism | Stable-link finding | Disable/reactivate finding | Status |
| --- | --- | --- | --- | --- |
| Frappe HR / ERPNext | Native social-login JIT user followed by reviewed Employee onboarding | `tabUser Social Login.userid` stores immutable Keycloak `sub`; Employee is linked to the Frappe user after HR review | Guarded user disable/reactivate revokes MariaDB and Redis sessions while preserving HR and business records | HRMS installed and locally validated; production data cutover pending |
| BookStack | Native OIDC JIT; guarded linking of an existing unique account | `users.external_auth_id` stores the Keycloak subject; local lifecycle confirmed stable across repeat login and email/name changes | Keycloak employees-only flow blocks new login; database sessions are revoked without changing roles or content | Discover/link/disable/reactivate adapter implemented; local JIT lifecycle passed |
| EspoCRM | Native OIDC JIT guarded by the Keycloak `employees` role | `user.user_name` stores the immutable Keycloak `sub`; profile email/name synchronize on login without changing the link | Guarded `user.is_active` disable/reactivate is implemented; exact active auth tokens are invalidated while roles, teams, records and ownership are preserved | Discover/disable/reactivate adapter implemented; local JIT lifecycle passed |
| Seafile | Native OAuth JIT guarded by the Keycloak `employees` role | `social_auth_usersocialauth.uid` stores immutable Keycloak `sub`; changed verified email updates `profile_profile.contact_email` while the same internal account is reused | Guarded `EmailUser.is_active` disable/reactivate is implemented; exact Django sessions and user-owned API/client/device tokens are revoked while repositories and ownership are preserved | Discover/disable/reactivate adapter implemented; local JIT lifecycle passed |
| Penpot | Native OIDC JIT guarded by the Keycloak `employees` role | In `userinfo` mode, `profile.props["~:oidc/sub"]` stores immutable Keycloak `sub`; guarded profile updates migrate verified email/name before the next login | Guarded `profile.is_active` disable/reactivate is implemented; exact v1/v2 HTTP sessions and access tokens are revoked while teams, projects, files and ownership are preserved | Discover/update/disable/reactivate adapter implemented; local JIT lifecycle passed |
| NetBird | External IdP JIT guarded by Keycloak `employees` and `app-netbird` roles | The NetBird user ID encodes the immutable Keycloak `sub` together with the configured identity-provider ID; email and name are display metadata only | Guarded API block/reactivate is implemented; synchronized groups and peer ownership must remain unchanged | Discover/disable/reactivate adapter implemented; local JIT lifecycle passed |
| Guacamole | Transactional pre-provisioned PostgreSQL identity plus OIDC | Registry links `issuer + subject` to Guacamole entity ID; `preferred_username` is the target login | Disable/reactivate is implemented; active-session termination remains pending | Adapter implemented locally; disabled and dry-run |
| osTicket agents | Guarded pre-provisioning against the pinned 1.17.5 MariaDB schema; bundled `manage.php agent import` is intentionally not used because it cannot prove approved role placement | OAuth agent backend resolves `preferred_username` through `StaffSession::lookup`; Keycloak subject is not stored, so the registry retains the stable link | Guarded `ost_staff.isactive` disable/reactivate and exact staff-session deletion are implemented | Adapter implemented and locally lifecycle-tested; target disabled/dry-run; browser login remains a deployment test |
| Vaultwarden | Native organization invitation through a dedicated organization-admin personal API key; acceptance and cryptographic confirmation remain human workflows | Registry links immutable Keycloak identity to the Vaultwarden organization-membership ID; verified email is used only for the first invitation | Exact organization membership is removed; the personal account, personal vault, and organization-owned items remain untouched; eligibility return creates a fresh least-privilege invitation | Discover/invite/disable/reactivate adapter implemented; local credentialed lifecycle passed; production module deployed disabled/dry-run with production credentials pending |

## Protected Accounts

The active Frappe HR/ERPNext, BookStack, Seafile and Penpot adapters now enforce protection during both
discovery and execution:

- Frappe HR/ERPNext rejects built-in and System Manager identities and accepts
  additional protected IDs, usernames and emails from the environment.
- BookStack protects users with a non-empty `system_name` or the `admin` system
  role automatically and accepts additional environment exclusions.
- Protected-account settings participate in the target-state hash. Changing an
  exclusion invalidates an already planned action.

Environment variables for the active adapters are:

```dotenv
PROVISIONING_BOOKSTACK_PROTECTED_ACCOUNT_IDS=
PROVISIONING_BOOKSTACK_PROTECTED_USERNAMES=
PROVISIONING_BOOKSTACK_PROTECTED_EMAILS=
PROVISIONING_ERPNEXT_PROTECTED_ACCOUNT_IDS=Administrator,Guest
PROVISIONING_ERPNEXT_PROTECTED_USERNAMES=Administrator,Guest
PROVISIONING_ERPNEXT_PROTECTED_EMAILS=
PROVISIONING_SEAFILE_PROTECTED_ACCOUNT_IDS=
PROVISIONING_SEAFILE_PROTECTED_USERNAMES=
PROVISIONING_SEAFILE_PROTECTED_EMAILS=admin@example.com
PROVISIONING_PENPOT_PROTECTED_ACCOUNT_IDS=
PROVISIONING_PENPOT_PROTECTED_USERNAMES=
PROVISIONING_PENPOT_PROTECTED_EMAILS=
PROVISIONING_OSTICKET_PROTECTED_ACCOUNT_IDS=1
PROVISIONING_OSTICKET_PROTECTED_USERNAMES=ostadmin
PROVISIONING_OSTICKET_PROTECTED_EMAILS=admin@example.com
```

BookStack privileged roles are detected from its database relationships and do not
depend solely on a known email address. Frappe HR/ERPNext always rejects
`Administrator`, `Guest`, `System Manager`,
and `Administrator` roles in addition to its configurable exclusions. Seafile
rejects staff/administrator accounts and defaults its protected email to
`SEAFILE_ADMIN_EMAIL`. Penpot verifies the immutable OIDC subject again during
execution and accepts configurable UUID, username, and email exclusions.

Before another adapter gains write capability, it must implement equivalent
role-based detection plus environment-configured stable-ID exclusions. Expected
built-ins include Guacamole `guacadmin`; its deployed stable ID must not be guessed
or hard-coded.

## Evidence Commands

The inventory used read-only commands equivalent to:

```bash
docker inspect <container> --format '{{.Config.Image}}|{{.Image}}'
docker image inspect <image-id> --format '{{join .RepoDigests ","}}'
docker exec support-keycloak /opt/keycloak/bin/kc.sh --version
docker exec support-vaultwarden /vaultwarden --version
docker exec support-erpnext-backend sh -lc 'cd /home/frappe/frappe-bench && bench version'
```

Application files supplied the EspoCRM, Seafile and osTicket versions where the
container did not expose a usable version command. No credentials, password hashes,
tokens, personal vault data or business records were captured.

## Remaining Phase 0 Evidence

- Export and reconcile the production OrangeHRM records before enabling Frappe HR
  as the production HR master.
- Execute and approve the Frappe HR production validation and formal onboarding records.
- Verify stable external IDs and supported lifecycle APIs for every manual adapter.
- Complete osTicket browser-login acceptance after configuring its OAuth plugin
  instance; adapter placement and lifecycle behavior are documented in
  [osTicket Agent Provisioning Validation](identity-provisioning-osticket-validation.md).
- Record protected stable IDs in each environment as each adapter is implemented.
- Deploy and test the approved Keycloak client login gates.
- Record named business and technical owners in release evidence.
