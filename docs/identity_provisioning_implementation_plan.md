# Identity Provisioning and JIT Implementation Plan

## 1. Purpose

Build an auditable automation in Support Tools that reconciles Keycloak users with accounts in applicable support-stack services. Adding a user to the Keycloak `employees` group makes the user eligible for approved baseline applications at the next reconciliation. Restricted applications additionally require an application-specific Keycloak group.

The automation will never synchronize passwords. Keycloak remains the authentication source, while each application retains its own authorization roles, business records, and application-specific data.

## 2. Guiding Rules

- The OIDC `(issuer, sub)` pair is the immutable source identity key. A bare `sub`, email, or username is not globally unique.
- A verified, normalized email may be used only for an initial match when it is unique in both systems and the target is not an administrator, service, emergency, or shared account.
- Names alone must never trigger an automatic account merge.
- Provisioning must be idempotent and safe to rerun.
- JIT is preferred when the application supports reliable first-login account creation and stable external-identity linking. Until that login occurs, the account remains `awaiting_first_login`, not provisioned.
- Pre-provisioning is used when the application requires an account, employee record, permissions, or invitation before login.
- Offboarding disables access before any optional deletion. Business and audit records are not automatically deleted.
- Authentication eligibility and target authorization are separate controls. Provisioning never substitutes for Keycloak client access restrictions or target-side least-privilege roles.
- Attribute ownership is explicit per field. Reconciliation changes only fields owned by the automation and does not overwrite approved target-managed data.
- No target failure may block reconciliation of unrelated targets.
- Every planned change must support dry-run, audit history, retry, and a per-target kill switch.
- Direct database writes are allowed only when no supported API or CLI exists and the adapter has explicit transactional and compatibility tests.
- Membership in `employees` does not grant sensitive support or administrative access by itself.
- Emergency, built-in administrator, service, and shared accounts are excluded from automated matching and lifecycle actions unless explicitly approved.
- Production changes use least-privilege, independently rotatable service credentials and encrypted transport.

## 3. Initial Service Classification

The final classification must be confirmed against the deployed version during Phase 0. This inventory covers end-user applications currently represented in the stack. Databases, reverse proxies, workers, SMTP test infrastructure, and other internal components are not separate identity targets.

| Service | Current identity path | Planned provisioning strategy | Preliminary eligibility |
| --- | --- | --- | --- |
| Frappe HR / ERPNext | Keycloak social login plus HR Employee records | JIT Frappe user, then reviewed Employee onboarding with approved HR master data | `employees` |
| EspoCRM | Keycloak OIDC client; application-side behavior must be verified | Prefer JIT; otherwise pre-create/link through supported API | `employees` |
| BookStack | Native OIDC and external auth ID | Validate JIT account creation and stable `sub` linking; provision default role if JIT cannot assign it safely | `employees` |
| Seafile | Keycloak/OAuth login | JIT creation linked by immutable `sub`; one personal library and no automatic group or organization membership | `employees` |
| Penpot | Native OIDC | Validate JIT profile creation/linking; invitations remain separate for teams/projects | `employees` |
| NetBird | Keycloak external identity provider | Use JIT for identity; synchronize approved NetBird groups only | `app-netbird` |
| Guacamole | OIDC plus PostgreSQL identities for permissions/connections | Pre-create/link local identity; assign only approved connection permissions | `app-guacamole` |
| osTicket | Keycloak OAuth plugin; agent record normally exists locally | Pre-create/link agent record and approved department/role | `app-osticket-agent` |
| Vaultwarden | Local encrypted vault account and organization invitation | Invitation workflow with user acceptance; never create or handle a master password | `app-vaultwarden` |
| Support Portal | oauth2-proxy; no separate local user account | No provisioning target | Authenticated realm users |
| Support Tools | Portal identity headers; no local user account | No provisioning target | `support-admin` |
| Penpot MCP | Uses an authenticated Penpot session | No separate user provisioning | Inherits Penpot access |
| Uptime Kuma | No managed Keycloak client in the current stack | Excluded until SSO and role requirements are approved | Explicit administrators only |

Approved baseline applications are Frappe HR/ERPNext, EspoCRM, BookStack, Seafile, and Penpot. Restricted applications require their application-specific group even when the user is also in `employees`.

The matrix is a discovery baseline, not approval to enable a target. Phase 0 must replace every preliminary eligibility value with an approved group, role, owner, and lifecycle policy.

