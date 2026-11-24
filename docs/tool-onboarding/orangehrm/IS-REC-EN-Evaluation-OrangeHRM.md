# IS-REC-EN-Evaluation-OrangeHRM

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

| **Name** | OrangeHRM |
| --- | --- |
| **Version / state (date)** | OrangeHRM 5.8.1; self-hosted support-stack deployment |
| **Manufacturer** | OrangeHRM, Inc.; operated by Bonescreen GmbH |
| **Purpose of the software** | Employee master-data administration and leave request, approval, and absence management. |
| **Processes in which the software is used** | Human resources administration; leave planning; leave approval; personnel availability planning. |
| **User (role / function)** | Employees; supervisors; HR personnel; system administrators. |
| **QM relevant, justification** | Approved for current scope: No direct QM/GxP relevance. The system is currently used for employee and leave administration, not as the authoritative repository for competence, training, electronic signatures, product data, or QMS records. Re-evaluation is required before extending its use to those processes. |
| **Software category (Class 1, 2, 3)** | Class 2 - configurable standard software with a locally applied OIDC endpoint compatibility patch. |
| **Criticality** | Moderate. Failure affects HR operations, employee availability information, and personal data, but does not directly control product realization or release. |

## System boundary

The evaluated system includes OrangeHRM, its MariaDB database, persistent application data, Keycloak/OIDC login configuration, administrative roles, leave workflows, backup/restore procedures, and the locally maintained internal-endpoint compatibility patch. Keycloak is evaluated separately.

The Support Tools application and OrangeHRM leave-email notifier are explicitly excluded. They are standalone internally developed systems and will be evaluated after their testing and approval.

## Purpose / task of the software

| **Question** | **Answer** |
| --- | --- |
| **What is the purpose of the software?** | To maintain employee information and process employee leave requests and approvals. |
| **What tasks does it perform?** | Employee record administration, leave entitlement/configuration, leave requests, supervisor approval or rejection, leave status display, and reporting. |
| **Other requirements** | Data protection; role-based access; Keycloak login; browser compatibility; reliable backup/restore; controlled configuration and updates. |
| **Could a bug affect medical-device safety or quality?** | Not directly within the approved scope. Incorrect leave information could affect staffing plans, but qualified process owners remain responsible for adequate staffing. |
| **Does it perform a regulated activity?** | No. Leave approval is an HR activity. The system must not be used for regulated approval or training workflows without re-evaluation. |
| **Does it generate or manage product-approval data?** | No. |
| **Does it manage QMS or authority records?** | No, under the current intended use. HR leave records are business and personal-data records. |
| **Does it generate electronic signatures?** | No. |

# Requirements

## Regulatory and quality requirements

| **Requirement source** | **Application to this system** | **Requirement-ID** |
| --- | --- | --- |
| GDPR and applicable employment/data-protection requirements | Employee identity, contact, employment, and leave information must be accessible only to authorized persons and retained only as required. | OHRM-PRIV-001 |
| Internal HR procedures | Leave requests and decisions must follow assigned employee, supervisor, and HR roles. | OHRM-LEAVE-001 |
| Internal information-security requirements | Authentication, authorization, HTTPS, backups, administrative restriction, and controlled updates are required. | OHRM-ACCESS-001, OHRM-BACKUP-001 |
| ISO 13485:2016 6.2 - human resources | This evaluation does not approve OrangeHRM as the authoritative system for competence or training records. Such use requires change control and re-evaluation. | OHRM-SCOPE-001 |

## Functional and operational requirements

|  | **Requirement** | **Requirement-ID** |
| --- | --- | --- |
| 1 | Authorized users shall authenticate through the approved Keycloak/OpenID Connect configuration. | OHRM-LOGIN-001 |
| 2 | Employees shall see and modify only information permitted by their role. | OHRM-ACCESS-001 |
| 3 | HR and administrator functions shall be restricted to approved roles. | OHRM-ACCESS-002 |
| 4 | An employee shall be able to submit a leave request with type, date or period, and available details. | OHRM-LEAVE-001 |
| 5 | The assigned approver shall be able to approve or reject the request, and the resulting status shall be visible. | OHRM-LEAVE-002 |
| 6 | Leave balances and approved periods shall be calculated and displayed consistently with configured rules. | OHRM-LEAVE-003 |
| 7 | Employee and leave data shall be protected in transit, at rest in controlled storage, and in backups. | OHRM-PRIV-001 |
| 8 | The system shall support account disabling and removal of access following offboarding. | OHRM-OFFBOARD-001 |
| 9 | A documented backup and restore procedure shall recover the database and required persistent application data. | OHRM-BACKUP-001 |
| 10 | The locally applied OIDC patch shall be version controlled and regression tested after OrangeHRM updates. | OHRM-CHANGE-001 |
| 11 | The system shall not be used for competence, training, QMS approvals, or electronic signatures without approved change control and re-evaluation. | OHRM-SCOPE-001 |

