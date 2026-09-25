# Secure Remote Support with NetBird

## Why We Recommend Controlled Network Access Instead of Unattended Desktop Access

Remote support requires a careful balance: our engineers need enough access to
maintain your systems, while your organization must retain strong control over
what can be reached, by whom, and for what purpose.

For ongoing managed support, we use NetBird as a secure, policy-controlled
connection between authorized support systems and approved customer services.
This provides a narrower and more auditable access model than permanently
enabled unattended access through tools such as AnyDesk or TeamViewer.

## Executive Summary

With unattended remote-desktop access, possession of the remote-access
credentials can provide control over an entire desktop. Depending on the
configured permissions, this may include:

- Viewing everything displayed on the screen
- Controlling the keyboard and mouse
- Running applications and administrative tools
- Accessing files and clipboard contents
- Using the customer machine to reach other systems on its local network

Our NetBird configuration follows a least-privilege model instead. Access is
limited to explicitly approved systems, protocols, and ports. For example, an
engineer who only needs SSH access to a Linux server can be permitted to reach
TCP port 22 without receiving general desktop access or access to unrelated
services.

```text
Unattended remote desktop

Support engineer --------> Complete customer desktop
                           Applications, files, clipboard,
                           interactive user session and local network


NetBird least-privilege access

Authorized support device == encrypted tunnel ==> Approved customer service
                                                   TCP/22 only, for example
```

## Security Benefits

### 1. Only Approved Services Are Reachable

NetBird policies can restrict access to the exact service required for support:

| Support activity | Example permitted access |
| --- | --- |
| Linux administration | TCP/22 for SSH |
| Windows administration | TCP/3389 for RDP |
| Application support | Only the application's specific TCP port |
| Web administration | TCP/443 or the approved application port |

All other ports remain unavailable through the NetBird policy unless they are
explicitly approved. These ports are not opened to the public internet; they
are reachable only through the authenticated, encrypted private network.

By comparison, unattended remote-desktop access commonly grants broad control
of the operating system after login, even when the original support task
concerns only one service.

### 2. Every Engineer Uses an Individual Identity

Access is tied to named support identities rather than a remote-desktop ID and
password shared among multiple engineers.

- Engineers authenticate through our central identity provider.
- Multi-factor authentication can be enforced centrally.
- Access can be removed immediately when a role changes or an employee leaves.
- Customer access does not depend on distributing a reusable desktop password.

This reduces the risk of password sharing and makes administrative changes
easier to attribute to an individual identity.

### 3. Customer-to-Customer Access Is Denied

Customer systems are placed in a destination-only group. Our access policy is
unidirectional:

```text
Support systems  --->  Customer systems
Customer systems -X->  Support systems
Customer A       -X->  Customer B
Customer B       -X->  Customer A
```

Customer devices cannot initiate connections to support devices or to other
customer devices through NetBird. Return packets belonging to a connection
initiated by an authorized support system are allowed, as required for normal
network communication, but this does not permit a customer system to initiate
a separate connection.

### 4. Customer Resources Are Narrowly Defined

Where access to a machine's normal LAN address is required, we can define only
that individual address as a `/32` resource. This is narrower than exposing an
entire customer subnet.

```text
Approved: 192.168.152.10/32   One specific host
Avoided:  192.168.152.0/24    Every address in the subnet
```

Each resource is assigned to an access policy and is unavailable to peers that
are not included in that policy.

### 5. Traffic Is Encrypted

NetBird uses WireGuard-based encrypted tunnels between peers. When a direct
peer-to-peer connection is not possible and a relay is required, application
traffic remains encrypted through the relay.

The customer does not need to expose SSH, RDP, or application ports directly
to the internet. The customer device establishes its own outbound connection
to the NetBird infrastructure, which avoids traditional public port forwarding
to the supported service.

### 6. Access Can Be Centrally Revoked

Access can be withdrawn without visiting every customer device to change a
shared unattended-access password. Administrators can centrally:

- Remove an engineer or support device from the support group
- Disable or delete a customer peer
- Disable an access policy
- Remove a particular resource or permitted port
- Revoke enrollment credentials

