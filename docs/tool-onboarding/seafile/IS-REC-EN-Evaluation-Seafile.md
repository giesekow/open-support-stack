# IS-REC-EN-Evaluation-Seafile

## Meta information

| **Document type** | Evaluation of computerized system |
| --- | --- |
| **Version** | 1.2 |
| **Status** | Approved |
| **Last release date** | 2026-09-25 |
| **Page ID** | TBD after publication |
| **Last change to the document** | Risk assessment screening questions completed; approved scope and decision unchanged. |

# Evaluation of computerized system

## Meta data of the software

| **Name** | Seafile secure file-sharing service |
| --- | --- |
| **Version / state (date)** | Self-hosted `seafileltd/seafile-mc` deployment. Exact immutable version is TBD because the current Compose configuration uses the floating `latest` tag. |
| **Manufacturer** | Seafile Ltd.; operated by Bonescreen GmbH |
| **Purpose of the software** | Controlled exchange of files with internal personnel and authorized external recipients. |
| **Processes in which the software is used** | Customer support; secure file transfer; controlled collaboration; exchange of diagnostic, technical, and business files. |
| **User (role / function)** | Support engineers; authorized employees; approved customer or external users; system administrators. |
| **QM relevant, justification** | Approved: Yes when files exchanged through the system form input to, output from, or evidence of QMS and customer-support processes. Seafile is a transfer and collaboration system, not the authoritative long-term QMS record repository. |
| **Software category (Class 1, 2, 3)** | Class 2 - configurable standard software. |
| **Criticality** | Moderate. Failure can delay secure exchange; unauthorized sharing or corruption can disclose confidential data or affect downstream work. |

## System boundary

The evaluated system includes Seafile, MariaDB, memcached, persistent file data, Keycloak/OIDC configuration, libraries, users, groups, shares, upload/download behavior, version/history behavior used locally, backup/restore, and reverse-proxy controls. Keycloak is evaluated separately. Recipient endpoint security and the authoritative repository into which approved records are transferred are outside this boundary.

## Purpose / task of the software

| **Question** | **Answer** |
| --- | --- |
| **What is the purpose of the software?** | To exchange files without email attachments or public anonymous storage and to restrict access to approved recipients. |
| **What tasks does it perform?** | Authentication, library management, upload/download, synchronization, internal sharing, external sharing where approved, link expiry/password controls, and file-history support. |
| **Other requirements** | HTTPS; upload-size support; access expiry; malware-handling procedure; backup/restore; browser compatibility; immutable release versions; data retention and deletion rules. |
| **Could a bug affect medical-device safety or quality?** | Indirectly if an incorrect, incomplete, corrupted, or unavailable file is used in a downstream quality or support process. Process owners must transfer authoritative records to their approved repository. |
| **Does it perform a regulated activity?** | No regulated decision is made automatically. It may transport files used by regulated processes. |
| **Does it generate or manage product-approval data?** | It may temporarily transport such data but is not approved as the authoritative product-approval repository. |
| **Does it manage QMS or authority records?** | It may temporarily hold copies during transfer. Final controlled records must be stored in the designated QMS repository according to retention procedures. |
| **Does it generate electronic signatures?** | No. |

# Requirements

## Regulatory and quality requirements

| **Requirement source** | **Application to this system** | **Requirement-ID** |
| --- | --- | --- |
| ISO 13485:2016 4.2.5 - identification, storage, security, integrity, retrieval, retention and disposition | Files involved in QMS processes must remain identifiable, protected, retrievable, and transferred to the authoritative repository. | SF-INTEGRITY-001, SF-RETENTION-001 |
| Confidentiality and data-protection requirements | Internal, customer, personal, and potentially health-related files must be shared only with authorized recipients. | SF-ACCESS-001, SF-SHARE-001 |
| Internal information-security requirements | HTTPS, least privilege, expiring external access, backups, malware procedure, monitoring, and controlled updates are required. | SF-SEC-001, SF-BACKUP-001 |

## Functional and operational requirements

|  | **Requirement** | **Requirement-ID** |
| --- | --- | --- |
| 1 | Authorized users shall authenticate using the approved identity configuration. | SF-LOGIN-001 |
| 2 | Users shall access only libraries, folders, and files explicitly shared with them. | SF-ACCESS-001 |
| 3 | Users shall upload and download files without unreported content alteration. | SF-INTEGRITY-001 |
| 4 | Approved sharing methods shall support recipient restriction and expiry or revocation where applicable. | SF-SHARE-001 |
| 5 | Revoking a user, group, library permission, or share shall remove subsequent access. | SF-REVOKE-001 |
| 6 | Access shall use valid HTTPS and persistent data shall not be publicly exposed. | SF-SEC-001 |
| 7 | File size limits shall support the approved business use and reject oversized uploads predictably. | SF-UPLOAD-001 |
| 8 | A documented procedure shall address malicious or prohibited files and endpoint scanning responsibilities. | SF-MALWARE-001 |
| 9 | QMS-relevant files shall be transferred to the authoritative repository; Seafile shall not replace approved document control. | SF-RETENTION-001 |
| 10 | Database and file-data backups shall be consistent and successfully restorable. | SF-BACKUP-001 |
| 11 | The production image shall use an approved immutable version or digest rather than `latest`. | SF-CHANGE-001 |
| 12 | Updates shall follow change control and regression testing of login, upload, download, sharing, revocation, and restore. | SF-CHANGE-002 |

