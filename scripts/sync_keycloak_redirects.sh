#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="${1:-.env}"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing env file ($ENV_FILE) in $ROOT_DIR"
  exit 1
fi

dc() {
  docker compose --env-file "$ENV_FILE" "$@"
}

env_get() {
  local key="$1"
  local def="$2"
  local val
  val="$(grep -E "^${key}=" "$ENV_FILE" | head -n1 | cut -d= -f2- || true)"
  if [[ -z "$val" ]]; then
    printf '%s' "$def"
  else
    printf '%s' "$val"
  fi
}

BASE_DOMAIN="$(env_get BASE_DOMAIN "example.com")"
SUPPORT_HOST="$(env_get SUPPORT_HOST "support.${BASE_DOMAIN}")"
NETBIRD_HOST="$(env_get NETBIRD_HOST "mesh.${BASE_DOMAIN}")"
NETBIRD_OIDC_REDIRECT_URI="$(env_get NETBIRD_OIDC_REDIRECT_URI "")"
DOCS_HOST="$(env_get DOCS_HOST "docs.${BASE_DOMAIN}")"
REMOTE_HOST="$(env_get REMOTE_HOST "remote.${BASE_DOMAIN}")"
TICKETS_HOST="$(env_get TICKETS_HOST "tickets.${BASE_DOMAIN}")"
CRM_HOST="$(env_get CRM_HOST "crm.${BASE_DOMAIN}")"
HR_HOST="$(env_get HR_HOST "hr.${BASE_DOMAIN}")"
ERP_HOST="$(env_get ERP_HOST "erp.${BASE_DOMAIN}")"
FILES_HOST="$(env_get FILES_HOST "files.${BASE_DOMAIN}")"
PENPOT_HOST="$(env_get PENPOT_HOST "penpot.${BASE_DOMAIN}")"
REALM="$(env_get KEYCLOAK_REALM "support")"
PORTAL_CLIENT_ID="$(env_get SUPPORT_PORTAL_OIDC_CLIENT_ID "support-portal")"
SUPPORT_ADMIN_GROUP="$(env_get SUPPORT_TOOLS_ALLOWED_GROUP "support-admin")"
EMPLOYEES_GROUP="employees"
EMPLOYEES_ROLE="employees"
BOOKSTACK_BROWSER_FLOW="bookstack-employees-browser"
BOOKSTACK_DENY_SUBFLOW="bookstack-deny-non-employees"
OSTICKET_BROWSER_FLOW="osticket-agent-eligible-browser"
OSTICKET_ROLE="app-osticket-agent"
ERPNEXT_BROWSER_FLOW="erpnext-eligible-browser"
SEAFILE_BROWSER_FLOW="seafile-employees-browser"
PENPOT_BROWSER_FLOW="penpot-employees-browser"
NETBIRD_BROWSER_FLOW="netbird-eligible-browser"
ESPOCRM_BROWSER_FLOW="espocrm-employees-browser"
NETBIRD_ROLE="app-netbird"
APPLICATION_GROUPS=(app-netbird app-guacamole app-osticket-agent app-vaultwarden)
GUAC_CLIENT_ID="$(env_get GUACAMOLE_OPENID_CLIENT_ID "guacamole")"
BOOKSTACK_CLIENT_ID="$(env_get BOOKSTACK_OIDC_CLIENT_ID "bookstack")"
OSTICKET_CLIENT_ID="$(env_get OSTICKET_OIDC_CLIENT_ID "osticket")"
ESPOCRM_CLIENT_ID="$(env_get ESPOCRM_OIDC_CLIENT_ID "espocrm")"
ORANGEHRM_CLIENT_ID="$(env_get ORANGEHRM_OIDC_CLIENT_ID "orangehrm")"
ERPNEXT_CLIENT_ID="$(env_get ERPNEXT_OIDC_CLIENT_ID "erpnext")"
SEAFILE_CLIENT_ID="$(env_get SEAFILE_OIDC_CLIENT_ID "seafile")"
PENPOT_CLIENT_ID="$(env_get PENPOT_OIDC_CLIENT_ID "penpot")"
NETBIRD_CLIENT_ID="$(env_get NETBIRD_OIDC_CLIENT_ID "netbird")"
KEYCLOAK_ADMIN_USER="$(env_get KEYCLOAK_ADMIN_USER "")"
KEYCLOAK_ADMIN_PASSWORD="$(env_get KEYCLOAK_ADMIN_PASSWORD "")"
PROVISIONING_CLIENT_ID="$(env_get PROVISIONING_KEYCLOAK_CLIENT_ID "support-tools-provisioning")"
PROVISIONING_CLIENT_SECRET="$(env_get PROVISIONING_KEYCLOAK_CLIENT_SECRET "")"

if [[ -z "$KEYCLOAK_ADMIN_USER" || -z "$KEYCLOAK_ADMIN_PASSWORD" ]]; then
  echo "Missing KEYCLOAK_ADMIN_USER/KEYCLOAK_ADMIN_PASSWORD in $ENV_FILE"
  exit 1
fi
if [[ -z "$PROVISIONING_CLIENT_SECRET" || "$PROVISIONING_CLIENT_SECRET" == replace-with-* ]]; then
  echo "Missing or unsafe PROVISIONING_KEYCLOAK_CLIENT_SECRET in $ENV_FILE"
  exit 1
fi
if [[ -z "$NETBIRD_OIDC_REDIRECT_URI" || "$NETBIRD_OIDC_REDIRECT_URI" != https://* || "$NETBIRD_OIDC_REDIRECT_URI" == *"*"* || "$NETBIRD_OIDC_REDIRECT_URI" == *"replace-with"* ]]; then
  echo "NETBIRD_OIDC_REDIRECT_URI must be the exact HTTPS callback shown by NetBird"
  exit 1
fi

echo "==> Login to Keycloak admin API"
dc exec -T keycloak /opt/keycloak/bin/kcadm.sh config credentials \
  --server http://localhost:8080 \
  --realm master \
  --user "$KEYCLOAK_ADMIN_USER" \
  --password "$KEYCLOAK_ADMIN_PASSWORD" >/dev/null

PROVISIONING_CLIENT_UUID="$(
  dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get clients -r "$REALM" -q clientId="$PROVISIONING_CLIENT_ID" --fields id --format csv --noquotes \
    | tr -d '\r' | tail -n 1
)"
if [[ -z "$PROVISIONING_CLIENT_UUID" || "$PROVISIONING_CLIENT_UUID" == "id" ]]; then
  echo "==> Creating least-privilege provisioning client '$PROVISIONING_CLIENT_ID'"
  dc exec -T keycloak /opt/keycloak/bin/kcadm.sh create clients -r "$REALM" \
    -s "clientId=$PROVISIONING_CLIENT_ID" \
    -s "name=Support Tools Provisioning" \
    -s "description=Read-only service account used for identity reconciliation" \
    -s enabled=true \
    -s protocol=openid-connect \
    -s publicClient=false \
    -s standardFlowEnabled=false \
    -s implicitFlowEnabled=false \
    -s directAccessGrantsEnabled=false \
    -s serviceAccountsEnabled=true \
    -s authorizationServicesEnabled=false \
    -s fullScopeAllowed=false \
    -s "secret=$PROVISIONING_CLIENT_SECRET" >/dev/null
  PROVISIONING_CLIENT_UUID="$(
    dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get clients -r "$REALM" -q clientId="$PROVISIONING_CLIENT_ID" --fields id --format csv --noquotes \
      | tr -d '\r' | tail -n 1
  )"
