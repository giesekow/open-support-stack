# Support Stack Implementation Plan

## 1. Scope and Success Criteria

### 1.1 Objective
Implement a secure, auditable, and scalable remote support platform for regulated and enterprise customers (including hospitals and PACS/DICOM environments), based on:

- Dedicated support VM per engineer
- Shared infrastructure VM for identity, vault, docs, remote gateway, and mesh control plane
- Headscale/Tailscale for modern customer connectivity
- Compatibility with traditional VPN and jump-host patterns

### 1.2 In-Scope Components

- Hypervisor and network baseline: ESXi + pfSense + existing FRP path
- Infrastructure VM (Ubuntu Server 24.04)
- Docker Compose deployment of:
  - Keycloak
  - Vaultwarden
  - BookStack
  - Guacamole
  - Headscale
- Engineer support VMs (Windows 11 Pro preferred)
- DNS and certificate model
- Backup, restore, audit logging, and operational runbooks

### 1.3 Out-of-Scope (Phase 1)

- Full HA/active-active architecture for all services
- SIEM integration beyond log export and retention basics
- Automated customer self-service portal
- Billing/showback automation

### 1.4 Success Criteria

- 100% support engineers use dedicated support VMs
- All internal support services accessible only via VPN/internal routes
- Headscale publicly reachable on 443/TCP only
- Centralized identity and MFA enforced for all admins and engineers
- Passwords/secrets stored in Vaultwarden, not documentation tools
- Successful restore test from backup within RTO target
- Pilot customer support flow works end-to-end:
  - Browser -> Guacamole -> Support VM -> Headscale -> Customer resource

---

## 2. Target Architecture

### 2.1 Logical Topology

- Public VPS:
  - `frps`
  - Public 443 -> Headscale (via FRP to office)
  - Public 1194 -> pfSense OpenVPN (via FRP)
- Office/ESXi:
  - `pfSense` VM
  - `Infrastructure VM` (Docker Compose services)
  - `Support-VM-<EngineerName>` per engineer
  - Optional site-to-site VPN and customer jump-host connectivity

### 2.2 Exposure Policy

Publicly exposed:
- `mesh.company.com` (Headscale over HTTPS/443)

Internal-only (VPN/office/internal DNS):
- `vault.company.internal`
- `docs.company.internal`
- `remote.company.internal`
- `sso.company.internal`
- Keycloak admin endpoints
- Support VM management interfaces

### 2.3 Trust Boundaries

- Boundary A: Internet <-> Public VPS
- Boundary B: Public VPS <-> FRP tunnel <-> Office
- Boundary C: Office network <-> Infrastructure VM services
- Boundary D: Engineer identity/session <-> Guacamole session
- Boundary E: Support VM <-> Customer networks (Headscale or legacy VPN)

---

## 3. Delivery Phases

## Phase 0 - Project Preparation (Week 1)

### Goals
- Lock requirements, ownership, timeline, and acceptance criteria

### Tasks
- Assign owners for platform, networking, identity, and operations
- Define environment naming conventions and inventory format
- Finalize domain names and DNS zones
- Confirm certificate issuance approach (public CA for Headscale, internal CA/private PKI for internal services)
- Define RTO/RPO targets (example: RTO 4h, RPO 24h)
- Create project tracker with milestones and change log

### Deliverables
- Approved architecture baseline
- Owner matrix (RACI)
- Milestone plan and acceptance checklist

---

## Phase 1 - Infrastructure Foundation (Weeks 2-3)

### Goals
- Prepare stable compute, storage, network, and OS baseline

### Tasks
- Create Infrastructure VM on ESXi:
  - Ubuntu Server 24.04 LTS
  - Initial size: 8 vCPU, 32 GB RAM, 300+ GB SSD (or minimum 4/16/200 for pilot)
- Harden OS baseline:
  - Patch and reboot policy
  - SSH hardening (keys only, no password auth)
  - Host firewall default deny + explicit allow rules
  - Time sync (NTP)
  - Audit logging enabled
- Prepare storage layout:
  - `/opt/support-stack/` and persistent volume directories
- Configure network segmentation:
  - Management network
  - Service network
  - Optional backup network
- Configure pfSense rules and routing prerequisites

### Deliverables
- Hardened infrastructure VM
- Documented network segments/firewall rules
- Host-level baseline checklist complete

---

## Phase 2 - Public Access Path (Week 3)

### Goals
- Provide secure minimal public ingress for Headscale and OpenVPN forwarding

### Tasks
- Validate existing VPS + FRP chain capacity and reliability
- Configure FRP mappings:
  - 443/TCP -> Headscale service endpoint
  - 1194/UDP(or TCP as configured) -> pfSense OpenVPN
- Apply VPS firewall policy:
  - Allow only required ports
  - Restrict management access by IP where possible
- Add monitoring checks for:
  - Port availability
  - Tunnel health
  - Certificate expiry

