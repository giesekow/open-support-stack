# IS-REC-EN-Evaluation-Vaultwarden

## Meta information

| **Document type** | Evaluation of computerized system |
| --- | --- |
| **Version** | 1.3 |
| **Status** | Approved |
| **Last release date** | 2026-09-25 |
| **Page ID** | TBD after publication |
| **Last change to the document** | Validation execution status updated; approved scope and decision unchanged. |

# Evaluation of computerized system

## Meta data of the software

| **Name** | Vaultwarden password vault |
| --- | --- |
| **Version / state (date)** | Vaultwarden 1.37.2; self-hosted support-stack deployment |
| **Manufacturer** | Vaultwarden open-source project; operated by Bonescreen GmbH |
| **Purpose of the software** | Secure storage and controlled sharing of credentials used by the support team. |
| **Processes in which the software is used** | IT administration; customer support; access management; employee onboarding and offboarding. |
| **User (role / function)** | Support engineers; system administrators; authorized organization owners. |
| **QM relevant, justification** | Approved: Yes. The vault protects credentials that provide access to QMS-relevant and customer systems. Failure or unauthorized access could affect confidentiality, integrity, availability, and traceability in dependent systems. |
| **Software category (Class 1, 2, 3)** | Class 2 - configurable standard software. No internally developed Vaultwarden application code is included. |
| **Criticality** | High. Compromise or loss could expose privileged credentials or prevent authorized access to supported systems. |

## System boundary

The evaluated system includes the Vaultwarden server, its persistent data, SMTP integration, reverse-proxy exposure, user and organization configuration, and backup/restore procedures. Keycloak is evaluated separately. Browser extensions and desktop/mobile Bitwarden-compatible clients are in scope only for interoperability tests. Their vendor code is not part of this system boundary.

## Purpose / task of the software

| **Question** | **Answer** |
| --- | --- |
| **What is the purpose of the software?** | To store individual and shared credentials in encrypted vaults and make approved organization collections available to authorized support personnel. |
| **What tasks does it perform?** | User authentication, vault synchronization, credential creation and retrieval, organization membership, collection sharing, access revocation, and administrative configuration. |
| **Other requirements** | HTTPS-only access; supported browser and desktop clients; reliable backup and restore; SMTP for invitations; controlled registration; timely security updates. |
| **Could a bug affect medical-device safety or quality?** | Indirectly. Incorrect access control or unavailable credentials could enable unauthorized changes or delay work in dependent systems. The vault does not control a medical device. |
| **Does it perform a regulated activity?** | No regulated activity is performed automatically. It supports access control for systems that may contain regulated records. |
| **Does it generate or manage product-approval data?** | No product data is intended to be stored. It may store credentials used to access systems containing such data. |
| **Does it manage QMS or authority records?** | It manages credentials, not authoritative QMS records. Administrative and backup records support information-security controls. |
| **Does it generate electronic signatures?** | No. |

# Requirements

## Regulatory and quality requirements

| **Requirement source** | **Application to this system** | **Requirement-ID** |
| --- | --- | --- |
| ISO 13485:2016 4.2.5 - protection, integrity and retrieval of records | Credentials protecting regulated records must be available only to authorized personnel and recoverable after failure. | VW-SEC-001, VW-BACKUP-001 |
| ISO 13485:2016 6.2 - competence and awareness | Administrators and users must be trained in secure vault use, sharing, recovery, and offboarding. | VW-TRAIN-001 |
| Internal information-security and access-control procedures | Access must be role-based, individually attributable, reviewed, and revoked when no longer needed. | VW-ACCESS-001, VW-OFFBOARD-001 |
| Data-protection requirements | Vault contents, account data, backups, and SMTP configuration must be protected against unauthorized disclosure. | VW-SEC-002 |

## Functional and operational requirements

|  | **Requirement** | **Requirement-ID** |
| --- | --- | --- |
| 1 | Authorized users shall be able to authenticate and access only their personal vault and permitted organization collections. | VW-LOGIN-001 |
| 2 | Unauthorized users shall be denied access. Public self-registration shall be disabled in production unless explicitly approved. | VW-ACCESS-001 |
| 3 | Organization owners shall be able to invite, assign, change, and remove members according to approved roles. | VW-ORG-001 |
| 4 | Credential items shall synchronize correctly between the web vault and approved clients. | VW-SYNC-001 |
| 5 | Removing a user from an organization shall remove access to its collections. | VW-OFFBOARD-001 |
| 6 | Connections shall use valid HTTPS transport encryption. | VW-SEC-001 |
| 7 | Sensitive configuration, administrative tokens, persistent data, and backups shall not be publicly accessible. | VW-SEC-002 |
| 8 | A documented backup and restore procedure shall recover vault service and data. | VW-BACKUP-001 |
| 9 | Invitation and account-related email shall use the approved SMTP configuration without exposing SMTP credentials. | VW-SMTP-001 |
| 10 | The deployed version shall be recorded and updates shall follow change control and regression testing. | VW-CHANGE-001 |
| 11 | Users and administrators shall receive role-appropriate training. | VW-TRAIN-001 |

