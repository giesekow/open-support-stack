# IS-REC-EN-Validation-Plan-Keycloak-2026-09

## Meta information

| **Document type** | Validation Plan |
| --- | --- |
| **Version** | 0.5 |
| **Status** | Executed - all tests passed; formal approval pending |
| **Planned validation date** | 2026-09-25 |
| **Page ID** | TBD after publication |
| **Last change** | Interactive run 0003 completed; all planned tests pass and all deviations are closed. |

## 1 Purpose

This plan defines risk-based validation of Keycloak as the shared identity and access-management service for support-stack applications. Validation focuses on the configured realm, clients, identities, MFA, claims, redirects, sessions, administration, synchronization scripts, production mode, and recovery.

## 2 Roles and responsibilities

| **Role** | **Responsibility / person** |
| --- | --- |
| Validation Planning | Validation lead - TBD |
| Validation Execution | Trained tester independent of identity configuration where practical - TBD |
| Process Owner | Management IT - named person TBD |
| System Owner | Identity/support-stack administrator - named person TBD |
| Review and Approval | QM representative - TBD |

## 3 Milestones

| **Milestone** | **Target** |
| --- | --- |
| Evaluation approved | 2026-09-25 |
| Plan and protocol approved | Before execution |
| Test realm/users and relying clients prepared | Before execution |
| Tests performed | 2026-09-25 |
| Deviations resolved or accepted | Before report approval |
| Validation report approved and system released | TBD |

## 4 Software to be validated

| **ID** | **Software** | **Version** | **Category** |
| --- | --- | --- | --- |
| TBD from computerized-system list | Keycloak support realm and PostgreSQL persistence | Keycloak 26.7.4 (immutable image digest); PostgreSQL 16.14 | Class 2 - configurable standard infrastructure software |

Associated record: [Evaluation - Keycloak](../IS-REC-EN-Evaluation-Keycloak.md).

## 5 Scope

In scope: valid and invalid login, MFA, disabled users, groups/roles/claims, client secrets, exact redirect URIs and origins, sessions and logout, administrative separation, HTTPS/public issuer, restricted internal endpoints, production mode, configuration rendering/client synchronization, backup/restore, and version/security baseline.

Out of scope: source-level cryptographic verification, application-specific authorization after identity claims are received, and validation of each relying application beyond a representative integration check.

## 6 Preconditions and test environment

- Approved Keycloak and PostgreSQL versions are deployed in a production-representative environment.
- Production mode and proxy/hostname settings are documented.
- At least one ordinary user, one MFA user, one disabled user, and separate administrator account are available.
- Representative confidential clients and test redirect URIs are configured.
- No real password, token, client secret, recovery code, or personal data is retained in evidence.
- Time synchronization and backup/restore targets are available.

## 7 Test strategy

Configuration inspection and end-to-end OIDC tests cover positive and negative cases. Tests verify both browser behavior and protocol metadata where appropriate. Synchronization scripts are tested for expected updates and repeatability in a controlled environment.

## 8 Requirements and traceability

| **Requirement(s)** | **Planned test** |
| --- | --- |
| KC-AUTH-001, KC-AUTH-002, KC-MFA-001 | KC-T01 Authentication and MFA decision matrix |
| KC-CLAIM-001 | KC-T02 Group/role claims and resulting access |
| KC-CLIENT-001, KC-SECRET-001 | KC-T03 Client boundary and secret lifecycle |
| KC-OFFBOARD-001, KC-SESSION-001 | KC-T04 User and session lifecycle |
| KC-ADMIN-001 | KC-T05 Administrative separation |
| KC-TLS-001, KC-PROD-001 | KC-T06 HTTPS issuer, backend restriction and production runtime |
| KC-BACKUP-001 | KC-T07 Database/configuration backup and isolated restore |
| KC-CONFIG-001, KC-CHANGE-001 | KC-T08 Configuration synchronization and release baseline |

Each execution is designed to produce reusable identity-provider evidence for dependent-system integration checks.

## 9 Acceptance criteria

- Approved identities and clients authenticate successfully.
- Invalid, disabled, unauthorized-admin, and unapproved-redirect cases fail.
- MFA and expected least-privilege claims are demonstrated.
- Offboarding and session revocation take effect within approved behavior.
- Public metadata reports the correct HTTPS issuer.
- Production mode is confirmed and development-mode warning is absent.
- Isolated restore returns required realm, users, clients, groups, and roles without exposing secrets in evidence.
- No unresolved high-priority deviation remains.

## 10 Deviations and revalidation

Revalidation is considered after major Keycloak upgrades, realm/client/mapper model changes, identity or MFA policy changes, session-policy changes, proxy/hostname changes, database/backup changes, synchronization-script changes, or a security incident.

## 11 Applicable documents

- Evaluation - Keycloak
- SOP Computer System Validation
- Test Protocol - Keycloak
- Identity and access-management procedure
- User onboarding/offboarding procedure
- Backup and restore procedure
- Change-control procedure