else
  echo "==> Updating provisioning client '$PROVISIONING_CLIENT_ID'"
  dc exec -T keycloak /opt/keycloak/bin/kcadm.sh update "clients/$PROVISIONING_CLIENT_UUID" -r "$REALM" \
    -s enabled=true \
    -s publicClient=false \
    -s standardFlowEnabled=false \
    -s directAccessGrantsEnabled=false \
    -s serviceAccountsEnabled=true \
    -s fullScopeAllowed=false \
    -s "secret=$PROVISIONING_CLIENT_SECRET" >/dev/null
fi
if [[ -z "$PROVISIONING_CLIENT_UUID" || "$PROVISIONING_CLIENT_UUID" == "id" ]]; then
  echo "Failed to create/find provisioning client '$PROVISIONING_CLIENT_ID'"
  exit 1
fi

echo "==> Enforcing read-only realm-management roles for '$PROVISIONING_CLIENT_ID'"
SERVICE_ACCOUNT_USERNAME="service-account-${PROVISIONING_CLIENT_ID}"
for role in view-users query-users query-groups; do
  if ! dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get-roles -r "$REALM" \
    --uusername "$SERVICE_ACCOUNT_USERNAME" --cclientid realm-management \
    --fields name --format csv --noquotes | tr -d '\r' | grep -qx "$role"; then
    dc exec -T keycloak /opt/keycloak/bin/kcadm.sh add-roles -r "$REALM" \
      --uusername "$SERVICE_ACCOUNT_USERNAME" \
      --cclientid realm-management \
      --rolename "$role" >/dev/null
  fi
done

# fullScopeAllowed=false is intentional. Add only the three approved roles to the
# client's scope so assigned service-account roles can appear in its token.
REALM_MANAGEMENT_UUID="$(
  dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get clients -r "$REALM" -q clientId=realm-management --fields id --format csv --noquotes \
    | tr -d '\r' | tail -n 1
)"
SCOPE_BODY='['
SCOPE_SEPARATOR=''
for role in view-users query-users query-groups; do
  ROLE_UUID="$(
    dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get "clients/$REALM_MANAGEMENT_UUID/roles/$role" -r "$REALM" \
      --fields id --format csv --noquotes | tr -d '\r' | tail -n 1
  )"
  SCOPE_BODY="${SCOPE_BODY}${SCOPE_SEPARATOR}{\"id\":\"${ROLE_UUID}\",\"name\":\"${role}\"}"
  SCOPE_SEPARATOR=','
done
SCOPE_BODY="${SCOPE_BODY}]"
dc exec -T keycloak /opt/keycloak/bin/kcadm.sh create \
  "clients/$PROVISIONING_CLIENT_UUID/scope-mappings/clients/$REALM_MANAGEMENT_UUID" \
  -r "$REALM" -b "$SCOPE_BODY" >/dev/null

PORTAL_CLIENT_UUID="$(
  dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get clients -r "$REALM" -q clientId="$PORTAL_CLIENT_ID" --fields id --format csv --noquotes \
    | tr -d '\r' | tail -n 1
)"

if [[ -z "$PORTAL_CLIENT_UUID" || "$PORTAL_CLIENT_UUID" == "id" ]]; then
  echo "Client '$PORTAL_CLIENT_ID' not found in realm '$REALM'"
  exit 1
fi

echo "==> Updating redirect URIs/web origins for client '$PORTAL_CLIENT_ID'"
dc exec -T keycloak /opt/keycloak/bin/kcadm.sh update "clients/$PORTAL_CLIENT_UUID" -r "$REALM" \
  -s "redirectUris=[\"https://${SUPPORT_HOST}/oauth2/callback\"]" \
  -s "webOrigins=[\"https://${SUPPORT_HOST}\"]" \
  -s "attributes.\"post.logout.redirect.uris\"=\"https://${SUPPORT_HOST}/\"" \
  >/dev/null

if ! dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get "roles/$SUPPORT_ADMIN_GROUP" -r "$REALM" >/dev/null 2>&1; then
  echo "==> Creating realm role '$SUPPORT_ADMIN_GROUP'"
  dc exec -T keycloak /opt/keycloak/bin/kcadm.sh create roles -r "$REALM" \
    -s "name=$SUPPORT_ADMIN_GROUP" \
    -s "description=Support Tools administrators" \
    >/dev/null
fi

SUPPORT_ADMIN_GROUP_UUID="$(
  dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get groups -r "$REALM" -q "search=$SUPPORT_ADMIN_GROUP" \
    | python3 -c 'import json, sys; name=sys.argv[1]; groups=json.load(sys.stdin); print(next((g["id"] for g in groups if g.get("name") == name), ""))' "$SUPPORT_ADMIN_GROUP"
)"
if [[ -z "$SUPPORT_ADMIN_GROUP_UUID" ]]; then
  echo "==> Creating Keycloak group '$SUPPORT_ADMIN_GROUP'"
  dc exec -T keycloak /opt/keycloak/bin/kcadm.sh create groups -r "$REALM" \
    -s "name=$SUPPORT_ADMIN_GROUP" \
    >/dev/null
  SUPPORT_ADMIN_GROUP_UUID="$(
    dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get groups -r "$REALM" -q "search=$SUPPORT_ADMIN_GROUP" \
      | python3 -c 'import json, sys; name=sys.argv[1]; groups=json.load(sys.stdin); print(next((g["id"] for g in groups if g.get("name") == name), ""))' "$SUPPORT_ADMIN_GROUP"
  )"
fi
if [[ -z "$SUPPORT_ADMIN_GROUP_UUID" ]]; then
  echo "Failed to create/find group '$SUPPORT_ADMIN_GROUP' in realm '$REALM'"
  exit 1
fi

if ! dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get "groups/$SUPPORT_ADMIN_GROUP_UUID/role-mappings/realm" -r "$REALM" \
  --fields name --format csv --noquotes | tr -d '\r' | grep -qx "$SUPPORT_ADMIN_GROUP"; then
  echo "==> Assigning realm role '$SUPPORT_ADMIN_GROUP' to group '$SUPPORT_ADMIN_GROUP'"
  dc exec -T keycloak /opt/keycloak/bin/kcadm.sh add-roles -r "$REALM" \
    --gid "$SUPPORT_ADMIN_GROUP_UUID" \
    --rolename "$SUPPORT_ADMIN_GROUP" \
    >/dev/null
fi

EMPLOYEES_GROUP_UUID="$(
  dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get groups -r "$REALM" -q "search=$EMPLOYEES_GROUP" \
    | python3 -c 'import json, sys; name=sys.argv[1]; groups=json.load(sys.stdin); print(next((g["id"] for g in groups if g.get("name") == name), ""))' "$EMPLOYEES_GROUP"
)"
if [[ -z "$EMPLOYEES_GROUP_UUID" ]]; then
  echo "==> Creating Keycloak group '$EMPLOYEES_GROUP'"
  dc exec -T keycloak /opt/keycloak/bin/kcadm.sh create groups -r "$REALM" \
    -s "name=$EMPLOYEES_GROUP" \
    >/dev/null
  EMPLOYEES_GROUP_UUID="$(
    dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get groups -r "$REALM" -q "search=$EMPLOYEES_GROUP" \
      | python3 -c 'import json, sys; name=sys.argv[1]; groups=json.load(sys.stdin); print(next((g["id"] for g in groups if g.get("name") == name), ""))' "$EMPLOYEES_GROUP"
  )"
