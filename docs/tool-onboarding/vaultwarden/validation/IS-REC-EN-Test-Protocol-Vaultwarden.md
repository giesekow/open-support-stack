# IS-REC-EN-Test-Protocol-Vaultwarden-2026-09

**Table of contents**

# Meta information

| **Document type** | Test Protocol and Execution Record |
| --- | --- |
| **Version** | 0.4 |
| **Status** | Execution in progress; formal review and signatures pending |
| **Last release date** | Not released |
| **Page ID** | TBD after publication |
| **Last change to the document** | Command-based security and restore checks executed; encrypted user-workflow checks remain pending. |

# Test protocol

Execution rules: use only dedicated test data; mask credentials, tokens, personal data, and customer data; record evidence references and timestamps; record each discrepancy before proceeding where safe. Evidence may be reused for multiple requirements when traceability is explicit. Command and interactive evidence must follow [the evidence requirements](evidence/README.md).

## Test #1: Account onboarding, authentication, and revocation lifecycle

|  |  |
| --- | --- |
| **Test ID** | **Title** |
| VW-T01 | Account onboarding, authentication, and revocation lifecycle |

*Table 1.1:* Test identification

| **System identification** | **Test goal** | **Acceptance criterion** |
| --- | --- | --- |
| Vaultwarden | Verify the approved configuration for: account onboarding, authentication, and revocation lifecycle. | Invitation uses the approved sender/public URL without exposing secrets; approved login succeeds; signup and invalid/unauthenticated access fail; removed member cannot obtain new organization data. Any local-cache limitation is documented in the offboarding procedure. |

*Table 1.2:* System identification

| **Test run** | **Start date/time** | **End date/time** |
| --- | --- | --- |
| 0001 | TBD | TBD |

*Table 1.3:* Run through

| **Requirement** |
| --- |
| Requirement IDs: VW-LOGIN-001, VW-ACCESS-001, VW-SMTP-001, VW-OFFBOARD-001. Approved Vaultwarden test environment; dedicated test users and disposable credentials; secrets masked in evidence. |

*Table 1.4:* Requirements

| **Test step** | **Requirement-ID** | **Action** | **Data to be recorded** | **Expected results** | **Actual results** | **Passed / not passed** |
| --- | --- | --- | --- | --- | --- | --- |
| 1.1 | VW-LOGIN-001, VW-ACCESS-001, VW-SMTP-001, VW-OFFBOARD-001 | Confirm public signup is disabled. Invite a disposable member through approved SMTP, authenticate successfully, then try an invalid password and unauthenticated access. Remove the member and attempt fresh web and client synchronization access. | Redacted screenshots, command/API output, configuration identifiers, and evidence reference as applicable | Invitation uses the approved sender/public URL without exposing secrets; approved login succeeds; signup and invalid/unauthenticated access fail; removed member cannot obtain new organization data. Any local-cache limitation is documented in the offboarding procedure. |  | Not executed |

*Table 1.5:* Test steps

| **Postconditions or action after execution** |
| --- |
| Remove disposable users/items and retain only approved redacted evidence. For restore testing, remove the isolated restore target according to procedure. |

*Table 1.6:* Postconditions or action after execution

| **Comment** |
| --- |
|  |

*Table 1.7:* Comments

|  |  |  |  |
| --- | --- | --- | --- |
| **Test result** | **[ ] Passed  [ ] Not passed  [x] Not executed** | **Reference Nr. deviation / bug report** |  |

*Table 1.8:* Test result

## Test #2: Organization and collection authorization

|  |  |
| --- | --- |
| **Test ID** | **Title** |
| VW-T02 | Organization and collection authorization |

*Table 2.1:* Test identification

| **System identification** | **Test goal** | **Acceptance criterion** |
| --- | --- | --- |
| Vaultwarden | Verify the approved configuration for: organization and collection authorization. | Each user sees and changes only authorized content; unauthorized collection access and prohibited role actions are denied. |

*Table 2.2:* System identification

| **Test run** | **Start date/time** | **End date/time** |
| --- | --- | --- |
| 0001 | 2026-09-25 22:13 UTC | 2026-09-25 22:13 UTC |

*Table 2.3:* Run through

| **Requirement** |
| --- |
| Requirement IDs: VW-ORG-001, VW-ACCESS-001. Approved Vaultwarden test environment; dedicated test users and disposable credentials; secrets masked in evidence. |

*Table 2.4:* Requirements

