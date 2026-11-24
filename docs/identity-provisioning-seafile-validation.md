# Seafile JIT Local Validation

## Record

- Date: 2026-09-29
- Environment: local Docker Compose stack
- Seafile: 11.0.13 Community Edition
- Keycloak: 26.7.4
- Production contacted: no
- Global provisioning writes: locked

## Controls Applied

- Keycloak client browser flow requires `employees` after password and conditional OTP.
- Seafile OAuth maps Keycloak `sub` to `uid`, the external identifier used by Seafile 11.
- Email and name map only to profile metadata.
- Browser authorization uses public HTTPS; token and user-info requests remain on
  the private Docker network.
- Staff, administrator, configured protected IDs/usernames, and
  `SEAFILE_ADMIN_EMAIL` are excluded from automation.

The identity mapping follows the official
[Seafile 11 OAuth configuration](https://manual.seafile.com/11.0/deploy/oauth/).

## Commands And Results

Passwords, authorization codes, cookies, generated subjects, internal usernames,
and full session/token values are intentionally omitted. Disposable identities used
the prefix `seafile-jit-` and were deleted after validation.

### Adapter Suite

```bash
./scripts/test_identity_provisioning.sh .env
```

```text
Ran 48 tests
OK
```

### Eligibility And First Login

```text
groups=<none>       result=HTTP 401 Access denied  account_count=0
groups=employees    result=HTTP 200 /              account_count=1
```

The eligible account had these defaults:

```text
provider=keycloak
uid=<KEYCLOAK_SUB>
account_id=2
is_staff=0
is_active=1
group_count=0
organization_count=0
personal_library_count=1
```

### Repeat Login And Profile Change

A separate repeat login reused account ID 2. Keycloak then changed the user's first
name, last name, and verified email while retaining the immutable subject and realm
username. The next login produced:

```text
result=HTTP 200 /
social_identity_count=1
minimum_account_id=2
maximum_account_id=2
contact_email=<CHANGED_VERIFIED_EMAIL>
```

No duplicate account or library was created.

### Offboarding And Reactivation

After removing `employees`, terminating Keycloak sessions, and executing the
Seafile adapter:

```text
disable_state=suspended
sessions_revoked=3
tokens_revoked=1
old_cookie=HTTP 403
fresh_login=HTTP 401 Access denied
account_is_active=0
personal_library_count=1
```

After restoring `employees` and executing guarded reactivation:

```text
reactivate_state=active
login=HTTP 200 /
account_count=1
account_id=2
is_staff=0
personal_library_count=1
```

### Cleanup

The disposable account was removed through Seafile's administrator API, followed
by removal of both Keycloak test users:

```text
seafile_delete_status=HTTP 200
remaining_social_identities=0
remaining_internal_accounts=0
remaining_repository_owners=0
remaining_keycloak_test_users=0
```

## Result

Pass. The local Seafile implementation denies ineligible users before JIT creation,
links one standard account to immutable Keycloak `sub`, updates profile metadata
without duplication, applies least-privilege defaults, revokes active sessions and
tokens, preserves user content during suspension, and reuses the same account after
reactivation. Production remains unchanged and requires separate dry-run evidence
and approval before deployment or enabling writes.