The proposed Phase 0 decisions and outstanding approvals are maintained in [Identity Provisioning Policy Baseline](identity_provisioning_policy.md).

## 4. Common Lifecycle States

Use one normalized state model even when a target exposes different terminology:

| State | Meaning |
| --- | --- |
| `ineligible` | The Keycloak identity does not satisfy the target's approved eligibility rule. |
| `not_ready` | Eligible, but required attributes or approval are missing. |
| `planned` | A dry-run action exists and has not been executed. |
| `awaiting_first_login` | JIT is approved, but the target account does not exist until the user signs in. |
| `invited` | An invitation was sent and requires user action. |
| `active` | The target identity is linked and expected access is verified. |
| `conflict` | Matching is ambiguous or unsafe; no write is allowed. |
| `suspended` | Interactive access is disabled while records and the identity link are retained. |
| `error` | The last attempt failed and is subject to bounded retry or manual review. |

State transitions must be explicit, auditable, and idempotent. A target-specific adapter may omit unsupported states, but it must document the mapping and safe fallback.

## 5. Delivery Phases

Complete a phase only when its tasks and acceptance criteria are checked and its evidence links, approver, and completion date are recorded. Phase 0 gates all implementation. Phases 1 and 2 gate target adapters. Each target may then move independently through its applicable Phase 3, 4, or 5 work, but must satisfy Phases 6 through 8 before its Phase 9 production activation.

### Phase 0 - Discovery and Provisioning Policy

#### Tasks

- [ ] Confirm the deployed version and supported user-management API, CLI, JIT, invitation, and disable operations for every service in the classification table.
- [ ] Record whether each service persists OIDC issuer/subject, email, username, or another external ID and whether that value survives email and username changes.
- [x] Decide which applications are baseline targets for `employees` and which require `app-<service>` groups.
- [x] Create the approved application groups in the realm template and idempotent Keycloak sync script.
- [x] Define Keycloak client-level login restrictions for every baseline and restricted application; deployed enforcement must be validated before target activation.
- [x] Define the default role, department, team, organization, or permission set for each target. Exact deployed identifiers remain target-validation gates.
- [x] Define authoritative sources for first name, last name, email, employee number, location, subunit, job title, supervisor, and status.
- [x] Create a per-target field-ownership matrix distinguishing source-managed, target-managed, and immutable fields.
- [x] Decide which required profile attributes live in Keycloak and which may be collected temporarily in Support Tools for approved onboarding.
- [x] Define conflict handling for duplicate emails, changed emails, missing attributes, and existing unlinked accounts.
- [x] Define disable, archive, retention, reactivation, and deletion rules per application, including approved configurable retention periods.
- [x] Define how active sessions, refresh tokens, API tokens, invitations, owned devices, and peer ownership are handled during suspension.
- [ ] Identify and exclude built-in administrators, service accounts, emergency accounts, and shared accounts. The exclusion policy is approved; concrete stable IDs must still be inventoried and tested per environment.
- [x] Assign a business owner and technical owner role to every target and define evidence required for approval. Named individuals remain a production-release prerequisite.
- [x] Set measurable objectives for reconciliation frequency, maximum offboarding delay, retry duration, and alerting.
- [x] Mark unsupported or unsafe operations as manual rather than using unreviewed database writes.

#### Acceptance Criteria

- [x] Every current account-bearing service has an approved strategy: JIT, pre-provision, invitation, manual, or excluded.
- [x] Baseline and restricted group mappings are approved and documented.
- [x] Required attributes and their authoritative sources are unambiguous.
- [x] Each target has an approved field-ownership matrix, login gate, lifecycle mapping, owner roles, and measurable synchronization objectives. Deployed enforcement remains a validation gate.
- [x] Offboarding and conflict policies are approved before implementation begins.
- [ ] Excluded privileged and non-human accounts are recorded and cannot be modified by automation.

### Phase 1 - Provisioning Foundation in Support Tools

#### Tasks

