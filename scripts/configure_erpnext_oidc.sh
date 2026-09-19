#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${1:-.env}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Environment file not found: $ENV_FILE" >&2
  exit 1
fi

env_get() {
  local key="$1"
  local fallback="${2:-}"
  local value

  value="$(awk -F= -v key="$key" '$1 == key {sub(/^[^=]*=/, ""); print; exit}' "$ENV_FILE")"
  printf '%s' "${value:-$fallback}"
}

ERP_HOST="$(env_get ERP_HOST "erp.example.com")"
SSO_HOST="$(env_get SSO_HOST "sso.example.com")"
KEYCLOAK_REALM="$(env_get KEYCLOAK_REALM "support")"
CLIENT_ID="$(env_get ERPNEXT_OIDC_CLIENT_ID "erpnext")"
CLIENT_SECRET="$(env_get ERPNEXT_OIDC_CLIENT_SECRET)"

if [[ -z "$CLIENT_SECRET" ]]; then
  echo "ERPNEXT_OIDC_CLIENT_SECRET is required" >&2
  exit 1
fi

docker compose --env-file "$ENV_FILE" exec -T \
  -e ERP_HOST="$ERP_HOST" \
  -e SSO_HOST="$SSO_HOST" \
  -e KEYCLOAK_REALM="$KEYCLOAK_REALM" \
  -e ERPNEXT_OIDC_CLIENT_ID="$CLIENT_ID" \
  -e ERPNEXT_OIDC_CLIENT_SECRET="$CLIENT_SECRET" \
  erpnext-backend sh -lc '
    cd /home/frappe/frappe-bench
    bench --site "$ERP_HOST" console
  ' <<'PY'
import json
import os

import frappe

name = "keycloak"
if frappe.db.exists("Social Login Key", name):
    provider = frappe.get_doc("Social Login Key", name)
else:
    provider = frappe.new_doc("Social Login Key")
    provider.get_social_login_provider("Keycloak", initialize=True)
    provider.social_login_provider = "Keycloak"
    provider.provider_name = "Keycloak"

realm = os.environ["KEYCLOAK_REALM"]
public_base = f"https://{os.environ['SSO_HOST']}/realms/{realm}"
internal_base = f"http://keycloak:8080/realms/{realm}"

# Frappe accepts absolute endpoint overrides. Keep browser authorization on
# public HTTPS while token and user-info calls stay inside the Docker network.
provider.base_url = internal_base
provider.custom_base_url = 1
provider.authorize_url = f"{public_base}/protocol/openid-connect/auth"
provider.access_token_url = f"{internal_base}/protocol/openid-connect/token"
provider.api_endpoint = f"{internal_base}/protocol/openid-connect/userinfo"
provider.redirect_url = "/api/method/frappe.integrations.oauth2_logins.login_via_keycloak"
provider.user_id_property = "preferred_username"
provider.client_id = os.environ["ERPNEXT_OIDC_CLIENT_ID"]
provider.client_secret = os.environ["ERPNEXT_OIDC_CLIENT_SECRET"]
provider.enable_social_login = 1
provider.sign_ups = "Allow"
provider.auth_url_data = json.dumps(
    {"response_type": "code", "scope": "openid profile email"}
)

if provider.is_new():
    provider.insert(ignore_permissions=True)
else:
    provider.save(ignore_permissions=True)

frappe.db.commit()
print("ERPNext Keycloak provider configured")
exit()
PY
