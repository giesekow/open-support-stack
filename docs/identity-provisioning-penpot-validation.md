# Penpot JIT Local Validation

## Record

- Date: 2026-09-29
- Environment: local Docker Compose stack
- Penpot: 2.15.3
- Keycloak: 26.7.4
- Production contacted: no
- Global provisioning writes: locked

## Controls Applied

- Keycloak's Penpot client requires `employees` after password and conditional OTP.
- Browser authorization uses public HTTPS while token and user-info requests use
  the private Docker network.
- Penpot's SSRF allowlist contains only the private `keycloak` hostname and the
  configured public SSO hostname.
- `PENPOT_OIDC_USER_INFO_SOURCE=userinfo` preserves Keycloak `sub` in
  `profile.props["~:oidc/sub"]`; the adapter uses that immutable value before email.
- Configured protected IDs, usernames, and emails are excluded from automation.
- Team, project, file, and ownership relationships are never modified by lifecycle
  actions.

The OIDC setup follows the official
[Penpot configuration guide](https://help.penpot.app/technical-guide/configuration/).
Penpot's official authentication documentation confirms that OIDC profile lookup
uses email and that team invitations are a separate process:
[Penpot authentication subsystem](https://help.penpot.app/technical-guide/developer/subsystems/authentication/).

## Commands And Results

Passwords, authorization codes, cookies, generated subjects, and complete profile
properties are intentionally omitted. Disposable identities used the prefix
`penpot-jit-` and were deleted after validation.

### Adapter Suite

```bash
./scripts/test_identity_provisioning.sh .env
```

```text
Ran 51 tests
OK
```

### Eligibility And First Login

```text
groups=<none>       result=Access denied  profile_count=0
groups=employees    result=Penpot dashboard
```

The eligible account had these defaults:

```text
auth_backend=oidc
oidc_subject=<KEYCLOAK_SUB>
is_active=true
is_blocked=false
team_memberships=1
project_memberships=1
file_memberships=0
```

The team and project are the user's personal defaults. No existing shared team,
project, file, invitation, or role was assigned.

### Repeat Login And Profile Change

A repeat login produced exactly one profile and reused the same profile, default
team, and default project UUIDs. Keycloak's verified email and name were then
changed while its subject and username remained stable. The adapter discovered the
same profile by `oidc/sub`, planned a guarded `update`, and changed only the profile
email/name. The next login produced:

```text
profile_count=1
minimum_profile_id=<ORIGINAL_PROFILE_ID>
maximum_profile_id=<ORIGINAL_PROFILE_ID>
fullname=Changed Person
default_team_count=1
default_project_count=1
```

### Offboarding And Reactivation

After removing `employees`, terminating Keycloak sessions, and executing the
Penpot adapter:

```text
disable_state=suspended
sessions_revoked=3
tokens_revoked=0
old_session_identity=anonymous
fresh_login=Access denied
profile_is_active=false
default_team_id=<ORIGINAL_TEAM_ID>
default_project_id=<ORIGINAL_PROJECT_ID>
```

After restoring `employees` and executing guarded reactivation:

```text
discovered_state=suspended
planned_action=reactivate
reactivate_state=active
same_profile_id=true
login=Penpot dashboard
```

### Cleanup

The disposable account was removed through Penpot's authenticated
`delete-profile` command, followed by removal of both Keycloak users:

```text
penpot_delete_status=HTTP 204
active_disposable_profiles=0
remaining_disposable_team_links=0
remaining_keycloak_test_users=0
```

## Result

Pass. The local implementation blocks ineligible users before JIT registration,
creates one standard OIDC profile with only personal defaults, links it to the
immutable Keycloak subject, prevents duplicate profiles during reviewed email/name
migration, revokes exact sessions/tokens during suspension, preserves design and
ownership references, and reuses the same profile after reactivation. Production
remains unchanged and requires separate dry-run evidence and approval before
deployment or enabling writes.
