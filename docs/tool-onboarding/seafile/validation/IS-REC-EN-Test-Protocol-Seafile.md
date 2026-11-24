# IS-REC-EN-Test-Protocol-Seafile-2026-09

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

## Test #1: Identity integration and authorization

|  |  |
| --- | --- |
| **Test ID** | **Title** |
| SF-T01 | Identity integration and authorization |

*Table 1.1:* Test identification

| **System identification** | **Test goal** | **Acceptance criterion** |
| --- | --- | --- |
| Seafile | Verify the approved configuration for: identity integration and authorization. | Approved users authenticate and access only explicitly authorized content; disabled, unauthenticated, cross-library, and prohibited write access fail. |

*Table 1.2:* System identification

| **Test run** | **Start date/time** | **End date/time** |
| --- | --- | --- |
| 0001 | TBD | TBD |

*Table 1.3:* Run through

| **Requirement** |
| --- |
| Requirement IDs: SF-LOGIN-001, SF-ACCESS-001. Approved immutable Seafile image/digest; disposable users and synthetic files; approved upload limit; hashes recorded before transfer; no sensitive records used. |

*Table 1.4:* Requirements

| **Test step** | **Requirement-ID** | **Action** | **Data to be recorded** | **Expected results** | **Actual results** | **Passed / not passed** |
| --- | --- | --- | --- | --- | --- | --- |
| 1.1 | SF-LOGIN-001, SF-ACCESS-001 | Authenticate through the approved identity flow as User A and B; attempt a disabled identity and unauthenticated URL. Create separate libraries, share only one controlled folder, and attempt discovery/read/write outside each permission. | Redacted screenshots, command/API output, configuration identifiers, and evidence reference as applicable | Approved users authenticate and access only explicitly authorized content; disabled, unauthenticated, cross-library, and prohibited write access fail. |  | Not executed |

*Table 1.5:* Test steps

| **Postconditions or action after execution** |
| --- |
| Revoke test shares/users, remove synthetic files according to disposition procedure, and remove the isolated restore target after evidence approval. |

*Table 1.6:* Postconditions or action after execution

| **Comment** |
| --- |
|  |

*Table 1.7:* Comments

|  |  |  |  |
| --- | --- | --- | --- |
| **Test result** | **[ ] Passed  [ ] Not passed  [x] Not executed** | **Reference Nr. deviation / bug report** |  |

*Table 1.8:* Test result

## Test #2: Transfer integrity and size boundaries

|  |  |
| --- | --- |
| **Test ID** | **Title** |
| SF-T02 | Transfer integrity and size boundaries |

*Table 2.1:* Test identification

| **System identification** | **Test goal** | **Acceptance criterion** |
| --- | --- | --- |
| Seafile | Verify the approved configuration for: transfer integrity and size boundaries. | Within-limit files succeed with matching hashes; over-limit upload is clearly rejected and creates no retrievable partial object or misleading success. |

*Table 2.2:* System identification

| **Test run** | **Start date/time** | **End date/time** |
| --- | --- | --- |
| 0001 | TBD | TBD |

*Table 2.3:* Run through

| **Requirement** |
| --- |
| Requirement IDs: SF-INTEGRITY-001, SF-UPLOAD-001. Approved immutable Seafile image/digest; disposable users and synthetic files; approved upload limit; hashes recorded before transfer; no sensitive records used. |

*Table 2.4:* Requirements

| **Test step** | **Requirement-ID** | **Action** | **Data to be recorded** | **Expected results** | **Actual results** | **Passed / not passed** |
| --- | --- | --- | --- | --- | --- | --- |
| 2.1 | SF-INTEGRITY-001, SF-UPLOAD-001 | Calculate hashes for synthetic files below, at, and above the approved size boundary; upload safely, download each accepted file through approved interfaces, and recalculate hashes. | Redacted screenshots, command/API output, configuration identifiers, and evidence reference as applicable | Within-limit files succeed with matching hashes; over-limit upload is clearly rejected and creates no retrievable partial object or misleading success. |  | Not executed |

*Table 2.5:* Test steps

| **Postconditions or action after execution** |
| --- |
| Revoke test shares/users, remove synthetic files according to disposition procedure, and remove the isolated restore target after evidence approval. |

*Table 2.6:* Postconditions or action after execution

| **Comment** |
| --- |
|  |

*Table 2.7:* Comments

|  |  |  |  |
| --- | --- | --- | --- |
| **Test result** | **[ ] Passed  [ ] Not passed  [x] Not executed** | **Reference Nr. deviation / bug report** |  |

*Table 2.8:* Test result

## Test #3: Controlled-share lifecycle