fi

if ! dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get "roles/$EMPLOYEES_ROLE" -r "$REALM" >/dev/null 2>&1; then
  echo "==> Creating baseline login role '$EMPLOYEES_ROLE'"
  dc exec -T keycloak /opt/keycloak/bin/kcadm.sh create roles -r "$REALM" \
    -s "name=$EMPLOYEES_ROLE" \
    -s "description=Baseline application login eligibility" \
    >/dev/null
fi
if ! dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get "groups/$EMPLOYEES_GROUP_UUID/role-mappings/realm" -r "$REALM" \
  --fields name --format csv --noquotes | tr -d '\r' | grep -qx "$EMPLOYEES_ROLE"; then
  echo "==> Mapping group '$EMPLOYEES_GROUP' to login role '$EMPLOYEES_ROLE'"
  dc exec -T keycloak /opt/keycloak/bin/kcadm.sh add-roles -r "$REALM" \
    --gid "$EMPLOYEES_GROUP_UUID" \
    --rolename "$EMPLOYEES_ROLE" \
    >/dev/null
fi

for application_group in "${APPLICATION_GROUPS[@]}"; do
  APPLICATION_GROUP_UUID="$(
    dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get groups -r "$REALM" -q "search=$application_group" \
      | python3 -c 'import json, sys; name=sys.argv[1]; groups=json.load(sys.stdin); print(next((g["id"] for g in groups if g.get("name") == name), ""))' "$application_group"
  )"
  if [[ -z "$APPLICATION_GROUP_UUID" ]]; then
    echo "==> Creating Keycloak application group '$application_group'"
    dc exec -T keycloak /opt/keycloak/bin/kcadm.sh create groups -r "$REALM" \
      -s "name=$application_group" \
      >/dev/null
    APPLICATION_GROUP_UUID="$(
      dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get groups -r "$REALM" -q "search=$application_group" \
        | python3 -c 'import json, sys; name=sys.argv[1]; groups=json.load(sys.stdin); print(next((g["id"] for g in groups if g.get("name") == name), ""))' "$application_group"
    )"
  fi
done

if ! dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get "clients/$PORTAL_CLIENT_UUID/protocol-mappers/models" -r "$REALM" \
  --fields name --format csv --noquotes | tr -d '\r' | grep -qx 'groups'; then
  echo "==> Adding Keycloak groups claim mapper to '$PORTAL_CLIENT_ID'"
  dc exec -T keycloak /opt/keycloak/bin/kcadm.sh create "clients/$PORTAL_CLIENT_UUID/protocol-mappers/models" -r "$REALM" \
    -s "name=groups" \
    -s "protocol=openid-connect" \
    -s "protocolMapper=oidc-group-membership-mapper" \
    -s 'config."full.path"="false"' \
    -s 'config."id.token.claim"="true"' \
    -s 'config."access.token.claim"="true"' \
    -s 'config."userinfo.token.claim"="true"' \
    -s 'config."claim.name"="groups"' \
    >/dev/null
fi

GUAC_CLIENT_UUID="$(
  dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get clients -r "$REALM" -q clientId="$GUAC_CLIENT_ID" --fields id --format csv --noquotes \
    | tr -d '\r' | tail -n 1
)"

if [[ -z "$GUAC_CLIENT_UUID" || "$GUAC_CLIENT_UUID" == "id" ]]; then
  echo "Client '$GUAC_CLIENT_ID' not found in realm '$REALM'"
  exit 1
fi

echo "==> Updating redirect URIs/web origins for client '$GUAC_CLIENT_ID'"
dc exec -T keycloak /opt/keycloak/bin/kcadm.sh update "clients/$GUAC_CLIENT_UUID" -r "$REALM" \
  -s "redirectUris=[\"https://${REMOTE_HOST}/guacamole/\"]" \
  -s "webOrigins=[\"https://${REMOTE_HOST}\"]" \
  >/dev/null

BOOKSTACK_CLIENT_UUID="$(
  dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get clients -r "$REALM" -q clientId="$BOOKSTACK_CLIENT_ID" --fields id --format csv --noquotes \
    | tr -d '\r' | tail -n 1
)"

if [[ -z "$BOOKSTACK_CLIENT_UUID" || "$BOOKSTACK_CLIENT_UUID" == "id" ]]; then
  echo "Client '$BOOKSTACK_CLIENT_ID' not found in realm '$REALM'"
  exit 1
fi

echo "==> Updating redirect URIs/web origins for client '$BOOKSTACK_CLIENT_ID'"
dc exec -T keycloak /opt/keycloak/bin/kcadm.sh update "clients/$BOOKSTACK_CLIENT_UUID" -r "$REALM" \
  -s "redirectUris=[\"https://${DOCS_HOST}/oidc/callback\"]" \
  -s "webOrigins=[\"https://${DOCS_HOST}\"]" \
  >/dev/null

echo "==> Enforcing '$EMPLOYEES_GROUP' login gate for client '$BOOKSTACK_CLIENT_ID'"
BOOKSTACK_FLOW_UUID="$(
  dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get authentication/flows -r "$REALM" \
    | python3 -c 'import json,sys; alias=sys.argv[1]; print(next((flow["id"] for flow in json.load(sys.stdin) if flow.get("alias") == alias), ""))' "$BOOKSTACK_BROWSER_FLOW"
)"
if [[ -z "$BOOKSTACK_FLOW_UUID" ]]; then
  dc exec -T keycloak /opt/keycloak/bin/kcadm.sh create \
    "authentication/flows/browser/copy" -r "$REALM" \
    -s "newName=$BOOKSTACK_BROWSER_FLOW" >/dev/null
  BOOKSTACK_FLOW_UUID="$(
    dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get authentication/flows -r "$REALM" \
      | python3 -c 'import json,sys; alias=sys.argv[1]; print(next(flow["id"] for flow in json.load(sys.stdin) if flow.get("alias") == alias))' "$BOOKSTACK_BROWSER_FLOW"
  )"
fi

BOOKSTACK_FLOW_EXECUTIONS="$(
  dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get \
    "authentication/flows/$BOOKSTACK_BROWSER_FLOW/executions" -r "$REALM"
)"
BOOKSTACK_DENY_SUBFLOW_ID="$(
  printf '%s' "$BOOKSTACK_FLOW_EXECUTIONS" \
    | python3 -c 'import json,sys; alias=sys.argv[1]; print(next((item["id"] for item in json.load(sys.stdin) if item.get("displayName") == alias), ""))' "$BOOKSTACK_DENY_SUBFLOW"
)"
if [[ -n "$BOOKSTACK_DENY_SUBFLOW_ID" ]]; then
  BOOKSTACK_DENY_SUBFLOW_LEVEL="$(
    printf '%s' "$BOOKSTACK_FLOW_EXECUTIONS" \
      | python3 -c 'import json,sys; identifier=sys.argv[1]; print(next(item["level"] for item in json.load(sys.stdin) if item.get("id") == identifier))' "$BOOKSTACK_DENY_SUBFLOW_ID"
  )"
  if [[ "$BOOKSTACK_DENY_SUBFLOW_LEVEL" != "1" ]]; then
    dc exec -T keycloak /opt/keycloak/bin/kcadm.sh delete \
      "authentication/executions/$BOOKSTACK_DENY_SUBFLOW_ID" -r "$REALM" >/dev/null
    BOOKSTACK_DENY_SUBFLOW_ID=""
    BOOKSTACK_FLOW_EXECUTIONS="$(
      dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get \
        "authentication/flows/$BOOKSTACK_BROWSER_FLOW/executions" -r "$REALM"
    )"
  fi
