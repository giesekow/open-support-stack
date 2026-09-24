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