# Risk management

## Risk assessment questions

| **Risk assessment question** | **Applicable** | **Assessment for Seafile** |
| --- | --- | --- |
| Can the software system cause risks for people? | Indirect | Use of an incorrect, corrupted, malicious, or unavailable transferred file could contribute to harmful downstream decisions, although Seafile performs no medical or physical control. |
| Can patients, users, or third parties be harmed by a defective medical device which could be caused by the software system? | No direct effect | Seafile cannot make a device defective. An undetected wrong file could indirectly affect a separate design, service, or quality process if procedural controls fail. |
| Can users of this or another system suffer damage? | Yes | Unauthorized disclosure, malware transfer, corruption, or unavailable files could cause privacy, operational, contractual, financial, or cybersecurity harm. |
| Can regulatory risks arise? | Yes | Loss, disclosure, misidentification, or failure to transfer QMS-relevant files to the authoritative repository can affect record control and customer-support evidence. |
| Can regulatory-relevant records or documents be falsified? | Indirect | Unauthorized replacement or undetected alteration of a transfer copy is possible; hashes, permissions, and transfer to the authoritative repository control this risk. |
| Can data essential for product approval be falsified? | Indirect | Such data may only be transported temporarily. Undetected alteration could affect downstream use, but approval and authoritative storage occur outside Seafile. |
| Can damage to the environment or other assets occur? | Indirect | Malware or excessive resource consumption could affect connected endpoints, storage, or company/customer IT assets; no environmental process is controlled. |
| Can downstream processes be affected? | Yes | Support, analysis, collaboration, and QMS processes may use transferred files and can be delayed or misled by unavailable, wrong, or corrupted content. |
| Are there any other risks? | Yes | Public-link misuse, excessive retention, recipient error, oversized partial uploads, inconsistent database/file backups, and floating image versions are relevant. |

## Risk control measures

|  | **Risk** | **Probability** | **Damage** | **Detectability** | **Initial priority** | **Risk control measure** | **Verification / Requirement-ID** | **Residual priority** |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | File is disclosed to an unauthorized recipient. | Medium | High | Low | High | Named users/groups, least-privilege libraries, controlled external shares, expiry, and revocation tests. | SF-ACCESS-001, SF-SHARE-001 | Medium |
| 2 | Uploaded and downloaded file differs without detection. | Low | High | Medium | Medium | Transfer tests using recorded file hashes and error handling. | SF-INTEGRITY-001 | Low |
| 3 | Revoked link or user remains able to access data. | Medium | High | Medium | High | Explicit revocation tests and periodic share review. | SF-REVOKE-001 | Low |
| 4 | Malware is distributed through the service. | Medium | High | Low | High | Approved-file policy, endpoint protection, optional scanning integration, training, and incident procedure. | SF-MALWARE-001 | Medium |
| 5 | File or database data is lost or restored inconsistently. | Low | High | Low | High | Coordinated backup of database and file data plus restore verification. | SF-BACKUP-001 | Medium |
| 6 | Temporary copy is mistaken for the controlled QMS record. | Medium | High | Low | High | Scope statement, retention procedure, user training, and transfer to authoritative repository. | SF-RETENTION-001 | Low |
| 7 | Floating `latest` image introduces an unreviewed version. | Medium | High | Medium | High | Pin an approved version or digest before release and control updates. | SF-CHANGE-001 | Low |
| 8 | Oversized file fails silently or incompletely. | Medium | Medium | High | Low | Defined proxy/application limits and boundary-size upload/download tests. | SF-UPLOAD-001 | Low |

## Determination of criticality

- [ ] high
- [x] moderate
- [ ] low

## Decision on validation obligation

Approved decision:

- [x] System is QM relevant and needs to be validated for its intended secure-transfer configuration.
- [ ] System is QM relevant and does not have to be validated.
- [ ] System is not QM relevant; formal validation is not required.
- [ ] System is already validated under another system record.

Justification: The service may transport files used in QMS and customer-support processes. A focused validation should verify configured authentication, authorization, file integrity, sharing, revocation, size limits, scope/retention controls, and restoration. Release is conditional on replacing the floating `latest` image with an approved immutable version or digest.

## Release

- [ ] Yes
- [x] No - immutable version, validation execution, and release approval are pending
- [ ] Subject to conditions

| **Date of release** | **Person approving release** | **Role** |
| --- | --- | --- |
| TBD | TBD | Process Owner / QM |

# Test specifications and validations

The validation records are prepared but have not yet been executed or approved for release:

- [Validation Plan - Seafile](validation/IS-REC-EN-Validation-Plan-Seafile.md)
- [Test Protocol - Seafile](validation/IS-REC-EN-Test-Protocol-Seafile.md)
- [Validation Report - Seafile](validation/IS-REC-EN-Validation-Report-Seafile.md)

# Decommissioning

| **Date of decommissioning** | Not applicable - active system |
| --- | --- |