# Risk management

## Risk assessment questions

| **Risk assessment question** | **Applicable** | **Assessment for Vaultwarden** |
| --- | --- | --- |
| Can the software system cause risks for people? | Indirect | Compromised credentials could permit unauthorized actions in connected systems, but Vaultwarden does not itself control a medical device or physical process. |
| Can patients, users, or third parties be harmed by a defective medical device which could be caused by the software system? | No direct effect | Vaultwarden cannot create a defective device. Loss or misuse of credentials could indirectly enable unauthorized changes in a separate system, which remains controlled there. |
| Can users of this or another system suffer damage? | Yes | Credential disclosure, loss, stale synchronization, or unavailable access could cause confidentiality, operational, contractual, or financial harm. |
| Can regulatory risks arise? | Yes | Loss of controlled access or unavailable credentials could delay regulated work and weaken access-control or audit evidence in dependent systems. |
| Can regulatory-relevant records or documents be falsified? | Indirect | Vaultwarden does not store those records, but stolen credentials could be used to alter them in an authoritative downstream system. |
| Can data essential for product approval be falsified? | No direct effect | Product-approval data is outside scope; credentials could only provide access to a separate system where its own authorization and audit controls apply. |
| Can damage to the environment or other assets occur? | Indirect | Compromised privileged credentials could expose customer or company IT assets; no direct environmental control is performed. |
| Can downstream processes be affected? | Yes | Support, administration, onboarding/offboarding, and access to dependent systems can be blocked or performed by unauthorized persons. |
| Are there any other risks? | Yes | Relevant risks include weak recovery practices, client incompatibility, excessive collection access, retained local caches, and prohibited sensitive content in free-text fields. |

## Risk control measures

|  | **Risk** | **Probability** | **Damage** | **Detectability** | **Initial priority** | **Risk control measure** | **Verification / Requirement-ID** | **Residual priority** |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | Unauthorized person obtains credentials. | Medium | High | Low | High | Individual accounts, strong authentication, HTTPS, restricted registration, least-privilege collections, and hardened administration. | VW-LOGIN-001, VW-ACCESS-001, VW-SEC-001 | Medium |
| 2 | Shared credential is visible to an unauthorized organization member. | Medium | High | Medium | High | Collection-based access, membership review, and tests for positive and negative authorization. | VW-ORG-001, VW-ACCESS-001 | Low |
| 3 | Former employee retains access. | Medium | High | Medium | High | Documented offboarding with account and organization removal; periodic access review. | VW-OFFBOARD-001 | Low |
| 4 | Vault data is lost or unavailable. | Low | High | Medium | Medium | Protected backups, restore test, service monitoring, and documented recovery. | VW-BACKUP-001 | Low |
| 5 | SMTP or administrative secrets are disclosed. | Low | High | Low | High | Secrets stored outside version control, restricted environment files, and protected backups. | VW-SEC-002, VW-SMTP-001 | Low |
| 6 | Client/server incompatibility causes missing or stale credentials. | Medium | Medium | High | Low | Test supported clients and synchronization after relevant upgrades. | VW-SYNC-001, VW-CHANGE-001 | Low |
| 7 | User stores prohibited sensitive business data in free-text fields. | Medium | Medium | Low | Medium | Usage policy and training define permitted content and prohibit storage of unnecessary personal or product data. | VW-TRAIN-001 | Low |

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

Justification: Vaultwarden enforces access to credentials for dependent systems. A focused configuration validation should verify authentication, organization authorization, revocation, synchronization, HTTPS, and backup restoration. Cryptographic implementation testing remains the responsibility of the upstream project and is not repeated locally.

## Release

The computerized system is released under this evaluation:

- [ ] Yes
- [x] No - validation execution and release approval are pending
- [ ] Subject to conditions

| **Date of release** | **Person approving release** | **Role** |
| --- | --- | --- |
| TBD | TBD | Process Owner / QM |

# Test specifications and validations

The validation records are prepared and execution is in progress; release approval remains pending:

- [Validation Plan - Vaultwarden](validation/IS-REC-EN-Validation-Plan-Vaultwarden.md)
- [Test Protocol - Vaultwarden](validation/IS-REC-EN-Test-Protocol-Vaultwarden.md)
- [Validation Report - Vaultwarden](validation/IS-REC-EN-Validation-Report-Vaultwarden.md)

# Decommissioning

| **Date of decommissioning** | Not applicable - active system |
| --- | --- |
