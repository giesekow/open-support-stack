# IS-REC-EN-Validation-Report-NetBird-2026-09

**Table of contents**

## Meta information

| **Document type** | Validation Report |
| --- | --- |
| **Version** | 0.3 |
| **Status** | Draft - awaiting test execution and approval |
| **Last release date** | Not released |
| **Page ID** | TBD after publication |
| **Last change to the document** | Reformatted to the approved validation-report template; no test results recorded. |

## Validation Report

### 1 Information about the computerized system

| **Aspect** | **Description** |
| --- | --- |
| ID | TBD from the List of Computerized Systems |
| Identification | NetBird self-hosted service and approved clients; exact released versions/digests recorded during execution; see [Evaluation - NetBird](../IS-REC-EN-Evaluation-NetBird.md) |

*Table 1:* System information

### 2 Executive Summary

- This document reports the initial focused validation of the configured NetBird service.
- Requirements and intended use are defined in [Evaluation - NetBird](../IS-REC-EN-Evaluation-NetBird.md).
- Validation activities are defined in [Validation Plan - NetBird](IS-REC-EN-Validation-Plan-NetBird.md).
- Test specifications and execution records are defined in [Test Protocol - NetBird](IS-REC-EN-Test-Protocol-NetBird.md).
- Testing has not yet been executed; therefore no conclusion about suitability or release can be made.

**Current conclusion:** Validation and release recommendation pending execution, deviation assessment, and approval.

### 3 Validation results

#### 3.1 Context of use

One-way support access from approved support peers to customer peers and narrowly scoped network resources. Customer-to-customer and customer-to-support initiation must remain denied.

#### 3.2 Acceptance criterion

See [Test Protocol - NetBird](IS-REC-EN-Test-Protocol-NetBird.md). Every mandatory test must pass, or deviations must be documented, risk-assessed, resolved or formally accepted. No unresolved high-priority deviation may remain.

#### 3.3 Validation approach

Risk-based testing uses enrollment lifecycle evidence, identity integration, one positive/negative access matrix, routed-resource checks, direct/relay connectivity, recovery, and release-baseline inspection.

#### 3.4 Validation evaluation

|  | **Test case** | **No. of test runs** | **Deviations found** | **Solution** | **Re-validation** |
| --- | --- | --- | --- | --- | --- |
| 1 | NB-T01 - Peer enrollment, revocation, and review lifecycle | 0 | Not assessed | TBD | TBD |
| 2 | NB-T02 - NetBird-Keycloak identity integration | 0 | Not assessed | TBD | TBD |
| 3 | NB-T03 - Positive and negative access matrix | 0 | Not assessed | TBD | TBD |
| 4 | NB-T04 - Windows /32 routed-resource access | 0 | Not assessed | TBD | TBD |
| 5 | NB-T05 - Direct and encrypted relay connectivity | 0 | Not assessed | TBD | TBD |
| 6 | NB-T06 - Backup and isolated restore | 0 | Not assessed | TBD | TBD |
| 7 | NB-T07 - Version and upgrade baseline | 0 | Not assessed | TBD | TBD |

### 4 Release recommendation

No release recommendation is issued for NetBird. Complete the approved protocol, attach objective evidence, assess all deviations, and obtain Process Owner and QM approval before release under validation.

### 5 Annex

#### 5.1 Applicable documents

|  | **Document ID** | **Title** |
| --- | --- | --- |
| 1 | [Evaluation - NetBird](../IS-REC-EN-Evaluation-NetBird.md) | Evaluation - NetBird |
| 2 | [Validation Plan - NetBird](IS-REC-EN-Validation-Plan-NetBird.md) | Validation Plan - NetBird |
| 3 | [Test Protocol - NetBird](IS-REC-EN-Test-Protocol-NetBird.md) | Test Protocol - NetBird |
| 4 | SOP Computer System Validation | SOP Computer System Validation |
| 5 | [NetBird proxy and SSH runbook](../../../netbird_proxy_and_ssh_runbook.md) | NetBird proxy and SSH runbook |
| 6 | Access-control and backup/restore procedures | Access-control and backup/restore procedures |