- [x] Add a provisioning module under `/automations/provisioning`.
- [x] Add PostgreSQL migrations for provisioning targets, source identities, identity links, synchronization cursors, runs, planned actions, approvals, execution attempts, and audit events.
- [x] Store the immutable Keycloak issuer and subject plus the target-system account ID after the first successful link.
- [x] Define adapter interfaces for `discover`, `plan`, `create`, `link`, `update`, `disable`, `reactivate`, and `verify`.
- [x] Represent lifecycle state and supported adapter capabilities explicitly so unsupported operations fail closed.
- [x] Add per-target settings for enabled state, dry-run state, eligibility groups, default role mapping, retry policy, and rate limits.
- [x] Keep target credentials in environment/secrets only; never store them in rule or audit tables.
- [ ] Add structured logging, correlation IDs, redaction, bounded retry with exponential backoff and jitter, dead-letter/manual-review handling, and independent failure isolation.
- [x] Add a scheduler plus a manual `Reconcile now` operation.
- [x] Add advisory locking and idempotency keys so concurrent runs and repeated deliveries cannot duplicate writes.
- [x] Separate planning from execution and reject stale plans when source or target state changed after planning.
- [x] Make audit records append-only at the application layer and record actor, reason, source snapshot hash, target result, and correlation ID.
- [x] Add readiness and liveness checks that distinguish database health from scheduler and adapter health.
- [ ] Add database backup and migration rollback procedures.

#### Acceptance Criteria

- [x] Migrations apply cleanly to an empty and an existing Support Tools database.
- [ ] A mock adapter proves create, update, disable, retry, and idempotent rerun behavior.
- [x] Dry-run records a plan without changing any target system.
- [x] A stale or already-executed plan cannot be applied twice.
- [x] Secrets are absent from logs and audit payloads; personal data is limited to approved fields and redacted where not needed.
- [x] A target outage does not stop other target adapters.
- [ ] Health and audit evidence show who planned, approved, executed, retried, or rejected every mutation.

### Phase 2 - Keycloak Source Connector and Eligibility Engine

#### Tasks

- [x] Create a dedicated confidential Keycloak service-account client for provisioning.
- [x] Grant only the minimum roles required to view users, groups, memberships, and approved attributes.
- [x] Restrict the service account from managing users, credentials, groups, roles, and clients unless a separately approved write operation requires it.
- [x] Read users using pagination; begin with scheduled full reconciliation and add a supported incremental mechanism only after cursor-loss recovery is tested.
- [x] Normalize email and username without changing the immutable Keycloak `sub`.
- [x] Reject unverified or missing email when a target requires email identity.
- [x] Resolve nested and direct group membership consistently and normalize configured group paths without accepting similarly named groups accidentally.
- [x] Implement baseline `employees` eligibility and application-specific group eligibility.
- [x] Implement precedence rules so restricted application groups are always required where configured.
- [x] Treat disabled Keycloak users as ineligible regardless of group membership.
- [ ] Detect create, update, disable, reactivate, conflict, and no-change states.
- [x] Retain a source tombstone so deletion from Keycloak is distinguishable from pagination or connector failure and produces the approved suspension plan.
- [x] Treat a recreated Keycloak user as a new identity even when the previous email or username is reused; require reviewed relinking to historical target accounts.
- [x] Add a full reconciliation mode to repair missed events or drift.
- [x] Add a profile-readiness status for users missing required target attributes.
- [x] Snapshot only approved source attributes and avoid storing access tokens or unnecessary Keycloak profile data.

#### Acceptance Criteria

- [x] The connector reads the expected users and memberships using least privilege.
- [x] Removing eligibility creates a disable plan, not an immediate deletion.
- [x] Repeated scans with unchanged data produce only `no change` results.
- [x] Duplicate or ambiguous target matches stop safely for administrator review.
- [x] Users outside target eligibility cannot be provisioned accidentally.
- [ ] Disabling a user or removing eligibility is detected within the Phase 0 maximum-offboarding objective.
- [ ] Loss of an incremental cursor or event does not prevent a later full reconciliation from reaching the correct state.
- [x] Keycloak deletion and identity recreation tests cannot silently retain or inherit the former user's access.

### Phase 3 - JIT and OIDC Application Wave

#### Tasks

