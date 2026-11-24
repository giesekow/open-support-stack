# IS-REC-EN-Operational-Acceptance-OrangeHRM-2026-09

## Meta information

| **Document type** | Operational Acceptance Record |
| --- | --- |
| **Version** | 0.2 |
| **Status** | Draft - approval required before execution |
| **Execution date** | Not executed |
| **Page ID** | TBD after publication |
| **Last change** | Consolidated overlapping identity, workflow, and readiness checks into six executions. |

## 1 Purpose and boundary

This record verifies that OrangeHRM is fit for the approved non-QM/GxP scope of employee administration and leave management. It is not a formal CSV validation package and does not approve use for competence, training, QMS approvals, product records, or electronic signatures.

The OrangeHRM leave-email notifier and Support Tools application are excluded and require their own evaluation.

## 2 Preconditions

- OrangeHRM 5.8.1 and its MariaDB persistence are deployed in a production-representative environment.
- The approved Keycloak client and internal OIDC endpoint compatibility patch are installed.
- Disposable employee, supervisor, HR, administrator, and disabled-user accounts are available.
- Synthetic leave and employee data are used; evidence contains no real personal data or secrets.
- Backup and isolated restore locations are available.
- Provider-level authentication and MFA evidence is referenced from Keycloak; this record tests OrangeHRM integration and effective application access.

## 3 Acceptance checks

| **ID** | **Requirement(s)** | **Test procedure** | **Expected result** | **Evidence / actual result** | **Result** |
| --- | --- | --- | --- | --- | --- |
| OHRM-A01 | OHRM-LOGIN-001, OHRM-OFFBOARD-001, OHRM-CHANGE-001 | Confirm the OIDC compatibility patch/version is traceable. Sign in through Keycloak as an approved user; attempt invalid/disabled identities; establish a session, disable/remove the test user, and retry existing and new access. | Approved callback/login succeeds without TLS, discovery, or unexpected-error failures; invalid/disabled users are denied; offboarding ends access according to approved session behavior; patch identity is traceable. |  | Not executed |
| OHRM-A02 | OHRM-ACCESS-001, OHRM-ACCESS-002, OHRM-PRIV-001 | As employee, supervisor, HR, and administrator, inspect and attempt representative read/write actions inside and outside assigned permissions. | Each role sees and changes only approved data; unauthorized employee, peer, and administrative access is denied. |  | Not executed |
| OHRM-A03 | OHRM-LEAVE-001, OHRM-LEAVE-002, OHRM-LEAVE-003 | Submit representative full-day, partial-day, and multi-day synthetic leave requests; approve one and reject another as assigned supervisor; review statuses and balances. | Request data, duration, decision status, and balance effects are consistent with configured rules and visible only to authorized roles. |  | Not executed |
| OHRM-A04 | OHRM-PRIV-001 | Verify HTTPS and that database/storage are not publicly exposed; inspect administrative and backup access controls without displaying sensitive values. | Personal data is encrypted in transit; database, storage, and backups are restricted to approved administrators. |  | Not executed |
| OHRM-A05 | OHRM-BACKUP-001 | Create uniquely identifiable synthetic records; back up database/persistent data; restore in isolation and retrieve the records and leave status. | Restore is complete and consistent, production is unaffected, and no real personal data appears in evidence. |  | Not executed |
| OHRM-A06 | OHRM-SCOPE-001 | Review procedures, user instructions, and Process Owner declaration for the approved use and re-evaluation trigger. | OrangeHRM is not designated as the authoritative source for competence, training, QMS approvals, product records, or signatures; expansion requires approved change control and re-evaluation. |  | Not executed |

## 4 Acceptance criteria

- All six checks pass, or deviations are documented, risk-assessed, and formally accepted.
- No unresolved privacy, authentication, authorization, workflow, or restore issue remains.
- The OIDC compatibility patch is traceable and the integrated login/offboarding test passes.
- The HR Process Owner confirms the intended-use restriction.

## 5 Deviations

| **Deviation ID** | **Check** | **Description and impact** | **Correction / decision** | **Owner** | **Status** |
| --- | --- | --- | --- | --- | --- |
| None recorded |  |  |  |  | Not assessed |

## 6 Acceptance decision

- [ ] Accepted for the approved leave-management scope
- [ ] Conditionally accepted with approved deviations
- [x] Not yet accepted - checks have not been executed

| **Role** | **Name** | **Date** | **Approval** |
| --- | --- | --- | --- |
| HR Process Owner | TBD | TBD | TBD |
| System Owner / IT | TBD | TBD | TBD |
| QM review | TBD | TBD | TBD |

## 7 Applicable documents

- [Evaluation - OrangeHRM](IS-REC-EN-Evaluation-OrangeHRM.md)
- HR leave-management procedure
- User onboarding/offboarding procedure
- Backup and restore procedure
- Change-control procedure
