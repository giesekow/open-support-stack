# Vaultwarden Invitation Provisioning Validation

## Scope

This record covers the Support Tools adapter for Vaultwarden 1.37.2. The adapter
uses Vaultwarden's native API to discover organization members, invite eligible
users, and remove only organization membership. It does not create or handle a
master password, decrypt vault data, confirm encrypted organization keys, assign
collections, or delete a personal account.

## Approved Baseline

- Eligibility requires both `employees` and `app-vaultwarden` in Keycloak.
- The source email must be present and verified.
- Each invitation has role `User` (`type=2`), `accessAll=false`, no groups, no
  collections, and no custom permissions.
- `Invited` and `Accepted` remain `invited` in Support Tools. Accepted membership
  is marked as requiring manual cryptographic confirmation.
- Only `Confirmed` is reported as active.
- Any privileged role, access-all grant, duplicate email, or unknown status fails
  closed as a conflict. Owner-managed groups and collections are recorded for review
  but are not changed by this adapter and never prevent urgent offboarding.
- Offboarding deletes the exact organization-membership ID. It does not call a
  personal-user deletion endpoint.
- Restored eligibility creates a new least-privilege invitation when the prior
  membership no longer exists.

## Credential Boundary

Use a dedicated, protected organization Admin account and its personal API key.
Vaultwarden personal API-key login bypasses 2FA, so the secret must be stored only
in the deployment environment, excluded from logs/evidence, and rotated after any
suspected disclosure. The adapter extracts only `access_token` from the token
response and discards returned encrypted key fields.

Required environment variables:

```dotenv
PROVISIONING_VAULTWARDEN_CLIENT_ID=user.<service-account-uuid>
PROVISIONING_VAULTWARDEN_CLIENT_SECRET=<secret>
PROVISIONING_VAULTWARDEN_ORGANIZATION_ID=<organization-uuid>
PROVISIONING_VAULTWARDEN_DEVICE_IDENTIFIER=<persistent-random-uuid>
PROVISIONING_VAULTWARDEN_PROTECTED_EMAILS=<service-account-email>
```

## Automated Evidence

Run:

```bash
./scripts/test_identity_provisioning.sh .env
docker compose --env-file .env config --quiet
./scripts/preflight_production.sh .env.production
```

Expected results:

- All provisioning tests pass.
- Compose configuration renders successfully.
- Production preflight passes without exposing secrets.
- With credentials absent, readiness reports `not_configured` and lists the four
  required credential/identifier variables.

## Controlled Local Lifecycle

Keep the target disabled, dry-run enabled, and the global write gate closed until
steps 1-5 are reviewed. Use a disposable test user and an empty test collection.

1. Add the user to `employees` and `app-vaultwarden`; reconcile and verify exactly
   one `create` plan for the verified email.
2. Open the global write gate only for the approved execution, disable target
   dry-run, execute with a reason, and close the global gate immediately.
3. Verify one email invitation, one membership with status Invited or Accepted,
   role User, and no collection/group access. A second reconcile must create no
   duplicate invitation.
4. Have the user accept with their own account/master password. Have an authorized
   owner/admin perform Vaultwarden's confirmation flow. Reconcile and verify Active.
5. Remove `app-vaultwarden`, reconcile, review the exact membership-removal plan,
   briefly open the write gate for approval, then verify organization access is
   gone while the personal account and personal vault remain.
6. Restore eligibility and verify a single fresh invitation is planned rather than
   an unsafe relink or automatic privilege restoration.

Record sanitized command output, membership status/role/access screenshots, email
delivery evidence, approver, reason, and timestamps. Never record the API secret,
master password, bearer token, encrypted key fields, recovery code, or vault item.

## Current Result

- Adapter implementation and isolated automated tests: **Pass**.
- Compose render and production preflight: **Pass**.
- Local credentialed invitation lifecycle (steps 1-4): **Pass**. The controlled
  test produced one least-privilege invitation, delivered it through Mailpit,
  prevented a duplicate, and reconciled the owner-confirmed membership as Active.
- Local offboarding lifecycle (step 5): **Pass**. The controlled action removed
  only the organization membership, retained exactly one personal account, and
  reconciled the identity link as Suspended.
- Local restored-eligibility lifecycle (step 6): **Pass**. Restoring
  `app-vaultwarden` produced one `reactivate` plan because the previous membership
  was absent. The reviewed action executed through the fresh least-privilege
  invitation path and produced one new invitation with no collection or group
  access.
- Validation cleanup: **Pass**. The disposable Keycloak identity was deleted, a
  fresh offboarding action removed the re-created organization membership, the
  identity link reconciled to Suspended, and both write gates were closed. No
  matching personal Vaultwarden account or organization membership remained.
- Lifecycle deduplication regression: **Pass**. Historical actions now remain
  immutable while the same semantic action may be planned again in a later
  lifecycle cycle. The full 73-test identity-provisioning suite passed, including
  the execution-control transition regression.
- Production module deployment: **Pass (fail-closed)**. On 2026-10-01 the
  Support Tools service was backed up, migrated from schema `0001` to `0004`,
  rebuilt, and verified healthy. The Vaultwarden target is disabled and in
  dry-run, while both global provisioning gates are false.
- Production Vaultwarden credential activation: **Pending**. The production
  environment contains the required variable names but no values for the client
  ID, client secret, organization ID, persistent device identifier, or protected
  service-account email. Local credentials were intentionally not copied because
  they belong to a different Vaultwarden deployment. No production reconciliation
  or application write was run.

## References

- Vaultwarden 1.37.2 organization API source:
  <https://github.com/dani-garcia/vaultwarden/blob/1.37.2/src/api/core/organizations.rs>
- Vaultwarden 1.37.2 membership model and status/type values:
  <https://github.com/dani-garcia/vaultwarden/blob/1.37.2/src/db/models/organization.rs>
- Vaultwarden 1.37.2 API-key login source:
  <https://github.com/dani-garcia/vaultwarden/blob/1.37.2/src/api/identity.rs>
