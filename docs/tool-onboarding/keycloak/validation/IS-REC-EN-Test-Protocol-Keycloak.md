# IS-REC-EN-Test-Protocol-Keycloak-2026-09

**Table of contents**

# Meta information

| **Document type** | Test Protocol and Execution Record |
| --- | --- |
| **Version** | 0.7 |
| **Status** | Executed - passed; review and signatures pending |
| **Last release date** | Not released |
| **Page ID** | TBD after publication |
| **Last change to the document** | Added command-level evidence transcripts and explicit historical-evidence limitations; all eight tests pass. |

# Test protocol

Execution rules: use only dedicated test data; mask credentials, tokens, personal data, and customer data; record evidence references and timestamps; record each discrepancy before proceeding where safe. Evidence may be reused for multiple requirements when traceability is explicit. Command-based evidence must also include the complete sanitized command, relevant response/output and status, assertions, cleanup proof, and reusable-script hash where applicable; summary-only evidence is insufficient. See [evidence requirements](evidence/README.md). KC-E02 and KC-E13 through KC-E16 are explicitly identified supplemental reruns captured after the original runs; they corroborate current controls and are not presented as reconstructed historical output.

## Test #1: Authentication and MFA decision matrix

|  |  |
| --- | --- |
| **Test ID** | **Title** |
| KC-T01 | Authentication and MFA decision matrix |

*Table 1.1:* Test identification

| **System identification** | **Test goal** | **Acceptance criterion** |
| --- | --- | --- |
| Keycloak | Verify the approved configuration for: authentication and mfa decision matrix. | Active user with correct factors succeeds; every invalid, disabled, missing-factor, and unauthorized case fails without sensitive disclosure; designated roles require MFA. |

*Table 1.2:* System identification

| **Test run** | **Start date/time** | **End date/time** |
| --- | --- | --- |
| 0001 | 2026-09-25 15:39 UTC | 2026-09-25 15:55 UTC |
| 0002 (remediation revalidation) | 2026-09-25 18:51 UTC | 2026-09-25 19:08 UTC |
| 0003 (interactive MFA completion) | 2026-09-25 19:26 UTC | 2026-09-25 19:26 UTC |

*Table 1.3:* Run through

| **Requirement** |
| --- |
| Requirement IDs: KC-AUTH-001, KC-AUTH-002, KC-MFA-001. Approved production-representative realm; dedicated active, disabled, MFA, and administrator identities; representative clients; secrets and tokens redacted. |

*Table 1.4:* Requirements

| **Test step** | **Requirement-ID** | **Action** | **Data to be recorded** | **Expected results** | **Actual results** | **Passed / not passed** |
| --- | --- | --- | --- | --- | --- | --- |
| 1.1 | KC-AUTH-001, KC-AUTH-002, KC-MFA-001 | Authenticate an active MFA-enforced user to a representative client; try a wrong password, missing/incorrect second factor, disabled user, and unauthorized client flow; inspect administrator MFA enforcement. | Redacted screenshots, command/API output, configuration identifiers, and evidence reference as applicable | Active user with correct factors succeeds; every invalid, disabled, missing-factor, and unauthorized case fails without sensitive disclosure; designated roles require MFA. | Run 0001 found privileged MFA and brute-force gaps. Run 0002 enabled and revalidated brute-force protection and made TOTP enrollment mandatory. In run 0003, the single user shared by both privileged groups completed TOTP enrollment; missing and incorrect OTP attempts were rejected, correct OTP succeeded, and server-side verification found one OTP credential and no pending enrollment action. Evidence: KC-E01, KC-E01b, KC-E01c, KC-E02, KC-E10, KC-E12, KC-E13, KC-E14. | Passed |

*Table 1.5:* Test steps

| **Postconditions or action after execution** |
| --- |
| Remove test identities/clients and temporary secrets, restore the approved configuration baseline, and retain only redacted evidence. |

*Table 1.6:* Postconditions or action after execution

| **Comment** |
| --- |
|  |

*Table 1.7:* Comments

|  |  |  |  |
| --- | --- | --- | --- |
| **Test result** | **[x] Passed  [ ] Not passed  [ ] Not executed** | **Reference Nr. deviation / bug report** | KC-DEV-001 closed in run 0003; KC-DEV-002 closed in run 0002 |

*Table 1.8:* Test result

## Test #2: Group and role claims

|  |  |
| --- | --- |
| **Test ID** | **Title** |
| KC-T02 | Group and role claims |

*Table 2.1:* Test identification

