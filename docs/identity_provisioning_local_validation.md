# Identity Provisioning Local Validation

> Historical record: OrangeHRM-specific results below describe the former adapter.
> Frappe HR superseded that target on 2026-11-24; current local verification is
> recorded in `docs/frappe_hr_cutover.md` and the repository test results.

## Validation Record

- Date: 2026-09-29
- Environment: local Docker Compose development stack
- Scope: provisioning foundation, Keycloak source connector, BookStack, EspoCRM, ERPNext, Seafile, Penpot, NetBird, OrangeHRM, Guacamole and osTicket adapters, access control, migrations, retention configuration, protected-account controls, and fail-closed execution
- Production writes: not enabled

## Results

| Test | Expected | Actual | Result |
| --- | --- | --- | --- |
| Containerized unit suite | Existing and provisioning tests pass | 73 tests passed | Pass |
| Existing database migration | Upgrade from `0002` to `0003` | Support Tools started healthy at `0003` | Pass |
| Empty database migration | Upgrade from base to head | `0001` through `0003` applied; execution-attempt controls created | Pass |
| Migration rollback | Downgrade to base | All provisioning tables removed from disposable database | Pass |
| Target seed safety | Every target disabled and dry-run | 10 targets seeded with `enabled=false`, `dry_run=true` | Pass |
| Keycloak service token | Only approved realm-management roles | `view-users`, `query-users`, `query-groups` | Pass |
| Keycloak connector | Full scan succeeds with read-only token | Reconciliation completed with zero errors | Pass |
| Restricted group policy | App group alone cannot make a non-employee eligible | employees and the app-specific group are both required | Pass |
| Keycloak application groups | Fresh imports and sync contain the five restricted groups | Realm JSON validated; local sync created exact empty groups and second run was idempotent | Pass |
| Temporary employee lifecycle | Ingest eligible employee and tombstone deletion | One dry-run action; deletion recorded as disabled/tombstoned | Pass |
| Unsupported target behavior | No write; explicit review state | Vaultwarden produced `manual_review / not_ready` | Pass |
| BookStack isolated adapter | Unique email can be linked and rediscovered | Link and active discovery passed | Pass |
| OrangeHRM isolated adapter | Create, discover, disable, and reactivate | All four operations passed against disposable MariaDB schema | Pass |
| Support Tools authorization | `support-admin` allowed, other group denied | HTTP `200` and HTTP `403` respectively | Pass |
| Execution safety | Stale and duplicate actions fail closed | Source/target drift and second execution were rejected | Pass |
| Retry exhaustion | Failed writes require bounded manual retries | First failure became `retryable`; second became `manual_review` | Pass |
| Audit redaction | Secrets are absent from attempt and audit errors | Configured secret was replaced with `[REDACTED]` | Pass |
| Health separation | Liveness and provisioning readiness are distinct | `/internal/healthz` and `/internal/readyz` returned expected states | Pass |
| Unchanged reconciliation | Stable source/target state creates no duplicate work | Second full scan created zero actions | Pass |
| Eligibility removal | Access loss creates disable plan, not deletion | Linked account received one reviewable `disable` plan | Pass |
| Identity recreation | Reused email cannot inherit an old identity link | New Keycloak subject produced a reviewable conflict | Pass |
| Target isolation | One unavailable target does not block another | Healthy target planned successfully while failed target was audited | Pass |
| Global write protection | Writes remain locked | `PROVISIONING_ALLOW_WRITES=false` | Pass |
| Retention configuration | Defaults and overrides validate; invalid values fail closed | 730/90/730 days reported; cleanup remains manual | Pass |
| JIT first-login review threshold | Waiting action escalates once after 7 configurable days without changing eligibility or target data | One transition and one audit event were recorded; the next scan created neither a duplicate event nor action, and source eligibility remained unchanged | Pass |
| BookStack unauthorized JIT | Identity outside `employees` is denied before account creation | Keycloak returned `Access denied`; BookStack account count remained zero | Pass |
| BookStack first/repeat login | Eligible identity creates exactly one least-privileged account | Account ID 4 was reused; only Viewer role was assigned | Pass |
| BookStack immutable link | Keycloak `sub` survives source email/name changes | One account retained the original `external_auth_id`; BookStack correctly left target-managed profile values unchanged | Pass |
| BookStack offboarding/reactivation | Eligibility loss blocks fresh login, revokes active target sessions, preserves account/data, and reuses the identity after restoration | One database session was revoked; old cookie redirected to login; account/link/Viewer role remained; restored login reused ID 4 | Pass |
| EspoCRM unauthorized JIT | Identity outside `employees` is denied before account creation | Keycloak returned no authorization code and EspoCRM account count remained zero | Pass |
| EspoCRM first/repeat login | Eligible identity creates exactly one least-privileged account linked by immutable subject | One active `regular` user was reused; `user_name` equalled Keycloak `sub`; roles=0 and teams=0 | Pass |
| EspoCRM profile synchronization | Changed verified email/name updates profile metadata without relinking or duplication | Repeat login reused the same account ID and synchronized email, first name and last name | Pass |
| EspoCRM offboarding/reactivation | Disable invalidates active tokens while preserving CRM authorization and data | Two exact auth tokens were invalidated; old token changed from HTTP `200` to `401`; roles/teams stayed unchanged; reactivation reused the account and required a fresh token | Pass |
| ERPNext unauthorized JIT | Both `employees` and `app-erpnext` are required before account creation | Users with neither group or only one group received Keycloak HTTP `401`; no callback or ERPNext account was created | Pass |
| ERPNext first/repeat login | Eligible identity creates exactly one least-privileged account | Repeat login reused one Website User; no target roles were assigned and the social-login ID equalled Keycloak `sub` | Pass |
| ERPNext email-change safety | Changed source email cannot silently duplicate or relink an account | Adapter returned `not_ready / manual_review` for the immutable subject and made no target change | Pass |
| ERPNext offboarding/reactivation | Eligibility loss blocks fresh login and invalidates an active application session without deleting the account | Reactivation reused the account; disable removed one MariaDB session and both Redis cache entries; the old cookie changed from HTTP `200` to HTTP `403`; fresh login returned HTTP `401` | Pass |
| Seafile unauthorized JIT | A user outside `employees` is denied before account creation | Keycloak returned HTTP `401 Access denied`; no social-auth or internal account was created | Pass |
| Seafile first/repeat login | Eligible identity creates one standard account with approved defaults | Account ID 2 was reused; `uid` equalled Keycloak `sub`, staff=false, groups=0, organizations=0, and exactly one personal library existed | Pass |
| Seafile source profile change | Changed verified email/name cannot create a duplicate | Login reused account ID 2 and updated only the contact profile email; social-auth count remained one | Pass |
| Seafile offboarding/reactivation | Eligibility loss blocks fresh login and invalidates application sessions/tokens without deleting content | Disable revoked three Django sessions and one user token; old cookie returned HTTP `403`, fresh login returned HTTP `401`, and reactivation reused account ID 2 and its library | Pass |
| Penpot unauthorized JIT | A user outside `employees` is denied before profile creation | Keycloak showed `Access denied`; Penpot profile count remained zero | Pass |
| Penpot first/repeat login | Eligible identity creates one standard profile with personal defaults only | One profile UUID was reused; `oidc/sub` equalled Keycloak `sub`, with one personal team, one personal project, and no file membership | Pass |
| Penpot source profile change | Changed verified email/name cannot create a duplicate | Subject-first adapter migration and subsequent login reused the original profile, team, and project UUIDs | Pass |
| Penpot offboarding/reactivation | Eligibility loss blocks fresh login and invalidates sessions/tokens without deleting designs | Disable revoked three HTTP sessions; the old cookie became anonymous, fresh login was denied, and reactivation reused the original profile | Pass |
| NetBird unauthorized JIT | Both `employees` and `app-netbird` are required before account creation | An `employees`-only identity created no NetBird user; the client-specific Keycloak browser flow denied access to the Management API | Pass |
| NetBird first/repeat login | Eligible identity creates exactly one regular user linked to the immutable subject | One regular user was reused; its composite user ID contained the Keycloak `sub` and configured IdP connector; only `app-netbird` was synchronized | Pass |
| NetBird profile drift | Changed source email/name cannot relink or duplicate the account | Repeat login reused the same immutable user ID and created no duplicate; NetBird 0.79 retained its original display email/name | Pass with documented metadata limitation |
| NetBird offboarding/reactivation | Blocking prevents API/network use while preserving groups and peer ownership | API blocking changed discovery to `suspended`; an already-issued bearer token returned HTTP `403`; reactivation restored HTTP `200`; group and peer ownership sets were unchanged | Pass |
| Protected-account configuration | IDs, usernames and emails are normalized and affect stale-plan detection | Exact case-insensitive matching and target hash change passed | Pass |
| Privileged-role protection SQL | Queries match deployed BookStack and OrangeHRM schemas without reading user data | Both zero-row production schema checks returned `OK` | Pass |
| Floating target images | Account-bearing services using `latest` are pinned reproducibly | BookStack, EspoCRM, Seafile and osTicket resolve to observed production repository digests | Pass |
| Guacamole lifecycle adapter | Create a non-password identity with no permissions; disable/reactivate safely; reject administrator | Disposable PostgreSQL test passed with one stable entity, 32-byte random hash/salt, zero permissions and `ADMINISTER` conflict | Pass |
| Guacamole deployed schema | Adapter discovery query matches 1.5.5 production schema without reading account data | Zero-row schema query returned `OK` | Pass |
| Existing-target adapter upgrade | Only a system-owned `manual` Guacamole target advances to the implemented adapter | Local row is `guacamole`, `enabled=false`, `dry_run=true`, updated by `system:adapter-upgrade` | Pass |
| osTicket role bootstrap | Backup precedes placement setup; pinned schema and least-privilege role are exact | Backup created; schema signature matched; `Support Agent` role ID 5 grants only `ticket.reply` | Pass |
| osTicket lifecycle adapter | Create a non-admin agent with no password, team, extra department, or API key changes; disable/reactivate safely | Disposable agent used Support/Support Agent; one exact session was revoked; reactivation and cleanup passed | Pass |
| osTicket Keycloak gate | Both employee and application-specific eligibility are required | Client read-back showed `osticket-agent-eligible-browser` bound to `osticket` | Pass |
| Production preflight | Approved retention values and pinned target images pass; unsafe values fail | Production env passed; zero-day retention and `latest` image produced two hard failures | Pass |

