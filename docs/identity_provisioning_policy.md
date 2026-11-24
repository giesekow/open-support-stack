# Identity Provisioning Policy Baseline

## Status

- Status: core provisioning policy approved; technical discovery and release evidence pending
- Eligibility approval date: 2026-09-28
- Eligibility approver: project owner
- Baseline role-default approval date: 2026-09-28
- Baseline role-default approver: project owner
- Restricted role-default approval date: 2026-09-28
- Restricted role-default approver: project owner
- Attribute-authority approval date: 2026-09-28
- Attribute-authority approver: project owner
- Identity-conflict policy approval date: 2026-09-28
- Identity-conflict policy approver: project owner
- Account-lifecycle policy approval date: 2026-09-28
- Account-lifecycle policy approver: project owner
- Session-token policy approval date: 2026-09-28
- Session-token policy approver: project owner
- Protected-account policy approval date: 2026-09-28
- Protected-account policy approver: project owner
- Synchronization-objectives approval date: 2026-09-28
- Synchronization-objectives approver: project owner
- Ownership-evidence model approval date: 2026-09-28
- Ownership-evidence model approver: project owner
- Client-login-gate policy approval date: 2026-09-28
- Client-login-gate policy approver: project owner
- Retention-privacy policy approval date: 2026-09-28
- Retention-privacy policy approver: project owner
- osTicket-placement approval date: 2026-09-28
- osTicket-placement approver: project owner
- Provisioning-strategy approval date: 2026-09-28
- Provisioning-strategy approver: project owner
- JIT first-login review policy approval date: 2026-09-29
- JIT first-login review policy approver: project owner
- Technical status: group primitives and dry-run control plane implemented locally
- Production activation: not approved
- Password synchronization: prohibited

A proposed value is not authorization to enable writes or grant users access. Each target remains disabled and dry-run until its business and technical owners approve its row and target-specific validation passes.

## Identity And Matching Policy

- Keycloak is authoritative for issuer, subject, enabled state, verified email, names, approved groups, and approved workforce attributes.
- The immutable source key is the OIDC issuer and subject pair.
- Verified normalized email may be used once to propose a link when exactly one non-privileged target account matches.
- Email or username changes never transfer a link to another Keycloak subject.
- Names are display attributes only and never matching keys.
- Administrator, emergency, service, shared, and built-in accounts require explicit exclusion before a target can leave dry-run.
- Business records, permissions, documents, leave, attendance, vault contents, devices, connections, and audit history are never deleted automatically.

## Eligibility Model

| Class | Keycloak requirement | Targets |
| --- | --- | --- |
| Baseline workforce | employees | Frappe HR / ERPNext, BookStack, EspoCRM, Seafile, Penpot |
| Restricted support access | employees and app-netbird | NetBird |
| Restricted remote access | employees and app-guacamole | Guacamole |
| Restricted ticket agents | employees and app-osticket-agent | osTicket agents |
| Restricted password vault | employees and app-vaultwarden | Vaultwarden organization |
| Administrative configuration | support-admin | Support Tools only |
| Excluded pending design | Explicit administrator assignment | Uptime Kuma |

This eligibility structure is approved. Restricted groups are empty by default.
Creating a group never assigns a user. Group membership establishes provisioning
eligibility only; target roles and Keycloak client-login restrictions remain separate
controls.

## Target Policy Matrix

The strategies in this matrix are approved. A preferred JIT strategy that fails
deployed-version validation does not fall back to direct database writes: the target
remains disabled and dry-run until its supported alternative is separately approved.

