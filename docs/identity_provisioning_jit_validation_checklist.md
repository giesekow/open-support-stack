# JIT Provisioning Validation Checklist

Use this checklist once per deployed JIT/OIDC target. Combine evidence where one
test proves multiple controls, but do not infer account linkage from successful
authentication alone.

## Test Record

| Field | Value |
| --- | --- |
| Target | TBD |
| Version/image | See technical inventory |
| Environment | Isolated validation environment |
| Tester/date | TBD |
| Eligible test subject | Dedicated non-privileged identity |
| Ineligible test subject | Dedicated identity outside approved groups |
| Evidence directory | TBD |

## Preconditions

- [ ] Target is backed up or disposable.
- [ ] Target remains dry-run and production writes remain locked.
- [ ] Test identities are not privileged, shared, service or emergency accounts.
- [ ] Approved default role and client login gate are configured.
- [ ] Target account table/API is observable before and after each test.

## Test 1 - Login Gate And Initial Creation

1. Attempt login with the ineligible identity.
2. Confirm access is denied before JIT creation and no target account appears.
3. Add the eligible identity to the approved group set and perform first login.
4. Confirm exactly one target account appears with only the approved default role.
5. Record the target account ID and persisted external identity value.

Expected: unauthorized login creates nothing; authorized first login creates one
least-privileged account with a verifiable Keycloak link.

## Test 2 - Repeat Login And Stable Link

1. Sign out, terminate the Keycloak session and sign in again.
2. Repeat once in a separate browser session.
3. Confirm the same target account ID is reused and no duplicate account exists.

Expected: repeated authentication resolves to the original linked account.

## Test 2A - First-Login Review Threshold

1. Leave an eligible JIT test identity in `awaiting_first_login` beyond the
   configured `PROVISIONING_JIT_REVIEW_AFTER_DAYS` period.
2. Run reconciliation and confirm the existing action changes to `manual_review`.
3. Confirm one `jit.first_login_review_required` audit event is recorded.
4. Reconcile again and confirm neither the action nor audit event is duplicated.
5. Confirm the Keycloak identity remains enabled and eligible and no target
   account or business data is changed by the escalation.
6. Remove eligibility from a separate waiting fixture and confirm its action is
   superseded rather than escalated for review.

Expected: stale first-login verification is surfaced once for review without
changing access eligibility or target data.

## Test 3 - Mutable Identity Attributes

1. Change first/last name and confirm only approved display fields update.
2. Change email or username in the isolated test identity.
3. Confirm the immutable external subject remains linked to the same target ID.
4. If the target cannot safely update its login identifier, confirm reconciliation
   stops for manual review rather than creating or relinking an account.

Expected: names may update where approved; email/username changes never transfer
or duplicate identity ownership.

## Test 4 - Suspension And Session Handling

1. Remove target eligibility and run immediate reconciliation.
2. Confirm new login is denied and target access is suspended within 10 minutes.
3. Verify active-session behavior and record any residual-session limitation.
4. Restore eligibility and confirm the same target account ID is reactivated.
5. Repeat the disable check by disabling the Keycloak user itself.

Expected: access is removed without deleting content; reactivation reuses the
original identity and target failures do not affect other services.

## Test 5 - Conflict And Protected Account

1. Create or select an isolated duplicate-email condition.
2. Confirm reconciliation creates a conflict/manual-review action and performs no
   write.
3. Attempt matching against a protected administrator fixture.
4. Confirm both planning and execution reject the protected account.

Expected: ambiguous and privileged matches fail closed with an audit event.

## Completion Criteria

- [ ] All five tests pass with command/API/database evidence.
- [ ] First and repeated login use exactly one target account.
- [ ] First-login timeout escalates once without disabling or deleting anything.
- [ ] Stored external identity and default authorization are explicitly verified.
- [ ] Disable/reactivate and active-session behavior are documented.
- [ ] Conflicts and protected accounts cannot be written.
- [ ] Business and technical owners sign the target evidence.

Failure moves the target to an approved pre-provision/API strategy or leaves it
disabled. A failed JIT test is never accepted as an undocumented exception.
