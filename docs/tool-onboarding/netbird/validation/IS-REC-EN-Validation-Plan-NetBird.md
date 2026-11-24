# IS-REC-EN-Validation-Plan-NetBird-2026-09

## Meta information

| **Document type** | Validation Plan |
| --- | --- |
| **Version** | 0.2 |
| **Status** | Draft - approval required before execution |
| **Planned validation date** | TBD |
| **Page ID** | TBD after publication |
| **Last change** | Test strategy consolidated to avoid duplicate evidence while retaining risk coverage. |

## 1 Purpose

This plan defines risk-based validation of the self-hosted NetBird configuration used for encrypted, least-privilege remote support. It gives particular emphasis to customer isolation, directionality, exact service ports, routed `/32` resources, Windows local forwarding, revocation, relay fallback, and recovery.

## 2 Roles and responsibilities

| **Role** | **Responsibility / person** |
| --- | --- |
| Validation Planning | Validation lead - TBD |
| Validation Execution | Network/system tester independent of configuration where practical - TBD |
| Process Owner | Management IT / Support - named person TBD |
| System Owner | Support-stack administrator - named person TBD |
| Review and Approval | QM representative - TBD |

## 3 Milestones

| **Milestone** | **Target** |
| --- | --- |
| Evaluation approved | 2026-09-25 |
| Plan and protocol approved | Before execution |
| Test support and two customer peers prepared | Before execution |
| Tests performed | TBD |
| Deviations resolved or accepted | Before report approval |
| Validation report approved and system released | TBD |

## 4 Software to be validated

| **ID** | **Software** | **Version** | **Category** |
| --- | --- | --- | --- |
| TBD from computerized-system list | NetBird server, dashboard and approved clients | 0.79.0 / pinned deployment images | Class 2 - configurable standard software |

Associated record: [Evaluation - NetBird](../IS-REC-EN-Evaluation-NetBird.md).

## 5 Scope

In scope: controlled enrollment, Keycloak login/MFA, group membership, default-policy state, one-way Support-Group to Customer-Group access, customer-to-customer denial, service-port restriction, `/32` resources, Windows LAN-IP routing, direct or STUN connectivity, WebSocket relay fallback, peer/policy revocation, management events, version alignment, and datastore recovery.

Out of scope: security proof of WireGuard cryptography, customer application authentication, general customer LAN security, and unsupported client platforms.

## 6 Preconditions and test environment

- Server, dashboard, and clients use the approved version.
- Test topology includes one support peer and two independently identifiable customer peers.
- No production customer data is used.
- Default `All -> All` policy is disabled.
- The one-way support/customer policy and exact test ports are documented.
- One Windows customer peer has a test LAN IP resource represented as `/32`.
- Direct/STUN and forced relay test paths are available.
- Backups include NetBird data and the datastore encryption key.

## 7 Test strategy

Tests combine configuration inspection, positive connectivity, negative connectivity, route inspection, status/handshake evidence, revocation, and isolated restoration. Network captures may record addressing metadata but must not contain customer payloads or credentials. Negative tests are mandatory for customer isolation and closed ports.

## 8 Requirements and traceability

| **Requirement(s)** | **Planned test** |
| --- | --- |
| NB-ENROLL-001, NB-REVOKE-001, NB-REVIEW-001 | NB-T01 Peer enrollment, revocation and review lifecycle |
| NB-IDENTITY-001 | NB-T02 NetBird-Keycloak integration; provider-level MFA evidence reused from Keycloak |
| NB-POLICY-001, NB-POLICY-002, NB-ISOLATION-001, NB-LEASTPRIV-001 | NB-T03 Positive and negative access matrix |
| NB-ROUTE-001, NB-WINROUTE-001 | NB-T04 Windows `/32` routed-resource access |
| NB-ENCRYPT-001, NB-CONNECT-001 | NB-T05 Direct/STUN and encrypted relay fallback |
| NB-BACKUP-001 | NB-T06 Backup and isolated restoration |
| NB-CHANGE-001 | NB-T07 Version and upgrade baseline |

The access matrix is one controlled execution covering permitted and prohibited paths; those negative results must not be inferred from successful access.

## 9 Acceptance criteria

- Authorized support connectivity succeeds only for approved customer destinations and ports.
- Both customer-to-customer directions and customer-to-support initiation fail.
- The LAN resource is exactly `/32`, is installed via `wt0`, and works only after approved policy/local-forwarding controls.
- Relay fallback succeeds when direct P2P is unavailable, with a recorded WireGuard handshake.
- Revocation removes effective access within the expected synchronization interval.
- No unresolved high-priority deviation remains.

## 10 Deviations and revalidation

Record and risk-assess every deviation. Revalidation is considered after major server/client upgrades, identity-provider changes, policy model changes, proxy/relay/STUN changes, route or customer-group model changes, backup-store changes, or a security incident.

## 11 Applicable documents

- Evaluation - NetBird
- NetBird Proxy and SSH Runbook
- Customer NetBird Security Overview
- SOP Computer System Validation
- Test Protocol - NetBird
- Access management and offboarding procedure
- Backup and restore procedure