| Target | Configured image reference | Strategy | Stable link or match | Proposed default authorization | Disable and reactivate | Owner approval still required |
| --- | --- | --- | --- | --- | --- | --- |
| Frappe HR / ERPNext | Pinned `ghcr.io/frappe/hrms:v15.64.3` bundle | Keycloak JIT user plus reviewed Employee onboarding | `tabUser Social Login.userid` equals immutable Keycloak subject; reviewed Employee identifiers link HR data | System User with `Employee` role only; HR/finance roles and approvers are assigned separately | Disable user and sessions; preserve HR, expense and accounting history | HR, finance and platform owners |
| BookStack | LinuxServer v26.03.5-ls262, pinned digest | JIT plus verification | external_auth_id equals subject; unique email only for reviewed initial link | Approved: lowest non-admin read-only role; exact ID unresolved | Block login where supported; preserve content | Documentation and platform owners |
| EspoCRM | 9.3.7, pinned digest | JIT plus verification | `user.user_name` equals immutable Keycloak `sub`; email/name are synchronized profile fields | Approved: regular non-admin user with no automatic roles or teams | Disable login and active auth tokens; preserve roles, teams, records, assignments and ownership | CRM and platform owners |
| Seafile | 11.0.13, pinned digest | JIT plus verification | `social_auth_usersocialauth.uid` equals immutable Keycloak subject | Approved: active non-staff user; one personal library; no automatic group, organization, or shared-library membership | Disable login and revoke user sessions/tokens; preserve libraries and ownership | File-service and platform owners |
| Penpot | penpotapp/backend:2.15.3 | JIT plus verification | `profile.props["~:oidc/sub"]` equals immutable Keycloak subject in required `userinfo` mode | Approved: standard account with personal default team/project only; no automatic shared team/project membership | Disable login and revoke HTTP sessions/access tokens; preserve files and ownership | Design-service and platform owners |
| NetBird | Immutable server image digest | JIT plus restricted group sync | Keycloak subject encoded with the external IdP connector in the NetBird user ID | Approved: regular user synchronized only to `app-netbird`; no routes, policies, setup keys, or peer ownership grants | Block user access; retain tokens and peers for ownership review | Network/security owner |
| Guacamole | guacamole/guacamole:1.5.5 | Pre-provision/link | preferred_username maps to PostgreSQL identity | Approved: non-admin identity with no connections by default; grants are assigned separately | Disable identity and permissions; retain definitions | Remote-access and platform owners |
| osTicket agents | 1.17.5, pinned digest | Pre-provision/link | Verified email and approved agent identity | Approved: primary department `Support`; lowest custom non-admin support-agent role; assigned/department ticket view and response only; no default team | Disable agent; preserve tickets | Service-desk and platform owners |
| Vaultwarden | vaultwarden/server:1.37.2 | Invitation | Organization invitation and membership by verified email | Approved: organization User role with no collection access by default; collections are assigned separately after invitation acceptance | Remove organization access; preserve personal vault | Vault and security owners |

The deployed-version and immutable-image evidence is maintained in
[Identity Provisioning Technical Inventory](identity_provisioning_technical_inventory.md).

## Attribute Ownership

| Attribute | Authority | Automation behavior |
| --- | --- | --- |
| OIDC issuer and subject | Keycloak | Immutable; never reassigned automatically |
| Enabled and deleted state | Keycloak | Drives eligibility and disable planning |
| Verified email | Keycloak | Source-managed; changes require review when used as login |
| First and last name | Keycloak | Source-managed where target permits |
| Eligibility groups | Keycloak | Source-managed; determine eligibility but do not replace target authorization |
| Employee number | Frappe HR | HR approves any value needed for initial creation; later changes are made in Frappe HR |
| Job title, branch, department, supervisor and employment details | Frappe HR | The reviewed onboarding command sets initial values but reconciliation does not overwrite later HR changes |
| Target role, department, team, collections, connections | Target business owner | Apply only explicitly approved defaults |
| Leave, attendance, business records and owned content | Target | Never overwritten or deleted by reconciliation |
| Username | Derived or target-managed | Derive from verified email only where required; never use as the immutable identity link |

The Frappe HR onboarding command accepts HR-approved values required to create or
link an Employee. After creation, Frappe HR is authoritative for those fields.
Support Tools is not a personnel system of record.

### Per-Target Field Ownership