## Commands Used

```bash
docker compose build support-tools
docker compose run --rm --no-deps --entrypoint python support-tools \
  -m unittest discover -s tests -v

docker compose up -d keycloak support-tools
./scripts/test_identity_provisioning.sh .env
./scripts/render_keycloak_realm.sh .env
./scripts/sync_keycloak_redirects.sh .env
./scripts/bootstrap_netbird_provisioning.sh .env
./scripts/configure_netbird_oidc.sh .env

docker exec support-support-tools alembic current\ndocker exec support-support-tools wget -qO- http://127.0.0.1:8000/internal/readyz
docker compose ps support-tools keycloak support-tools-db
```

Disposable PostgreSQL and MariaDB databases were created for migration and adapter write-path tests and dropped immediately afterward. A temporary Keycloak user was deleted after the lifecycle test. No production environment was contacted and no production application write was enabled.

## Remaining Gates

- Complete the credentialed Vaultwarden invitation/acceptance/confirmation/removal
  lifecycle after configuring its dedicated organization-admin API key; complete
  osTicket's browser-login acceptance test after configuring its OAuth plugin instance.
- Validate OrangeHRM against an initialized application database and approved employee-number policy.
- Complete conflict approval, unlink/relink, automatic backoff/dead-letter scheduling, session revocation, backup/restore, and monitoring tests.
- Obtain approval before setting any target out of dry-run or opening the global write gate.