### Deliverables
- Validated public ingress path
- Runbook for FRP restart/recovery
- Monitoring alerts active for external reachability

---

## Phase 3 - Core Platform Deployment (Weeks 4-5)

### Goals
- Deploy and validate all shared services via Docker Compose

### Tasks
- Create `docker-compose.yml` with explicit image tags (no floating `latest`)
- Define persistent volumes:
  - keycloak-db
  - vaultwarden-data
  - bookstack-db
  - bookstack-uploads
  - guacamole-db
  - headscale-data
- Deploy and validate each service:
  - Keycloak
  - Vaultwarden
  - BookStack
  - Guacamole
  - Headscale
- Place all services behind internal reverse proxy if used
- Enforce TLS for all service access paths
- Add secure secrets handling for Compose environment values

### Deliverables
- Running platform services with persistent storage
- Service inventory with versions and ports
- Initial health checks and startup dependency validation

---

## Phase 4 - Identity and Access Control (Week 5)

### Goals
- Centralize authentication and enforce MFA and least privilege

### Tasks
- Configure Keycloak realms, groups, and role model:
  - `platform-admin`
  - `support-engineer`
  - `auditor` (read-only)
- Enforce MFA policy for all interactive users
- Integrate SSO with:
  - Guacamole
  - BookStack
  - Vaultwarden (OIDC where supported by chosen configuration)
- Define identity lifecycle runbook:
  - Joiner
  - Mover
  - Leaver (access removal SLA)
- Disable all shared engineer accounts

### Deliverables
- Working SSO + MFA across core services
- Role mapping document
- Access lifecycle SOP approved

---

## Phase 5 - Engineer Workspace Rollout (Weeks 6-7)

### Goals
- Migrate from shared support host model to dedicated engineer VM model

### Tasks
- Create one VM template for support engineers (Windows 11 Pro preferred)
- Apply hardening baseline:
  - Full-disk encryption where feasible
  - OS patching and endpoint protection
  - Standard support toolset
- Provision per-engineer VMs:
  - `Support-VM-Alice`, `Support-VM-Bob`, etc.
- Integrate access via Guacamole (RDP)
- Document per-VM owner and exception tracking

### Deliverables
- Dedicated support VM for each active engineer
- Decommission plan for any legacy shared support VM
- Engineer onboarding/offboarding checklist

---

## Phase 6 - Customer Connectivity Model (Weeks 7-9)

### Goals
- Establish modern mesh-first connectivity with safe isolation

### Tasks
- Configure Headscale namespaces/users/tags strategy
- Define ACL policy for strict customer isolation:
  - No lateral access between customers
  - Engineer access scoped to assigned cases/customers
- Pilot with one internal test customer lab
- Pilot with 1-2 real customers that accept Tailscale client deployment
- Keep traditional VPN paths available for constrained hospitals:
  - OpenVPN/IPsec/site-to-site/jump-host fallback
- Document customer onboarding workflow:
  - Prerequisites
  - Tailscale install steps
  - `tailscale up --login-server https://mesh.company.com`
  - Validation checks

### Deliverables
- Approved ACL baseline with customer isolation proof
- Pilot results and lessons learned
- Standard customer onboarding pack

---

## Phase 7 - Security, Audit, and Compliance Controls (Weeks 8-10)

### Goals
- Make auditing and control evidence production-ready

### Tasks
- Enable and centralize logs (at minimum export + retention strategy):
  - Keycloak auth events
  - Guacamole session/auth events
  - Headscale access events
  - Host and container logs
- Decide and configure session recording policy for Guacamole where legally/contractually allowed
- Define retention and access policy for logs and recordings
- Conduct access review:
  - Admin roles
  - Service accounts
  - Break-glass account controls
- Validate least-privilege in ACL and VPN profiles
- Run tabletop incident scenarios:
  - Credential compromise
  - Support VM compromise
  - Tunnel outage

### Deliverables
- Audit control matrix
- Logging and retention SOP
- Incident response playbook (v1)

---

## Phase 8 - Backup, Restore, and DR Validation (Week 10)

### Goals
- Prove recoverability under realistic failure conditions

### Tasks
- Implement backup jobs for:
  - Docker volumes
  - Service databases
  - Critical config files
  - Key material and certificates
- Store backups in separate failure domain
- Define backup schedule and integrity checks
- Execute restore drills:
  - Service-level restore (single component)
  - Full infrastructure VM restore
- Measure against RTO/RPO targets

### Deliverables
- Backup architecture document
- Restore test evidence and timings
- Corrective actions for gaps

---

## Phase 9 - Production Readiness and Go-Live (Week 11)

### Goals
- Complete operational handoff and controlled rollout

### Tasks
- Finalize runbooks:
  - Daily operations
  - Patch/upgrade
  - Incident handling
  - Customer onboarding
  - Access revocation
- Conduct engineer training sessions
- Execute go-live checklist
- Start with phased customer migration waves
- Hold hypercare period (2-4 weeks)

