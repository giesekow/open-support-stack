# BookStack JIT Local Validation

## Record

- Date: 2026-09-29
- Environment: local Docker Compose stack
- BookStack: LinuxServer v26.03.5-ls262
- Keycloak: 26.7.4
- Production contacted: no
- Global provisioning writes: locked

## Controls Applied

```dotenv
BOOKSTACK_DEFAULT_REGISTRATION_ROLE=Viewer
BOOKSTACK_SESSION_DRIVER=database
```

`sync_keycloak_redirects.sh` creates an idempotent BookStack browser-flow override.
After username/password and conditional OTP, `conditional-user-role` evaluates
`condUserRole=employees` with `negate=true`; `deny-access-authenticator` therefore
runs only for users who do not have the role inherited from the `employees` group.

## Commands And Results

### Default Authorization

```bash
docker exec support-bookstack-db sh -lc \
  'mariadb -N -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" \
  -e "SELECT setting_key,value,type FROM settings WHERE setting_key=\"registration-role\";"'
```

```text
registration-role  3  string
```

The role lookup for ID 3 returned `Viewer` with an empty `system_name`.

### Ineligible Login

The test used the normal browser authorization-code flow with PKCE. Passwords and
cookies are intentionally omitted from this controlled evidence.

```text
result_title=Sign in to Support Realm
denied_text=Access denied
bookstack_account_count=0
```

### First And Repeat Login

```sql
SELECT u.id,u.email,u.external_auth_id,
       GROUP_CONCAT(r.display_name ORDER BY r.id)
FROM users u
LEFT JOIN role_user ru ON ru.user_id=u.id
LEFT JOIN roles r ON r.id=ru.role_id
WHERE u.email='<DISPOSABLE_ELIGIBLE_EMAIL>'
GROUP BY u.id;
```

```text
4  <DISPOSABLE_ELIGIBLE_EMAIL>  90c23d38-7dfc-420f-a78b-af3b6959665a  Viewer

# After a separate repeat-login browser session:
1  4  4  Viewer
```

Exactly one account was created. Its `external_auth_id` matched the temporary
Keycloak subject, its only role was Viewer, and repeat login reused account ID 4.

### Source Name And Email Change

After changing first name, last name, and email in the disposable Keycloak user:

```text
result_title=BookStack
account_count=1
minimum_id=4
maximum_id=4
stored_external_auth_id=90c23d38-7dfc-420f-a78b-af3b6959665a
```

BookStack resolved the existing account by subject and created no duplicate. The
pinned version does not update its stored name/email during OIDC login, so those
fields remain target-managed and are not overwritten by automation.

### Offboarding And Reactivation

After removing `employees`, terminating Keycloak sessions, and executing the
BookStack adapter disable operation:

```text
fresh_login_denied=yes
session_before_disable=1
adapter_result={"details":{"sessions_revoked":1},"state":"suspended","target_account_id":"4"}
session_after_disable=0
account_after_disable=1  90c23d38-7dfc-420f-a78b-af3b6959665a  Viewer
revoked_session_status=HTTP/1.1 302 Found
revoked_session_redirect=https://docs.support.bonescreen.de/login
```

After restoring `employees`:

```text
adapter_reactivate={"state":"active","target_account_id":"4"}
reactivated_login_title=BookStack
stable_account=1  4  4  90c23d38-7dfc-420f-a78b-af3b6959665a  Viewer
```

## Result

Pass. The local BookStack JIT implementation denies ineligible users before
creation, assigns Viewer, links by immutable subject, avoids duplicates, revokes
sessions without deleting or changing target data, and reuses the same account on
reactivation. Production remains unchanged and requires its own dry-run evidence
and approval before these controls are deployed.
