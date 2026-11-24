# IS-REC-EN-Deviation-Register-Keycloak-2026-09

## Meta information

| **Document type** | Validation Deviation Register |
| --- | --- |
| **Version** | 0.3 |
| **Status** | Closed - all deviations remediated and revalidated |
| **Execution date** | 2026-09-25 |
| **Related protocol** | [Test Protocol - Keycloak](IS-REC-EN-Test-Protocol-Keycloak.md) |

## Deviations

| **ID** | **Related test / requirement** | **Observation** | **Risk assessment** | **Required action** | **Status** |
| --- | --- | --- | --- | --- | --- |
| KC-DEV-001 | KC-T01; KC-MFA-001 | Run 0001 found no privileged OTP. Runs 0002-0003 enforced enrollment; the shared privileged user enrolled TOTP, missing/incorrect OTP failed, correct OTP succeeded, and server-side verification found no pending action. | Residual risk is controlled by mandatory TOTP enrollment and tested second-factor enforcement. | Maintain required TOTP and periodically audit privileged credential coverage. | Closed 2026-09-25; KC-E10, KC-E12 |
| KC-DEV-002 | KC-T01; KC-AUTH-002 | Run 0001 found brute-force protection disabled. Run 0002 enabled failure factor 5 and verified baseline success, lock after five failures, denial while locked, recovery after unlock, and complete synthetic-data cleanup. | Residual risk is controlled by the configured lockout and operational monitoring. | Maintain the approved realm setting and include it in configuration drift checks. | Closed 2026-09-25; KC-E10 |
| KC-DEV-003 | KC-T03; KC-CLIENT-001 | Run 0001 found HTTP and wildcard callbacks. Run 0002 synchronized all ten managed clients to exact HTTPS callbacks; zero HTTP/wildcard entries remained, exact callbacks succeeded, and all altered callbacks returned HTTP 400. | Residual risk is controlled by exact callback registration and fail-closed synchronization. | Retain exact callback inventory and rerun boundary checks after hostname or client changes. | Closed 2026-09-25; KC-E11 |
| KC-DEV-004 | KC-T05; KC-ADMIN-001, KC-MFA-001 | Run 0002 assigned 11 reviewed delegated roles. Run 0003 verified MFA-protected Support realm administration while Master realm and impersonation access remained unavailable; `realm-admin` and `impersonation` were absent server-side. | Residual risk is controlled by named MFA-protected delegated administration and separate bootstrap/break-glass credentials. | Periodically review delegated roles, privileged membership, MFA coverage, and break-glass access. | Closed 2026-09-25; KC-E10, KC-E12 |
| KC-DEV-005 | KC-T08; KC-CHANGE-001 | Run 0001 found Keycloak 25.0.6 on a mutable tag. Run 0002 rehearsed migration from a restored backup, created fresh production backups, migrated to 26.7.4, pinned the approved digest, and completed lean regression checks. | Residual upgrade risk is controlled by immutable deployment, protected backups, rehearsal, and database-aware rollback instructions. | Continue release/advisory review and rehearse major schema upgrades against restored backups. | Closed 2026-09-25; KC-E09 |

## Disposition

All five deviations are remediated and closed. Runs 0002 and 0003 completed the required revalidation. Formal protocol/report review and approval signatures remain required before controlled release of the validation record.
