# EspoCRM JIT Local Validation

## Record

- Date: 2026-09-29
- Environment: local Docker Compose stack
- EspoCRM: 9.3.7
- Keycloak: 26.7.4
- Production contacted: no
- Global provisioning writes: locked

## Controls Applied

- The EspoCRM Keycloak client requires `employees` after password and conditional
  OTP, before an authorization code is issued.
- EspoCRM uses its supported `ESPOCRM_CONFIG_*` startup mechanism.
- `oidcUsernameClaim=sub` stores the immutable Keycloak subject in
  `user.user_name`; email and names remain synchronized profile attributes.
- OIDC JIT and profile synchronization are enabled; team synchronization is off.
- Local fallback is available only to the break-glass administrator. OIDC login to
  administrators and fallback login by regular users are disabled.
- The lifecycle adapter excludes non-regular and configured protected accounts,
  invalidates exact user tokens, and preserves CRM authorization and ownership.

This configuration follows EspoCRM's official
[OIDC authentication](https://docs.espocrm.com/administration/oidc/),
[user inactivation](https://docs.espocrm.com/administration/users-management/),
and [REST API](https://docs.espocrm.com/development/api/) guidance.

## Commands And Results

Passwords, authorization codes, nonces, cookies, auth tokens, and generated
subjects are intentionally omitted. Disposable identities used the prefix
`codex-espo-` and were deleted after validation.

### Adapter Suite

```bash
./scripts/test_identity_provisioning.sh .env
```

```text
Ran 61 tests
OK
```

Contract tests cover immutable-subject discovery, refusal of email-only matches,
privileged-account exclusion, exact token invalidation, authorization preservation,
and rollback if role/team sets change during a lifecycle operation.

### Effective Configuration

```text
authenticationMethod=Oidc
oidcUsernameClaim=sub
oidcCreateUser=true
oidcSync=true
oidcSyncTeams=false
oidcFallback=true
oidcAllowRegularUserFallback=false
oidcAllowAdminUser=false
adapter_health=ready
target_enabled=false
target_dry_run=true
```

### Eligibility And First Login

```text
groups=<none>       authorization_code=false  account_count=0
groups=employees    authorization_code=true   account_count=1
type=regular
is_active=true
roles=0
teams=0
user_name=<KEYCLOAK_SUB>
```

A repeat login reused the same EspoCRM account ID and created no duplicate.

### Profile Synchronization

Keycloak's verified email and names were changed while its subject remained
stable. The next login produced:

```text
same_account_id=true
same_user_name_subject=true
email=<UPDATED_VERIFIED_EMAIL>
first_name=Updated
last_name=Person
roles=0
teams=0
```

### Offboarding And Reactivation

```text
issued_token_before_disable=HTTP 200
disable_state=suspended
tokens_invalidated=2
issued_token_after_disable=HTTP 401
roles_preserved=true
teams_preserved=true
reactivate_state=active
old_tokens_restored=false
fresh_token_after_reactivation=HTTP 200
authorization_after_employees_removal=false
account_count_after_employees_removal=1
```

The account, CRM authorization relationships, records, assignments, and ownership
were not deleted or transferred.

### Cleanup

The disposable CRM account was removed through EspoCRM's authenticated REST API,
then the exact Keycloak identity was deleted:

```text
espocrm_delete_status=HTTP 200
remaining_active_disposable_espocrm_users=0
remaining_disposable_keycloak_users=0
temporary_credential_files=removed
```

## Result

Pass. The local implementation blocks ineligible users before JIT, creates one
regular subject-linked account with no automatic roles or teams, synchronizes
profile attributes without relinking, invalidates exact tokens during suspension,
preserves CRM authorization and data, and reuses the identity after reactivation.
Production remains unchanged and requires separate dry-run evidence and approval
before deployment or enabling writes.
