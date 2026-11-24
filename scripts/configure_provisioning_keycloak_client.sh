#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="${1:-.env}"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing env file: $ENV_FILE" >&2
  exit 1
fi

env_get() {
  local key="$1"
  local default_value="${2:-}"
  local value
  value="$(grep -E "^${key}=" "$ENV_FILE" | tail -n 1 | cut -d= -f2- || true)"
  printf '%s' "${value:-$default_value}"
}

dc() {
  docker compose --env-file "$ENV_FILE" "$@"
}

REALM="$(env_get KEYCLOAK_REALM support)"
ADMIN_USER="$(env_get KEYCLOAK_ADMIN_USER)"
ADMIN_PASSWORD="$(env_get KEYCLOAK_ADMIN_PASSWORD)"
CLIENT_ID="$(env_get PROVISIONING_KEYCLOAK_CLIENT_ID support-tools-provisioning)"
CLIENT_SECRET="$(env_get PROVISIONING_KEYCLOAK_CLIENT_SECRET)"
REQUIRED_ROLES=(view-users query-users query-groups)

if [[ -z "$ADMIN_USER" || -z "$ADMIN_PASSWORD" ]]; then
  echo "KEYCLOAK_ADMIN_USER and KEYCLOAK_ADMIN_PASSWORD are required" >&2
  exit 1
fi
if [[ ${#CLIENT_SECRET} -lt 32 || "$CLIENT_SECRET" == replace-with-* ]]; then
  echo "PROVISIONING_KEYCLOAK_CLIENT_SECRET must contain at least 32 characters" >&2
  exit 1
fi

echo "==> Authenticating to Keycloak"
dc exec -T keycloak /opt/keycloak/bin/kcadm.sh config credentials \
  --server http://localhost:8080 \
  --realm master \
  --user "$ADMIN_USER" \
  --password "$ADMIN_PASSWORD" >/dev/null

client_uuid="$({
  dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get clients -r "$REALM" \
    -q "clientId=$CLIENT_ID" --fields id --format csv --noquotes
} | tr -d '\r' | tail -n 1)"

if [[ -z "$client_uuid" || "$client_uuid" == id ]]; then
  echo "==> Creating read-only provisioning client"
  dc exec -T keycloak /opt/keycloak/bin/kcadm.sh create clients -r "$REALM" \
    -s "clientId=$CLIENT_ID" \
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
    -s "secret=$CLIENT_SECRET" >/dev/null
  client_uuid="$({
    dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get clients -r "$REALM" \
      -q "clientId=$CLIENT_ID" --fields id --format csv --noquotes
  } | tr -d '\r' | tail -n 1)"
else
  echo "==> Enforcing provisioning client controls"
  dc exec -T keycloak /opt/keycloak/bin/kcadm.sh update "clients/$client_uuid" -r "$REALM" \
    -s enabled=true \
    -s publicClient=false \
    -s standardFlowEnabled=false \
    -s implicitFlowEnabled=false \
    -s directAccessGrantsEnabled=false \
    -s serviceAccountsEnabled=true \
    -s authorizationServicesEnabled=false \
    -s fullScopeAllowed=false \
    -s "secret=$CLIENT_SECRET" >/dev/null
fi

if [[ -z "$client_uuid" || "$client_uuid" == id ]]; then
  echo "Unable to create or locate provisioning client" >&2
  exit 1
fi

service_account="service-account-${CLIENT_ID}"
realm_management_uuid="$({
  dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get clients -r "$REALM" \
    -q clientId=realm-management --fields id --format csv --noquotes
} | tr -d '\r' | tail -n 1)"
if [[ -z "$realm_management_uuid" || "$realm_management_uuid" == id ]]; then
  echo "Unable to locate realm-management client" >&2
  exit 1
fi

echo "==> Assigning approved read-only roles"
for role in "${REQUIRED_ROLES[@]}"; do
  if ! dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get-roles -r "$REALM" \
    --uusername "$service_account" --cclientid realm-management \
    --fields name --format csv --noquotes | tr -d '\r' | grep -qx "$role"; then
    dc exec -T keycloak /opt/keycloak/bin/kcadm.sh add-roles -r "$REALM" \
      --uusername "$service_account" \
      --cclientid realm-management \
      --rolename "$role" >/dev/null
  fi
done

scope_body='['
separator=''
for role in "${REQUIRED_ROLES[@]}"; do
  role_uuid="$({
    dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get \
      "clients/$realm_management_uuid/roles/$role" -r "$REALM" \
      --fields id --format csv --noquotes
  } | tr -d '\r' | tail -n 1)"
  scope_body="${scope_body}${separator}{\"id\":\"${role_uuid}\",\"name\":\"${role}\"}"
  separator=','
done
scope_body="${scope_body}]"
dc exec -T keycloak /opt/keycloak/bin/kcadm.sh create \
  "clients/$client_uuid/scope-mappings/clients/$realm_management_uuid" \
  -r "$REALM" -b "$scope_body" >/dev/null

assigned_roles="$({
  dc exec -T keycloak /opt/keycloak/bin/kcadm.sh get-roles -r "$REALM" \
    --uusername "$service_account" --cclientid realm-management \
    --fields name --format csv --noquotes
} | tr -d '\r' | sort -u)"
for role in $assigned_roles; do
  case " ${REQUIRED_ROLES[*]} " in
    *" $role "*) ;;
    *)
      echo "Unexpected realm-management role assigned to provisioning account: $role" >&2
      exit 1
      ;;
  esac
done

echo "Provisioning Keycloak client is configured with approved read-only roles only."