| Target | Source-managed identity fields | Immutable link | Target-managed fields |
| --- | --- | --- | --- |
| Frappe HR / ERPNext | Keycloak verified email and names at first login; later email changes require review | `tabUser Social Login.userid` linked to Keycloak subject; Employee link added after HR review | Employee number, employment profile, approvers, leave, attendance, expenses, payroll, accounting records and ownership |
| BookStack | Keycloak verified email and names | `external_auth_id` linked to Keycloak subject | Roles, shelves, books, pages, permissions and ownership |
| EspoCRM | Keycloak verified email and names synchronized at login | `user.user_name` linked to immutable Keycloak subject | Roles, teams, records, assignments and ownership |
| Seafile | Keycloak verified email and name; profile metadata updates on login | `social_auth_usersocialauth.provider + uid` linked to `keycloak + Keycloak subject` | Libraries, sharing, groups, organizations, quotas and ownership |
| Penpot | Keycloak verified email and name; guarded migration occurs before login after changes | `profile.props["~:oidc/sub"]` linked to Keycloak subject | Teams, projects, files, invitations, roles and ownership |
| NetBird | Keycloak login eligibility; initial verified email and names at JIT creation | Keycloak subject plus external IdP connector encoded in the NetBird user ID | Display email/name after creation, all groups except synchronized `app-netbird`, routes, policies, setup keys, peers and peer ownership |
| Guacamole | Approved Keycloak username/email used for the local identity | Provisioning registry `issuer + subject` plus Guacamole identity ID | Connections, connection groups and permissions |
| osTicket agents | Keycloak verified email and names | Provisioning registry `issuer + subject` plus agent ID | Department, team, role, tickets and assignments |
| Vaultwarden | Keycloak verified email for the invitation decision | Provisioning registry `issuer + subject`; organization membership ID after acceptance | Master password, personal vault, organization role, collections and vault items |

Exact target identifiers and OIDC persistence behavior remain validation requirements;
this approval defines ownership boundaries, not permission to enable writes.

## Conflict And Lifecycle Policy

1. Missing or unverified required email produces `not_ready`; no target account is created.
2. An exact existing `issuer + subject` link is reused.
3. A single target account matching by verified email is proposed for manual approval on the first link; it is never linked automatically.
4. Multiple matches, a reused email, or an account linked to another subject produces `conflict`; no write is allowed.
5. Email or username changes update an already linked account only when the target safely supports the change; otherwise the change requires manual review.
6. A recreated Keycloak identity with a new subject cannot inherit the former identity link without reviewed relinking.
7. Administrator, emergency, service, shared, and built-in accounts are never matched automatically.
8. Accounts are never merged, reassigned, or deleted automatically.
9. Eligibility loss plans disable, never deletion.
10. Reactivation uses the existing target ID and preserves history.
11. Technical failures use the target retry limit and then enter `manual_review`.
12. Target failures are isolated from unrelated targets.
13. A JIT action that remains `awaiting_first_login` for seven days enters
    `manual_review`. This does not remove eligibility, disable the source identity,
    alter target data, or delete an account. The period is configurable with
    `PROVISIONING_JIT_REVIEW_AFTER_DAYS`.
14. If eligibility is removed or the target is disabled before first login, the
    waiting action is superseded rather than escalated.

### Approved Account Lifecycle

- Disabling a Keycloak user or removing target eligibility disables access to that
  target. It never deletes the account or its business data.
- Reactivation reuses the same target account only when the original
  `issuer + subject` link remains valid and no conflict exists.
- If a target cannot safely disable an account, automation stops at manual review
  rather than deleting an account or modifying business records.
- Data remains subject to each application's approved retention policy;
  provisioning automation never performs automatic purging.

| Target | Approved suspension behavior | Data and ownership behavior |
| --- | --- | --- |
| Frappe HR / ERPNext | Disable the user and revoke sessions | Preserve employee, leave, attendance, expense, payroll, accounting and audit history |
| BookStack | Block login | Preserve authored content and ownership until a manual transfer is approved |
| EspoCRM | Disable the user | Preserve records, assignments and audit history |
| Seafile | Deactivate access | Preserve libraries; ownership transfer is manual |
| Penpot | Deactivate access | Preserve files; team and file ownership review is manual |
| NetBird | Disable user access | Retain peers until ownership and removal are reviewed |
| Guacamole | Disable the identity and its permissions | Preserve connection definitions |
| osTicket agents | Disable the agent | Preserve tickets; active work is reassigned manually where needed |
| Vaultwarden | Remove organization access | Do not delete the personal vault; organization items remain in the organization |

