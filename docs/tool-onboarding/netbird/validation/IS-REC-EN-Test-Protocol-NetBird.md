# IS-REC-EN-Test-Protocol-NetBird-2026-09

**Table of contents**

# Meta information

| **Document type** | Test Protocol and Execution Record |
| --- | --- |
| **Version** | 0.3 |
| **Status** | Draft - approval required before execution |
| **Last release date** | Not released |
| **Page ID** | TBD after publication |
| **Last change to the document** | Reformatted to the approved per-test protocol template; test scope unchanged. |

# Test protocol

Execution rules: use only dedicated test data; mask credentials, tokens, personal data, and customer data; record evidence references and timestamps; record each discrepancy before proceeding where safe. Evidence may be reused for multiple requirements when traceability is explicit.

## Test #1: Peer enrollment, revocation, and review lifecycle

|  |  |
| --- | --- |
| **Test ID** | **Title** |
| NB-T01 | Peer enrollment, revocation, and review lifecycle |

*Table 1.1:* Test identification

| **System identification** | **Test goal** | **Acceptance criterion** |
| --- | --- | --- |
| NetBird | Verify the approved configuration for: peer enrollment, revocation, and review lifecycle. | Peer enrolls only in the approved group; secret value is not logged; prohibited reuse fails; revocation removes effective access; events/inventory support an attributable access review. |

*Table 1.2:* System identification

| **Test run** | **Start date/time** | **End date/time** |
| --- | --- | --- |
| 0001 | TBD | TBD |

*Table 1.3:* Run through

| **Requirement** |
| --- |
| Requirement IDs: NB-ENROLL-001, NB-REVOKE-001, NB-REVIEW-001. Approved test topology with one support peer and two customer peers; non-customer addresses; approved and deliberately non-approved listening test ports; secrets excluded from evidence. |

*Table 1.4:* Requirements

| **Test step** | **Requirement-ID** | **Action** | **Data to be recorded** | **Expected results** | **Actual results** | **Passed / not passed** |
| --- | --- | --- | --- | --- | --- | --- |
| 1.1 | NB-ENROLL-001, NB-REVOKE-001, NB-REVIEW-001 | Create a scoped, expiring one-off setup key; enroll Customer A; verify its group and administrative event. Attempt prohibited key reuse, then revoke/delete the test peer or key and review the resulting active peer/key inventory. | Redacted screenshots, command/API output, configuration identifiers, and evidence reference as applicable | Peer enrolls only in the approved group; secret value is not logged; prohibited reuse fails; revocation removes effective access; events/inventory support an attributable access review. |  | Not executed |

*Table 1.5:* Test steps

| **Postconditions or action after execution** |
| --- |
| Remove test peers, keys, routes, and temporary policies/resources or restore the approved baseline; retain redacted evidence only. |

*Table 1.6:* Postconditions or action after execution

| **Comment** |
| --- |
|  |

*Table 1.7:* Comments

|  |  |  |  |
| --- | --- | --- | --- |
| **Test result** | **[ ] Passed  [ ] Not passed  [x] Not executed** | **Reference Nr. deviation / bug report** |  |

*Table 1.8:* Test result

## Test #2: NetBird-Keycloak identity integration

|  |  |
| --- | --- |
| **Test ID** | **Title** |
| NB-T02 | NetBird-Keycloak identity integration |

*Table 2.1:* Test identification

| **System identification** | **Test goal** | **Acceptance criterion** |
| --- | --- | --- |
| NetBird | Verify the approved configuration for: netbird-keycloak identity integration. | Approved identity reaches NetBird; unauthorized or disabled identity is denied; NetBird consumes the approved identity flow. |

*Table 2.2:* System identification

| **Test run** | **Start date/time** | **End date/time** |
| --- | --- | --- |
| 0001 | TBD | TBD |

*Table 2.3:* Run through

| **Requirement** |
| --- |
| Requirement IDs: NB-IDENTITY-001. Approved test topology with one support peer and two customer peers; non-customer addresses; approved and deliberately non-approved listening test ports; secrets excluded from evidence. |

*Table 2.4:* Requirements

