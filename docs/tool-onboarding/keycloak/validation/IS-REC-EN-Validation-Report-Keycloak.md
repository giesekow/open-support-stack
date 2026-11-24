# IS-REC-EN-Validation-Report-Keycloak-2026-09

**Table of contents**

## Meta information

| **Document type** | Validation Report |
| --- | --- |
| **Version** | 0.7 |
| **Status** | Executed - passed; formal review and approval pending |
| **Last release date** | Not released |
| **Page ID** | TBD after publication |
| **Last change to the document** | Added command-level supplemental evidence and explicit historical-evidence limitations; all eight tests pass and all five deviations are closed. |

## Validation Report

### 1 Information about the computerized system

| **Aspect** | **Description** |
| --- | --- |
| ID | TBD from the List of Computerized Systems |
| Identification | Keycloak support realm with PostgreSQL persistence; exact approved image/version recorded during execution; see [Evaluation - Keycloak](../IS-REC-EN-Evaluation-Keycloak.md) |

*Table 1:* System information

### 2 Executive Summary

- This document reports the initial focused validation of the configured Keycloak service.
- Requirements and intended use are defined in [Evaluation - Keycloak](../IS-REC-EN-Evaluation-Keycloak.md).
- Validation activities are defined in [Validation Plan - Keycloak](IS-REC-EN-Validation-Plan-Keycloak.md).
- Test specifications and execution records are defined in [Test Protocol - Keycloak](IS-REC-EN-Test-Protocol-Keycloak.md).
- Production runs 0001-0003 were executed on 2026-09-25. All eight tests pass and all five deviations are remediated and closed. Supplemental command-level reruns were then captured in KC-E02 and KC-E13 through KC-E16 without representing them as original-run transcripts.

**Current conclusion:** Technical validation passed. The configured Keycloak service is recommended for controlled release after the protocol and report receive the required Process Owner and QM review/signatures.

### 3 Validation results

#### 3.1 Context of use

Support realm, configured clients, MFA, claims, sessions, administration, synchronization scripts, public issuer/proxy behavior, and persistence. Application authorization is evaluated by each relying system.

#### 3.2 Acceptance criterion

See [Test Protocol - Keycloak](IS-REC-EN-Test-Protocol-Keycloak.md). Every mandatory test must pass, or deviations must be documented, risk-assessed, resolved or formally accepted. No unresolved high-priority deviation may remain.

#### 3.3 Validation approach

Risk-based OIDC testing covers authentication/MFA, claims, client boundaries, user/session lifecycle, administration, production exposure, recovery, and configuration/release repeatability.

#### 3.4 Validation evaluation

|  | **Test case** | **No. of test runs** | **Deviations found** | **Solution** | **Re-validation** |
| --- | --- | --- | --- | --- | --- |
| 1 | KC-T01 - Authentication and MFA decision matrix | 3 | KC-DEV-001 and KC-DEV-002 closed | Brute-force and privileged MFA positive/negative checks passed. | Complete |
| 2 | KC-T02 - Group and role claims | 1 | None | No corrective action. | Not required unless mapper design changes |
| 3 | KC-T03 - Client boundary and secret lifecycle | 2 | KC-DEV-003 closed | Exact HTTPS callbacks and altered-path rejection passed for all ten managed clients. | Complete |
| 4 | KC-T04 - User and session lifecycle | 1 | None | No corrective action. | Not required unless lifecycle/session policy changes |
| 5 | KC-T05 - Administrative separation | 3 | KC-DEV-001 and KC-DEV-004 closed | Named MFA-protected delegated administration passed; Master realm and impersonation remained unavailable. | Complete |
| 6 | KC-T06 - HTTPS issuer and production exposure baseline | 1 | None | No corrective action. | Not required unless proxy/hostname/runtime changes |
| 7 | KC-T07 - Backup and isolated restore | 1 | None | Continue scheduled protected backup and periodic restore tests. | Periodic |
| 8 | KC-T08 - Configuration synchronization and release baseline | 2 | KC-DEV-005 closed | Migration rehearsal, protected backup, Keycloak 26.7.4 upgrade, immutable digest, and lean regression passed. | Complete |

### 4 Release recommendation

Keycloak is recommended for controlled release for the evaluated intended use. The recommendation becomes effective after the Process Owner and QM approve/sign the completed protocol and report. Continue periodic privileged-access, MFA, backup/restore, callback, and security-release review.

### 5 Annex

#### 5.1 Applicable documents

|  | **Document ID** | **Title** |
| --- | --- | --- |
| 1 | [Evaluation - Keycloak](../IS-REC-EN-Evaluation-Keycloak.md) | Evaluation - Keycloak |
| 2 | [Validation Plan - Keycloak](IS-REC-EN-Validation-Plan-Keycloak.md) | Validation Plan - Keycloak |
| 3 | [Test Protocol - Keycloak](IS-REC-EN-Test-Protocol-Keycloak.md) | Test Protocol - Keycloak |
| 4 | SOP Computer System Validation | SOP Computer System Validation |
| 5 | Identity and access-management procedure | Identity and access-management procedure |
| 6 | Onboarding/offboarding and backup/restore procedures | Onboarding/offboarding and backup/restore procedures |
| 7 | Change-control procedure | Change-control procedure |
| 8 | [Deviation Register - Keycloak](IS-REC-EN-Deviation-Register-Keycloak.md) | Open validation deviations |
| 9 | [Evidence index](evidence/2026-09-25/) | Redacted production execution evidence, complete command transcripts, and disclosed historical limitations |
