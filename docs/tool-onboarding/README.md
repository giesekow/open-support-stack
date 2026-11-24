# Support Stack Tool Onboarding

This directory contains the approved computerized-system evaluations and the
associated draft validation or operational-acceptance records for the first
support-stack onboarding scope.

## Current Scope and Approved Decisions

| System | Intended use | Approved criticality | Approved validation decision |
| --- | --- | --- | --- |
| Vaultwarden | Storage and controlled sharing of support credentials | High | QM relevant; focused configuration validation required |
| NetBird | Encrypted, policy-controlled remote support access | High | QM relevant; focused configuration validation required |
| OrangeHRM (retired) | Historical employee and leave administration | Retired | Superseded by Frappe HR; records retained only for approved migration/rollback period |
| Seafile | Secure exchange of customer, technical, and potentially QMS-related files | Moderate | QM relevant; focused configuration validation required |
| Keycloak | Central identity, authentication, groups, roles, and sessions | High | QM relevant; focused configuration validation required |

These decisions were approved on 2026-09-25. The Process Owner and QM must
approve the validation plans and test protocols before test execution.

## Deferred System

Support Tools and the Frappe HR leave-email notifier are excluded from the
historical OrangeHRM evaluation. They form a standalone internally developed system and
will receive their own evaluation and validation package after functional
and operational testing has been completed and approved.

## Workflow

1. Review and approve each evaluation's intended use, system boundary,
   software category, criticality, risks, requirements, and validation
   decision.
2. Record the assigned computerized-system ID, document owner, approvers,
   release date, and published page ID.
3. Pin the exact production software version or image digest before release.
4. For systems requiring validation, create and approve the Validation Plan.
5. Approve the Test Protocol before execution.
6. Execute tests and retain objective evidence without real customer secrets or
   personal data.
7. Document deviations and corrective actions.
8. Approve the Validation Report and release decision.
9. Maintain the records through change control, periodic review, upgrade,
   incident, and decommissioning activities.

## Lean Evidence Principles

- Execute one coherent lifecycle or decision-matrix test when the same setup
  and evidence demonstrates several related requirements.
- Reference approved Keycloak evidence for provider-level authentication and
  MFA. Dependent systems test only their OIDC integration and effective access.
- Do not infer denial from a successful positive test. Customer isolation,
  unauthorized access, prohibited ports, revocation, and expiry require
  explicit negative results.
- Do not repeat an action only to create separate screenshots. One evidence
  reference may support several requirements when traceability is explicit.
- Keep backup/restore separate because configuration inspection or normal
  operation cannot prove recoverability.

## Execution Scope

| System | Execution records | Focus |
| --- | ---: | --- |
| Vaultwarden | 5 tests | Account lifecycle, collection authorization, synchronization, readiness, restore |
| NetBird | 7 tests | Enrollment, identity integration, access matrix, routing, connectivity, restore, release baseline |
| OrangeHRM (historical) | 6 checks | Retained evidence; do not reuse as Frappe HR approval |
| Seafile | 6 tests | Authorization, integrity/limits, share lifecycle, readiness, file handling, restore |
| Keycloak | 8 tests | Authentication/MFA, claims, clients, sessions, administration, exposure, restore, configuration |

## Records

### Vaultwarden

- [Approved evaluation](vaultwarden/IS-REC-EN-Evaluation-Vaultwarden.md)
- [Validation plan - execution in progress](vaultwarden/validation/IS-REC-EN-Validation-Plan-Vaultwarden.md)
- [Test protocol - execution in progress](vaultwarden/validation/IS-REC-EN-Test-Protocol-Vaultwarden.md)
- [Validation report - execution in progress](vaultwarden/validation/IS-REC-EN-Validation-Report-Vaultwarden.md)

### NetBird

- [Approved evaluation](netbird/IS-REC-EN-Evaluation-NetBird.md)
- [Validation plan - execution in progress](netbird/validation/IS-REC-EN-Validation-Plan-NetBird.md)
- [Test protocol - execution in progress](netbird/validation/IS-REC-EN-Test-Protocol-NetBird.md)
- [Validation report - execution in progress](netbird/validation/IS-REC-EN-Validation-Report-NetBird.md)

### OrangeHRM

- Status: retired and superseded by Frappe HR. These records remain historical evidence.
- [Approved evaluation](orangehrm/IS-REC-EN-Evaluation-OrangeHRM.md)
- [Draft operational acceptance record](orangehrm/IS-REC-EN-Operational-Acceptance-OrangeHRM.md)

### Frappe HR

- Status: locally integrated; evaluation and applicable validation records must be approved before production HR cutover.
- Cutover controls: [Frappe HR Cutover Runbook](../frappe_hr_cutover.md)

### Seafile

- [Approved evaluation](seafile/IS-REC-EN-Evaluation-Seafile.md)
- [Validation plan - execution in progress](seafile/validation/IS-REC-EN-Validation-Plan-Seafile.md)
- [Test protocol - execution in progress](seafile/validation/IS-REC-EN-Test-Protocol-Seafile.md)
- [Validation report - execution in progress](seafile/validation/IS-REC-EN-Validation-Report-Seafile.md)

### Keycloak

- [Approved evaluation](keycloak/IS-REC-EN-Evaluation-Keycloak.md)
- [Validation plan - execution in progress](keycloak/validation/IS-REC-EN-Validation-Plan-Keycloak.md)
- [Test protocol - execution in progress](keycloak/validation/IS-REC-EN-Test-Protocol-Keycloak.md)
- [Validation report - execution in progress](keycloak/validation/IS-REC-EN-Validation-Report-Keycloak.md)

All test protocols and reports remain unexecuted. Their draft status must be
preserved until objective evidence has been recorded, deviations reviewed, and
the required approvals completed. Seafile additionally requires an immutable
image version or digest before validation execution.