| **Test step** | **Requirement-ID** | **Action** | **Data to be recorded** | **Expected results** | **Actual results** | **Passed / not passed** |
| --- | --- | --- | --- | --- | --- | --- |
| 2.1 | NB-IDENTITY-001 | Sign in to NetBird through Keycloak using an approved MFA-enforced support identity; attempt NetBird access with an unauthorized or disabled identity. Reference the approved Keycloak MFA test rather than re-enrolling/testing second factors here. | Redacted screenshots, command/API output, configuration identifiers, and evidence reference as applicable | Approved identity reaches NetBird; unauthorized or disabled identity is denied; NetBird consumes the approved identity flow. |  | Not executed |

*Table 2.5:* Test steps

| **Postconditions or action after execution** |
| --- |
| Remove test peers, keys, routes, and temporary policies/resources or restore the approved baseline; retain redacted evidence only. |

*Table 2.6:* Postconditions or action after execution

| **Comment** |
| --- |
|  |

*Table 2.7:* Comments

|  |  |  |  |
| --- | --- | --- | --- |
| **Test result** | **[ ] Passed  [ ] Not passed  [x] Not executed** | **Reference Nr. deviation / bug report** |  |

*Table 2.8:* Test result

## Test #3: Positive and negative access matrix

|  |  |
| --- | --- |
| **Test ID** | **Title** |
| NB-T03 | Positive and negative access matrix |

*Table 3.1:* Test identification

| **System identification** | **Test goal** | **Acceptance criterion** |
| --- | --- | --- |
| NetBird | Verify the approved configuration for: positive and negative access matrix. | Support reaches only the approved port on both customers. The non-approved port fails. Both customer-to-customer directions and customer-to-support initiation fail; return traffic for support-initiated sessions works. |

*Table 3.2:* System identification

| **Test run** | **Start date/time** | **End date/time** |
| --- | --- | --- |
| 0001 | TBD | TBD |

*Table 3.3:* Run through

| **Requirement** |
| --- |
| Requirement IDs: NB-POLICY-001, NB-POLICY-002, NB-ISOLATION-001, NB-LEASTPRIV-001. Approved test topology with one support peer and two customer peers; non-customer addresses; approved and deliberately non-approved listening test ports; secrets excluded from evidence. |

*Table 3.4:* Requirements

| **Test step** | **Requirement-ID** | **Action** | **Data to be recorded** | **Expected results** | **Actual results** | **Passed / not passed** |
| --- | --- | --- | --- | --- | --- | --- |
| 3.1 | NB-POLICY-001, NB-POLICY-002, NB-ISOLATION-001, NB-LEASTPRIV-001 | Confirm `All -> All` is disabled. Using a deliberately listening approved and non-approved test port, execute one access matrix: Support to Customer A/B; Customer A to Customer B/support; Customer B to Customer A/support. | Redacted screenshots, command/API output, configuration identifiers, and evidence reference as applicable | Support reaches only the approved port on both customers. The non-approved port fails. Both customer-to-customer directions and customer-to-support initiation fail; return traffic for support-initiated sessions works. |  | Not executed |

*Table 3.5:* Test steps

| **Postconditions or action after execution** |
| --- |
| Remove test peers, keys, routes, and temporary policies/resources or restore the approved baseline; retain redacted evidence only. |

*Table 3.6:* Postconditions or action after execution

| **Comment** |
| --- |
|  |

*Table 3.7:* Comments

|  |  |  |  |
| --- | --- | --- | --- |
| **Test result** | **[ ] Passed  [ ] Not passed  [x] Not executed** | **Reference Nr. deviation / bug report** |  |

*Table 3.8:* Test result

## Test #4: Windows /32 routed-resource access

|  |  |
| --- | --- |
| **Test ID** | **Title** |
| NB-T04 | Windows /32 routed-resource access |

*Table 4.1:* Test identification

| **System identification** | **Test goal** | **Acceptance criterion** |
| --- | --- | --- |
| NetBird | Verify the approved configuration for: windows /32 routed-resource access. | Resource is exactly `/32`; route uses NetBird `wt0`; no wider customer route exists; approved LAN service works and non-approved port fails. |

*Table 4.2:* System identification

| **Test run** | **Start date/time** | **End date/time** |
| --- | --- | --- |
| 0001 | TBD | TBD |

*Table 4.3:* Run through

