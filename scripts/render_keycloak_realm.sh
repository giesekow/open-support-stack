#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="${1:-.env}"
TPL="config/keycloak/realm-support.template.json"
OUT="config/keycloak/realm-support.json"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "[FAIL] Missing env file: $ENV_FILE"
  exit 1
fi
if [[ ! -f "$TPL" ]]; then
  echo "[FAIL] Missing template: $TPL"
  exit 1
fi

if ! command -v sed >/dev/null 2>&1; then
  echo "[FAIL] sed is required but not installed"
  exit 1
fi

env_get() {
  local key="$1"
  local def="$2"
  local val
  val="$(
    awk -F= -v k="$key" '$1==k {sub(/^[^=]*=/, "", $0); print; exit}' "$ENV_FILE" \
      | tr -d '\r'
  )"
  if [[ -z "${val}" ]]; then
    printf '%s' "$def"
  else
    printf '%s' "$val"
  fi
}

escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'
}

escape_json_sed_replacement() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/[|&]/\\&/g'
}

strip_wrapping_quotes() {
  local value="$1"
  if [[ "$value" == \"*\" && "$value" == *\" ]]; then
    value="${value:1:${#value}-2}"
  elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
    value="${value:1:${#value}-2}"
  fi
  printf '%s' "$value"
}

BASE_DOMAIN="$(env_get BASE_DOMAIN "example.com")"
KEYCLOAK_REALM="$(env_get KEYCLOAK_REALM "support")"
SUPPORT_HOST="$(env_get SUPPORT_HOST "support.${BASE_DOMAIN}")"
SSO_HOST="$(env_get SSO_HOST "sso.${BASE_DOMAIN}")"
VAULT_HOST="$(env_get VAULT_HOST "vault.${BASE_DOMAIN}")"
DOCS_HOST="$(env_get DOCS_HOST "docs.${BASE_DOMAIN}")"
REMOTE_HOST="$(env_get REMOTE_HOST "remote.${BASE_DOMAIN}")"
NETBIRD_HOST="$(env_get NETBIRD_HOST "mesh.${BASE_DOMAIN}")"
NETBIRD_OIDC_REDIRECT_URI="$(env_get NETBIRD_OIDC_REDIRECT_URI "")"
TICKETS_HOST="$(env_get TICKETS_HOST "tickets.${BASE_DOMAIN}")"
CRM_HOST="$(env_get CRM_HOST "crm.${BASE_DOMAIN}")"
HR_HOST="$(env_get HR_HOST "hr.${BASE_DOMAIN}")"
ERP_HOST="$(env_get ERP_HOST "erp.${BASE_DOMAIN}")"
FILES_HOST="$(env_get FILES_HOST "files.${BASE_DOMAIN}")"
PENPOT_HOST="$(env_get PENPOT_HOST "penpot.${BASE_DOMAIN}")"
GUACAMOLE_OPENID_CLIENT_SECRET="$(env_get GUACAMOLE_OPENID_CLIENT_SECRET "replace-with-guacamole-oidc-client-secret")"
BOOKSTACK_OIDC_CLIENT_SECRET="$(env_get BOOKSTACK_OIDC_CLIENT_SECRET "replace-with-bookstack-oidc-client-secret")"
VAULTWARDEN_PROXY_OIDC_CLIENT_SECRET="$(env_get VAULTWARDEN_PROXY_OIDC_CLIENT_SECRET "replace-with-vaultwarden-proxy-oidc-client-secret")"
SUPPORT_PORTAL_OIDC_CLIENT_SECRET="$(env_get SUPPORT_PORTAL_OIDC_CLIENT_SECRET "replace-with-support-portal-client-secret")"
OSTICKET_OIDC_CLIENT_SECRET="$(env_get OSTICKET_OIDC_CLIENT_SECRET "replace-with-osticket-oidc-client-secret")"
ESPOCRM_OIDC_CLIENT_SECRET="$(env_get ESPOCRM_OIDC_CLIENT_SECRET "replace-with-espocrm-oidc-client-secret")"
ERPNEXT_OIDC_CLIENT_SECRET="$(env_get ERPNEXT_OIDC_CLIENT_SECRET "replace-with-erpnext-oidc-client-secret")"
SEAFILE_OIDC_CLIENT_SECRET="$(env_get SEAFILE_OIDC_CLIENT_SECRET "replace-with-seafile-oidc-client-secret")"
PENPOT_OIDC_CLIENT_SECRET="$(env_get PENPOT_OIDC_CLIENT_SECRET "replace-with-penpot-oidc-client-secret")"
NETBIRD_OIDC_CLIENT_SECRET="$(env_get NETBIRD_OIDC_CLIENT_SECRET "replace-with-netbird-oidc-client-secret")"
PROVISIONING_KEYCLOAK_CLIENT_SECRET="$(env_get PROVISIONING_KEYCLOAK_CLIENT_SECRET "replace-with-random-provisioning-client-secret")"
SMTP_HOST="$(strip_wrapping_quotes "$(env_get SMTP_HOST "mailpit")")"
SMTP_PORT="$(strip_wrapping_quotes "$(env_get SMTP_PORT "1025")")"
SMTP_SECURITY="$(strip_wrapping_quotes "$(env_get SMTP_SECURITY "off")")"
SMTP_FROM="$(strip_wrapping_quotes "$(env_get SMTP_FROM "no-reply@${BASE_DOMAIN}")")"
SMTP_FROM_NAME="$(strip_wrapping_quotes "$(env_get SMTP_FROM_NAME "Support Stack")")"
SMTP_USER="$(strip_wrapping_quotes "$(env_get SMTP_USER "")")"
SMTP_PASS="$(strip_wrapping_quotes "$(env_get SMTP_PASS "")")"

SMTP_AUTH=false
[[ -n "$SMTP_USER" ]] && SMTP_AUTH=true
SMTP_STARTTLS=false
SMTP_SSL=false
case "$SMTP_SECURITY" in
  off) ;;
  starttls) SMTP_STARTTLS=true ;;
  force_tls) SMTP_SSL=true ;;
  *)
    echo "[FAIL] SMTP_SECURITY must be one of: off, starttls, force_tls"
    exit 1
    ;;