- [x] Build a reusable JIT verification checklist: first login, repeat login, stable linking, renamed user, changed email, disabled Keycloak user, removed group, and unauthorized user.
- [x] Record eligible JIT users as `awaiting_first_login`; do not report success until the target account ID and expected authorization are verified.
- [x] BookStack: verify first-login creation, `external_auth_id` linkage to Keycloak `sub`, Viewer default role, employees-only login gate, database-session revocation, stable repeat login, and reactivation.
- [x] ERPNext: verify social sign-up creation, email/sub linkage, approved default roles, duplicate prevention, and disable behavior.
- [x] Seafile: verify first-login creation, stable external identity, default organization/library behavior, and disable behavior.
- [x] Penpot: verify first-login profile creation, stable identity linkage, and separation between account creation and team/project invitation.
- [x] NetBird: verify JIT identity creation, application-group restriction, JWT/group synchronization, peer ownership retention, and user disable behavior.
- [x] EspoCRM: verify that deployed OIDC JIT creates one regular user linked by `sub`, synchronizes profile fields, grants no roles/teams, and supports guarded disable/reactivate.
- [x] For each JIT target, add an adapter that verifies account existence/linkage and performs disable/reactivate operations where supported.
- [x] Prevent login-based JIT from bypassing approved Keycloak eligibility groups.
- [x] Store the resulting target account ID after successful first login or discovery.
- [x] Verify logout, session expiry, and active-session invalidation behavior after source disable or eligibility removal.
- [x] Escalate users that remain `awaiting_first_login` for the configurable
  `PROVISIONING_JIT_REVIEW_AFTER_DAYS` period (default 7 days) to one-time
  `manual_review` without changing eligibility or target data.

#### Acceptance Criteria

- [x] Every approved JIT service passes the reusable JIT checklist.
- [x] First and repeated logins produce exactly one linked target account.
- [x] Unauthorized Keycloak users cannot trigger JIT creation.
- [x] The automation can discover, audit, disable, and reactivate JIT-created accounts.
- [x] An account is not reported as `active` until target identity linkage and expected roles are verified.
- [ ] Source disable or eligibility removal blocks new login and handles active sessions within the approved objective.
- [x] Any service failing the JIT criteria is moved explicitly to Phase 4 rather than accepted with an undocumented exception; no current JIT target required fallback.

### Phase 4 - Pre-Provisioned and Linked Account Wave

#### Tasks

- [x] Frappe HR: create or safely match an Employee using approved employee attributes after Keycloak JIT login.
- [x] Frappe HR: require approved employee number, company, gender, birth date and joining date; never synthesize HR master data.
- [x] Frappe HR: link the Employee to the immutable-sub-backed Frappe User and grant only the Employee role.
- [x] Frappe HR: preserve leave, attendance, expense, payroll and historical records during disable/reactivation.
- [x] Guacamole: create/link the PostgreSQL identity using `preferred_username` with random unusable credential material and no managed password.
- [x] Guacamole: preserve `guacadmin`, any `ADMINISTER` identity, and configured break-glass identifiers outside automated lifecycle management.
- [x] Guacamole: grant no connection, connection-group, user or system permissions during provisioning; never grant `ADMINISTER` from group membership.
- [x] osTicket: create/link an agent with the approved department, team, role, and email identity.
- [x] osTicket: distinguish staff/agent provisioning from end-user ticket accounts.
- [x] osTicket: keep privileged administrator roles and API keys outside automatic employee provisioning.
- [x] EspoCRM: API pre-provisioning is not required because the deployed native JIT path passed Phase 3 validation.
- [ ] Add adapter-specific transaction, compatibility, and rollback tests for any approved direct-database operation.
- [x] Prefer API/CLI writes; require a documented risk acceptance, pre-write backup, exact schema/version guard, and read-back verification for every direct-database adapter.
- [ ] Make a schema-changing application upgrade disable affected writes until compatibility is revalidated.

#### Acceptance Criteria

- [ ] A newly eligible user can authenticate and receives exactly the approved non-administrative access in each target.
- [ ] Existing matching accounts are linked only after an unambiguous match or administrator approval.
- [ ] Reconciliation never creates duplicate employee, agent, CRM, or Guacamole identities.
- [ ] Disable/reactivate preserves business history and removes interactive access as designed.
- [ ] Direct-database adapters are transactional, version-guarded, backed up, and documented.
- [ ] Break-glass and privileged local accounts remain usable and untouched after reconciliation and offboarding tests.

### Phase 5 - Vaultwarden Invitation Workflow

#### Tasks

- [x] Confirm the supported Vaultwarden invitation and organization-member API for the deployed version.
- [x] Implement an organization invitation for users eligible through `app-vaultwarden`.
- [x] Require user acceptance and creation/unlocking of their own encrypted vault account.
- [x] Never generate, capture, reset, or synchronize the user's master password.
- [x] Create only the approved organization User role with no initial collection/group access; later collection assignment remains an owner-controlled workflow.
- [x] Track invited, accepted, confirmed, revoked, conflict, and failed states; the deployed API exposes no invitation expiry timestamp, so expiry aging remains manual.
- [ ] Add reminder and expired-invitation retry behavior with rate limits.
- [x] Define and implement offboarding of organization membership without deleting the personal vault.
- [x] Preserve organization-owned items during membership removal; ownership/collection transfer remains an owner review before approval where applicable.
- [x] Ensure a pending invitation is cancelled when eligibility is removed.

