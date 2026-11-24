# NetBird JIT Local Validation

## Record

- Date: 2026-09-29
- Environment: local Docker Compose stack
- NetBird: 0.79.0
- Keycloak: 26.7.4
- Production contacted: no
- Global provisioning writes: locked

## Controls Applied

- The NetBird Keycloak client requires both `employees` and `app-netbird` after
  password and conditional OTP.
- The OIDC mapper emits only `groups=["app-netbird"]`; unrelated Keycloak groups
  are not synchronized to NetBird.
- Automatic JIT approval is enabled only after the dual Keycloak gate.
- A dedicated NetBird service user and expiring PAT provide supported API access.
- The adapter uses the immutable Keycloak subject encoded in NetBird's composite
  user ID and treats the IdP connector ID separately.
- Configured protected IDs, usernames, and emails are excluded from automation.
- Routes, policies, setup keys, peers, peer ownership, and non-synchronized groups
  are never created or changed by provisioning.

The integration uses NetBird's supported public APIs for
[users](https://docs.netbird.io/api/resources/users),
[tokens](https://docs.netbird.io/api/resources/tokens), and
[identity providers](https://docs.netbird.io/api/resources/identity-providers).

## Commands And Results

Secrets, passwords, authorization codes, cookies, complete bearer tokens, and
generated subjects are intentionally omitted. Disposable identities used the
prefix `codex-netbird-` and were deleted after validation.

### Adapter Suite

```bash
./scripts/test_identity_provisioning.sh .env
```

```text
Ran 56 tests
OK
```

The contract tests include exact-subject discovery, refusal of email-only matches,
pending-approval handling, group/peer preservation, and fail-closed peer drift.

### Bootstrap And Configuration

```bash
./scripts/bootstrap_netbird_provisioning.sh .env
./scripts/sync_keycloak_redirects.sh .env
./scripts/configure_netbird_oidc.sh .env
```

```text
provisioning_service_user=present
provisioning_pat=valid
oidc_provider=Keycloak
jwt_groups_enabled=true
jwt_group_claim=groups
jwt_allow_groups=app-netbird
user_approval_required=false
```

Re-running each script retained the same configuration without duplicate clients,
flows, mappers, providers, users, or groups.

### Eligibility And First Login

```text
groups=employees                 netbird_user_count=0
groups=employees,app-netbird    netbird_user_count=1
role=user
is_service_user=false
is_blocked=false
pending_approval=false
synchronized_groups=app-netbird
```

The eligible account's composite NetBird user ID decoded to the exact Keycloak
subject and configured IdP connector ID. A repeat login reused the same account.

### Profile Change

Keycloak's verified email and names were changed while its subject stayed stable.
The next login and adapter discovery produced:

```text
account_count=1
same_netbird_user_id=true
same_keycloak_subject=true
display_email_updated=false
display_name_updated=false
```

The last two values are a documented NetBird 0.79 metadata limitation, not an
identity or access-control failure. Display email/name are not matching keys.

### Offboarding And Reactivation

```text
disable_state=suspended
issued_token_while_blocked=HTTP 403
synchronized_groups_preserved=true
owned_peer_ids_preserved=true
reactivate_state=active
same_user_id=true
issued_token_after_reactivation=HTTP 200
```

The live disposable account owned no peers. The non-empty peer-ownership invariant
was additionally exercised by the adapter contract test, which fails closed if the
before/after peer ID sets differ.

### Cleanup

```text
remaining_disposable_netbird_users=0
remaining_disposable_keycloak_users=0
temporary_credential_files=removed
```

## Result

Pass. The local implementation blocks ineligible users before JIT registration,
creates one regular account with only the approved synchronized group, links it to
the immutable Keycloak subject, blocks access without altering peer ownership, and
reactivates the same identity. Display profile drift remains explicitly documented.
Production remains unchanged and requires separate dry-run evidence and approval
before deployment or enabling writes.
