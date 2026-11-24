# VW-E03 Manual Test Checklist
Status: Execution in progress

Use only disposable accounts, collections, and credentials. Record no real
password, email address, recovery material, customer data, or vault content.

## Preconditions

- Two disposable invited users are available: Test User A and Test User B.
- The production organization owner performs membership changes.
- A browser client and one approved Bitwarden-compatible desktop or browser
  extension client are available.
- Use neutral test names such as `VW-VAL-A`, `VW-VAL-B`, and
  `VW-VAL-SYNC-20260925` in screenshots.

## VW-T01 Account lifecycle

Execution note (2026-09-25 21:56 UTC): invitations were delivered to both
disposable test users and both users were successfully added. This proves the
SMTP delivery and organization-onboarding portions. At 2026-09-25 22:04 UTC,
the operator confirmed successful login for both test users and confirmed that an
intentionally incorrect password was rejected without sensitive disclosure. The
revocation and fresh-synchronization checks remain pending.

1. Invite Test User A through the production organization.
2. Confirm the invitation arrives from the approved sender and links to the
   approved Vaultwarden URL.
3. Accept the invitation and confirm a correct login succeeds.
4. Confirm an incorrect password fails without sensitive disclosure.
5. Remove Test User A from the organization and sign out all test clients.
6. Perform a fresh login/synchronization and confirm new organization data is
   unavailable.
7. Confirm the offboarding record notes that previously synchronized offline
   data requires device control and credential rotation.

Expected result: every step passes. Server-side signup denial and unauthenticated
API denial are already recorded in `VW-E01-security-state.txt`.

## VW-T02 Collection authorization

Execution note (2026-09-25 22:13 UTC): the operator confirmed that both
test users had the User role without all-collection access. User A could see and
edit only `VW-VAL-A`; User B could see only `VW-VAL-B`, and the configured
read-only permission prevented editing. All authorization assertions passed.

1. Create collections `VW-VAL-A` and `VW-VAL-B` with disposable items.
2. Grant Test User A access only to `VW-VAL-A` and Test User B only to
   `VW-VAL-B`.
3. Confirm each user can read and perform only the approved actions in the
   assigned collection.
4. Confirm each user cannot see or alter the other collection.
5. Apply read-only access to one user and confirm editing is rejected.

Expected result: authorized actions succeed and every unauthorized read/edit is
denied.

## VW-T03 Client synchronization

Execution note (2026-09-25 22:22 UTC): the operator confirmed that the
disposable item created in the web vault appeared exactly once in the approved
client after synchronization. A non-secret marker changed in the client then
appeared in the web vault without duplicate, missing, or stale data. All
synchronization assertions passed.

1. Create `VW-VAL-SYNC-20260925` in the web vault with a disposable value.
2. Synchronize the approved client and confirm exactly one matching item is
   visible.
3. Change a non-secret marker in the approved client and synchronize.
4. Refresh the web vault and confirm the same update appears without duplicate,
   missing, or stale data.

Expected result: one consistent item and update are visible in both clients.

## VW-T05 Encrypted-data usability

After the disposable organization data above exists, rerun the protected backup
and isolated restore procedure. Authenticate to the isolated target using the
disposable account and confirm the test organization, assigned collection, and
test item are retrievable with the expected permissions.

Expected result: restored encrypted data is usable and permission-consistent.
The infrastructure, integrity, count-consistency, isolation, cleanup, and
production-health portions are already recorded in
`VW-E02-backup-restore.txt`.

## Execution record

| Check | UTC time | Actual result | Passed | Evidence reference |
| --- | --- | --- | --- | --- |
| VW-T01 | 2026-09-25 21:56-22:04 UTC | Partial: invitation delivery, user addition, both valid logins, and invalid-password rejection passed; revocation and fresh synchronization remain pending | Pending | Operator confirmations recorded in VW-E03 |
| VW-T02 | 2026-09-25 22:13 UTC | User A was limited to editable collection A; User B was limited to read-only collection B; cross-collection visibility and prohibited editing were denied | Yes | Operator confirmation recorded in VW-E03 |
| VW-T03 | 2026-09-25 22:22 UTC | The item synchronized once from web to client, and the client-side marker synchronized back without duplicate, missing, or stale data | Yes | Operator confirmation recorded in VW-E03 |
| VW-T05 encrypted-data usability | TBD | Not executed | No | TBD |