#### Acceptance Criteria

- [ ] An eligible user receives one invitation and can complete enrollment without administrator knowledge of the master password.
- [ ] Reconciliation does not create duplicate invitations or memberships.
- [ ] Revocation removes organization access while preserving required audit and organization-owned data.
- [ ] Removing eligibility cancels an unaccepted invitation and prevents automatic re-invitation until eligibility returns.
- [ ] Signup restrictions remain enabled except for an explicitly approved workflow requirement.

### Phase 6 - Lifecycle, Drift, and Offboarding

#### Tasks

- [ ] Implement profile updates for approved mutable fields while retaining stable identity links.
- [ ] Treat email changes as reviewed updates when a target uses email as its login key.
- [ ] Disable target access when a user is disabled in Keycloak or loses target eligibility.
- [ ] Revoke or expire active sessions and target-issued API credentials where supported; document residual sessions where immediate revocation is impossible.
- [ ] Reactivate the same target identity when eligibility is restored.
- [ ] Add grace periods where required for business continuity.
- [ ] Detect accounts existing in targets but absent from the provisioning registry.
- [ ] Report unmanaged, duplicate, orphaned, and permission-drift accounts.
- [ ] Add an administrator-approved unlink/relink workflow.
- [ ] Add periodic full reconciliation alongside incremental runs.
- [ ] Ensure offboarding from one target does not affect unrelated applications.
- [ ] Record temporary exemptions with owner, reason, expiration, and compensating control; expired exemptions fail closed.
- [ ] Define retry exhaustion and escalation so permanent errors do not retry indefinitely.

#### Acceptance Criteria

- [ ] Disable and reactivation tests pass for every enabled target.
- [ ] No automated workflow deletes business records or encrypted user data.
- [ ] Drift reports identify unmanaged and over-privileged accounts without automatically merging them.
- [ ] Email changes and rehires preserve the intended identity rather than creating duplicates.
- [ ] Offboarding completes within the approved objective, including session/token handling or a documented residual-risk exception.
- [ ] Reconciliation changes only automation-owned fields and preserves target-owned business data.

### Phase 7 - Administration UI and Approval Workflow

#### Tasks

- [x] Add a dashboard showing target health, last successful run, pending actions, conflicts, and failures.
- [x] Add user detail showing Keycloak identity, eligibility groups, required attributes, and linked target accounts.
- [x] Add dry-run preview before enabling a target.
- [ ] Add approval controls for conflicts, sensitive role changes, unlink/relink, and destructive actions.
- [x] Require a reason and fresh target-state check when approving or executing a plan.
- [x] Add manual retry and `Reconcile now` controls.
- [ ] Add audit views with actor, timestamp, before/after state, target response, and correlation ID.
- [x] Restrict UI and mutation endpoints to `support-admin` and retain CSRF protection.
- [ ] Require recent MFA-authenticated login for sensitive approvals where the current proxy/session architecture can enforce it.
- [ ] Add data minimization and retention rules for provisioning history.

#### Acceptance Criteria

- [ ] Administrators can understand why each action is planned or blocked.
- [ ] Sensitive and ambiguous actions cannot execute without approval.
- [ ] Approvers cannot apply stale plans, and approval records include the actor and reason.
- [x] Non-`support-admin` users cannot view or change provisioning configuration.
- [ ] Every mutation is attributable and auditable.

### Phase 8 - Security, Functional, and Resilience Validation

#### Tasks