| **System identification** | **Test goal** | **Acceptance criterion** |
| --- | --- | --- |
| Keycloak | Verify the approved configuration for: group and role claims. | Only client-required claims are present; removal changes subsequent claims and access as designed. |

*Table 2.2:* System identification

| **Test run** | **Start date/time** | **End date/time** |
| --- | --- | --- |
| 0001 | 2026-09-25 15:39 UTC | 2026-09-25 15:55 UTC |

*Table 2.3:* Run through

| **Requirement** |
| --- |
| Requirement IDs: KC-CLAIM-001. Approved production-representative realm; dedicated active, disabled, MFA, and administrator identities; representative clients; secrets and tokens redacted. |

*Table 2.4:* Requirements

| **Test step** | **Requirement-ID** | **Action** | **Data to be recorded** | **Expected results** | **Actual results** | **Passed / not passed** |
| --- | --- | --- | --- | --- | --- | --- |
| 2.1 | KC-CLAIM-001 | Assign and remove approved test groups/roles; inspect redacted token/userinfo claims and representative application behavior. | Redacted screenshots, command/API output, configuration identifiers, and evidence reference as applicable | Only client-required claims are present; removal changes subsequent claims and access as designed. | The dedicated group claim was present before membership removal and absent from the next token after removal. No token value was retained. Evidence: KC-E02. | Passed |

*Table 2.5:* Test steps

| **Postconditions or action after execution** |
| --- |
| Remove test identities/clients and temporary secrets, restore the approved configuration baseline, and retain only redacted evidence. |

*Table 2.6:* Postconditions or action after execution

| **Comment** |
| --- |
|  |

*Table 2.7:* Comments

|  |  |  |  |
| --- | --- | --- | --- |
| **Test result** | **[x] Passed  [ ] Not passed  [ ] Not executed** | **Reference Nr. deviation / bug report** |  |

*Table 2.8:* Test result

## Test #3: Client boundary and secret lifecycle

|  |  |
| --- | --- |
| **Test ID** | **Title** |
| KC-T03 | Client boundary and secret lifecycle |

*Table 3.1:* Test identification

| **System identification** | **Test goal** | **Acceptance criterion** |
| --- | --- | --- |
| Keycloak | Verify the approved configuration for: client boundary and secret lifecycle. | Only exact approved redirects/origins and current secret work; unauthorized variants and old/incorrect secrets fail; secret values never enter evidence. |

*Table 3.2:* System identification

| **Test run** | **Start date/time** | **End date/time** |
| --- | --- | --- |
| 0001 | 2026-09-25 15:39 UTC | 2026-09-25 15:55 UTC |
| 0002 (remediation revalidation) | 2026-09-25 18:51 UTC | 2026-09-25 19:08 UTC |

*Table 3.3:* Run through

| **Requirement** |
| --- |
| Requirement IDs: KC-CLIENT-001, KC-SECRET-001. Approved production-representative realm; dedicated active, disabled, MFA, and administrator identities; representative clients; secrets and tokens redacted. |

*Table 3.4:* Requirements

| **Test step** | **Requirement-ID** | **Action** | **Data to be recorded** | **Expected results** | **Actual results** | **Passed / not passed** |
| --- | --- | --- | --- | --- | --- | --- |
| 3.1 | KC-CLIENT-001, KC-SECRET-001 | Authenticate with the approved redirect and confidential-client secret; try modified host/scheme/port/path origins and an incorrect secret; rotate the secret in a controlled environment and update the relying client. | Redacted screenshots, command/API output, configuration identifiers, and evidence reference as applicable | Only exact approved redirects/origins and current secret work; unauthorized variants and old/incorrect secrets fail; secret values never enter evidence. | Run 0001 proved exact matching and secret rotation but found broad production callbacks. Run 0002 synchronized ten managed clients to exact HTTPS callbacks: all ten exact callbacks were accepted and all ten altered paths returned HTTP 400. The managed-client audit found zero HTTP and zero wildcard entries; OrangeHRM emitted its exact HTTPS callback while retaining internal server-side OIDC endpoints. Evidence: KC-E02, KC-E03, KC-E11, KC-E13, KC-E16. | Passed |

*Table 3.5:* Test steps

| **Postconditions or action after execution** |
| --- |
| Remove test identities/clients and temporary secrets, restore the approved configuration baseline, and retain only redacted evidence. |

*Table 3.6:* Postconditions or action after execution

| **Comment** |
| --- |
|  |

*Table 3.7:* Comments

|  |  |  |  |
| --- | --- | --- | --- |
| **Test result** | **[x] Passed  [ ] Not passed  [ ] Not executed** | **Reference Nr. deviation / bug report** | KC-DEV-003 closed in run 0002 |