fi
if [[ -z "$BOOKSTACK_DENY_SUBFLOW_ID" ]]; then
  dc exec -T keycloak /opt/keycloak/bin/kcadm.sh create \
    "authentication/flows/${BOOKSTACK_BROWSER_FLOW}%20forms/executions/flow" -r "$REALM" \
    -s "alias=$BOOKSTACK_DENY_SUBFLOW" \
    -s type=basic-flow \
    -s provider=registration-page-form \
    -s "description=Deny users without $EMPLOYEES_GROUP eligibility" >/dev/null
  BOOKSTACK_FLOW_EXECUTIONS="$(
    dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get \
      "authentication/flows/$BOOKSTACK_BROWSER_FLOW/executions" -r "$REALM"
  )"
  BOOKSTACK_DENY_SUBFLOW_ID="$(
    printf '%s' "$BOOKSTACK_FLOW_EXECUTIONS" \
      | python3 -c 'import json,sys; alias=sys.argv[1]; print(next(item["id"] for item in json.load(sys.stdin) if item.get("displayName") == alias))' "$BOOKSTACK_DENY_SUBFLOW"
  )"
  printf '{"id":"%s","requirement":"CONDITIONAL"}' "$BOOKSTACK_DENY_SUBFLOW_ID" \
    | dc exec -T keycloak /opt/keycloak/bin/kcadm.sh update \
      "authentication/flows/$BOOKSTACK_BROWSER_FLOW/executions" -r "$REALM" -f - >/dev/null
fi

if ! printf '%s' "$BOOKSTACK_FLOW_EXECUTIONS" \
  | python3 -c 'import json,sys; raise SystemExit(0 if any(item.get("providerId") == "deny-access-authenticator" for item in json.load(sys.stdin)) else 1)'; then
  dc exec -T keycloak /opt/keycloak/bin/kcadm.sh create \
    "authentication/flows/$BOOKSTACK_DENY_SUBFLOW/executions/execution" -r "$REALM" \
    -s provider=deny-access-authenticator >/dev/null
fi
if ! printf '%s' "$BOOKSTACK_FLOW_EXECUTIONS" \
  | python3 -c 'import json,sys; raise SystemExit(0 if any(item.get("providerId") == "conditional-user-role" for item in json.load(sys.stdin)) else 1)'; then
  dc exec -T keycloak /opt/keycloak/bin/kcadm.sh create \
    "authentication/flows/$BOOKSTACK_DENY_SUBFLOW/executions/execution" -r "$REALM" \
    -s provider=conditional-user-role >/dev/null
fi

BOOKSTACK_FLOW_EXECUTIONS="$(
  dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get \
    "authentication/flows/$BOOKSTACK_BROWSER_FLOW/executions" -r "$REALM"
)"
BOOKSTACK_CONDITION_ID="$(
  printf '%s' "$BOOKSTACK_FLOW_EXECUTIONS" \
    | python3 -c 'import json,sys; print(next(item["id"] for item in json.load(sys.stdin) if item.get("providerId") == "conditional-user-role"))'
)"
BOOKSTACK_DENY_ID="$(
  printf '%s' "$BOOKSTACK_FLOW_EXECUTIONS" \
    | python3 -c 'import json,sys; print(next(item["id"] for item in json.load(sys.stdin) if item.get("providerId") == "deny-access-authenticator"))'
)"
for execution_id in "$BOOKSTACK_CONDITION_ID" "$BOOKSTACK_DENY_ID"; do
  printf '{"id":"%s","requirement":"REQUIRED"}' "$execution_id" \
    | dc exec -T keycloak /opt/keycloak/bin/kcadm.sh update \
      "authentication/flows/$BOOKSTACK_BROWSER_FLOW/executions" -r "$REALM" -f - >/dev/null
done

BOOKSTACK_CONDITION_CONFIG_ID="$(
  printf '%s' "$BOOKSTACK_FLOW_EXECUTIONS" \
    | python3 -c 'import json,sys; print(next((item.get("authenticationConfig", "") for item in json.load(sys.stdin) if item.get("providerId") == "conditional-user-role"), ""))'
)"
if [[ -z "$BOOKSTACK_CONDITION_CONFIG_ID" ]]; then
  printf '{"alias":"deny-non-employees","config":{"condUserRole":"%s","negate":"true"}}' "$EMPLOYEES_ROLE" \
    | dc exec -T keycloak /opt/keycloak/bin/kcadm.sh create \
      "authentication/executions/$BOOKSTACK_CONDITION_ID/config" -r "$REALM" -f - >/dev/null
else
  printf '{"id":"%s","alias":"deny-non-employees","config":{"condUserRole":"%s","negate":"true"}}' \
    "$BOOKSTACK_CONDITION_CONFIG_ID" "$EMPLOYEES_ROLE" \
    | dc exec -T keycloak /opt/keycloak/bin/kcadm.sh update \
      "authentication/config/$BOOKSTACK_CONDITION_CONFIG_ID" -r "$REALM" -f - >/dev/null
fi

BOOKSTACK_FLOW_EXECUTIONS="$(
  dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get \
    "authentication/flows/$BOOKSTACK_BROWSER_FLOW/executions" -r "$REALM"
)"
BOOKSTACK_CONDITION_CONFIG_ID="$(
  printf '%s' "$BOOKSTACK_FLOW_EXECUTIONS" \
    | python3 -c 'import json,sys; print(next((item.get("authenticationConfig", "") for item in json.load(sys.stdin) if item.get("providerId") == "conditional-user-role"), ""))'
)"
if [[ -z "$BOOKSTACK_CONDITION_CONFIG_ID" ]]; then
  echo "BookStack employees-role condition has no configuration" >&2
  exit 1
fi

# The gate is inside the copied forms flow and must run after password and OTP.
for _ in 1 2 3 4 5 6 7 8; do
  BOOKSTACK_FLOW_EXECUTIONS="$(
    dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get \
      "authentication/flows/$BOOKSTACK_BROWSER_FLOW/executions" -r "$REALM"
  )"
  read -r gate_index max_index < <(
    printf '%s' "$BOOKSTACK_FLOW_EXECUTIONS" \
      | python3 -c 'import json,sys; gate=sys.argv[1]; rows=json.load(sys.stdin); print(next(item["index"] for item in rows if item.get("id") == gate), max(item["index"] for item in rows if item.get("level") == 1))' "$BOOKSTACK_DENY_SUBFLOW_ID"
  )
  [[ "$gate_index" -ge "$max_index" ]] && break
  dc exec -T keycloak /opt/keycloak/bin/kcadm.sh create \
    "authentication/executions/$BOOKSTACK_DENY_SUBFLOW_ID/lower-priority" -r "$REALM" >/dev/null
done