### Deliverables
- Signed go-live checklist
- Trained support team
- Hypercare issue log and closeout report

---

## 4. Implementation Workstreams

### 4.1 Platform Engineering
- Docker Compose packaging
- Version pinning and upgrade strategy
- Health checks and service dependencies

### 4.2 Network and Security
- FRP/pfSense routing and firewall rules
- Exposure minimization
- Segmentation and ACL policy

### 4.3 Identity and IAM
- Keycloak realm/role/group model
- MFA and SSO integrations
- User lifecycle automation (future)

### 4.4 Support Operations
- BookStack knowledge structure
- Credential handling procedures
- On-call and escalation runbooks

### 4.5 Compliance and Assurance
- Logging/retention evidence
- Access reviews
- Control testing cadence

---

## 5. Detailed Hardening Checklist

### 5.1 Host and VM Security
- Disable password-based SSH on Linux hosts
- Enforce strong admin credential policy and MFA
- Restrict inbound management access to trusted ranges
- Apply CIS-aligned hardening where practical
- Enable automatic security updates or managed patch cycle

### 5.2 Container and Image Security
- Pin image versions
- Scan images before deployment
- Remove unused containers/images
- Use non-root users where supported
- Keep secrets out of repository

### 5.3 Identity Security
- MFA mandatory
- No shared accounts
- Group-based access (not direct ad-hoc grants)
- Immediate deprovisioning SLA for leavers

### 5.4 Data Security
- Encrypt backups at rest
- Protect key material and recovery codes
- Restrict direct DB access
- Separate documentation from credentials

### 5.5 Network Security
- Public exposure limited to required endpoints only
- Internal service access over VPN/internal DNS only
- Customer isolation by ACL
- Explicit deny rules for cross-customer access

---

## 6. Operations Model

### 6.1 Onboarding Process
- Create user in Keycloak
- Assign support role group
- Provision dedicated support VM
- Grant Guacamole and required customer access
- Add required credentials in Vaultwarden vault collections

### 6.2 Offboarding Process
- Disable user in Keycloak immediately
- Revoke sessions/tokens
- Rotate shared customer-facing credentials where used
- Archive/transfer documentation ownership
- Snapshot then retire engineer VM

### 6.3 Change Management
- Changes tracked in ticket system
- Mandatory peer review for:
  - ACL changes
  - firewall changes
  - privileged role changes
- Maintenance windows for high-risk upgrades

---

## 7. Testing and Validation Plan

### 7.1 Functional Tests
- SSO login flow across all services
- MFA enforcement test
- Guacamole RDP and SSH session test
- Vaultwarden access and vault permissions test
- BookStack role-based access test
- Headscale node enrollment and connectivity test

### 7.2 Security Tests
- External surface scan (only expected ports/services visible)
- Attempted cross-customer access blocked by ACL
- Privilege escalation negative tests
- Credential leakage checks in docs and logs

### 7.3 Resilience Tests
- Container restart and service recovery
- FRP tunnel interruption and recovery
- Backup restore to alternate environment
- Simulated support VM loss and rebuild

---

## 8. Risks and Mitigations

- Single infrastructure VM failure risk
  - Mitigation: strong backup/restore discipline, snapshots, documented rebuild
- FRP/public VPS dependency
  - Mitigation: monitoring, runbook, spare VPS strategy
- SSO integration complexity
  - Mitigation: staged integration and test realm before production cutover
- Customer IT restrictions on mesh clients
  - Mitigation: maintain traditional VPN/jump-host fallback
- Audit/legal concerns around session recording
  - Mitigation: policy gating per customer contract and legal guidance

---

## 9. Timeline Summary (Suggested)

- Week 1: Phase 0
- Weeks 2-3: Phase 1 + 2
- Weeks 4-5: Phase 3 + 4
- Weeks 6-7: Phase 5
- Weeks 7-9: Phase 6
- Weeks 8-10: Phase 7 + 8 (overlap)
- Week 11: Phase 9 go-live
- Weeks 12-14: Hypercare

---

## 10. Deliverables Checklist

- Architecture baseline and trust boundary diagram
- Hardened infrastructure VM with Compose stack
- Identity model + MFA + SSO working
- Dedicated support VMs provisioned
- Headscale ACL policy with customer isolation proof
- Operational runbooks (onboarding/offboarding/incident/change)
- Backup + restore evidence and RTO/RPO report
- Go-live signoff and hypercare report

---

## 11. Immediate Next Actions (This Week)

1. Create repository structure for `support-stack` (compose, env templates, docs, runbooks).
2. Draft initial `docker-compose.yml` with pinned versions and persistent volumes.
3. Draft Keycloak realm/role design and mapping to Guacamole/BookStack/Vaultwarden.
4. Draft Headscale ACL policy skeleton for customer isolation.
5. Build a pilot checklist for one engineer + one test customer.

