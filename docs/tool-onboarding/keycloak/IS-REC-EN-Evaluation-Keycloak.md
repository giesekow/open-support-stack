# IS-REC-EN-Evaluation-Keycloak

## Meta information

| **Document type** | Evaluation of computerized system |
| --- | --- |
| **Version** | 1.3 |
| **Status** | Approved |
| **Last release date** | 2026-09-25 |
| **Page ID** | TBD after publication |
| **Last change to the document** | Runtime baseline updated to immutable Keycloak 26.7.4 after remediation run 0002; approved scope and decision unchanged. |

# Evaluation of computerized system

## Meta data of the software

| **Name** | Keycloak identity and access management |
| --- | --- |
| **Version / state (date)** | Keycloak 26.7.4 pinned by immutable image digest; self-hosted support realm backed by PostgreSQL 16 (2026-09-25) |
| **Manufacturer** | Keycloak open-source project / Red Hat community; operated by Bonescreen GmbH |
| **Purpose of the software** | Central authentication, user lifecycle, groups, roles, sessions, and OpenID Connect identity for support-stack applications. |
| **Processes in which the software is used** | Identity and access management; application login; support-team onboarding and offboarding; privileged-access control. |
| **User (role / function)** | All users of integrated applications; identity administrators; system administrators. |
| **QM relevant, justification** | Approved: Yes. Keycloak is a shared security control for systems that may contain QMS, HR, customer, credential, and confidential records. Incorrect identity or client configuration could grant unauthorized access across multiple systems. |
| **Software category (Class 1, 2, 3)** | Class 2 - configurable standard infrastructure software with locally managed realm/client configuration and synchronization scripts. |
| **Criticality** | High. Failure can cause organization-wide loss of login or unauthorized access to several dependent systems. |

## System boundary

The evaluated system includes Keycloak, the support realm, PostgreSQL persistence, users, credentials, groups, roles, client registrations, redirect URIs, protocol mappers, token/session settings, MFA configuration, administration, configuration rendering/synchronization scripts, reverse proxy, and backup/restore. Each relying application is evaluated separately.

## Purpose / task of the software

| **Question** | **Answer** |
| --- | --- |
| **What is the purpose of the software?** | To provide a central source of authenticated user identity and authorization claims to integrated support applications. |
| **What tasks does it perform?** | User authentication, MFA, session management, token issuance, OIDC discovery, client authentication, group/role claims, password management, and user disablement. |
| **Other requirements** | High availability appropriate to business use; HTTPS issuer; secure internal token/JWKS paths; restricted administration; backup/restore; time synchronization; controlled client redirects and secrets. |
| **Could a bug affect medical-device safety or quality?** | Indirectly. Unauthorized or unavailable access to dependent systems could affect regulated records or delay support and quality activities. Keycloak does not control a medical device. |
| **Does it perform a regulated activity?** | It performs authentication and authorization supporting regulated processes but does not make regulated decisions. |
| **Does it generate or manage product-approval data?** | No. It manages identity and access metadata. |
| **Does it manage QMS or authority records?** | It manages access-control configuration and identity records used to protect dependent systems. It is not the authoritative QMS record repository. |
| **Does it generate electronic signatures?** | No. Authentication through Keycloak is not approved as a compliant electronic signature unless separately specified and validated. |

# Requirements

## Regulatory and quality requirements

| **Requirement source** | **Application to this system** | **Requirement-ID** |
| --- | --- | --- |
| ISO 13485:2016 4.2.5 - security, integrity and retrieval | Identity controls must protect regulated records in relying systems from unauthorized access. | KC-AUTH-001, KC-CLAIM-001, KC-ADMIN-001 |
| Internal access-control and information-security requirements | Individual identity, least privilege, MFA, secure sessions, restricted administration, review, revocation, logging, backup, and recovery are required. | KC-MFA-001, KC-ADMIN-001, KC-BACKUP-001 |
| Data-protection requirements | User profile data, credentials, tokens, client secrets, and logs must be protected and minimized. | KC-TLS-001, KC-SECRET-001, KC-SESSION-001 |

## Functional and operational requirements

|  | **Requirement** | **Requirement-ID** |
| --- | --- | --- |
| 1 | Active authorized users shall authenticate to configured clients using their individual identity. | KC-AUTH-001 |
| 2 | Invalid credentials, disabled users, and unauthorized clients or redirects shall be rejected. | KC-AUTH-002 |
| 3 | MFA shall be enforceable for administrators and designated support users. | KC-MFA-001 |
| 4 | Groups and roles shall produce only the claims required by each approved client. | KC-CLAIM-001 |
| 5 | Client redirect URIs and web origins shall be limited to approved application endpoints. | KC-CLIENT-001 |
| 6 | Confidential clients shall use protected, unique secrets that can be rotated. | KC-SECRET-001 |
| 7 | Disabling a user or removing relevant group membership shall prevent new access to dependent applications within the approved session/revocation behavior. | KC-OFFBOARD-001 |
| 8 | Realm and administrative access shall be limited to approved administrators and protected independently from ordinary application roles. | KC-ADMIN-001 |
| 9 | The public issuer and browser endpoints shall use valid HTTPS; internal endpoints shall remain restricted to the backend network or approved proxy path. | KC-TLS-001 |
| 10 | Token lifetimes, session idle/max periods, and clock synchronization shall follow the approved security baseline. | KC-SESSION-001 |
| 11 | Database and required realm/configuration data shall be backed up and restorable together with protected secrets. | KC-BACKUP-001 |
| 12 | Realm-rendering and client-synchronization scripts shall be version controlled, idempotent where intended, and regression tested. | KC-CONFIG-001 |
| 13 | Production shall use the approved production start mode and shall not run Keycloak development mode. | KC-PROD-001 |
| 14 | Version updates and security advisories shall be evaluated through change control. | KC-CHANGE-001 |