# Keycloak 26 expects the flow UUID. Partial map updates are silently discarded,
# so preserve and update the complete client representation.
dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get "clients/$BOOKSTACK_CLIENT_UUID" -r "$REALM" \
  | python3 -c 'import json,sys; data=json.load(sys.stdin); data["authenticationFlowBindingOverrides"]={"browser":sys.argv[1]}; json.dump(data,sys.stdout)' "$BOOKSTACK_FLOW_UUID" \
  | dc exec -T keycloak /opt/keycloak/bin/kcadm.sh update \
    "clients/$BOOKSTACK_CLIENT_UUID" -r "$REALM" -f - >/dev/null

BOOKSTACK_BOUND_FLOW="$(
  dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get "clients/$BOOKSTACK_CLIENT_UUID" -r "$REALM" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin).get("authenticationFlowBindingOverrides", {}).get("browser", ""))'
)"
if [[ "$BOOKSTACK_BOUND_FLOW" != "$BOOKSTACK_FLOW_UUID" ]]; then
  echo "BookStack browser-flow binding did not persist" >&2
  exit 1
fi
BOOKSTACK_CONDITION_ROLE="$(
  dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get \
    "authentication/config/$BOOKSTACK_CONDITION_CONFIG_ID" -r "$REALM" \
    | python3 -c 'import json,sys; config=json.load(sys.stdin).get("config", {}); print(config.get("condUserRole", "") + ":" + config.get("negate", ""))'
)"
if [[ "$BOOKSTACK_CONDITION_ROLE" != "$EMPLOYEES_ROLE:true" ]]; then
  echo "BookStack employees-role condition did not persist" >&2
  exit 1
fi
BOOKSTACK_FLOW_EXECUTIONS="$(
  dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get \
    "authentication/flows/$BOOKSTACK_BROWSER_FLOW/executions" -r "$REALM"
)"
if ! printf '%s' "$BOOKSTACK_FLOW_EXECUTIONS" | python3 -c '
import json, sys
rows = json.load(sys.stdin)
gate = next(item for item in rows if item.get("displayName") == "bookstack-deny-non-employees")
password = next(item for item in rows if item.get("providerId") == "auth-username-password-form")
otp = next(item for item in rows if "Conditional OTP" in item.get("displayName", ""))
valid = gate.get("level") == 1 and gate.get("requirement") == "CONDITIONAL"
valid = valid and gate.get("index") > max(password.get("index"), otp.get("index"))
raise SystemExit(0 if valid else 1)
'; then
  echo "BookStack employees gate is not ordered after password and OTP" >&2
  exit 1
fi

OSTICKET_CLIENT_UUID="$(
  dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get clients -r "$REALM" -q clientId="$OSTICKET_CLIENT_ID" --fields id --format csv --noquotes \
    | tr -d '\r' | tail -n 1
)"

if [[ -z "$OSTICKET_CLIENT_UUID" || "$OSTICKET_CLIENT_UUID" == "id" ]]; then
  echo "Client '$OSTICKET_CLIENT_ID' not found in realm '$REALM'"
  exit 1
fi

echo "==> Updating redirect URIs/web origins for client '$OSTICKET_CLIENT_ID'"
dc exec -T keycloak /opt/keycloak/bin/kcadm.sh update "clients/$OSTICKET_CLIENT_UUID" -r "$REALM" \
  -s "redirectUris=[\"https://${TICKETS_HOST}/api/auth/oauth2\"]" \
  -s "webOrigins=[\"https://${TICKETS_HOST}\"]" \
  >/dev/null

ESPOCRM_CLIENT_UUID="$(
  dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get clients -r "$REALM" -q clientId="$ESPOCRM_CLIENT_ID" --fields id --format csv --noquotes \
    | tr -d '\r' | tail -n 1
)"

if [[ -z "$ESPOCRM_CLIENT_UUID" || "$ESPOCRM_CLIENT_UUID" == "id" ]]; then
  echo "Client '$ESPOCRM_CLIENT_ID' not found in realm '$REALM'"
  exit 1
fi

echo "==> Updating redirect URIs/web origins for client '$ESPOCRM_CLIENT_ID'"
dc exec -T keycloak /opt/keycloak/bin/kcadm.sh update "clients/$ESPOCRM_CLIENT_UUID" -r "$REALM" \
  -s "secret=$(env_get ESPOCRM_OIDC_CLIENT_SECRET \"replace-with-espocrm-oidc-client-secret\")" \
  -s "redirectUris=[\"https://${CRM_HOST}/oauth-callback.php\"]" \
  -s "webOrigins=[\"https://${CRM_HOST}\"]" \
  >/dev/null

ORANGEHRM_CLIENT_UUID="$(
  dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get clients -r "$REALM" -q clientId="$ORANGEHRM_CLIENT_ID" --fields id --format csv --noquotes \
    | tr -d '\r' | tail -n 1
)"

if [[ -n "$ORANGEHRM_CLIENT_UUID" && "$ORANGEHRM_CLIENT_UUID" != "id" ]]; then
  echo "==> Disabling retired client '$ORANGEHRM_CLIENT_ID'"
  dc exec -T keycloak /opt/keycloak/bin/kcadm.sh update "clients/$ORANGEHRM_CLIENT_UUID" -r "$REALM" \
    -s "enabled=false" >/dev/null
fi