| **Test step** | **Requirement-ID** | **Action** | **Data to be recorded** | **Expected results** | **Actual results** | **Passed / not passed** |
| --- | --- | --- | --- | --- | --- | --- |
| 2.1 | VW-ORG-001, VW-ACCESS-001 | Create two collections; grant User A access only to Collection A and User B only to Collection B; attempt authorized and unauthorized reads/edits and an applicable read-only action. | Redacted screenshots, command/API output, configuration identifiers, and evidence reference as applicable | Each user sees and changes only authorized content; unauthorized collection access and prohibited role actions are denied. | Both users had the User role without all-collection access. User A could see and edit only Collection A. User B could see only Collection B; read-only editing was denied. Neither user could see the other collection. Evidence: VW-E03. | Passed |

*Table 2.5:* Test steps

| **Postconditions or action after execution** |
| --- |
| Remove disposable users/items and retain only approved redacted evidence. For restore testing, remove the isolated restore target according to procedure. |

*Table 2.6:* Postconditions or action after execution

| **Comment** |
| --- |
|  |

*Table 2.7:* Comments

|  |  |  |  |
| --- | --- | --- | --- |
| **Test result** | **[x] Passed  [ ] Not passed  [ ] Not executed** | **Reference Nr. deviation / bug report** | None |

*Table 2.8:* Test result

## Test #3: Client synchronization

|  |  |
| --- | --- |
| **Test ID** | **Title** |
| VW-T03 | Client synchronization |

*Table 3.1:* Test identification

| **System identification** | **Test goal** | **Acceptance criterion** |
| --- | --- | --- |
| Vaultwarden | Verify the approved configuration for: client synchronization. | The same item and approved update are visible in both clients without duplicate, missing, or stale data. |

*Table 3.2:* System identification

| **Test run** | **Start date/time** | **End date/time** |
| --- | --- | --- |
| 0001 | 2026-09-25 22:22 UTC | 2026-09-25 22:22 UTC |

*Table 3.3:* Run through

| **Requirement** |
| --- |
| Requirement IDs: VW-SYNC-001. Approved Vaultwarden test environment; dedicated test users and disposable credentials; secrets masked in evidence. |

*Table 3.4:* Requirements

| **Test step** | **Requirement-ID** | **Action** | **Data to be recorded** | **Expected results** | **Actual results** | **Passed / not passed** |
| --- | --- | --- | --- | --- | --- | --- |
| 3.1 | VW-SYNC-001 | Create a disposable item in the web vault; synchronize an approved browser/desktop client; modify it in the client; synchronize back. | Redacted screenshots, command/API output, configuration identifiers, and evidence reference as applicable | The same item and approved update are visible in both clients without duplicate, missing, or stale data. | The item synchronized exactly once from web to the approved client. The client-side non-secret marker synchronized back to the web vault without duplicate, missing, or stale data. Evidence: VW-E03. | Passed |

*Table 3.5:* Test steps

| **Postconditions or action after execution** |
| --- |
| Remove disposable users/items and retain only approved redacted evidence. For restore testing, remove the isolated restore target according to procedure. |

*Table 3.6:* Postconditions or action after execution

| **Comment** |
| --- |
|  |

*Table 3.7:* Comments

|  |  |  |  |
| --- | --- | --- | --- |
| **Test result** | **[x] Passed  [ ] Not passed  [ ] Not executed** | **Reference Nr. deviation / bug report** | None |

*Table 3.8:* Test result

## Test #4: Security, version, and operating readiness

|  |  |
| --- | --- |
| **Test ID** | **Title** |
| VW-T04 | Security, version, and operating readiness |

*Table 4.1:* Test identification

| **System identification** | **Test goal** | **Acceptance criterion** |
| --- | --- | --- |
| Vaultwarden | Verify the approved configuration for: security, version, and operating readiness. | Valid HTTPS is enforced; sensitive storage/configuration is not publicly reachable and is administratively restricted; versions match the approved baseline; update and user/admin instructions cover backup, security review, sharing, recovery, prohibited content, and offboarding. |

*Table 4.2:* System identification

| **Test run** | **Start date/time** | **End date/time** |
| --- | --- | --- |
| 0001 | 2026-09-25 21:27 UTC | 2026-09-25 21:28 UTC |

*Table 4.3:* Run through

| **Requirement** |
| --- |
| Requirement IDs: VW-SEC-001, VW-SEC-002, VW-CHANGE-001, VW-TRAIN-001. Approved Vaultwarden test environment; dedicated test users and disposable credentials; secrets masked in evidence. |

*Table 4.4:* Requirements

