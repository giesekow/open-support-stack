# IS-REC-EN-Validation-Report-Vaultwarden-2026-09

**Table of contents**

## Meta information

| **Document type** | Validation Report |
| --- | --- |
| **Version** | 0.4 |
| **Status** | Execution in progress; approval pending |
| **Last release date** | Not released |
| **Page ID** | TBD after publication |
| **Last change to the document** | Security/readiness, collection authorization, and client synchronization passed; revocation and restored-data checks remain pending. |

## Validation Report

### 1 Information about the computerized system

| **Aspect** | **Description** |
| --- | --- |
| ID | TBD from the List of Computerized Systems |
| Identification | Vaultwarden 1.37.2, self-hosted support-stack deployment; see [Evaluation - Vaultwarden](../IS-REC-EN-Evaluation-Vaultwarden.md) |

*Table 1:* System information

### 2 Executive Summary

- This document reports the initial focused validation of the configured Vaultwarden service.
- Requirements and intended use are defined in [Evaluation - Vaultwarden](../IS-REC-EN-Evaluation-Vaultwarden.md).
- Validation activities are defined in [Validation Plan - Vaultwarden](IS-REC-EN-Validation-Plan-Vaultwarden.md).
- Test specifications and execution records are defined in [Test Protocol - Vaultwarden](IS-REC-EN-Test-Protocol-Vaultwarden.md).
- Command-based security and operating-readiness testing passed. Organization and collection authorization testing passed. Backup integrity, isolated service restoration, aggregate data consistency, cleanup, and production health passed. The final account-revocation check and restored encrypted-data usability remain pending manual execution.

**Current conclusion:** Validation remains in progress. No release recommendation is issued until the pending encrypted user-workflow tests pass and formal approvals are complete.

### 3 Validation results

#### 3.1 Context of use

Self-hosted password vault used to store and share support credentials through controlled organizations and collections. Upstream cryptographic source-code verification is outside scope.

#### 3.2 Acceptance criterion

See [Test Protocol - Vaultwarden](IS-REC-EN-Test-Protocol-Vaultwarden.md). Every mandatory test must pass, or deviations must be documented, risk-assessed, resolved or formally accepted. No unresolved high-priority deviation may remain.

#### 3.3 Validation approach

Risk-based configuration and user-acceptance testing covers account lifecycle, collection authorization, synchronization, security/readiness, and isolated restoration.

#### 3.4 Validation evaluation

|  | **Test case** | **No. of test runs** | **Deviations found** | **Solution** | **Re-validation** |
| --- | --- | --- | --- | --- | --- |
| 1 | VW-T01 - Account onboarding, authentication, and revocation lifecycle | 1 partial | None identified | Complete revocation and fresh-synchronization checks | Required before acceptance |
| 2 | VW-T02 - Organization and collection authorization | 1 | None | No corrective action | Revalidate after material role, collection-permission, or authorization changes |
| 3 | VW-T03 - Client synchronization | 1 | None | No corrective action | Revalidate after material client, API, or synchronization changes |
| 4 | VW-T04 - Security, version, and operating readiness | 1 | None | No corrective action | Revalidate after material security, proxy, version, or procedure changes |
| 5 | VW-T05 - Backup and isolated restore | 1 partial | None identified | Complete manual restored-login and item/permission retrieval | Required before acceptance |

### 4 Release recommendation

No release recommendation is issued yet. Complete VW-T01 through VW-T03 and the encrypted-data usability portion of VW-T05, assess any deviations, and obtain Process Owner and QM approval before release under validation.

### 5 Annex

#### 5.1 Applicable documents

|  | **Document ID** | **Title** |
| --- | --- | --- |
| 1 | [Evaluation - Vaultwarden](../IS-REC-EN-Evaluation-Vaultwarden.md) | Evaluation - Vaultwarden |
| 2 | [Validation Plan - Vaultwarden](IS-REC-EN-Validation-Plan-Vaultwarden.md) | Validation Plan - Vaultwarden |
| 3 | [Test Protocol - Vaultwarden](IS-REC-EN-Test-Protocol-Vaultwarden.md) | Test Protocol - Vaultwarden |
| 4 | SOP Computer System Validation | SOP Computer System Validation |
| 5 | Backup and restore procedure | Backup and restore procedure |
| 6 | Access-control and offboarding procedure | Access-control and offboarding procedure |
| 7 | Change-control procedure | Change-control procedure |

| 8 | [Vaultwarden Operating Guide](../../../vaultwarden_operations.md) | Sharing, recovery, offboarding, backup, and update instructions |
| 9 | [Evidence index](evidence/2026-09-25/) | Redacted command evidence and pending manual checklist |
| 10 | [Deviation Register - Vaultwarden](IS-REC-EN-Deviation-Register-Vaultwarden.md) | Validation deviations |