| **Requirement** |
| --- |
| Requirement IDs: NB-ROUTE-001, NB-WINROUTE-001. Approved test topology with one support peer and two customer peers; non-customer addresses; approved and deliberately non-approved listening test ports; secrets excluded from evidence. |

*Table 4.4:* Requirements

| **Test step** | **Requirement-ID** | **Action** | **Data to be recorded** | **Expected results** | **Actual results** | **Passed / not passed** |
| --- | --- | --- | --- | --- | --- | --- |
| 4.1 | NB-ROUTE-001, NB-WINROUTE-001 | Configure one Windows routing peer with `NB_ENABLE_LOCAL_FORWARDING=true` and one LAN host resource as `x.x.x.x/32`; select the Network on support, inspect NetBird/OS routes, and test approved and non-approved ports. | Redacted screenshots, command/API output, configuration identifiers, and evidence reference as applicable | Resource is exactly `/32`; route uses NetBird `wt0`; no wider customer route exists; approved LAN service works and non-approved port fails. |  | Not executed |

*Table 4.5:* Test steps

| **Postconditions or action after execution** |
| --- |
| Remove test peers, keys, routes, and temporary policies/resources or restore the approved baseline; retain redacted evidence only. |

*Table 4.6:* Postconditions or action after execution

| **Comment** |
| --- |
|  |

*Table 4.7:* Comments

|  |  |  |  |
| --- | --- | --- | --- |
| **Test result** | **[ ] Passed  [ ] Not passed  [x] Not executed** | **Reference Nr. deviation / bug report** |  |

*Table 4.8:* Test result

## Test #5: Direct and encrypted relay connectivity

|  |  |
| --- | --- |
| **Test ID** | **Title** |
| NB-T05 | Direct and encrypted relay connectivity |

*Table 5.1:* Test identification

| **System identification** | **Test goal** | **Acceptance criterion** |
| --- | --- | --- |
| NetBird | Verify the approved configuration for: direct and encrypted relay connectivity. | A WireGuard handshake occurs and the approved connection works directly or through the available encrypted relay; fallback does not expose the application port publicly. |

*Table 5.2:* System identification

| **Test run** | **Start date/time** | **End date/time** |
| --- | --- | --- |
| 0001 | TBD | TBD |

*Table 5.3:* Run through

| **Requirement** |
| --- |
| Requirement IDs: NB-ENCRYPT-001, NB-CONNECT-001. Approved test topology with one support peer and two customer peers; non-customer addresses; approved and deliberately non-approved listening test ports; secrets excluded from evidence. |

*Table 5.4:* Requirements

| **Test step** | **Requirement-ID** | **Action** | **Data to be recorded** | **Expected results** | **Actual results** | **Passed / not passed** |
| --- | --- | --- | --- | --- | --- | --- |
| 5.1 | NB-ENCRYPT-001, NB-CONNECT-001 | Record normal `netbird status -d`; verify Management/Signal and STUN where available; force or simulate direct-path failure and establish the approved service connection through `rels://...:443`. | Redacted screenshots, command/API output, configuration identifiers, and evidence reference as applicable | A WireGuard handshake occurs and the approved connection works directly or through the available encrypted relay; fallback does not expose the application port publicly. |  | Not executed |

*Table 5.5:* Test steps

| **Postconditions or action after execution** |
| --- |
| Remove test peers, keys, routes, and temporary policies/resources or restore the approved baseline; retain redacted evidence only. |

*Table 5.6:* Postconditions or action after execution

| **Comment** |
| --- |
|  |

*Table 5.7:* Comments

|  |  |  |  |
| --- | --- | --- | --- |
| **Test result** | **[ ] Passed  [ ] Not passed  [x] Not executed** | **Reference Nr. deviation / bug report** |  |

*Table 5.8:* Test result

## Test #6: Backup and isolated restore

|  |  |
| --- | --- |
| **Test ID** | **Title** |
| NB-T06 | Backup and isolated restore |

*Table 6.1:* Test identification

| **System identification** | **Test goal** | **Acceptance criterion** |
| --- | --- | --- |
| NetBird | Verify the approved configuration for: backup and isolated restore. | Required configuration is readable and consistent after restore; secrets are absent from evidence; documented peer re-enrollment limitations are addressed. |