*Table 3.8:* Test result

## Test #4: User and session lifecycle

|  |  |
| --- | --- |
| **Test ID** | **Title** |
| KC-T04 | User and session lifecycle |

*Table 4.1:* Test identification

| **System identification** | **Test goal** | **Acceptance criterion** |
| --- | --- | --- |
| Keycloak | Verify the approved configuration for: user and session lifecycle. | Settings match the approved baseline; clocks are synchronized; logout/revocation invalidates access as designed; new login and removed-group access fail within approved timing. |

*Table 4.2:* System identification

| **Test run** | **Start date/time** | **End date/time** |
| --- | --- | --- |
| 0001 | 2026-09-25 15:39 UTC | 2026-09-25 15:55 UTC |

*Table 4.3:* Run through

| **Requirement** |
| --- |
| Requirement IDs: KC-OFFBOARD-001, KC-SESSION-001. Approved production-representative realm; dedicated active, disabled, MFA, and administrator identities; representative clients; secrets and tokens redacted. |

*Table 4.4:* Requirements

| **Test step** | **Requirement-ID** | **Action** | **Data to be recorded** | **Expected results** | **Actual results** | **Passed / not passed** |
| --- | --- | --- | --- | --- | --- | --- |
| 4.1 | KC-OFFBOARD-001, KC-SESSION-001 | Record token/session idle/max settings and clock state; establish a session, test logout, then disable the user/remove its access group and revoke sessions; attempt existing and new access. | Redacted screenshots, command/API output, configuration identifiers, and evidence reference as applicable | Settings match the approved baseline; clocks are synchronized; logout/revocation invalidates access as designed; new login and removed-group access fail within approved timing. | Realm lifetimes were recorded; NTP was synchronized with 0-second host/container delta. Group removal affected the next token; logout plus disablement made the prior token inactive and prevented new login. Evidence: KC-E01, KC-E02, KC-E04, KC-E13. | Passed |

*Table 4.5:* Test steps

| **Postconditions or action after execution** |
| --- |
| Remove test identities/clients and temporary secrets, restore the approved configuration baseline, and retain only redacted evidence. |

*Table 4.6:* Postconditions or action after execution

| **Comment** |
| --- |
|  |

*Table 4.7:* Comments

|  |  |  |  |
| --- | --- | --- | --- |
| **Test result** | **[x] Passed  [ ] Not passed  [ ] Not executed** | **Reference Nr. deviation / bug report** |  |

*Table 4.8:* Test result

## Test #5: Administrative separation

|  |  |
| --- | --- |
| **Test ID** | **Title** |
| KC-T05 | Administrative separation |

*Table 5.1:* Test identification

| **System identification** | **Test goal** | **Acceptance criterion** |
| --- | --- | --- |
| Keycloak | Verify the approved configuration for: administrative separation. | Ordinary user is denied; approved administrator succeeds with only assigned privileges. |

*Table 5.2:* System identification

| **Test run** | **Start date/time** | **End date/time** |
| --- | --- | --- |
| 0001 | 2026-09-25 15:39 UTC | 2026-09-25 15:55 UTC |
| 0002 (remediation revalidation) | 2026-09-25 18:51 UTC | 2026-09-25 19:08 UTC |
| 0003 (interactive MFA completion) | 2026-09-25 19:26 UTC | 2026-09-25 19:26 UTC |

*Table 5.3:* Run through

| **Requirement** |
| --- |
| Requirement IDs: KC-ADMIN-001. Approved production-representative realm; dedicated active, disabled, MFA, and administrator identities; representative clients; secrets and tokens redacted. |

*Table 5.4:* Requirements

| **Test step** | **Requirement-ID** | **Action** | **Data to be recorded** | **Expected results** | **Actual results** | **Passed / not passed** |
| --- | --- | --- | --- | --- | --- | --- |
| 5.1 | KC-ADMIN-001 | Attempt realm administration as an ordinary user; sign in as a named MFA-protected administrator and inspect assigned realm/admin roles. | Redacted screenshots, command/API output, configuration identifiers, and evidence reference as applicable | Ordinary user is denied; approved administrator succeeds with only assigned privileges. | The admin API returned 403 for an ordinary-user token. Run 0002 assigned 11 reviewed delegated `realm-management` roles to `platform-admin`. In run 0003, the named MFA-protected administrator opened the Support realm console while Master realm access and impersonation remained unavailable; server-side verification confirmed no `realm-admin` or `impersonation` role. Evidence: KC-E01c, KC-E02, KC-E10, KC-E12, KC-E13. | Passed |