- [x] Unit-test normalization, matching, eligibility, planning, state transitions, and redaction.
- [ ] Add contract tests for every adapter against the pinned application version.
- [ ] Test create, JIT login, repeat login, update, disable, reactivate, conflict, and no-change paths.
- [ ] Test users in `employees`, users outside it, and users with each restricted application group.
- [ ] Test a user in both baseline and restricted/admin groups.
- [ ] Test target timeout, invalid credentials, rate limiting, malformed response, and partial outage.
- [ ] Test concurrent reconciliation and duplicate event delivery.
- [ ] Test stale-plan rejection, retry exhaustion, service restart during execution, and interrupted database transactions.
- [x] Verify that no target stores or receives a Keycloak password.
- [x] Verify least-privilege service accounts and network access.
- [ ] Verify built-in administrator, service, shared, and break-glass accounts cannot be matched or modified.
- [ ] Verify active-session/token behavior for every target during disable and group removal.
- [ ] Back up and restore the provisioning database, identity links, configuration, and secrets references.
- [ ] Run a dry-run against a sanitized production-like account inventory.
- [ ] Perform a security and privacy review before production writes are enabled.

#### Acceptance Criteria

- [ ] Automated tests pass for every enabled adapter and lifecycle state.
- [ ] Negative eligibility and privilege-escalation tests fail closed.
- [ ] Recovery tests prove that identity links and audit history survive restore.
- [ ] A target outage produces bounded retries and does not affect other targets.
- [ ] Security/privacy review findings are resolved or formally accepted.
- [ ] Evidence identifies the tested application image/version, configuration revision, tester, timestamp, command or procedure, expected result, and actual result.

### Phase 9 - Controlled Production Rollout

#### Tasks

- [x] Deploy database migrations and the provisioning module with all targets disabled or dry-run only. Completed 2026-10-01 at schema `0004`; all ten targets are disabled and dry-run, and both global gates are false.
- [ ] Back up Keycloak, Support Tools, and affected target data before each rollout wave.
- [ ] Run full production dry-run and review every proposed match and conflict.
- [ ] Pilot with test users and then a small employee cohort.
- [ ] Enable targets one at a time: low-risk JIT targets first, then pre-provisioned targets, then Vaultwarden invitations.
- [ ] Compare target account counts and permissions before and after each wave.
- [ ] Measure reconciliation and offboarding latency against the approved objectives during the pilot.
- [ ] Configure monitoring for failed runs, stale synchronization, growing conflict queues, and target authentication failures.
- [ ] Document rollback, manual fallback, credential rotation, target upgrades, and incident handling.
- [ ] Train administrators on group assignment, required attributes, approvals, retries, and offboarding.
- [ ] Record validation evidence and obtain production approval.

#### Acceptance Criteria

- [ ] Production dry-run has no unexplained create, link, disable, or permission-change actions.
- [ ] Pilot users complete login and receive only approved access in every enabled target.
- [ ] Offboarding and rollback are demonstrated in production-safe tests.
- [ ] Monitoring, backups, runbooks, and named operational ownership are active.
- [ ] Each target is explicitly approved before leaving dry-run mode.
- [ ] No unresolved high-severity conflict, security finding, or unexplained account/permission difference remains.

## 6. Definition of Done for Each Target Adapter

An application adapter is complete only when all relevant items are checked:

- [ ] Eligibility group and default role mapping are documented.
- [ ] Business owner, technical owner, supported application version, and adapter capability matrix are recorded.
- [ ] Required source attributes are validated before execution.
- [ ] Source-managed, target-managed, and immutable fields are documented.
- [ ] Initial matching is deterministic and conflicts fail closed.
- [ ] Create or JIT account creation is tested.
- [ ] Stable Keycloak-to-target identity linkage is stored.
- [ ] Repeat reconciliation is idempotent.
- [ ] Profile update behavior is defined and tested.
- [ ] Disable and reactivation are tested.
- [ ] Session, token, invitation, and owned-resource handling is tested or documented as unsupported with an accepted residual risk.
- [ ] Permission boundaries and unauthorized login are tested.
- [ ] Privileged, service, emergency, and shared accounts are excluded and tested.
- [ ] Audit output is complete and redacted.
- [ ] Backup, rollback, and application-upgrade compatibility are documented.
- [ ] Production dry-run and owner approval are complete.
- [ ] Evidence is attached and the target remains independently disableable.

## 7. Recommended First Implementation Slice

- [ ] Complete Phase 0 for all services before writing target adapters.
- [x] Implement Phases 1 and 2 with a mock target and production-safe dry-run.
- [ ] Use BookStack as the first JIT proof because an existing external-auth linkage pattern is already present.
- [x] Replace the original OrangeHRM adapter with Frappe HR JIT identity linking plus reviewed Employee onboarding.
- [ ] Add EspoCRM after its deployed-version JIT/API behavior is confirmed.
- [ ] Keep every remaining target disabled until its own Definition of Done is satisfied.
