# IS-REC-EN-Validation-Plan-Seafile-2026-09

## Meta information

| **Document type** | Validation Plan |
| --- | --- |
| **Version** | 0.2 |
| **Status** | Draft - approval required before execution |
| **Planned validation date** | TBD |
| **Page ID** | TBD after publication |
| **Last change** | Test strategy consolidated to avoid duplicate evidence while retaining risk coverage. |

## 1 Purpose

This plan defines risk-based validation of Seafile for secure transfer and controlled collaboration on customer, technical, and potentially QMS-related files. Seafile is validated as a transfer service, not as the authoritative QMS record repository.

## 2 Roles and responsibilities

| **Role** | **Responsibility / person** |
| --- | --- |
| Validation Planning | Validation lead - TBD |
| Validation Execution | Trained tester - TBD |
| Process Owner | Management IT / Support - named person TBD |
| System Owner | Support-stack administrator - named person TBD |
| Review and Approval | QM representative and data owner - TBD |

## 3 Milestones

| **Milestone** | **Target** |
| --- | --- |
| Evaluation approved | 2026-09-25 |
| Immutable image version/digest approved | Before plan approval |
| Plan and protocol approved | Before execution |
| Tests performed | TBD |
| Deviations resolved or accepted | Before report approval |
| Validation report approved and system released | TBD |

## 4 Software to be validated

| **ID** | **Software** | **Version** | **Category** |
| --- | --- | --- | --- |
| TBD from computerized-system list | Seafile server, MariaDB, memcached and configured proxy integration | TBD: replace floating `latest` with approved version/digest | Class 2 - configurable standard software |

Associated record: [Evaluation - Seafile](../IS-REC-EN-Evaluation-Seafile.md).

## 5 Scope

In scope: identity login, library authorization, upload/download integrity, sharing and expiry, revocation, HTTPS, configured size limits, prohibited/malicious-file handling procedure, transfer-to-authoritative-repository rule, coordinated database/file backup and restore, and immutable version control.

Out of scope: validation of recipient endpoint protection, authoritative QMS document control, content correctness of transferred files, and source-level verification of Seafile cryptography.

## 6 Preconditions and test environment

- An immutable Seafile version or image digest is recorded and approved.
- At least two test users and isolated libraries are available.
- Test files contain no personal, customer, product, or confidential information.
- Recorded hashes are available for integrity verification.
- SMTP/OIDC and HTTPS integrations are operational.
- A test includes files below, at, and above the approved upload boundary where technically safe.
- Database and file-data backups can be restored into an isolated target.

## 7 Test strategy

Positive and negative user tests verify access and sharing boundaries. File hashes verify transfer integrity. Restore testing must demonstrate consistency between metadata/database records and file blocks. Evidence must avoid retaining sensitive content.

## 8 Requirements and traceability

| **Requirement(s)** | **Planned test** |
| --- | --- |
| SF-LOGIN-001, SF-ACCESS-001 | SF-T01 Seafile identity integration and authorization |
| SF-INTEGRITY-001, SF-UPLOAD-001 | SF-T02 Transfer integrity and size boundaries |
| SF-SHARE-001, SF-REVOKE-001 | SF-T03 Controlled-share lifecycle |
| SF-SEC-001, SF-CHANGE-001, SF-CHANGE-002 | SF-T04 Security and immutable release baseline |
| SF-MALWARE-001, SF-RETENTION-001 | SF-T05 Controlled file-handling lifecycle |
| SF-BACKUP-001 | SF-T06 Coordinated backup and isolated restoration |

Provider-level authentication evidence is reused from Keycloak; SF-T01 verifies Seafile integration and effective application authorization.

## 9 Acceptance criteria

- All required tests pass or have approved deviations.
- Unauthorized users cannot discover or retrieve unshared test files.
- Uploaded and downloaded hashes match.
- Expired or revoked access fails.
- Size-limit behavior is explicit and does not produce an apparently successful partial file.
- Restored metadata and files are consistent and retrievable.
- The deployed image is immutable and recorded.
- No unresolved high-priority deviation remains.

## 10 Deviations and revalidation

Revalidation is considered after major upgrades, identity/sharing model changes, proxy upload-limit changes, storage architecture changes, backup changes, external-sharing changes, or a confidentiality/integrity incident.

## 11 Applicable documents

- Evaluation - Seafile
- SOP Computer System Validation
- Test Protocol - Seafile
- Secure file-sharing procedure
- Record retention and disposition procedure
- Backup and restore procedure
- Change-control procedure