*Table 5.5:* Test steps

| **Postconditions or action after execution** |
| --- |
| Remove test identities/clients and temporary secrets, restore the approved configuration baseline, and retain only redacted evidence. |

*Table 5.6:* Postconditions or action after execution

| **Comment** |
| --- |
|  |

*Table 5.7:* Comments

|  |  |  |  |
| --- | --- | --- | --- |
| **Test result** | **[x] Passed  [ ] Not passed  [ ] Not executed** | **Reference Nr. deviation / bug report** | KC-DEV-001 and KC-DEV-004 closed in run 0003 |

*Table 5.8:* Test result

## Test #6: HTTPS issuer and production exposure baseline

|  |  |
| --- | --- |
| **Test ID** | **Title** |
| KC-T06 | HTTPS issuer and production exposure baseline |

*Table 6.1:* Test identification

| **System identification** | **Test goal** | **Acceptance criterion** |
| --- | --- | --- |
| Keycloak | Verify the approved configuration for: https issuer and production exposure baseline. | Public issuer/browser endpoints use the approved valid HTTPS hostname; HTTP redirects/denies; backend is restricted; production mode is active with no development warning; proxy trust matches baseline. |

*Table 6.2:* System identification

| **Test run** | **Start date/time** | **End date/time** |
| --- | --- | --- |
| 0001 | 2026-09-25 15:39 UTC | 2026-09-25 15:55 UTC |

*Table 6.3:* Run through

| **Requirement** |
| --- |
| Requirement IDs: KC-TLS-001, KC-PROD-001. Approved production-representative realm; dedicated active, disabled, MFA, and administrator identities; representative clients; secrets and tokens redacted. |

*Table 6.4:* Requirements

| **Test step** | **Requirement-ID** | **Action** | **Data to be recorded** | **Expected results** | **Actual results** | **Passed / not passed** |
| --- | --- | --- | --- | --- | --- | --- |
| 6.1 | KC-TLS-001, KC-PROD-001 | Fetch OIDC discovery; inspect issuer/endpoints/certificate, HTTP behavior, direct backend exposure, runtime command/profile/logs, hostname, and trusted-proxy settings. | Redacted screenshots, command/API output, configuration identifiers, and evidence reference as applicable | Public issuer/browser endpoints use the approved valid HTTPS hostname; HTTP redirects/denies; backend is restricted; production mode is active with no development warning; proxy trust matches baseline. | Discovery reported the approved HTTPS issuer; certificate verification passed; HTTP was denied with 503; Keycloak had no host-published port and used production start mode, strict hostname, and xforwarded proxy headers with no development warning. Evidence: KC-E00, KC-E06, KC-E13. | Passed |

*Table 6.5:* Test steps

| **Postconditions or action after execution** |
| --- |
| Remove test identities/clients and temporary secrets, restore the approved configuration baseline, and retain only redacted evidence. |

*Table 6.6:* Postconditions or action after execution

| **Comment** |
| --- |
|  |

*Table 6.7:* Comments

|  |  |  |  |
| --- | --- | --- | --- |
| **Test result** | **[x] Passed  [ ] Not passed  [ ] Not executed** | **Reference Nr. deviation / bug report** |  |

*Table 6.8:* Test result

## Test #7: Backup and isolated restore

|  |  |
| --- | --- |
| **Test ID** | **Title** |
| KC-T07 | Backup and isolated restore |

*Table 7.1:* Test identification

| **System identification** | **Test goal** | **Acceptance criterion** |
| --- | --- | --- |
| Keycloak | Verify the approved configuration for: backup and isolated restore. | Realm, users, groups, clients, roles, and required secrets are usable after restore; production is unaffected and no secret appears in evidence. |

*Table 7.2:* System identification

| **Test run** | **Start date/time** | **End date/time** |
| --- | --- | --- |
| 0001 | 2026-09-25 15:39 UTC | 2026-09-25 15:55 UTC |

*Table 7.3:* Run through

| **Requirement** |
| --- |
| Requirement IDs: KC-BACKUP-001. Approved production-representative realm; dedicated active, disabled, MFA, and administrator identities; representative clients; secrets and tokens redacted. |

*Table 7.4:* Requirements

