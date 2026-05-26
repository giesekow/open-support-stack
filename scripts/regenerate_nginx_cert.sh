#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

HOSTNAMES_FILE="hostnames.txt"
ENV_FILE="${1:-.env}"
CERT_DIR="nginx/certs"
CA_KEY="$CERT_DIR/support-stack-ca.key"
CA_CRT="$CERT_DIR/support-stack-ca.crt"
LEAF_KEY="$CERT_DIR/support-stack.key"
LEAF_CRT="$CERT_DIR/support-stack.crt"
TMP_CNF="$(mktemp)"
TMP_CSR="$(mktemp)"
trap 'rm -f "$TMP_CNF" "$TMP_CSR"' EXIT

if [[ ! -f "$CA_KEY" || ! -f "$CA_CRT" ]]; then
  echo "[ERROR] Missing CA files in $CERT_DIR (support-stack-ca.key/.crt)"
  exit 1
fi

env_get() {
  local key="$1"
  local def="$2"
  local val
  if [[ -f "$ENV_FILE" ]]; then
    val="$(grep -E "^${key}=" "$ENV_FILE" | head -n1 | cut -d= -f2- || true)"
  else
    val=""
  fi
  if [[ -z "$val" ]]; then
    printf '%s' "$def"
  else
    printf '%s' "$val"
  fi
}

BASE_DOMAIN="$(env_get BASE_DOMAIN "example.com")"
SUPPORT_HOST="$(env_get SUPPORT_HOST "support.${BASE_DOMAIN}")"
SSO_HOST="$(env_get SSO_HOST "sso.${BASE_DOMAIN}")"
VAULT_HOST="$(env_get VAULT_HOST "vault.${BASE_DOMAIN}")"
DOCS_HOST="$(env_get DOCS_HOST "docs.${BASE_DOMAIN}")"
REMOTE_HOST="$(env_get REMOTE_HOST "remote.${BASE_DOMAIN}")"
MESH_HOST="$(env_get MESH_HOST "mesh.${BASE_DOMAIN}")"
MESH_WEB_HOST="$(env_get MESH_WEB_HOST "mesh-web.${BASE_DOMAIN}")"
TICKETS_HOST="$(env_get TICKETS_HOST "tickets.${BASE_DOMAIN}")"
CRM_HOST="$(env_get CRM_HOST "crm.${BASE_DOMAIN}")"
HR_HOST="$(env_get HR_HOST "hr.${BASE_DOMAIN}")"
ERP_HOST="$(env_get ERP_HOST "erp.${BASE_DOMAIN}")"
FILES_HOST="$(env_get FILES_HOST "files.${BASE_DOMAIN}")"
PENPOT_HOST="$(env_get PENPOT_HOST "penpot.${BASE_DOMAIN}")"
STATUS_HOST="$(env_get STATUS_HOST "status.${BASE_DOMAIN}")"

DNS_NAMES=(
  "$SUPPORT_HOST"
  "$SSO_HOST"
  "$VAULT_HOST"
  "$DOCS_HOST"
  "$REMOTE_HOST"
  "$MESH_HOST"
  "$MESH_WEB_HOST"
  "$TICKETS_HOST"
  "$CRM_HOST"
  "$HR_HOST"
  "$ERP_HOST"
  "$FILES_HOST"
  "$PENPOT_HOST"
  "$STATUS_HOST"
)

# Fallback: if env file is missing, try hostnames.txt
if [[ ! -f "$ENV_FILE" ]]; then
  if [[ ! -f "$HOSTNAMES_FILE" ]]; then
    echo "[ERROR] Missing both $ENV_FILE and $HOSTNAMES_FILE"
    exit 1
  fi
  mapfile -t DNS_NAMES < <(
    tr ' ' '\n' < "$HOSTNAMES_FILE" \
      | sed '/^\s*$/d' \
      | grep -E '^[a-zA-Z0-9.-]+$' \
      | grep -vE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'
  )
fi

if [[ ${#DNS_NAMES[@]} -eq 0 ]]; then
  echo "[ERROR] No hostname entries found."
  exit 1
fi

# Always include base domain even if not listed as a standalone line.
if ! printf '%s\n' "${DNS_NAMES[@]}" | grep -qx "$SUPPORT_HOST"; then
  DNS_NAMES=("$SUPPORT_HOST" "${DNS_NAMES[@]}")
fi

{
  echo "[ req ]"
  echo "default_bits       = 4096"
  echo "prompt             = no"
  echo "default_md         = sha256"
  echo "distinguished_name = dn"
  echo "req_extensions     = req_ext"
  echo
  echo "[ dn ]"
  echo "CN = $SUPPORT_HOST"
  echo
  echo "[ req_ext ]"
  echo "subjectAltName = @alt_names"
  echo
  echo "[ alt_names ]"
  idx=1
  for dns in "${DNS_NAMES[@]}"; do
    echo "DNS.$idx = $dns"
    idx=$((idx + 1))
  done
} > "$TMP_CNF"

openssl genrsa -out "$LEAF_KEY" 4096 >/dev/null 2>&1
openssl req -new -key "$LEAF_KEY" -out "$TMP_CSR" -config "$TMP_CNF" >/dev/null 2>&1
openssl x509 -req -in "$TMP_CSR" -CA "$CA_CRT" -CAkey "$CA_KEY" -CAcreateserial \
  -out "$LEAF_CRT" -days 825 -sha256 -extensions req_ext -extfile "$TMP_CNF" >/dev/null 2>&1

chmod 600 "$LEAF_KEY"
chmod 644 "$LEAF_CRT"

echo "Regenerated cert: $LEAF_CRT"
openssl x509 -in "$LEAF_CRT" -noout -text | sed -n '/Subject:/p;/Subject Alternative Name/,+1p'

echo
if docker compose ps nginx >/dev/null 2>&1; then
  docker compose exec -T nginx nginx -t >/dev/null
  docker compose exec -T nginx nginx -s reload >/dev/null
  echo "Nginx reloaded with updated certificate."
fi