### Approved Session, Token, Invitation And Ownership Handling

- Disabling a Keycloak user terminates their Keycloak sessions and offline sessions
  immediately.
- Target sessions are revoked through a supported API where available. If safe
  revocation is unavailable, the case enters urgent manual review.
- User-owned API tokens are revoked only when ownership is unambiguous and the
  target provides a supported operation.
- Shared, service, integration, setup and emergency tokens are never revoked
  automatically.
- Pending invitations are cancelled when the identity loses eligibility.
- No device, peer, file, vault item, ticket or business record is automatically
  deleted or transferred.

| Target | Approved handling |
| --- | --- |
| NetBird | Block API and network access through the supported user API; retain issued tokens, peers, setup keys, routes and ownership for review |
| Vaultwarden | Remove organization access and pending organization invitations; do not modify personal-vault access or personal sessions |
| Seafile, Penpot, BookStack, ERPNext and EspoCRM | Preserve owned content and authorization; ownership transfer remains manual |
| Guacamole | Terminate active sessions where supported; retain connection definitions |
| osTicket agents | Retain active assignments and open tickets until manually reassigned |

### Approved Protected-Account Policy

- Built-in administrators, bootstrap accounts, emergency accounts, service
  accounts, integrations, bots and shared accounts are excluded from automatic
  matching and lifecycle actions.
- Keycloak administrators, ERPNext `Administrator` and `Guest`, Guacamole
  `guacadmin`, and each application's initial administrator are always protected.
- Any account with an administrator or owner role is protected unless an explicit,
  audited exception is approved.
- Stable target IDs are the primary exclusions where available; normalized
  usernames and emails provide an additional safeguard.
- Keycloak group membership does not override a protected-account exclusion.
- Removing an exclusion requires manual approval and an audit record.
- Discovery of an unlisted privileged account blocks writes for that identity and
  creates a manual-review case.
- Concrete protected-account IDs are environment-specific configuration and must
  not be hard-coded as production identifiers in source control.

## Synchronization Objectives

Approved operational objectives:

| Objective | Proposed value |
| --- | --- |
| Scheduled reconciliation | Every 5 minutes |
| Maximum eligibility/offboarding detection | 10 minutes |
| Urgent offboarding | Disable Keycloak user, terminate sessions, reconcile immediately |
| Technical write retries | Maximum 3 attempts with bounded backoff; then `manual_review` |
| JIT first-login review | Escalate `awaiting_first_login` after 7 days; configurable with `PROVISIONING_JIT_REVIEW_AFTER_DAYS` |
| Stale-run alert | No successful run for 15 minutes |
| Conflict/error alert | Every run with conflicts, unsafe matches or exhausted retries |
| Failure isolation | One target failure must not block unrelated targets |
| Production writes | Disabled per target until validation passes and explicit enablement is approved |
| Provisioning audit records, approvals, identity links and outcomes | 730 days; configurable with `PROVISIONING_AUDIT_RETENTION_DAYS` |
| Detailed operational/debug logs | 90 days; configurable with `PROVISIONING_OPERATIONAL_LOG_RETENTION_DAYS` |
| Closed conflict/manual-review records | 730 days after closure; configurable with `PROVISIONING_CLOSED_REVIEW_RETENTION_DAYS` |

### Approved Retention And Privacy Controls

- Validation and release evidence follows the organization's controlled-document
  and QMS retention rules rather than ordinary log rotation.
- Logs contain only necessary identifiers and outcomes. Passwords, access tokens,
  refresh tokens, API keys, invitation secrets and complete authentication payloads
  must never be recorded.
- Target business data remains governed by each target application's retention
  policy and is never purged by provisioning automation.
- Legal holds and controlled-record requirements override ordinary deletion.
- Retention cleanup must be audited and tested before automatic deletion is
  enabled. Cleanup remains manual in the current implementation.
- Retention environment values must be positive whole numbers. Invalid values
  prevent Support Tools from becoming ready.

## Operations Requiring Manual Approval

- Linking an existing account by email
- Relinking or unlinking an identity
- Email-login changes
- Privileged role assignment
- Ownership transfer for files, vault items, peers, tickets, or business records
- Any unvalidated direct database write
- Account deletion
- Adding a service, shared, emergency, or built-in account to automation