esac

if [[ -z "$NETBIRD_OIDC_REDIRECT_URI" || "$NETBIRD_OIDC_REDIRECT_URI" != https://* || "$NETBIRD_OIDC_REDIRECT_URI" == *"*"* || "$NETBIRD_OIDC_REDIRECT_URI" == *"replace-with"* ]]; then
  echo "[FAIL] NETBIRD_OIDC_REDIRECT_URI must be the exact HTTPS callback shown by NetBird"
  exit 1
fi

KEYCLOAK_REALM_ESCAPED="$(escape_sed_replacement "$KEYCLOAK_REALM")"
SUPPORT_HOST_ESCAPED="$(escape_sed_replacement "$SUPPORT_HOST")"
SSO_HOST_ESCAPED="$(escape_sed_replacement "$SSO_HOST")"
VAULT_HOST_ESCAPED="$(escape_sed_replacement "$VAULT_HOST")"
DOCS_HOST_ESCAPED="$(escape_sed_replacement "$DOCS_HOST")"
REMOTE_HOST_ESCAPED="$(escape_sed_replacement "$REMOTE_HOST")"
NETBIRD_HOST_ESCAPED="$(escape_sed_replacement "$NETBIRD_HOST")"
NETBIRD_OIDC_REDIRECT_URI_ESCAPED="$(escape_sed_replacement "$NETBIRD_OIDC_REDIRECT_URI")"
TICKETS_HOST_ESCAPED="$(escape_sed_replacement "$TICKETS_HOST")"
CRM_HOST_ESCAPED="$(escape_sed_replacement "$CRM_HOST")"
HR_HOST_ESCAPED="$(escape_sed_replacement "$HR_HOST")"
ERP_HOST_ESCAPED="$(escape_sed_replacement "$ERP_HOST")"
FILES_HOST_ESCAPED="$(escape_sed_replacement "$FILES_HOST")"
PENPOT_HOST_ESCAPED="$(escape_sed_replacement "$PENPOT_HOST")"
GUACAMOLE_OPENID_CLIENT_SECRET_ESCAPED="$(escape_sed_replacement "$GUACAMOLE_OPENID_CLIENT_SECRET")"
BOOKSTACK_OIDC_CLIENT_SECRET_ESCAPED="$(escape_sed_replacement "$BOOKSTACK_OIDC_CLIENT_SECRET")"
VAULTWARDEN_PROXY_OIDC_CLIENT_SECRET_ESCAPED="$(escape_sed_replacement "$VAULTWARDEN_PROXY_OIDC_CLIENT_SECRET")"
SUPPORT_PORTAL_OIDC_CLIENT_SECRET_ESCAPED="$(escape_sed_replacement "$SUPPORT_PORTAL_OIDC_CLIENT_SECRET")"
OSTICKET_OIDC_CLIENT_SECRET_ESCAPED="$(escape_sed_replacement "$OSTICKET_OIDC_CLIENT_SECRET")"
ESPOCRM_OIDC_CLIENT_SECRET_ESCAPED="$(escape_sed_replacement "$ESPOCRM_OIDC_CLIENT_SECRET")"
ERPNEXT_OIDC_CLIENT_SECRET_ESCAPED="$(escape_sed_replacement "$ERPNEXT_OIDC_CLIENT_SECRET")"
SEAFILE_OIDC_CLIENT_SECRET_ESCAPED="$(escape_sed_replacement "$SEAFILE_OIDC_CLIENT_SECRET")"
PENPOT_OIDC_CLIENT_SECRET_ESCAPED="$(escape_sed_replacement "$PENPOT_OIDC_CLIENT_SECRET")"
NETBIRD_OIDC_CLIENT_SECRET_ESCAPED="$(escape_sed_replacement "$NETBIRD_OIDC_CLIENT_SECRET")"
PROVISIONING_KEYCLOAK_CLIENT_SECRET_ESCAPED="$(escape_sed_replacement "$PROVISIONING_KEYCLOAK_CLIENT_SECRET")"
SMTP_HOST_ESCAPED="$(escape_json_sed_replacement "$SMTP_HOST")"
SMTP_PORT_ESCAPED="$(escape_json_sed_replacement "$SMTP_PORT")"
SMTP_FROM_ESCAPED="$(escape_json_sed_replacement "$SMTP_FROM")"
SMTP_FROM_NAME_ESCAPED="$(escape_json_sed_replacement "$SMTP_FROM_NAME")"
SMTP_USER_ESCAPED="$(escape_json_sed_replacement "$SMTP_USER")"
SMTP_PASS_ESCAPED="$(escape_json_sed_replacement "$SMTP_PASS")"

TMP_OUT="$(mktemp)"
trap 'rm -f "$TMP_OUT"' EXIT

sed \
  -e "s|__KEYCLOAK_REALM__|${KEYCLOAK_REALM_ESCAPED}|g" \
  -e "s|__SUPPORT_HOST__|${SUPPORT_HOST_ESCAPED}|g" \
  -e "s|__SSO_HOST__|${SSO_HOST_ESCAPED}|g" \
  -e "s|__VAULT_HOST__|${VAULT_HOST_ESCAPED}|g" \
  -e "s|__DOCS_HOST__|${DOCS_HOST_ESCAPED}|g" \
  -e "s|__REMOTE_HOST__|${REMOTE_HOST_ESCAPED}|g" \
  -e "s|__NETBIRD_HOST__|${NETBIRD_HOST_ESCAPED}|g" \
  -e "s|__NETBIRD_OIDC_REDIRECT_URI__|${NETBIRD_OIDC_REDIRECT_URI_ESCAPED}|g" \
  -e "s|__TICKETS_HOST__|${TICKETS_HOST_ESCAPED}|g" \
  -e "s|__CRM_HOST__|${CRM_HOST_ESCAPED}|g" \
  -e "s|__HR_HOST__|${HR_HOST_ESCAPED}|g" \
  -e "s|__ERP_HOST__|${ERP_HOST_ESCAPED}|g" \
  -e "s|__FILES_HOST__|${FILES_HOST_ESCAPED}|g" \
  -e "s|__PENPOT_HOST__|${PENPOT_HOST_ESCAPED}|g" \
  -e "s|__GUACAMOLE_OPENID_CLIENT_SECRET__|${GUACAMOLE_OPENID_CLIENT_SECRET_ESCAPED}|g" \
  -e "s|__BOOKSTACK_OIDC_CLIENT_SECRET__|${BOOKSTACK_OIDC_CLIENT_SECRET_ESCAPED}|g" \
  -e "s|__VAULTWARDEN_PROXY_OIDC_CLIENT_SECRET__|${VAULTWARDEN_PROXY_OIDC_CLIENT_SECRET_ESCAPED}|g" \
  -e "s|__SUPPORT_PORTAL_OIDC_CLIENT_SECRET__|${SUPPORT_PORTAL_OIDC_CLIENT_SECRET_ESCAPED}|g" \
  -e "s|__OSTICKET_OIDC_CLIENT_SECRET__|${OSTICKET_OIDC_CLIENT_SECRET_ESCAPED}|g" \
  -e "s|__ESPOCRM_OIDC_CLIENT_SECRET__|${ESPOCRM_OIDC_CLIENT_SECRET_ESCAPED}|g" \
  -e "s|__ERPNEXT_OIDC_CLIENT_SECRET__|${ERPNEXT_OIDC_CLIENT_SECRET_ESCAPED}|g" \
  -e "s|__SEAFILE_OIDC_CLIENT_SECRET__|${SEAFILE_OIDC_CLIENT_SECRET_ESCAPED}|g" \
  -e "s|__PENPOT_OIDC_CLIENT_SECRET__|${PENPOT_OIDC_CLIENT_SECRET_ESCAPED}|g" \
  -e "s|__NETBIRD_OIDC_CLIENT_SECRET__|${NETBIRD_OIDC_CLIENT_SECRET_ESCAPED}|g" \
  -e "s|__PROVISIONING_KEYCLOAK_CLIENT_SECRET__|${PROVISIONING_KEYCLOAK_CLIENT_SECRET_ESCAPED}|g" \
  -e "s|__SMTP_HOST__|${SMTP_HOST_ESCAPED}|g" \
  -e "s|__SMTP_PORT__|${SMTP_PORT_ESCAPED}|g" \
  -e "s|__SMTP_FROM__|${SMTP_FROM_ESCAPED}|g" \
  -e "s|__SMTP_FROM_NAME__|${SMTP_FROM_NAME_ESCAPED}|g" \
  -e "s|__SMTP_AUTH__|${SMTP_AUTH}|g" \
  -e "s|__SMTP_USER__|${SMTP_USER_ESCAPED}|g" \
  -e "s|__SMTP_PASS__|${SMTP_PASS_ESCAPED}|g" \
  -e "s|__SMTP_STARTTLS__|${SMTP_STARTTLS}|g" \
  -e "s|__SMTP_SSL__|${SMTP_SSL}|g" \
  "$TPL" > "$TMP_OUT"

if grep -q '__[A-Z0-9_]\+__' "$TMP_OUT"; then
  echo "[FAIL] Unresolved template placeholder(s) remain in $OUT"
  grep -o '__[A-Z0-9_]\+__' "$TMP_OUT" | sort -u
  exit 1
fi

mv "$TMP_OUT" "$OUT"

echo "[OK] Rendered $OUT from $TPL using $ENV_FILE"