|  |  |
| --- | --- |
| **Test ID** | **Title** |
| SF-T03 | Controlled-share lifecycle |

*Table 3.1:* Test identification

| **System identification** | **Test goal** | **Acceptance criterion** |
| --- | --- | --- |
| Seafile | Verify the approved configuration for: controlled-share lifecycle. | Only the approved recipient/access method works before expiry; unauthorized access fails; all revoked or expired paths subsequently fail. |

*Table 3.2:* System identification

| **Test run** | **Start date/time** | **End date/time** |
| --- | --- | --- |
| 0001 | TBD | TBD |

*Table 3.3:* Run through

| **Requirement** |
| --- |
| Requirement IDs: SF-SHARE-001, SF-REVOKE-001. Approved immutable Seafile image/digest; disposable users and synthetic files; approved upload limit; hashes recorded before transfer; no sensitive records used. |

*Table 3.4:* Requirements

| **Test step** | **Requirement-ID** | **Action** | **Data to be recorded** | **Expected results** | **Actual results** | **Passed / not passed** |
| --- | --- | --- | --- | --- | --- | --- |
| 3.1 | SF-SHARE-001, SF-REVOKE-001 | Create a recipient-restricted, short-lived test share; test authorized and unauthorized access; then expire/revoke the link and user/library permission and retry in fresh sessions. | Redacted screenshots, command/API output, configuration identifiers, and evidence reference as applicable | Only the approved recipient/access method works before expiry; unauthorized access fails; all revoked or expired paths subsequently fail. |  | Not executed |

*Table 3.5:* Test steps

| **Postconditions or action after execution** |
| --- |
| Revoke test shares/users, remove synthetic files according to disposition procedure, and remove the isolated restore target after evidence approval. |

*Table 3.6:* Postconditions or action after execution

| **Comment** |
| --- |
|  |

*Table 3.7:* Comments

|  |  |  |  |
| --- | --- | --- | --- |
| **Test result** | **[ ] Passed  [ ] Not passed  [x] Not executed** | **Reference Nr. deviation / bug report** |  |

*Table 3.8:* Test result

## Test #4: Security and immutable release baseline

|  |  |
| --- | --- |
| **Test ID** | **Title** |
| SF-T04 | Security and immutable release baseline |

*Table 4.1:* Test identification

| **System identification** | **Test goal** | **Acceptance criterion** |
| --- | --- | --- |
| Seafile | Verify the approved configuration for: security and immutable release baseline. | Public access uses valid HTTPS; database, memcached, and file storage are not public; deployment is uniquely reproducible and approved; updates require backup, security review, and relevant regression testing. |

*Table 4.2:* System identification

| **Test run** | **Start date/time** | **End date/time** |
| --- | --- | --- |
| 0001 | TBD | TBD |

*Table 4.3:* Run through

| **Requirement** |
| --- |
| Requirement IDs: SF-SEC-001, SF-CHANGE-001, SF-CHANGE-002. Approved immutable Seafile image/digest; disposable users and synthetic files; approved upload limit; hashes recorded before transfer; no sensitive records used. |

*Table 4.4:* Requirements

| **Test step** | **Requirement-ID** | **Action** | **Data to be recorded** | **Expected results** | **Actual results** | **Passed / not passed** |
| --- | --- | --- | --- | --- | --- | --- |
| 4.1 | SF-SEC-001, SF-CHANGE-001, SF-CHANGE-002 | Verify certificate/HTTPS behavior and backend isolation; record immutable image/component versions; confirm production does not use `latest`; inspect update and regression controls. | Redacted screenshots, command/API output, configuration identifiers, and evidence reference as applicable | Public access uses valid HTTPS; database, memcached, and file storage are not public; deployment is uniquely reproducible and approved; updates require backup, security review, and relevant regression testing. |  | Not executed |

*Table 4.5:* Test steps

| **Postconditions or action after execution** |
| --- |
| Revoke test shares/users, remove synthetic files according to disposition procedure, and remove the isolated restore target after evidence approval. |

*Table 4.6:* Postconditions or action after execution

| **Comment** |
| --- |
|  |

*Table 4.7:* Comments

|  |  |  |  |
| --- | --- | --- | --- |
| **Test result** | **[ ] Passed  [ ] Not passed  [x] Not executed** | **Reference Nr. deviation / bug report** |  |

*Table 4.8:* Test result

## Test #5: Controlled file-handling lifecycle

|  |  |
| --- | --- |
| **Test ID** | **Title** |
| SF-T05 | Controlled file-handling lifecycle |

*Table 5.1:* Test identification

