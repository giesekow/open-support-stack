# Bonescreen GmbH support network configuration with netbird

## Ubuntu (Debian)

### Install
```bash
curl -fsSL https://pkgs.netbird.io/install.sh | sh
```

### Configure and start-service
execute the two commands below to configure and start the service

```bash
netbird up --management-url https://mesh.internal-support.bonescreen.de --setup-key SETUP_KEY --allow-server-ssh --enable-ssh-root
```
Where `SETUP_KEY` is the provided installation token and
```bash
netbird service reconfigure --service-env NB_ENABLE_LOCAL_FORWARDING=true
```

## Windows

### Install
Download and install the client from [https://pkgs.netbird.io/windows/x64](https://pkgs.netbird.io/windows/x64)

### Configuration and start-service
1. On first launch, NetBird asks where to connect. Select `Self-hosted` and enter the following `Management server URL`
```
https://mesh.internal-support.bonescreen.de
```

Already past that screen? Click the NetBird icon in your system tray, open `Settings` and set `Management Server` to `Self-hosted` under `General`.

2. Open Command-line or powershell as administrator (run as administrator) and execute the two commands below:
```bash
netbird up --allow-server-ssh --management-url https://mesh.internal-support.bonescreen.de --setup-key SETUP_KEY
```
Where `SETUP_KEY` is the provided installation token and

```bash
netbird service reconfigure --service-env NB_ENABLE_LOCAL_FORWARDING=true
```

## Firewall configuration

NetBird clients initiate their connections outbound. Do not create an inbound
firewall rule or router port-forward for UDP/3478 on the customer network.

### Recommended outbound access

Allow the following traffic from the NetBird client:

| Destination | Protocol/port | Requirement | Purpose |
| --- | --- | --- | --- |
| `mesh.internal-support.bonescreen.de` | TCP/443 | Required | Management, signalling, authentication and encrypted WebSocket relay fallback |
| `mesh.internal-support.bonescreen.de` | UDP/3478 | Recommended | STUN discovery and NAT traversal for direct peer connections |

The firewall must allow response traffic for these outbound connections. If the
customer uses a restrictive outbound policy, allowing outbound UDP to dynamic
peer endpoints is also recommended for direct WireGuard peer-to-peer traffic.
The destination port of another peer can be dynamically assigned by NAT and is
not necessarily UDP/51820. When direct peer traffic is blocked, NetBird uses the
relay where possible.

### If STUN is blocked or disabled

If outbound UDP/3478 is blocked, the client cannot use the STUN service for NAT
discovery and direct peer-to-peer hole punching may fail. The client should
remain connected to Management and Signal over TCP/443 and fall back to the
encrypted NetBird relay over WebSocket on TCP/443.

Relay fallback normally keeps approved services reachable, but it has the
following effects:

- traffic is routed through the NetBird relay instead of directly between peers;
- latency may increase and available bandwidth may decrease;
- the NetBird server carries the relayed traffic; and
- peer connectivity fails if both STUN/direct connectivity and the TCP/443 relay
  are unavailable.

Check connectivity after installation:

```text
netbird status -d
```

The preferred result is:

```text
[stun:mesh.internal-support.bonescreen.de:3478] is Available
[rels://mesh.internal-support.bonescreen.de:443] is Available via ws
```

If STUN is blocked but relay fallback is working, the first entry reports
`Unavailable` while the `rels://` entry remains `Available via ws`.
