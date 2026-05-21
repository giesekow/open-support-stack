You have now converged on a very solid and professional remote support architecture suitable for:

hospitals
PACS/DICOM environments
regulated customers
multi-engineer support teams
centralized support operations

The design balances:

security
operational simplicity
scalability
auditability
customer flexibility

while avoiding many common problems of shared VPN environments and ad-hoc remote support tooling.

Overall Architectural Goals

The infrastructure is intended to provide:

centralized remote support operations
isolated support engineer workspaces
centralized credential management
centralized documentation
browser-based access to support infrastructure
secure connectivity into customer environments
reduced dependence on TeamViewer/AnyDesk where possible
compatibility with hospitals and enterprise IT policies
Core Architectural Decisions
1. One Support VM per Engineer

Instead of a single shared multi-user Linux VM, each support engineer will receive their own dedicated support VM.

Reasons
avoids VPN route conflicts
avoids DNS conflicts
avoids engineers affecting each other
improves security isolation
improves troubleshooting
simplifies auditing
allows snapshots and rollback
allows customer-specific tooling if needed
Example
ESXi
 ├── Support-VM-Alice
 ├── Support-VM-Bob
 ├── Support-VM-Charlie
Recommended VM OS

Preferred:

Windows 11 Pro

Alternative:

Ubuntu XFCE

Windows is preferred because many enterprise VPN clients have better compatibility and support on Windows.

2. Centralized Shared Infrastructure VM

A dedicated infrastructure VM will host the shared support platform components using Docker Compose.

Components
Keycloak
Vaultwarden
BookStack
Guacamole
Headscale
Purpose of each component
Component	Purpose
Keycloak	centralized identity management and MFA
Vaultwarden	centralized credential/password vault
BookStack	internal support documentation/wiki
Guacamole	browser-based remote access gateway
Headscale	self-hosted mesh VPN control plane
3. Infrastructure VM Deployment Model

All core infrastructure services will initially run on a single Ubuntu Server 24.04 VM using Docker Compose.

Recommended VM size

Minimum:

4 vCPU
16 GB RAM
200 GB SSD

Preferred:

8 vCPU
32 GB RAM
300–500 GB SSD
Recommended OS
Ubuntu Server 24.04 LTS
4. Docker-Based Deployment

All services will run as isolated Docker containers.

Benefits
easier backup
easier migration
service isolation
easier upgrades
reproducible infrastructure
future scalability
Recommended storage layout
/opt/support-stack/
├── docker-compose.yml
├── keycloak-db/
├── vaultwarden-data/
├── bookstack-db/
├── bookstack-uploads/
├── guacamole-db/
├── headscale-data/
5. Identity and Authentication
Keycloak will provide:
centralized authentication
MFA
user lifecycle management
SSO integration
Integrated services
Guacamole
BookStack
Vaultwarden (OIDC/SSO)
Important note

Vaultwarden still requires a master password even when using Keycloak SSO because encryption keys remain user-controlled.

6. Credential Management
Vaultwarden will be used for:
VPN credentials
RDP credentials
SSH keys
TeamViewer/AnyDesk credentials
MFA secrets
customer portals
firewall credentials
Important rule

Passwords will NOT be stored in BookStack.

7. Documentation System
BookStack will store:
customer procedures
support notes
topology diagrams
VPN instructions
escalation procedures
PACS/DICOM notes
infrastructure documentation
BookStack chosen over Confluence because:
simpler
lighter
easier self-hosting
lower maintenance
excellent for support operations
8. Browser-Based Access Gateway
Apache Guacamole will provide:
browser-based RDP
browser-based SSH
browser-based VNC
centralized access portal
Benefits
engineers only need a browser
no local RDP clients required
centralized auditing
easier onboarding/offboarding
easier remote work
potential session recording
Example access flow
Engineer Browser
      ↓
Guacamole
      ↓
Support VM
9. Customer Connectivity Strategy

The primary long-term remote connectivity strategy will use:

Headscale + Tailscale clients