configure_client_role_gate() {
  local client_uuid="$1"
  local client_id="$2"
  local flow_alias="$3"
  shift 3
  local required_roles=("$@")
  local flow_uuid executions role subflow subflow_id subflow_level
  local condition_id deny_id config_id persisted gate_priority role_position=0

  flow_uuid="$(
    dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get authentication/flows -r "$REALM" \
      | python3 -c 'import json,sys; alias=sys.argv[1]; print(next((flow["id"] for flow in json.load(sys.stdin) if flow.get("alias") == alias), ""))' "$flow_alias"
  )"
  if [[ -z "$flow_uuid" ]]; then
    dc exec -T keycloak /opt/keycloak/bin/kcadm.sh create \
      "authentication/flows/browser/copy" -r "$REALM" -s "newName=$flow_alias" >/dev/null
    flow_uuid="$(
      dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get authentication/flows -r "$REALM" \
        | python3 -c 'import json,sys; alias=sys.argv[1]; print(next(flow["id"] for flow in json.load(sys.stdin) if flow.get("alias") == alias))' "$flow_alias"
    )"
  fi

  for role in "${required_roles[@]}"; do
    subflow="${client_id}-deny-without-${role}"
    executions="$(
      dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get \
        "authentication/flows/$flow_alias/executions" -r "$REALM"
    )"
    subflow_id="$(
      printf '%s' "$executions" | python3 -c 'import json,sys; alias=sys.argv[1]; print(next((row["id"] for row in json.load(sys.stdin) if row.get("displayName") == alias), ""))' "$subflow"
    )"
    if [[ -n "$subflow_id" ]]; then
      subflow_level="$(
        printf '%s' "$executions" | python3 -c 'import json,sys; identifier=sys.argv[1]; print(next(row["level"] for row in json.load(sys.stdin) if row.get("id") == identifier))' "$subflow_id"
      )"
      read -r existing_gate_index existing_auth_index < <(
        printf '%s' "$executions" \
          | python3 -c 'import json,sys; gate=sys.argv[1]; rows=json.load(sys.stdin); auth=[row["index"] for row in rows if row.get("providerId")=="auth-username-password-form" or "Conditional OTP" in row.get("displayName", "")]; print(next(row["index"] for row in rows if row.get("id")==gate), max(auth))' "$subflow_id"
      )
      if [[ "$subflow_level" != "1" || "$existing_gate_index" -le "$existing_auth_index" ]]; then
        # Some Keycloak versions cannot move a nested flow past another nested
        # flow. Recreate only a misplaced gate; correctly ordered gates remain
        # untouched on subsequent runs.
        dc exec -T keycloak /opt/keycloak/bin/kcadm.sh delete \
          "authentication/executions/$subflow_id" -r "$REALM" >/dev/null
        subflow_id=""
      fi
    fi
    if [[ -z "$subflow_id" ]]; then
      dc exec -T keycloak /opt/keycloak/bin/kcadm.sh create \
        "authentication/flows/${flow_alias}%20forms/executions/flow" -r "$REALM" \
        -s "alias=$subflow" -s type=basic-flow -s provider=registration-page-form \
        -s "description=Deny users without $role eligibility" >/dev/null
      executions="$(
        dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get \
          "authentication/flows/$flow_alias/executions" -r "$REALM"
      )"
      subflow_id="$(
        printf '%s' "$executions" | python3 -c 'import json,sys; alias=sys.argv[1]; print(next(row["id"] for row in json.load(sys.stdin) if row.get("displayName") == alias))' "$subflow"
      )"
    fi
    subflow_requirement="$(
      printf '%s' "$executions" \
        | python3 -c 'import json,sys; identifier=sys.argv[1]; print(next(row.get("requirement", "") for row in json.load(sys.stdin) if row.get("id")==identifier))' "$subflow_id"
    )"
    if [[ "$subflow_requirement" != "CONDITIONAL" ]]; then
      printf '{"id":"%s","requirement":"CONDITIONAL"}' "$subflow_id" \
        | dc exec -T keycloak /opt/keycloak/bin/kcadm.sh update \
          "authentication/flows/$flow_alias/executions" -r "$REALM" -f - >/dev/null
    fi

    # Keycloak can silently ignore a submitted numeric priority. Move the gate
    # through the execution API until it is the final top-level forms step.
    for _ in $(seq 1 64); do
      executions="$(
        dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get \
          "authentication/flows/$flow_alias/executions" -r "$REALM"
      )"
      read -r gate_index auth_index < <(
        printf '%s' "$executions" \
          | python3 -c 'import json,sys; gate=sys.argv[1]; rows=json.load(sys.stdin); auth=[row["index"] for row in rows if row.get("providerId")=="auth-username-password-form" or "Conditional OTP" in row.get("displayName", "")]; print(next(row["index"] for row in rows if row.get("id")==gate), max(auth))' "$subflow_id"
      )
      [[ "$gate_index" -gt "$auth_index" ]] && break
      dc exec -T keycloak /opt/keycloak/bin/kcadm.sh create \
        "authentication/executions/$subflow_id/lower-priority" -r "$REALM" >/dev/null
    done

    executions="$(
      dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get \
        "authentication/flows/$flow_alias/executions" -r "$REALM"
    )"
    condition_id="$(
      printf '%s' "$executions" | python3 -c '
import json,sys
rows=json.load(sys.stdin); parent=sys.argv[1]; provider=sys.argv[2]
start=next(i for i,row in enumerate(rows) if row.get("id")==parent); level=rows[start]["level"]
children=[]
for row in rows[start+1:]:
    if row.get("level", 0) <= level: break
    children.append(row)
print(next((row["id"] for row in children if row.get("providerId")==provider), ""))
' "$subflow_id" conditional-user-role
    )"
    if [[ -z "$condition_id" ]]; then
      dc exec -T keycloak /opt/keycloak/bin/kcadm.sh create \
        "authentication/flows/$subflow/executions/execution" -r "$REALM" \
        -s provider=conditional-user-role >/dev/null
    fi
    deny_id="$(
      printf '%s' "$executions" | python3 -c '
import json,sys
rows=json.load(sys.stdin); parent=sys.argv[1]; provider=sys.argv[2]
start=next(i for i,row in enumerate(rows) if row.get("id")==parent); level=rows[start]["level"]
children=[]
for row in rows[start+1:]:
    if row.get("level", 0) <= level: break
    children.append(row)
print(next((row["id"] for row in children if row.get("providerId")==provider), ""))
' "$subflow_id" deny-access-authenticator
    )"
    if [[ -z "$deny_id" ]]; then
      dc exec -T keycloak /opt/keycloak/bin/kcadm.sh create \
        "authentication/flows/$subflow/executions/execution" -r "$REALM" \
        -s provider=deny-access-authenticator >/dev/null
    fi

    executions="$(
      dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get \
        "authentication/flows/$flow_alias/executions" -r "$REALM"
    )"
    condition_id="$(
      printf '%s' "$executions" | python3 -c '
import json,sys
rows=json.load(sys.stdin); parent=sys.argv[1]; provider=sys.argv[2]
start=next(i for i,row in enumerate(rows) if row.get("id")==parent); level=rows[start]["level"]
children=[]
for row in rows[start+1:]:
    if row.get("level", 0) <= level: break
    children.append(row)
print(next(row["id"] for row in children if row.get("providerId")==provider))
' "$subflow_id" conditional-user-role
    )"
    deny_id="$(
      printf '%s' "$executions" | python3 -c '
import json,sys
rows=json.load(sys.stdin); parent=sys.argv[1]; provider=sys.argv[2]
start=next(i for i,row in enumerate(rows) if row.get("id")==parent); level=rows[start]["level"]
children=[]
for row in rows[start+1:]:
    if row.get("level", 0) <= level: break
    children.append(row)
print(next(row["id"] for row in children if row.get("providerId")==provider))
' "$subflow_id" deny-access-authenticator
    )"
    for execution_id in "$condition_id" "$deny_id"; do
      printf '{"id":"%s","requirement":"REQUIRED"}' "$execution_id" \
        | dc exec -T keycloak /opt/keycloak/bin/kcadm.sh update \
          "authentication/flows/$flow_alias/executions" -r "$REALM" -f - >/dev/null
    done

    config_id="$(
      printf '%s' "$executions" | python3 -c 'import json,sys; identifier=sys.argv[1]; print(next((row.get("authenticationConfig", "") for row in json.load(sys.stdin) if row.get("id")==identifier), ""))' "$condition_id"
    )"
    if [[ -z "$config_id" ]]; then
      printf '{"alias":"%s-deny-without-%s","config":{"condUserRole":"%s","negate":"true"}}' "$client_id" "$role" "$role" \
        | dc exec -T keycloak /opt/keycloak/bin/kcadm.sh create \
          "authentication/executions/$condition_id/config" -r "$REALM" -f - >/dev/null
    else
      printf '{"id":"%s","alias":"%s-deny-without-%s","config":{"condUserRole":"%s","negate":"true"}}' "$config_id" "$client_id" "$role" "$role" \
        | dc exec -T keycloak /opt/keycloak/bin/kcadm.sh update \
          "authentication/config/$config_id" -r "$REALM" -f - >/dev/null
    fi

    executions="$(
      dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get \
        "authentication/flows/$flow_alias/executions" -r "$REALM"
    )"
    if ! printf '%s' "$executions" | python3 -c '
