# ERPNext JIT Local Validation

## Record

- Date: 2026-09-29
- Environment: local Docker Compose stack
- ERPNext: 15.108.0
- Frappe: 15.107.2
- Keycloak: 26.7.4
- Production contacted: no
- Global provisioning writes: locked

## Controls Applied

- Keycloak client browser flow requires both `employees` and `app-erpnext`.
- ERPNext Social Login Key uses `user_id_property=sub` and allows JIT sign-up.
- JIT accounts must be enabled `Website User` accounts with no privileged role.
- ERPNext `Administrator`, `Guest`, `Administrator` role holders, and `System Manager`
  role holders are protected from automation.
- Support Tools reads the site's generated database credentials from a read-only
  `erpnext-sites` volume and connects to the site's Redis cache only to revoke exact
  session IDs.

## Commands And Results

Passwords, authorization codes, cookies, generated Keycloak IDs, and full session
IDs are intentionally omitted. All identities used the prefix `erp-jit-` and were
deleted after the test.

### Adapter Suite

```bash
./scripts/test_identity_provisioning.sh .env
```

```text
Ran 45 tests
OK
```

This includes changed-email fail-closed behavior and exact MariaDB/Redis session
revocation tests.

### Eligibility Matrix

Four disposable users exercised the normal authorization-code login flow:

```text
groups=<none>                    result=HTTP 401 Access denied
groups=employees                 result=HTTP 401 Access denied
groups=app-erpnext               result=HTTP 401 Access denied
groups=employees,app-erpnext     result=HTTP 200 /me
```

The three ineligible attempts never reached the ERPNext callback and created no
ERPNext account.

### First And Repeat Login

The eligible login and a separate repeat login produced:

```text
account_count=1
enabled=1
user_type=Website User
roles=<none>
social_provider=keycloak
social_userid=<KEYCLOAK_SUB>
repeat_login_account_count=1
```

The account's `tabUser Social Login.userid` exactly matched the temporary Keycloak
subject. Repeat login reused the same account and did not add roles.

### Changed Email

A non-mutating discovery using the same subject and a changed source email returned:

```text
state=not_ready
action=manual_review
reason=Keycloak email changed; ERPNext email migration must be reviewed before login
```

No account, social-login link, or target email was modified.

### Offboarding And Reactivation

After restoring both eligibility groups, reactivation and login reused the existing
account. Removing `app-erpnext`, terminating Keycloak sessions, and executing the
ERPNext adapter produced:

```text
reactivate_state=active
authenticated_api_before_disable=HTTP 200
disable_state=suspended
sessions_revoked=1
authenticated_api_after_disable=HTTP 403 session_expired
fresh_login_after_group_removal=HTTP 401 Access denied
```

The disable transaction set only the disposable user's `enabled` flag, removed its
MariaDB session row, and deleted the same session ID from the two site-prefixed Redis
hashes. The account and social-login link remained available for guarded reactivation.

### Cleanup

```text
remaining_keycloak_test_users=0
remaining_erpnext_test_users=0
```

## Result

Pass. The local ERPNext implementation enforces both approved eligibility groups,
creates one standard Website User, links it to immutable Keycloak `sub`, prevents
silent duplication after an email change, revokes active target sessions, and safely
reactivates the same account. Production remains unchanged and requires separate
dry-run evidence and approval before deployment or enabling writes.