## Target Ownership And Approval Evidence

| Target | Business owner role | Technical owner role |
| --- | --- | --- |
| Frappe HR / ERPNext | HR and finance owners | Platform administrator |
| BookStack | Quality/documentation owner | Platform administrator |
| EspoCRM | CRM/business-process owner | Platform administrator |
| Seafile | Information/data owner | Platform administrator |
| Penpot | Design/product owner | Platform administrator |
| NetBird | Security/network owner | Platform administrator |
| Guacamole | Support-operations owner | Platform administrator |
| osTicket agents | Service-desk owner | Platform administrator |
| Vaultwarden | Security/vault owner | Platform administrator |

Every target requires the following minimum evidence before production enablement:

- deployed version and supported integration mechanism;
- approved eligibility and default authorization;
- dry-run output showing the expected actions;
- successful create, link, disable and reactivate tests where supported;
- duplicate/conflict and protected-account tests;
- least-privilege verification;
- audit, retry and failure-isolation evidence; and
- business-owner and technical-owner sign-off.

Role-based accountability applies immediately. Named individuals must be recorded
in the release evidence before a target is activated in production.

## Approved Client Login Gates

- Baseline application clients require membership in `employees`.
- Restricted clients require both `employees` and their applicable `app-*` group.
- Support Tools requires `support-admin`.
- Provisioning eligibility and login authorization use the same approved mapping
  but remain separate controls.
- Enforcement occurs before JIT account creation so an ineligible login attempt
  cannot create a target account.
- Keycloak uses dedicated client browser-flow overrides with fail-closed eligibility
  checks. Group membership may be mapped to roles for flow evaluation.
- Restricted clients independently evaluate both required memberships; an
  `app-*` group alone is insufficient.
- Applications or reverse proxies enforce the same claim where supported as
  defense in depth. Merely placing groups or roles in a token is not enforcement.
- Service integrations use separate least-privilege confidential clients rather
  than employee-group access.
- A target remains disabled and dry-run if its deployed Keycloak/application
  combination cannot demonstrate the approved gate.

## Outstanding Approval Register

| Decision | Required approver | Blocking effect |
| --- | --- | --- |
| Baseline and restricted application eligibility | Project owner | Approved 2026-09-28 |
| Baseline default roles and placement | Project owner | Approved 2026-09-28; deployed role IDs still require validation |
| Restricted default roles and organizational placement | Project owner | Approved 2026-09-28; deployed role and department IDs still require validation |
| Attribute authority and profile placement | Project owner | Approved 2026-09-28; target field/API behavior still requires validation |
| Identity matching and conflict handling | Project owner | Approved 2026-09-28; first email-based links require manual approval |
| Account lifecycle and non-deletion behavior | Project owner | Approved 2026-09-28 |
| Sessions, tokens, invitations and ownership during suspension | Project owner | Approved 2026-09-28; unsupported revocation requires urgent manual review |
| Protected-account policy | Project owner | Approved 2026-09-28; environment account-ID inventories remain required |
| Synchronization and alerting objectives | Project owner | Approved 2026-09-28 |
| Target ownership roles and approval evidence | Project owner | Approved 2026-09-28; named individuals are required before production activation |
| Client login restriction mechanism | Project owner | Policy approved 2026-09-28; deployed browser-flow and defense-in-depth checks require validation |
| Retention and privacy controls | Project owner | Approved 2026-09-28; periods are environment-configurable and cleanup remains manual |
| osTicket default department, role and team placement | Project owner | Approved 2026-09-28; exact deployed IDs require validation |
| Per-target provisioning strategies | Project owner | Approved 2026-09-28; deployed capabilities and stable links require validation |
| JIT first-login timeout and review path | Project owner | Approved 2026-09-29; 7-day configurable threshold, review only, no eligibility or account deletion |
| Session/token offboarding behavior | Project owner | Approved 2026-09-28; unsupported revocation requires urgent manual review |
| Name individual business and technical owners | Management/platform owner | Required in release evidence before production activation |
| Pin services using latest | Platform owner | Completed locally 2026-09-28 using production repository digests; deployment pending |