import json,sys
rows=json.load(sys.stdin); gate_id=sys.argv[1]
gate=next(row for row in rows if row.get("id")==gate_id)
password=next(row for row in rows if row.get("providerId")=="auth-username-password-form")
otp=next(row for row in rows if "Conditional OTP" in row.get("displayName", ""))
valid=gate.get("level")==1 and gate.get("requirement")=="CONDITIONAL"
valid=valid and gate.get("index") > max(password.get("index"), otp.get("index"))
raise SystemExit(0 if valid else 1)
' "$subflow_id"; then
      echo "$client_id gate for role '$role' is not ordered after password and OTP" >&2
      exit 1
    fi
    config_id="$(
      printf '%s' "$executions" | python3 -c 'import json,sys; identifier=sys.argv[1]; print(next(row.get("authenticationConfig", "") for row in json.load(sys.stdin) if row.get("id")==identifier))' "$condition_id"
    )"
    persisted="$(
      dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get "authentication/config/$config_id" -r "$REALM" \
        | python3 -c 'import json,sys; config=json.load(sys.stdin).get("config", {}); print(config.get("condUserRole", "") + ":" + config.get("negate", ""))'
    )"
    if [[ "$persisted" != "$role:true" ]]; then
      echo "$client_id role condition for '$role' did not persist" >&2
      exit 1
    fi
    role_position=$((role_position + 1))
  done

  dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get "clients/$client_uuid" -r "$REALM" \
    | python3 -c 'import json,sys; data=json.load(sys.stdin); data["authenticationFlowBindingOverrides"]={"browser":sys.argv[1]}; json.dump(data,sys.stdout)' "$flow_uuid" \
    | dc exec -T keycloak /opt/keycloak/bin/kcadm.sh update \
      "clients/$client_uuid" -r "$REALM" -f - >/dev/null
  persisted="$(
    dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get "clients/$client_uuid" -r "$REALM" \
      | python3 -c 'import json,sys; print(json.load(sys.stdin).get("authenticationFlowBindingOverrides", {}).get("browser", ""))'
  )"
  if [[ "$persisted" != "$flow_uuid" ]]; then
    echo "$client_id browser-flow binding did not persist" >&2
    exit 1
  fi
}

echo "==> Enforcing '$EMPLOYEES_ROLE' login gate for client '$ESPOCRM_CLIENT_ID'"
configure_client_role_gate \
  "$ESPOCRM_CLIENT_UUID" "$ESPOCRM_CLIENT_ID" "$ESPOCRM_BROWSER_FLOW" \
  "$EMPLOYEES_ROLE"

echo "==> Enforcing '$EMPLOYEES_ROLE' and '$OSTICKET_ROLE' login gates for '$OSTICKET_CLIENT_ID'"
configure_client_role_gate \
  "$OSTICKET_CLIENT_UUID" "$OSTICKET_CLIENT_ID" "$OSTICKET_BROWSER_FLOW" \
  "$EMPLOYEES_ROLE" "$OSTICKET_ROLE"

ERPNEXT_CLIENT_UUID="$(
  dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get clients -r "$REALM" -q clientId="$ERPNEXT_CLIENT_ID" --fields id --format csv --noquotes \
    | tr -d '\r' | tail -n 1
)"

if [[ -z "$ERPNEXT_CLIENT_UUID" || "$ERPNEXT_CLIENT_UUID" == "id" ]]; then
  echo "==> Client '$ERPNEXT_CLIENT_ID' not found, creating it"
  dc exec -T keycloak /opt/keycloak/bin/kcadm.sh create clients -r "$REALM" \
    -s "clientId=$ERPNEXT_CLIENT_ID" \
    -s "name=ERPNext" \
    -s "enabled=true" \
    -s "protocol=openid-connect" \
    -s "publicClient=false" \
    -s "secret=$(env_get ERPNEXT_OIDC_CLIENT_SECRET "replace-with-erpnext-oidc-client-secret")" \
    -s "standardFlowEnabled=true" \
    -s "directAccessGrantsEnabled=false" \
    -s "serviceAccountsEnabled=false" \
    >/dev/null
  ERPNEXT_CLIENT_UUID="$(
    dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get clients -r "$REALM" -q clientId="$ERPNEXT_CLIENT_ID" --fields id --format csv --noquotes \
      | tr -d '\r' | tail -n 1
  )"
  if [[ -z "$ERPNEXT_CLIENT_UUID" || "$ERPNEXT_CLIENT_UUID" == "id" ]]; then
    echo "Failed to create/find client '$ERPNEXT_CLIENT_ID' in realm '$REALM'"
    exit 1
  fi
fi

echo "==> Updating redirect URIs/web origins for client '$ERPNEXT_CLIENT_ID'"
dc exec -T keycloak /opt/keycloak/bin/kcadm.sh update "clients/$ERPNEXT_CLIENT_UUID" -r "$REALM" \
  -s "redirectUris=[\"https://${ERP_HOST}/api/method/frappe.integrations.oauth2_logins.login_via_keycloak\"]" \
  -s "webOrigins=[\"https://${ERP_HOST}\"]" \
  >/dev/null

echo "==> Enforcing '$EMPLOYEES_ROLE' login gate for Frappe HR / ERPNext client '$ERPNEXT_CLIENT_ID'"
configure_client_role_gate \
  "$ERPNEXT_CLIENT_UUID" "$ERPNEXT_CLIENT_ID" "$ERPNEXT_BROWSER_FLOW" \
  "$EMPLOYEES_ROLE"

SEAFILE_CLIENT_UUID="$(
  dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get clients -r "$REALM" -q clientId="$SEAFILE_CLIENT_ID" --fields id --format csv --noquotes \
    | tr -d '\r' | tail -n 1
)"

if [[ -z "$SEAFILE_CLIENT_UUID" || "$SEAFILE_CLIENT_UUID" == "id" ]]; then
  echo "Client '$SEAFILE_CLIENT_ID' not found in realm '$REALM'"
  exit 1
fi

echo "==> Updating redirect URIs/web origins for client '$SEAFILE_CLIENT_ID'"
dc exec -T keycloak /opt/keycloak/bin/kcadm.sh update "clients/$SEAFILE_CLIENT_UUID" -r "$REALM" \
  -s "redirectUris=[\"https://${FILES_HOST}/oauth/callback/\"]" \
  -s "webOrigins=[\"https://${FILES_HOST}\"]" \
  >/dev/null

echo "==> Enforcing '$EMPLOYEES_ROLE' login gate for '$SEAFILE_CLIENT_ID'"
configure_client_role_gate \
  "$SEAFILE_CLIENT_UUID" "$SEAFILE_CLIENT_ID" "$SEAFILE_BROWSER_FLOW" \
  "$EMPLOYEES_ROLE"

PENPOT_CLIENT_UUID="$(
  dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get clients -r "$REALM" -q clientId="$PENPOT_CLIENT_ID" --fields id --format csv --noquotes \
    | tr -d '\r' | tail -n 1
)"

if [[ -z "$PENPOT_CLIENT_UUID" || "$PENPOT_CLIENT_UUID" == "id" ]]; then
  echo "Client '$PENPOT_CLIENT_ID' not found in realm '$REALM'"
  exit 1
fi

echo "==> Updating redirect URIs/web origins for client '$PENPOT_CLIENT_ID'"
dc exec -T keycloak /opt/keycloak/bin/kcadm.sh update "clients/$PENPOT_CLIENT_UUID" -r "$REALM" \
  -s "redirectUris=[\"https://${PENPOT_HOST}/api/auth/oidc/callback\"]" \
  -s "webOrigins=[\"https://${PENPOT_HOST}\"]" \
  >/dev/null

