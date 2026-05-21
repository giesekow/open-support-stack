#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

DOMAIN="${1:-example.com}"

if ! command -v openssl >/dev/null 2>&1; then
  echo "[FAIL] openssl is required but not installed."
  exit 1
fi

echo "==> Checking active cert for: ${DOMAIN}"

cert_text="$(
  docker compose exec -T nginx sh -lc \
    "echo | openssl s_client -servername '${DOMAIN}' -connect 127.0.0.1:443 2>/dev/null | openssl x509 -noout -subject -issuer -enddate -fingerprint -sha256" \
    || true
)"

if [[ -z "$cert_text" ]]; then
  echo "[FAIL] Could not read active certificate from nginx."
  exit 1
fi

echo "$cert_text"

if grep -qi "support-stack-ca" <<<"$cert_text"; then
  echo
  echo "[INFO] Active cert appears to be local/self-signed (support-stack-ca)."
else
  echo
  echo "[INFO] Active cert appears to be externally issued (likely Let's Encrypt or trusted CA)."
fi