# Risk management

## Risk assessment questions

| **Risk assessment question** | **Applicable** | **Assessment for Keycloak** |
| --- | --- | --- |
| Can the software system cause risks for people? | Indirect | Authentication failure or unauthorized access could permit harmful actions or delay work in dependent systems, but Keycloak does not itself control a medical device or physical process. |
| Can patients, users, or third parties be harmed by a defective medical device which could be caused by the software system? | No direct effect | Keycloak cannot create a defective device. Compromised identities could indirectly enable unauthorized changes in another system, whose own controls remain applicable. |
| Can users of this or another system suffer damage? | Yes | Account takeover, excessive claims, unavailable SSO, or exposed identity data could cause privacy, operational, contractual, financial, or cybersecurity harm across relying systems. |
| Can regulatory risks arise? | Yes | Unauthorized or unavailable access can weaken access control, attribution, segregation of duties, record availability, and timely execution of regulated activities. |
| Can regulatory-relevant records or documents be falsified? | Indirect | Keycloak does not store those records, but an incorrectly authenticated or over-privileged identity could alter records in an authoritative relying system. |
| Can data essential for product approval be falsified? | No direct effect | Product-approval data is outside Keycloak; risk arises through incorrect access granted to a separate system that manages such data. |
| Can damage to the environment or other assets occur? | Indirect | Compromised administrative or application identities could expose connected company/customer assets; Keycloak controls no environmental process. |
| Can downstream processes be affected? | Yes | Login, administration, onboarding/offboarding, support, and access to every integrated application depend on Keycloak availability and correct claims. |
| Are there any other risks? | Yes | Single-point authentication outage, administrator compromise, redirect/client-secret errors, stale sessions, proxy/hostname misconfiguration, and failed database migration or restore are relevant. |

## Risk control measures

|  | **Risk** | **Probability** | **Damage** | **Detectability** | **Initial priority** | **Risk control measure** | **Verification / Requirement-ID** | **Residual priority** |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | Unauthorized user authenticates to one or more applications. | Medium | High | Low | High | Individual credentials, MFA, brute-force protection, secure clients, HTTPS, and negative authentication tests. | KC-AUTH-001, KC-MFA-001 | Medium |
| 2 | Incorrect redirect URI or client configuration enables token/code disclosure. | Medium | High | Low | High | Exact approved redirects/origins, confidential clients, automated sync review, and negative redirect tests. | KC-CLIENT-001, KC-SECRET-001 | Low |
| 3 | Excessive group or role claim grants application privileges. | Medium | High | Medium | High | Least-privilege mappers, role/group review, and application authorization tests. | KC-CLAIM-001 | Low |
| 4 | Disabled employee retains an active session or access. | Medium | High | Medium | High | Offboarding procedure, session revocation, short approved lifetimes, and disablement tests. | KC-OFFBOARD-001, KC-SESSION-001 | Low |
| 5 | Administrator account is compromised. | Low | High | Low | High | Separate named administrators, MFA, restricted network access, no shared routine admin account, and activity review. | KC-ADMIN-001, KC-MFA-001 | Medium |
| 6 | Keycloak outage blocks access to all integrated applications. | Medium | High | High | Medium | Monitoring, documented recovery, protected break-glass accounts where justified, and restore testing. | KC-BACKUP-001 | Medium |
| 7 | Loss of database or secrets prevents restoration or invalidates clients. | Low | High | Low | High | Coordinated encrypted backups of database and configuration secrets plus restore exercise. | KC-BACKUP-001 | Medium |
| 8 | Production runs in development mode or with weak hostname/proxy settings. | Medium | High | High | Medium | Production preflight checks and verification of runtime mode, hostname strictness, and trusted proxy configuration. | KC-PROD-001, KC-TLS-001 | Low |
| 9 | Synchronization script unintentionally changes several clients. | Medium | High | Medium | High | Version control, test environment, reviewed changes, idempotence tests, backup, and post-run verification. | KC-CONFIG-001 | Low |

## Determination of criticality

- [x] high
- [ ] moderate
- [ ] low

## Decision on validation obligation

Approved decision:

- [x] System is QM relevant and needs to be validated.
- [ ] System is QM relevant and does not have to be validated.
- [ ] System is not QM relevant; formal validation is not required.
- [ ] System is already validated under another system record.

Justification: Keycloak is a shared authentication boundary for multiple dependent systems. Validation should focus on the configured realm, clients, MFA, claims, redirect restrictions, user disablement/session behavior, administrative separation, production mode, synchronization scripts, and restoration rather than re-testing upstream cryptographic libraries.

## Release

- [ ] Yes
- [x] No - validation execution and release approval are pending
- [ ] Subject to conditions

| **Date of release** | **Person approving release** | **Role** |
| --- | --- | --- |
| TBD | TBD | Process Owner / QM |

# Test specifications and validations

Production validation run 0001 was executed on 2026-09-25. The overall result is not passed; open deviations require remediation and revalidation before release approval:

- [Validation Plan - Keycloak](validation/IS-REC-EN-Validation-Plan-Keycloak.md)
- [Test Protocol - Keycloak](validation/IS-REC-EN-Test-Protocol-Keycloak.md)
- [Validation Report - Keycloak](validation/IS-REC-EN-Validation-Report-Keycloak.md)
- [Deviation Register - Keycloak](validation/IS-REC-EN-Deviation-Register-Keycloak.md)

# Decommissioning

| **Date of decommissioning** | Not applicable - active system |
| --- | --- |
