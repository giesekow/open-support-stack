# NetBird Proxy and SSH Runbook

This runbook records the production proxy failures diagnosed in September 2026
and the expected behavior of NetBird SSH. It applies when pfSense HAProxy
terminates TLS and forwards traffic to this stack's HTTP-mode nginx service.

## Required Network Paths

- TCP 443: clients to pfSense HAProxy.
- UDP 3478: public NAT directly to the Docker host for NetBird STUN.
- HAProxy to nginx TCP 80: HTTP/1.1 for the dashboard, API, OAuth2, and relay;
  cleartext HTTP/2 (h2c) for native gRPC.

Do not send UDP 3478 through HAProxy. WebSocket relay fallback is sufficient
when relay QUIC is unavailable, but the `/relay` WebSocket route must work.

## HAProxy Frontend

The TLS frontend must negotiate both protocols:

```haproxy
bind 10.1.128.9:443 ssl crt-list /var/etc/haproxy/https_frontend.crt_list alpn h2,http/1.1
mode http
option http-keep-alive
option forwardfor
timeout client 86400000
```

The one-day client timeout is required for long-lived gRPC streams. A 30-second
timeout caused Signal and Management streams to disconnect repeatedly.

Verify public ALPN negotiation:

```bash
echo | openssl s_client \
  -connect mesh.example.com:443 \
  -servername mesh.example.com \
  -alpn h2,http/1.1 2>/dev/null | grep -i 'ALPN protocol'
```

Expected: `ALPN protocol: h2`. Repeat with `-alpn http/1.1` and expect
`ALPN protocol: http/1.1`.

## HAProxy Routing

Route the native gRPC paths to a backend forced to h2c:

```haproxy
acl netbird-exchange var(txn.txnpath) -m beg -i /signalexchange.SignalExchange/
acl netbird-management var(txn.txnpath) -m beg -i /management.ManagementService/
acl netbird-proxy var(txn.txnpath) -m beg -i /management.ProxyService/

use_backend NetbirdgRPC_ipvANY if netbird-exchange aclcrt_https_frontend
use_backend NetbirdgRPC_ipvANY if netbird-management aclcrt_https_frontend
use_backend NetbirdgRPC_ipvANY if netbird-proxy aclcrt_https_frontend

backend NetbirdgRPC_ipvANY
    mode http
    timeout connect 30000
    timeout server 86400000
    server NetbirdgRPC 10.1.128.6:80 check inter 5000 proto h2
```

Use a TCP health check for the gRPC backend. An HTTP/1.1 health check does not
validate h2c and can incorrectly mark the backend down.

The normal HTTP backend needs a long tunnel timeout for relay WebSockets:

```haproxy
backend support_stack_backend_ipvANY
    mode http
    timeout connect 30000
    timeout server 3600000
    timeout tunnel 1d
    server support_stack_vm 10.1.128.6:80 check inter 5000
```

## Host Header With Explicit Port

NetBird constructs its relay URL from `rels://host:443`, so the WebSocket
request can contain this header:

```http
Host: mesh.example.com:443
```

An ACL that only checks whether the value ends with `example.com` will not
match because the value ends with `:443`. If no backend matches, HAProxy
returns `503` before the request reaches nginx.

Use an ACL that accepts an optional port:

```haproxy
acl internal-support-regex var(txn.txnhost) -m reg -i ^([^.]+\.)*example\.com(:[0-9]{1,5})?$
```

In pfSense, use `Custom acl` with the expression after the ACL name. If the
package provides `Host matches regex`, enter only the regular expression.

Regression test both Host forms:

```bash
curl -skv --http1.1 --max-time 5 \
  -H 'Host: mesh.example.com:443' \
  -H 'Connection: Upgrade' \
  -H 'Upgrade: websocket' \
  -H 'Sec-WebSocket-Version: 13' \
  -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' \
  https://mesh.example.com/relay
```

Expected: `HTTP/1.1 101 Switching Protocols`. A curl timeout after the `101`
is normal because the upgraded WebSocket remains open.

## nginx h2c Listener

In HTTP mode, many name-based virtual hosts share port 80. nginx must detect
the cleartext HTTP/2 preface before it can inspect the HTTP/2 `:authority`
value. Therefore both the NetBird virtual host and the shared default server
enable `http2 on;` in `nginx/templates/support-stack.http.conf.template`.

Verify the internal listener from a trusted LAN host:

```bash
curl -sv --http2-prior-knowledge \
  -H 'Host: mesh.example.com' \
  http://10.1.128.6/ -o /dev/null
```

Expected: `HTTP/2 200`. `Remote peer returned unexpected data while we
expected SETTINGS frame` means the listener is still responding with HTTP/1.x
instead of h2c.

## Diagnostic Interpretation

- `STUN ... unavailable`: verify UDP 3478 NAT directly to the Docker host.
- Relay WebSocket `503` with no nginx `/relay` access entry: HAProxy rejected
  the request or had no matching/available backend.
- `400 text/html` from a gRPC client: the request entered an HTTP/1.x path or a
  proxy mishandled the native gRPC stream.
- `server closed the stream` at a fixed interval: compare that interval with
  HAProxy `timeout client` and `timeout server`.
- `101 Switching Protocols`: WebSocket upgrade succeeded.
- `grpc-status` on an HTTP/2 response: the request reached the gRPC service;
  a nonzero status can be expected for an intentionally empty probe.

Useful production checks:

```bash
docker exec support-nginx nginx -t
docker logs --since 10m support-nginx
docker logs --since 10m support-netbird-server
netbird status -d
```