| **Test step** | **Requirement-ID** | **Action** | **Data to be recorded** | **Expected results** | **Actual results** | **Passed / not passed** |
| --- | --- | --- | --- | --- | --- | --- |
| 4.1 | VW-SEC-001, VW-SEC-002, VW-CHANGE-001, VW-TRAIN-001 | Inspect HTTPS/certificate and HTTP behavior; confirm admin/data/config paths are not publicly served; record server/client versions; review update controls and role-appropriate operating instructions. Do not display secret values. | Redacted screenshots, command/API output, configuration identifiers, and evidence reference as applicable | Valid HTTPS is enforced; sensitive storage/configuration is not publicly reachable and is administratively restricted; versions match the approved baseline; update and user/admin instructions cover backup, security review, sharing, recovery, prohibited content, and offboarding. | Valid HTTPS and certificate verification passed; HTTP was denied; unauthenticated synchronization and admin diagnostics returned 401; data/config paths returned 404; no host port was published; registration is disabled; the admin token is Argon2id-protected; SMTP controls are configured and verified TLS 1.3 connectivity to the SMTP endpoint; the environment file is owner-only; runtime versions were recorded; and the operating guide covers sharing, recovery, prohibited content, offline-cache offboarding, backup, and updates. Evidence: VW-E01. | Passed |

*Table 4.5:* Test steps

| **Postconditions or action after execution** |
| --- |
| Remove disposable users/items and retain only approved redacted evidence. For restore testing, remove the isolated restore target according to procedure. |

*Table 4.6:* Postconditions or action after execution

| **Comment** |
| --- |
|  |

*Table 4.7:* Comments

|  |  |  |  |
| --- | --- | --- | --- |
| **Test result** | **[x] Passed  [ ] Not passed  [ ] Not executed** | **Reference Nr. deviation / bug report** |  |

*Table 4.8:* Test result

## Test #5: Backup and isolated restore

|  |  |
| --- | --- |
| **Test ID** | **Title** |
| VW-T05 | Backup and isolated restore |

*Table 5.1:* Test identification

| **System identification** | **Test goal** | **Acceptance criterion** |
| --- | --- | --- |
| Vaultwarden | Verify the approved configuration for: backup and isolated restore. | Restore completes without affecting production; test account, organization membership, collection permissions, and item are usable and consistent; no secret is retained in evidence. |

*Table 5.2:* System identification

| **Test run** | **Start date/time** | **End date/time** |
| --- | --- | --- |
| 0001 | 2026-09-25 21:29 UTC | 2026-09-25 21:30 UTC |

*Table 5.3:* Run through

| **Requirement** |
| --- |
| Requirement IDs: VW-BACKUP-001. Approved Vaultwarden test environment; dedicated test users and disposable credentials; secrets masked in evidence. |

*Table 5.4:* Requirements

| **Test step** | **Requirement-ID** | **Action** | **Data to be recorded** | **Expected results** | **Actual results** | **Passed / not passed** |
| --- | --- | --- | --- | --- | --- | --- |
| 5.1 | VW-BACKUP-001 | Create identifiable disposable vault and collection data; take the documented backup; restore to an isolated target; authenticate and retrieve restored test data and permissions. | Redacted screenshots, command/API output, configuration identifiers, and evidence reference as applicable | Restore completes without affecting production; test account, organization membership, collection permissions, and item are usable and consistent; no secret is retained in evidence. | Vaultwarden created an online SQLite backup; database and archives passed integrity checks; the protected backup is owner-only; aggregate users, organizations, collections, ciphers, and membership counts matched after isolated restoration; the restored service returned HTTP 200 with no published port; isolated resources were removed and production remained healthy. Manual authentication and encrypted test item/permission retrieval remain pending. Evidence: VW-E02 and VW-E03. | Blocked - manual encrypted-data check pending |

*Table 5.5:* Test steps

| **Postconditions or action after execution** |
| --- |
| Remove disposable users/items and retain only approved redacted evidence. For restore testing, remove the isolated restore target according to procedure. |

*Table 5.6:* Postconditions or action after execution

| **Comment** |
| --- |
| Infrastructure restore passed. Final acceptance is blocked only by the manual restored-login and encrypted item/permission check. |

*Table 5.7:* Comments

|  |  |  |  |
| --- | --- | --- | --- |
| **Test result** | **[ ] Passed  [ ] Not passed  [ ] Not executed  [x] Blocked** | **Reference Nr. deviation / bug report** |  |

*Table 5.8:* Test result

# Protocol completion

| **Passed** | **Not passed** | **Blocked** | **Not executed** |
| --- | --- | --- | --- |
| 3 | 0 | 1 | 1 |

| **Role** | **Name** | **Date** | **Approval/signature reference** |
| --- | --- | --- | --- |
| Tester | TBD | TBD | TBD |
| Reviewer | TBD | TBD | TBD |

Overall protocol result: **[ ] Passed  [ ] Passed with accepted deviations  [ ] Not passed  [x] Not executed - execution remains in progress**