| **Test step** | **Requirement-ID** | **Action** | **Data to be recorded** | **Expected results** | **Actual results** | **Passed / not passed** |
| --- | --- | --- | --- | --- | --- | --- |
| 7.1 | KC-BACKUP-001 | Create a uniquely named test user/group/client; back up database and required configuration/secrets; restore to an isolated target; test discovery and controlled login. | Redacted screenshots, command/API output, configuration identifiers, and evidence reference as applicable | Realm, users, groups, clients, roles, and required secrets are usable after restore; production is unaffected and no secret appears in evidence. | A protected backup restored an isolated realm containing the synthetic user, group, role, client, and usable client secret. Discovery and controlled login returned 200; no ports were published; all temporary resources were removed. Evidence: KC-E07, KC-E15. | Passed |

*Table 7.5:* Test steps

| **Postconditions or action after execution** |
| --- |
| Remove test identities/clients and temporary secrets, restore the approved configuration baseline, and retain only redacted evidence. |

*Table 7.6:* Postconditions or action after execution

| **Comment** |
| --- |
|  |

*Table 7.7:* Comments

|  |  |  |  |
| --- | --- | --- | --- |
| **Test result** | **[x] Passed  [ ] Not passed  [ ] Not executed** | **Reference Nr. deviation / bug report** |  |

*Table 7.8:* Test result

## Test #8: Configuration synchronization and release baseline

|  |  |
| --- | --- |
| **Test ID** | **Title** |
| KC-T08 | Configuration synchronization and release baseline |

*Table 8.1:* Test identification

| **System identification** | **Test goal** | **Acceptance criterion** |
| --- | --- | --- |
| Keycloak | Verify the approved configuration for: configuration synchronization and release baseline. | Versions match the approved baseline; first sync makes only approved changes; second run is idempotent where intended; no unrelated clients change; update process covers backup, migration, rollback, security review, and lean regression testing. |

*Table 8.2:* System identification

| **Test run** | **Start date/time** | **End date/time** |
| --- | --- | --- |
| 0001 | 2026-09-25 15:39 UTC | 2026-09-25 15:55 UTC |
| 0002 (remediation revalidation) | 2026-09-25 18:51 UTC | 2026-09-25 19:08 UTC |

*Table 8.3:* Run through

| **Requirement** |
| --- |
| Requirement IDs: KC-CONFIG-001, KC-CHANGE-001. Approved production-representative realm; dedicated active, disabled, MFA, and administrator identities; representative clients; secrets and tokens redacted. |

*Table 8.4:* Requirements

| **Test step** | **Requirement-ID** | **Action** | **Data to be recorded** | **Expected results** | **Actual results** | **Passed / not passed** |
| --- | --- | --- | --- | --- | --- | --- |
| 8.1 | KC-CONFIG-001, KC-CHANGE-001 | Record Keycloak/PostgreSQL versions or digests; render controlled configuration; run client synchronization against the test environment twice; compare changes and review update/rollback controls. | Redacted screenshots, command/API output, configuration identifiers, and evidence reference as applicable | Versions match the approved baseline; first sync makes only approved changes; second run is idempotent where intended; no unrelated clients change; update process covers backup, migration, rollback, security review, and lean regression testing. | Run 0001 established synchronization repeatability but found a mutable and outdated runtime. Before run 0002, protected backups were created and a 25.x-to-26.7.4 migration was rehearsed against an isolated restored database. Production then migrated successfully to Keycloak 26.7.4 using an immutable image digest; discovery, production profile, realm access, exact redirects, hardening, and repeated synchronization passed. Rollback requires restoration of the pre-migration database and matching configuration. Evidence: KC-E00, KC-E08, KC-E09, KC-E10, KC-E11, KC-E13, KC-E15, KC-E16. | Passed |

*Table 8.5:* Test steps

| **Postconditions or action after execution** |
| --- |
| Remove test identities/clients and temporary secrets, restore the approved configuration baseline, and retain only redacted evidence. |

*Table 8.6:* Postconditions or action after execution

| **Comment** |
| --- |
|  |

*Table 8.7:* Comments

|  |  |  |  |
| --- | --- | --- | --- |
| **Test result** | **[x] Passed  [ ] Not passed  [ ] Not executed** | **Reference Nr. deviation / bug report** | KC-DEV-005 closed in run 0002 |

*Table 8.8:* Test result

# Protocol completion

| **Passed** | **Not passed** | **Blocked** | **Not executed** |
| --- | --- | --- | --- |
| 8 | 0 | 0 | 0 |

| **Role** | **Name** | **Date** | **Approval/signature reference** |
| --- | --- | --- | --- |
| Tester | TBD | TBD | TBD |
| Reviewer | TBD | TBD | TBD |

Overall protocol result: **[x] Passed  [ ] Passed with accepted deviations  [ ] Not passed  [ ] Not executed**