| **System identification** | **Test goal** | **Acceptance criterion** |
| --- | --- | --- |
| Seafile | Verify the approved configuration for: controlled file-handling lifecycle. | Procedure covers endpoint scanning, escalation, quarantine/deletion, ownership, and incident handling; authoritative copy is identifiable/retrievable; transfer copy is retained or removed only under the approved rule. |

*Table 5.2:* System identification

| **Test run** | **Start date/time** | **End date/time** |
| --- | --- | --- |
| 0001 | TBD | TBD |

*Table 5.3:* Run through

| **Requirement** |
| --- |
| Requirement IDs: SF-MALWARE-001, SF-RETENTION-001. Approved immutable Seafile image/digest; disposable users and synthetic files; approved upload limit; hashes recorded before transfer; no sensitive records used. |

*Table 5.4:* Requirements

| **Test step** | **Requirement-ID** | **Action** | **Data to be recorded** | **Expected results** | **Actual results** | **Passed / not passed** |
| --- | --- | --- | --- | --- | --- | --- |
| 5.1 | SF-MALWARE-001, SF-RETENTION-001 | Execute the approved file-handling workflow with a harmless designated test artifact if permitted; transfer a synthetic controlled-record example to the authoritative repository and apply the approved Seafile disposition. | Redacted screenshots, command/API output, configuration identifiers, and evidence reference as applicable | Procedure covers endpoint scanning, escalation, quarantine/deletion, ownership, and incident handling; authoritative copy is identifiable/retrievable; transfer copy is retained or removed only under the approved rule. |  | Not executed |

*Table 5.5:* Test steps

| **Postconditions or action after execution** |
| --- |
| Revoke test shares/users, remove synthetic files according to disposition procedure, and remove the isolated restore target after evidence approval. |

*Table 5.6:* Postconditions or action after execution

| **Comment** |
| --- |
|  |

*Table 5.7:* Comments

|  |  |  |  |
| --- | --- | --- | --- |
| **Test result** | **[ ] Passed  [ ] Not passed  [x] Not executed** | **Reference Nr. deviation / bug report** |  |

*Table 5.8:* Test result

## Test #6: Coordinated backup and isolated restore

|  |  |
| --- | --- |
| **Test ID** | **Title** |
| SF-T06 | Coordinated backup and isolated restore |

*Table 6.1:* Test identification

| **System identification** | **Test goal** | **Acceptance criterion** |
| --- | --- | --- |
| Seafile | Verify the approved configuration for: coordinated backup and isolated restore. | Libraries, permissions, metadata, and files are consistent after restore; hashes match and production is unaffected. |

*Table 6.2:* System identification

| **Test run** | **Start date/time** | **End date/time** |
| --- | --- | --- |
| 0001 | TBD | TBD |

*Table 6.3:* Run through

| **Requirement** |
| --- |
| Requirement IDs: SF-BACKUP-001. Approved immutable Seafile image/digest; disposable users and synthetic files; approved upload limit; hashes recorded before transfer; no sensitive records used. |

*Table 6.4:* Requirements

| **Test step** | **Requirement-ID** | **Action** | **Data to be recorded** | **Expected results** | **Actual results** | **Passed / not passed** |
| --- | --- | --- | --- | --- | --- | --- |
| 6.1 | SF-BACKUP-001 | Create unique test files, permissions, and share metadata; take a coordinated database/file-data backup; restore to an isolated target; retrieve files and verify hashes and permissions. | Redacted screenshots, command/API output, configuration identifiers, and evidence reference as applicable | Libraries, permissions, metadata, and files are consistent after restore; hashes match and production is unaffected. |  | Not executed |

*Table 6.5:* Test steps

| **Postconditions or action after execution** |
| --- |
| Revoke test shares/users, remove synthetic files according to disposition procedure, and remove the isolated restore target after evidence approval. |

*Table 6.6:* Postconditions or action after execution

| **Comment** |
| --- |
|  |

*Table 6.7:* Comments

|  |  |  |  |
| --- | --- | --- | --- |
| **Test result** | **[ ] Passed  [ ] Not passed  [x] Not executed** | **Reference Nr. deviation / bug report** |  |

*Table 6.8:* Test result

# Protocol completion

| **Passed** | **Not passed** | **Blocked** | **Not executed** |
| --- | --- | --- | --- |
| 0 | 0 | 0 | 6 |

| **Role** | **Name** | **Date** | **Approval/signature reference** |
| --- | --- | --- | --- |
| Tester | TBD | TBD | TBD |
| Reviewer | TBD | TBD | TBD |

Overall protocol result: **[ ] Passed  [ ] Passed with accepted deviations  [ ] Not passed  [x] Not executed**
