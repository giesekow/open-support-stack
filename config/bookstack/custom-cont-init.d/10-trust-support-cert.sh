#!/usr/bin/with-contenv bash
set -e

if [ -f /custom-certs/support-stack-ca.crt ]; then
  cp /custom-certs/support-stack-ca.crt /usr/local/share/ca-certificates/support-stack-ca.crt
fi

# If nginx uses a self-signed leaf cert, trust it explicitly for OIDC discovery.
if [ -f /custom-certs/support-stack.crt ]; then
  cp /custom-certs/support-stack.crt /usr/local/share/ca-certificates/support-stack.crt
fi

update-ca-certificates >/dev/null 2>&1 || true