## Reach a Windows Routing Peer's LAN IP

Use a NetBird Network resource when support engineers must reach a service on
a customer's normal LAN address instead of the peer's `100.x` NetBird address.
For one host, create a `/32` resource rather than exposing the full subnet.

Example:

```text
Customer Windows Server LAN IP: 10.250.20.110
Network resource:               10.250.20.110/32
Required service:               RDP on TCP/3389
```

### Management Configuration

1. Open **Network Routing -> Networks** and create or select the customer's
   Network.
2. Add a resource with address `10.250.20.110/32`.
3. Assign the resource to the customer destination group, such as
   `Customer-Group`.
4. Add the Windows Server peer as a routing peer for that Network. Leave
   masquerading enabled unless the customer LAN has an explicit return route
   for the NetBird address range.
5. Add or verify a one-way policy from `Support-Group` to the resource group,
   restricted to the required protocol and port, such as TCP/3389.
6. Add or verify a one-way peer policy from `Support-Group` to the group that
   contains the Windows routing peer on the same port. Reaching a service on
   the routing peer itself requires both the resource route and permission to
   the peer's input path.

The same `Support-Group -> Customer-Group` policy can cover both paths when
the Windows peer and its `/32` resource are both members of
`Customer-Group`. Keep the policy unidirectional and disable the default
`All -> All` policy to preserve customer-to-customer isolation.

### Enable Windows Local Forwarding

Windows NetBird peers use the userspace router. To deliver routed traffic to a
service on the routing peer's own LAN address, run the following in an
elevated PowerShell window on the customer Windows Server:

```powershell
netbird service reconfigure --service-env NB_ENABLE_LOCAL_FORWARDING=true
Restart-Service NetBird
Start-Sleep -Seconds 5
netbird status -d
```

This setting is not required when connecting directly to the server's
`100.x` NetBird address. It is required for this Windows self-access path:

```text
Support peer -> NetBird tunnel -> Windows routing peer -> its own LAN IP
```

Confirm that the resource address belongs to the Windows Server:

```powershell
Get-NetIPAddress -AddressFamily IPv4 |
  Where-Object IPAddress -eq "10.250.20.110"
```

The service must listen on that LAN address or on `0.0.0.0`, and Windows
Firewall must permit the selected service port.

To remove local forwarding later:

```powershell
netbird service reconfigure --service-env NB_ENABLE_LOCAL_FORWARDING=false
Restart-Service NetBird
```

### Verify the Support Client Route

On the Windows support machine, use an elevated PowerShell window:

```powershell
netbird networks ls

Get-NetRoute -DestinationPrefix "10.250.20.110/32" `
  -ErrorAction SilentlyContinue |
  Format-Table -AutoSize
```

The Network must be `Selected`, and the `/32` route must use the NetBird
`wt0` interface. If the route is missing after removing a previous manual
route, reselect the Network and restart NetBird:

```powershell
netbird networks deselect <network-id>
Start-Sleep -Seconds 2
netbird networks select <network-id>
Restart-Service NetBird
Start-Sleep -Seconds 5
```

Do not add a permanent Windows route manually. NetBird should install and
remove the route according to the Network selection and access policy.

Test the approved service:

```powershell
Test-NetConnection 10.250.20.110 -Port 3389
```

Expected:

```text
InterfaceAlias   : wt0
TcpTestSucceeded : True
```

If the peer's `100.x` address works but its LAN `/32` address does not, check
these items in order:

1. The Network is selected and the `/32` route exists on the support peer.
2. The `/32` resource has a support-to-resource policy for the service port.
3. The routing peer has a support-to-peer policy for the service port.
4. `NB_ENABLE_LOCAL_FORWARDING=true` is active on a Windows routing peer.
5. The service bind address and Windows Firewall allow the LAN-IP connection.

## TCP Port 22 Versus NetBird SSH

These policy types have different authentication models.

### TCP Policy, Port 22

A TCP policy for port 22 permits ordinary network traffic to Ubuntu's OpenSSH
daemon. Connect with `ssh`, then authenticate using the host's configured SSH
method, such as an OS password or public key.

### NetBird SSH Policy

A `NetBird SSH` policy uses the NetBird peer's embedded SSH server. Port 22 is
intercepted and internally forwarded to the NetBird SSH endpoint on port
22022. Authentication defaults to an OIDC/JWT user identity; it does not
validate the Ubuntu account password.

Configure the policy's Authorized Groups so the signed-in NetBird user group
is permitted to access the exact local Ubuntu username. Then connect with:

```bash
netbird ssh localuser@100.x.y.z
```

The client should initiate OIDC authentication when required. If native
`ssh localuser@100.x.y.z` merely prompts for an OS password, first test with
`netbird ssh`; the native OpenSSH integration/configuration may not be active.

On the target, NetBird SSH must be enabled:

```bash
sudo netbird down
sudo netbird up --allow-server-ssh
```

For reduced repeated OIDC prompts, the client may cache the JWT temporarily:

```bash
netbird up --ssh-jwt-cache-ttl 3600
```

For automation without user JWT authentication, NetBird supports
`--disable-ssh-auth`, but this changes authorization to machine identity and
removes the per-user identity/audit benefit. Prefer JWT authentication for
interactive support access.

Do not expect the same password behavior from both policy types. Keep a TCP/22
policy when native OpenSSH password/key authentication is desired; use a
NetBird SSH policy when centralized OIDC identity and local-user mappings are
desired.