This makes offboarding and incident response faster and more consistent.

### 7. The Control Plane Is Self-Hosted

We operate the NetBird management service within our own controlled
infrastructure. We control peer enrollment, identity integration, policies,
configuration backups, and management access instead of relying solely on a
third-party remote-desktop control plane.

NetBird management records administrative events such as peer enrollment and
changes to groups, policies, setup keys, and system settings. Host and service
logs can provide additional operational evidence where required.

## Comparison with Unattended Remote Desktop

| Security consideration | Controlled NetBird access | Unattended AnyDesk or TeamViewer |
| --- | --- | --- |
| Access scope | Explicit hosts, protocols and ports | Commonly the complete interactive desktop |
| Authentication | Individual organizational identity | Often a device ID and shared unattended password |
| Multi-factor authentication | Centrally enforceable through the identity provider | Product- and configuration-dependent |
| Customer approval per session | Not required for managed support | Not required in unattended mode |
| Public service exposure | Supported ports remain private behind the encrypted overlay | Remote-desktop agent connects to vendor infrastructure |
| Customer-to-customer communication | Denied by one-way policy | Not directly connected, but full desktop control may allow LAN access |
| Revocation | Central user, device, group and policy controls | Password, account, ACL or client configuration changes may be required |
| Least privilege | Can allow one service port only | Remote session commonly has broad operating-system control |
| Control plane | Self-hosted by the support provider | Commonly operated by the remote-desktop vendor |

AnyDesk and TeamViewer provide legitimate security capabilities, including
encryption, access control lists, multi-factor authentication and permission
profiles. The concern is not that these products are inherently insecure. The
important difference is the access model: permanently enabled unattended
desktop control is normally broader than granting access only to a required
network service.

## Operational Safeguards

We combine NetBird with the following controls:

- One-way access from support systems to customer systems
- No default all-to-all policy
- No customer-to-customer policy
- Only required protocols and ports
- Individual engineer identities and multi-factor authentication
- Restricted administrator privileges
- Controlled and expiring enrollment keys
- Prompt removal of retired devices and former personnel
- Regular updates of the NetBird server and clients
- Hardened support workstations with disk encryption and endpoint protection
- Review of peer, policy, group and enrollment-key changes

## What NetBird Does Not Do

NetBird is a secure connectivity layer, not a substitute for normal endpoint
security. The customer system must still be patched and protected, and the
service reached through NetBird must use appropriate operating-system or
application authentication.

For example, permission to reach TCP port 22 does not itself authenticate an
SSH user. The engineer must also possess an approved SSH identity or operating
system credential. This provides an additional security boundary beyond the
NetBird network policy.

## Customer Control and Offboarding

At the end of a support agreement, access can be terminated by removing the
customer peer from NetBird. The customer may also stop or uninstall the
NetBird client locally. Once removed, the device no longer participates in the
support network and the previously assigned private route is unavailable.

## Conclusion

Unattended desktop tools are useful for temporary troubleshooting and can be
retained as a controlled emergency option. For routine managed support,
however, NetBird gives us a more precise security boundary:

> An authenticated support system receives access only to an approved service
> on an approved customer system, through an encrypted tunnel, under a
> centrally managed one-way policy.

This least-privilege design reduces credential sharing, limits the accessible
attack surface, prevents customer-to-customer communication, and provides a
clearer basis for access review and revocation than permanently enabled access
to an entire desktop.

## Further Information

- [NetBird: Understanding groups and access policies](https://docs.netbird.io/manage/access-control)
- [NetBird: How routing peers and resource policies work](https://docs.netbird.io/manage/networks/how-routing-peers-work)
- [NetBird: Audit events](https://docs.netbird.io/manage/activity)
- [NetBird: Open-source security policy and advisories](https://github.com/netbirdio/netbird/security)
- [WireGuard protocol and cryptography](https://www.wireguard.com/protocol/)
- [AnyDesk: Interactive access, unattended access and permission settings](https://support.anydesk.com/settings)
- [TeamViewer: Security statement and unattended-access controls](https://www.teamviewer.com/en/global/support/knowledge-base/teamviewer-remote/security/security-statement/)