echo "==> Enforcing '$EMPLOYEES_ROLE' login gate for '$PENPOT_CLIENT_ID'"
configure_client_role_gate \
  "$PENPOT_CLIENT_UUID" "$PENPOT_CLIENT_ID" "$PENPOT_BROWSER_FLOW" \
  "$EMPLOYEES_ROLE"

NETBIRD_CLIENT_UUID="$(
  dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get clients -r "$REALM" -q clientId="$NETBIRD_CLIENT_ID" --fields id --format csv --noquotes \
    | tr -d '\r' | tail -n 1
)"

if [[ -z "$NETBIRD_CLIENT_UUID" || "$NETBIRD_CLIENT_UUID" == "id" ]]; then
  echo "==> Client '$NETBIRD_CLIENT_ID' not found, creating it"
  dc exec -T keycloak /opt/keycloak/bin/kcadm.sh create clients -r "$REALM" \
    -s "clientId=$NETBIRD_CLIENT_ID" \
    -s "name=NetBird" \
    -s "enabled=true" \
    -s "protocol=openid-connect" \
    -s "publicClient=false" \
    -s "secret=$(env_get NETBIRD_OIDC_CLIENT_SECRET "replace-with-netbird-oidc-client-secret")" \
    -s "standardFlowEnabled=true" \
    -s "directAccessGrantsEnabled=false" \
    -s "serviceAccountsEnabled=false" \
    >/dev/null
  NETBIRD_CLIENT_UUID="$(
    dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get clients -r "$REALM" -q clientId="$NETBIRD_CLIENT_ID" --fields id --format csv --noquotes \
      | tr -d '\r' | tail -n 1
  )"
fi

if [[ -z "$NETBIRD_CLIENT_UUID" || "$NETBIRD_CLIENT_UUID" == "id" ]]; then
  echo "Failed to create/find client '$NETBIRD_CLIENT_ID' in realm '$REALM'"
  exit 1
fi

echo "==> Updating redirect URIs/web origins for client '$NETBIRD_CLIENT_ID'"
dc exec -T keycloak /opt/keycloak/bin/kcadm.sh update "clients/$NETBIRD_CLIENT_UUID" -r "$REALM" \
  -s "secret=$(env_get NETBIRD_OIDC_CLIENT_SECRET "replace-with-netbird-oidc-client-secret")" \
  -s "redirectUris=[\"${NETBIRD_OIDC_REDIRECT_URI}\"]" \
  -s "webOrigins=[\"https://${NETBIRD_HOST}\"]" \
  -s "attributes.\"post.logout.redirect.uris\"=\"https://${NETBIRD_HOST}/oauth2/logout/callback\"" \
  >/dev/null

echo "==> Enforcing '$EMPLOYEES_ROLE' and '$NETBIRD_ROLE' login gates for '$NETBIRD_CLIENT_ID'"
configure_client_role_gate \
  "$NETBIRD_CLIENT_UUID" "$NETBIRD_CLIENT_ID" "$NETBIRD_BROWSER_FLOW" \
  "$EMPLOYEES_ROLE" "$NETBIRD_ROLE"

NETBIRD_GROUP_MAPPER_UUID="$(
  dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get "clients/$NETBIRD_CLIENT_UUID/protocol-mappers/models" -r "$REALM" \
    | python3 -c 'import json,sys; print(next((row["id"] for row in json.load(sys.stdin) if row.get("name") == "groups"), ""))'
)"
NETBIRD_GROUP_MAPPER_PAYLOAD="$(python3 -c '
import json,sys
payload = {
    "name": "groups",
    "protocol": "openid-connect",
    "protocolMapper": "oidc-hardcoded-claim-mapper",
    "consentRequired": False,
    "config": {
        "claim.value": json.dumps([sys.argv[1]]),
        "jsonType.label": "JSON",
        "id.token.claim": "true",
        "access.token.claim": "true",
        "userinfo.token.claim": "true",
        "claim.name": "groups",
    },
}
if sys.argv[2]: payload["id"] = sys.argv[2]
json.dump(payload, sys.stdout)
' "$NETBIRD_ROLE" "$NETBIRD_GROUP_MAPPER_UUID")"
if [[ -z "$NETBIRD_GROUP_MAPPER_UUID" ]]; then
  echo "==> Adding approved NetBird group claim mapper to '$NETBIRD_CLIENT_ID'"
  printf '%s' "$NETBIRD_GROUP_MAPPER_PAYLOAD" \
    | dc exec -T keycloak /opt/keycloak/bin/kcadm.sh create \
      "clients/$NETBIRD_CLIENT_UUID/protocol-mappers/models" -r "$REALM" -f - >/dev/null
else
  echo "==> Restricting '$NETBIRD_CLIENT_ID' groups claim to '$NETBIRD_ROLE'"
  printf '%s' "$NETBIRD_GROUP_MAPPER_PAYLOAD" \
    | dc exec -T keycloak /opt/keycloak/bin/kcadm.sh update \
      "clients/$NETBIRD_CLIENT_UUID/protocol-mappers/models/$NETBIRD_GROUP_MAPPER_UUID" \
      -r "$REALM" -f - >/dev/null
fi

echo "Done. Client '$PORTAL_CLIENT_ID' now allows:"
echo "  - https://${SUPPORT_HOST}/oauth2/callback"
echo "  - post logout redirect: https://${SUPPORT_HOST}/"
echo "  - groups claim mapper: groups"
echo "  - Support Tools administrator group: $SUPPORT_ADMIN_GROUP"
echo "  - General workforce group: $EMPLOYEES_GROUP"
echo "  - Restricted application groups: ${APPLICATION_GROUPS[*]}"
echo "Done. Client '$PROVISIONING_CLIENT_ID' has read-only user/group query roles."
echo "Done. Client '$GUAC_CLIENT_ID' now allows:"
echo "  - https://${REMOTE_HOST}/guacamole/"
echo "Done. Client '$BOOKSTACK_CLIENT_ID' now allows:"
echo "  - https://${DOCS_HOST}/oidc/callback"
echo "Done. Client '$OSTICKET_CLIENT_ID' now allows:"
echo "  - https://${TICKETS_HOST}/api/auth/oauth2"
echo "Done. Client '$ESPOCRM_CLIENT_ID' now allows:"
echo "  - https://${CRM_HOST}/oauth-callback.php"
echo "Done. Retired client '$ORANGEHRM_CLIENT_ID' is disabled when present."
echo "Done. Client '$ERPNEXT_CLIENT_ID' now allows:"
echo "  - https://${ERP_HOST}/api/method/frappe.integrations.oauth2_logins.login_via_keycloak"
echo "Done. Client '$SEAFILE_CLIENT_ID' now allows:"
echo "  - https://${FILES_HOST}/oauth/callback/"
echo "Done. Client '$PENPOT_CLIENT_ID' now allows:"
echo "  - https://${PENPOT_HOST}/api/auth/oidc/callback"
echo "Done. Client '$NETBIRD_CLIENT_ID' now allows:"
echo "  - ${NETBIRD_OIDC_REDIRECT_URI}"
echo "  - post logout redirect: https://${NETBIRD_HOST}/oauth2/logout/callback"