*Table 6.2:* System identification

| **Test run** | **Start date/time** | **End date/time** |
| --- | --- | --- |
| 0001 | TBD | TBD |

*Table 6.3:* Run through

| **Requirement** |
| --- |
| Requirement IDs: NB-BACKUP-001. Approved test topology with one support peer and two customer peers; non-customer addresses; approved and deliberately non-approved listening test ports; secrets excluded from evidence. |

*Table 6.4:* Requirements

| **Test step** | **Requirement-ID** | **Action** | **Data to be recorded** | **Expected results** | **Actual results** | **Passed / not passed** |
| --- | --- | --- | --- | --- | --- | --- |
| 6.1 | NB-BACKUP-001 | Back up NetBird persistent data and the separately protected datastore encryption key; restore to an isolated target; inspect groups, policies, peers/resources and dashboard/API health. | Redacted screenshots, command/API output, configuration identifiers, and evidence reference as applicable | Required configuration is readable and consistent after restore; secrets are absent from evidence; documented peer re-enrollment limitations are addressed. |  | Not executed |

*Table 6.5:* Test steps

| **Postconditions or action after execution** |
| --- |
| Remove test peers, keys, routes, and temporary policies/resources or restore the approved baseline; retain redacted evidence only. |

*Table 6.6:* Postconditions or action after execution

| **Comment** |
| --- |
|  |

*Table 6.7:* Comments

|  |  |  |  |
| --- | --- | --- | --- |
| **Test result** | **[ ] Passed  [ ] Not passed  [x] Not executed** | **Reference Nr. deviation / bug report** |  |

*Table 6.8:* Test result

## Test #7: Version and upgrade baseline

|  |  |
| --- | --- |
| **Test ID** | **Title** |
| NB-T07 | Version and upgrade baseline |

*Table 7.1:* Test identification

| **System identification** | **Test goal** | **Acceptance criterion** |
| --- | --- | --- |
| NetBird | Verify the approved configuration for: version and upgrade baseline. | Components are uniquely identified, compatible, and approved; unsupported combinations require documented assessment; the update procedure identifies the lean regression subset to rerun. |

*Table 7.2:* System identification

| **Test run** | **Start date/time** | **End date/time** |
| --- | --- | --- |
| 0001 | TBD | TBD |

*Table 7.3:* Run through

| **Requirement** |
| --- |
| Requirement IDs: NB-CHANGE-001. Approved test topology with one support peer and two customer peers; non-customer addresses; approved and deliberately non-approved listening test ports; secrets excluded from evidence. |

*Table 7.4:* Requirements

| **Test step** | **Requirement-ID** | **Action** | **Data to be recorded** | **Expected results** | **Actual results** | **Passed / not passed** |
| --- | --- | --- | --- | --- | --- | --- |
| 7.1 | NB-CHANGE-001 | Record server, dashboard, and test-client versions/digests; compare them with the approved baseline and review upgrade/regression controls. | Redacted screenshots, command/API output, configuration identifiers, and evidence reference as applicable | Components are uniquely identified, compatible, and approved; unsupported combinations require documented assessment; the update procedure identifies the lean regression subset to rerun. |  | Not executed |

*Table 7.5:* Test steps

| **Postconditions or action after execution** |
| --- |
| Remove test peers, keys, routes, and temporary policies/resources or restore the approved baseline; retain redacted evidence only. |

*Table 7.6:* Postconditions or action after execution

| **Comment** |
| --- |
|  |

*Table 7.7:* Comments

|  |  |  |  |
| --- | --- | --- | --- |
| **Test result** | **[ ] Passed  [ ] Not passed  [x] Not executed** | **Reference Nr. deviation / bug report** |  |

*Table 7.8:* Test result

# Protocol completion

| **Passed** | **Not passed** | **Blocked** | **Not executed** |
| --- | --- | --- | --- |
| 0 | 0 | 0 | 7 |

| **Role** | **Name** | **Date** | **Approval/signature reference** |
| --- | --- | --- | --- |
| Tester | TBD | TBD | TBD |
| Reviewer | TBD | TBD | TBD |

Overall protocol result: **[ ] Passed  [ ] Passed with accepted deviations  [ ] Not passed  [x] Not executed**
