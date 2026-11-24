# IS-REC-EN-Evaluation-NetBird

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

| **Name** | NetBird secure remote-access platform |
| --- | --- |
| **Version / state (date)** | NetBird server, dashboard, and tested clients 0.79.0; self-hosted deployment |
| **Manufacturer** | NetBird GmbH / NetBird open-source project; operated by Bonescreen GmbH |
| **Purpose of the software** | Encrypted, policy-controlled remote access from approved support machines to approved customer machines and services. |
| **Processes in which the software is used** | Customer support; remote system administration; incident response; controlled access provisioning and revocation. |
| **User (role / function)** | Support engineers; system administrators; authorized access administrators. |
| **QM relevant, justification** | Approved: Yes. NetBird controls privileged support access to customer and internal systems. Incorrect policy or routing could expose customer systems, cross customer boundaries, or prevent support activities. |
| **Software category (Class 1, 2, 3)** | Class 2 - configurable standard software integrated with the company identity provider and network infrastructure. |
| **Criticality** | High. The platform is a privileged security boundary for remote customer access. |

## System boundary

The evaluated system includes the self-hosted NetBird management, signal, relay and STUN services, dashboard, peer clients, access groups and policies, Network resources and routing peers, reverse-proxy paths, persistent configuration, and backup/restore procedures. Keycloak is evaluated separately. Customer operating systems and services reached through NetBird remain separate systems.

## Purpose / task of the software

| **Question** | **Answer** |
| --- | --- |
| **What is the purpose of the software?** | To provide encrypted remote support connectivity without publicly exposing customer SSH, RDP, or application ports. |
| **What tasks does it perform?** | Peer enrollment, device identity, tunnel establishment, NAT traversal, encrypted relay fallback, group and policy enforcement, network-resource routing, and access revocation. |
| **Other requirements** | Self-hosted availability; Keycloak authentication; MFA; support for Windows and Linux; TCP/443 relay fallback; UDP/3478 STUN; backup and recovery; least-privilege policies. |
| **Could a bug affect medical-device safety or quality?** | Indirectly. Unauthorized or unavailable support access could affect customer systems or delay corrective support. NetBird does not control a medical device. |
| **Does it perform a regulated activity?** | No regulated activity is performed automatically. It enforces access used during support activities. |
| **Does it generate or manage product-approval data?** | No. It manages access-control and network metadata. |
| **Does it manage QMS or authority records?** | It maintains security configuration and administrative audit events that may support access-control evidence. It is not the authoritative repository for product records. |
| **Does it generate electronic signatures?** | No. |

# Requirements

## Regulatory and quality requirements

| **Requirement source** | **Application to this system** | **Requirement-ID** |
| --- | --- | --- |
| ISO 13485:2016 4.2.5 - protection, integrity and retrieval | Access to systems containing quality records must be restricted and recoverable. | NB-POLICY-001, NB-ISOLATION-001, NB-BACKUP-001 |
| ISO 13485:2016 7.2 / 7.5 - customer communication and service activities | Remote support access must be controlled and available for authorized service work. | NB-CONNECT-001 |
| Internal information-security requirements | Strong identity, encryption, least privilege, customer isolation, review, and revocation are required. | NB-IDENTITY-001, NB-POLICY-001, NB-ISOLATION-001 |
| Data-protection and confidentiality requirements | Customer network information and traffic must be protected against unauthorized access. | NB-ENCRYPT-001 |

## Functional and operational requirements

|  | **Requirement** | **Requirement-ID** |
| --- | --- | --- |
| 1 | Only approved peers shall enroll using controlled setup keys or approved interactive authentication. | NB-ENROLL-001 |
| 2 | Support users shall authenticate through the approved identity provider with MFA where required. | NB-IDENTITY-001 |
| 3 | The default all-to-all policy shall be disabled in production. | NB-POLICY-001 |
| 4 | A one-way policy shall permit Support-Group to initiate only approved traffic to Customer-Group. | NB-POLICY-002 |
| 5 | Customer peers shall not initiate connections to support peers or other customer peers. | NB-ISOLATION-001 |
| 6 | Policies shall restrict protocol and ports to the minimum required for the support activity. | NB-LEASTPRIV-001 |
| 7 | Single LAN hosts shall be represented as `/32` resources unless a wider subnet is explicitly justified and approved. | NB-ROUTE-001 |
| 8 | Windows routing peers exposing their own LAN IP shall be configured and tested with local forwarding. | NB-WINROUTE-001 |
| 9 | Peer traffic shall remain encrypted for direct and relayed connections. | NB-ENCRYPT-001 |
| 10 | Management and Signal shall be reachable over TCP/443; STUN shall use UDP/3478; relay fallback shall remain available over TCP/443. | NB-CONNECT-001 |
| 11 | Removing a peer, group membership, user, setup key, policy, or resource shall revoke the corresponding access. | NB-REVOKE-001 |
| 12 | Configuration and datastore encryption keys shall be backed up and recoverable. | NB-BACKUP-001 |
| 13 | Server and clients shall run an approved supported version and upgrades shall undergo regression testing. | NB-CHANGE-001 |
| 14 | Policy and enrollment changes shall be periodically reviewed. | NB-REVIEW-001 |