# Risk management

## Risk assessment questions

| **Risk assessment question** | **Applicable** | **Assessment for OrangeHRM** |
| --- | --- | --- |
| Can the software system cause risks for people? | No direct effect | OrangeHRM manages employee and leave information only. Incorrect information may affect staffing or employee administration but does not control a physical or medical process. |
| Can patients, users, or third parties be harmed by a defective medical device which could be caused by the software system? | No | OrangeHRM does not participate in device design, production, verification, release, or operation within the approved scope. |
| Can users of this or another system suffer damage? | Yes | Unauthorized disclosure, incorrect leave balances, unavailable HR records, or incorrect approval status could cause privacy, employment, operational, or financial harm. |
| Can regulatory risks arise? | Yes, outside QMS | Data-protection and employment-law obligations apply. Direct medical-device/QMS risk is not expected within the approved leave-management scope. |
| Can regulatory-relevant records or documents be falsified? | No in approved scope | OrangeHRM is not approved for QMS, competence, training, product, or authority records. Unauthorized changes to HR records remain a data-protection and employment risk. |
| Can data essential for product approval be falsified? | No | Product-approval data is prohibited from the approved OrangeHRM scope. |
| Can damage to the environment or other assets occur? | Limited, indirect | Data loss or account compromise can affect company information assets, but OrangeHRM controls no equipment or environmental process. |
| Can downstream processes be affected? | Yes | Staffing, leave planning, supervisor scheduling, and support availability can be affected by incorrect or unavailable leave information. |
| Are there any other risks? | Yes | Personal-data exposure, role misconfiguration, OIDC patch regression, incomplete offboarding, backup failure, and unapproved scope expansion are relevant. |

## Risk control measures

|  | **Risk** | **Probability** | **Damage** | **Detectability** | **Initial priority** | **Risk control measure** | **Verification / Requirement-ID** | **Residual priority** |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | Unauthorized user accesses employee or leave information. | Medium | High | Medium | High | Keycloak authentication, role-based access, HTTPS, restricted administration, and access testing. | OHRM-LOGIN-001, OHRM-ACCESS-001 | Low |
| 2 | Incorrect role permits employee or supervisor to change unauthorized records. | Medium | Medium | Medium | Medium | Defined roles, least privilege, administrative review, and negative authorization tests. | OHRM-ACCESS-001, OHRM-ACCESS-002 | Low |
| 3 | Leave request or approval status is lost or incorrect. | Medium | Medium | High | Low | Workflow acceptance testing, visible statuses, and process-owner review. | OHRM-LEAVE-001 to OHRM-LEAVE-003 | Low |
| 4 | Personal data is lost after system failure. | Low | High | Medium | Medium | Protected backups and documented restore test. | OHRM-BACKUP-001 | Low |
| 5 | OIDC patch fails after upgrade and prevents login. | Medium | Medium | High | Low | Version control, staging test, local administrator recovery account, and regression testing. | OHRM-CHANGE-001 | Low |
| 6 | System is used later for training or QMS records without appropriate controls. | Medium | High | Low | High | Explicit scope restriction, user training, change control, and mandatory re-evaluation. | OHRM-SCOPE-001 | Low |
| 7 | Email automation is assumed to be covered by this evaluation. | Medium | Medium | Low | Medium | Explicitly exclude Support Tools and notifier; onboard them under separate records after approval. | OHRM-SCOPE-001 | Low |

## Determination of criticality

- [ ] high
- [x] moderate
- [ ] low

## Decision on validation obligation

Approved decision:

- [ ] System is QM relevant and needs to be validated.
- [ ] System is QM relevant and does not have to be validated.
- [x] System is not QM/GxP relevant in the currently approved leave-management scope; formal CSV validation is not required.
- [ ] System is already validated under another system record.

Justification: OrangeHRM currently manages HR and leave information and does not manage competence, training, product, QMS, approval, or electronic-signature records. Documented installation qualification, security checks, workflow acceptance, backup restoration, and release approval are still required as operational controls. Any expansion into training or competence management triggers re-evaluation and likely validation.

## Release

- [ ] Yes
- [x] No - operational acceptance execution and release approval are pending
- [ ] Subject to conditions

| **Date of release** | **Person approving release** | **Role** |
| --- | --- | --- |
| TBD | TBD | HR Process Owner / IT / QM review |

# Test specifications and validations

No formal validation package is required for the current approved scope. The [OrangeHRM Operational Acceptance Record](IS-REC-EN-Operational-Acceptance-OrangeHRM.md) covers login, roles, leave request/approval, privacy, offboarding, patch regression, backup restoration, and the intended-use restriction. If QM determines the system is QM relevant, create a Validation Plan, Test Protocol, and Validation Report before release.

# Decommissioning

| **Date of decommissioning** | Not applicable - active system |
| --- | --- |