instead of relying entirely on:

TeamViewer
AnyDesk
OpenVPN client installs
Reasons
easier onboarding
persistent private networking
full network access
RDP/SSH/Web access
lower operational overhead
more professional enterprise architecture
10. Why Headscale Was Chosen Over Self-Hosted ZeroTier
Headscale/Tailscale chosen because:
simpler operations
WireGuard-based
easier ACL model
easier debugging
cleaner integration with modern infrastructure
easier customer onboarding
better fit for support operations
ZeroTier advantages acknowledged

ZeroTier may still be useful for:

Layer 2 requirements
legacy network protocols
unusual medical device scenarios

But Headscale/Tailscale was considered a better operational fit overall.

11. Customer Connectivity Model
Recommended customer onboarding flow

Customer installs:

Tailscale client

Configured to use:

self-hosted Headscale server
Example
tailscale up --login-server https://mesh.company.com
12. Customer Isolation Strategy

Customers will NOT share one flat mesh network.

Instead:
Hospital-A isolated ACLs
Hospital-B isolated ACLs
Hospital-C isolated ACLs
Benefits
security isolation
compliance posture
reduced lateral access risk
easier auditing
13. Customer Access Flow
Preferred support flow
Engineer Browser
      ↓
Guacamole
      ↓
Dedicated Support VM
      ↓
Headscale/Tailscale
      ↓
Customer Environment
14. Traditional VPN Still Supported

Some hospitals may still require:

site-to-site VPN
pfSense VPN
OpenVPN
IPsec

The architecture remains compatible with:

traditional VPN access
jump hosts
customer firewall policies
15. Existing Public VPS + FRP Infrastructure

Current setup:

cloud VPS with public IP
frps on VPS
frpc inside office network
pfSense behind ESXi

Currently forwarding:

OpenVPN port 1194
16. Public Exposure Strategy
Only Headscale will be publicly exposed

Everything else remains:

VPN-only
office-network-only
internal-only
Publicly exposed
mesh.company.com
Internal only
Vaultwarden
BookStack
Guacamole
Keycloak admin
Support VMs
17. Recommended Public Routing
Cloud VPS
443/TCP → Headscale
1194 → pfSense OpenVPN
Through FRP tunnel
Public VPS
    ↓
frps
    ↓
frpc
    ↓
Office Infrastructure
18. Why Port 443 Was Chosen

Headscale can technically use any TCP port.

However:

hospitals often restrict outbound traffic
custom ports frequently fail
443 works reliably almost everywhere

Therefore:

Headscale should use HTTPS on 443
19. Recommended DNS Layout
Public
mesh.company.com
Internal/VPN only
vault.company.internal
docs.company.internal
remote.company.internal
sso.company.internal
20. Security Recommendations
Strongly recommended
MFA everywhere
Keycloak SSO
ACLs
customer isolation
VPN-only internal services
backups
snapshots
audit logging
session recording if possible
least privilege access
no shared engineer accounts
21. Recommended Final Architecture
────────────────────────────
Cloud VPS (Public)
────────────────────────────
├── frps
├── 443 → Headscale
└── 1194 → pfSense VPN

            ↓

────────────────────────────
Office Network / ESXi
────────────────────────────

├── pfSense VM
│
├── Infrastructure VM
│    ├── Keycloak
│    ├── Vaultwarden
│    ├── BookStack
│    ├── Guacamole
│    └── Headscale
│
├── Support-VM-Alice
├── Support-VM-Bob
├── Support-VM-Charlie
│
└── Optional:
     ├── Site-to-site VPNs
     ├── Customer jump hosts
     └── Traditional VPN access
Final Strategic Outcome

The resulting architecture provides:

enterprise-grade remote support
centralized operations
secure customer connectivity
hospital-friendly security posture
isolated engineer environments
scalable growth path
strong auditing capability
reduced operational friction
reduced dependency on TeamViewer-style tooling

while remaining:

practical
maintainable
Docker-friendly
compatible with your existing ESXi/pfSense infrastructure.