# Risk management

## Risk assessment questions

| **Risk assessment question** | **Applicable** | **Assessment for NetBird** |
| --- | --- | --- |
| Can the software system cause risks for people? | Indirect | Unauthorized or unavailable remote access could contribute to incorrect support actions or delayed intervention, but NetBird does not itself control a medical device. |
| Can patients, users, or third parties be harmed by a defective medical device which could be caused by the software system? | No direct effect | NetBird cannot make a device defective. Misconfigured privileged access could indirectly permit changes in a customer system, whose own controls remain applicable. |
| Can users of this or another system suffer damage? | Yes | Cross-customer access, exposed services, or loss of support connectivity could cause confidentiality, availability, operational, contractual, or financial harm. |
| Can regulatory risks arise? | Yes | Unauthorized support access or inability to perform urgent service work could affect controlled service activities, incident response, and access evidence. |
| Can regulatory-relevant records or documents be falsified? | Indirect | NetBird does not store regulated records, but excessive network access could enable alteration in a connected authoritative system. |
| Can data essential for product approval be falsified? | No direct effect | Product-approval data is outside NetBird; risk arises only through unauthorized access to another system that stores such data. |
| Can damage to the environment or other assets occur? | Yes, indirectly | Incorrect routes or policies can expose or disrupt customer and company systems; no direct environmental process is controlled. |
| Can downstream processes be affected? | Yes | Remote support, incident response, administration, and customer service availability depend on effective connectivity and isolation. |
| Are there any other risks? | Yes | Key leakage, cross-customer routing, overly broad subnet resources, unsupported clients, relay/proxy failure, and unrecoverable datastore encryption keys are material risks. |

## Risk control measures

|  | **Risk** | **Probability** | **Damage** | **Detectability** | **Initial priority** | **Risk control measure** | **Verification / Requirement-ID** | **Residual priority** |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | Customer A can initiate access to Customer B. | Low | High | Low | High | Remove default mesh policy; use one-way support-to-customer policy; negative connectivity tests between customers. | NB-POLICY-001, NB-ISOLATION-001 | Low |
| 2 | Compromised support machine reaches unnecessary customer services. | Medium | High | Medium | High | Harden support endpoints and allow only required protocols, ports, peers, and `/32` resources. | NB-LEASTPRIV-001, NB-ROUTE-001 | Medium |
| 3 | Unauthorized peer is enrolled using a leaked setup key. | Medium | High | Medium | High | Expiring, scoped, preferably one-off setup keys; key revocation and enrollment review. | NB-ENROLL-001, NB-REVIEW-001 | Low |
| 4 | Identity or group error grants unauthorized support access. | Medium | High | Medium | High | Keycloak MFA, restricted administrators, group review, policy tests, and immediate revocation. | NB-IDENTITY-001, NB-REVOKE-001 | Low |
| 5 | Incorrect route exposes a whole customer subnet. | Medium | High | Medium | High | Default to `/32`, require documented approval for wider routes, test effective routes. | NB-ROUTE-001 | Low |
| 6 | Windows LAN-IP resource is unavailable despite peer connectivity. | Medium | Medium | High | Low | Enable local forwarding on Windows routing peers and verify the `wt0` route and service port. | NB-WINROUTE-001 | Low |
| 7 | Proxy, STUN, or relay failure prevents remote support. | Medium | Medium | High | Low | Monitor services; test direct and relay paths; document HAProxy/nginx requirements and recovery procedures. | NB-CONNECT-001 | Low |
| 8 | Loss of datastore or encryption key prevents recovery. | Low | High | Low | High | Protected backup of persistent data and encryption key plus restore testing. | NB-BACKUP-001 | Medium |
| 9 | Vulnerability remains because an unsupported version is deployed. | Medium | High | Medium | High | Track upstream advisories and keep server and clients on approved supported versions. | NB-CHANGE-001 | Low |

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

Justification: The locally configured identity, policy, routing, proxy, and recovery controls determine the effective security boundary. Validation should focus on the intended configuration, including positive support access, negative customer-to-customer tests, least-privilege ports, `/32` resources, revocation, relay fallback, and restoration.

## Release

- [ ] Yes
- [x] No - validation execution and release approval are pending
- [ ] Subject to conditions

| **Date of release** | **Person approving release** | **Role** |
| --- | --- | --- |
| TBD | TBD | Process Owner / QM |

# Test specifications and validations

The validation records are prepared but have not yet been executed or approved for release:

- [Validation Plan - NetBird](validation/IS-REC-EN-Validation-Plan-NetBird.md)
- [Test Protocol - NetBird](validation/IS-REC-EN-Test-Protocol-NetBird.md)
- [Validation Report - NetBird](validation/IS-REC-EN-Validation-Report-NetBird.md)

# Decommissioning

| **Date of decommissioning** | Not applicable - active system |
| --- | --- |
