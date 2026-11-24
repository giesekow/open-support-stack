#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="${1:-.env}"
[[ -f "$ENV_FILE" ]] || { echo "Missing env file: $ENV_FILE" >&2; exit 1; }

env_get() {
  awk -F= -v k="$1" '$1==k {sub(/^[^=]*=/, "", $0); gsub(/^"|"$/, "", $0); print; exit}' "$ENV_FILE" | tr -d '\r'
}

REALM="$(env_get KEYCLOAK_REALM)"; REALM="${REALM:-support}"
SSO_HOST="$(env_get SSO_HOST)"
ADMIN_USER="$(env_get KEYCLOAK_ADMIN_USER)"
ADMIN_PASSWORD="$(env_get KEYCLOAK_ADMIN_PASSWORD)"
[[ -n "$SSO_HOST" && -n "$ADMIN_USER" && -n "$ADMIN_PASSWORD" ]] || {
  echo "Missing SSO_HOST or Keycloak administrator credentials in $ENV_FILE" >&2
  exit 1
}

DC=(docker compose --env-file "$ENV_FILE")
KCADM=("${DC[@]}" exec -T keycloak /opt/keycloak/bin/kcadm.sh)
kc() { "${KCADM[@]}" "$@" </dev/null; }
show_cmd() { printf '\n$ %s\n' "$*"; }

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
CLIENT="kc-e02-${STAMP,,}"
USER="kc-e02-${STAMP,,}"
GROUP="kc-e02-${STAMP,,}"
PASSWORD="$(openssl rand -base64 24 | tr -d '\n')Aa1!"
OLD_SECRET="$(openssl rand -hex 32)"
NEW_SECRET="$(openssl rand -hex 32)"
TOKEN_URL="https://${SSO_HOST}/realms/${REALM}/protocol/openid-connect/token"
INTROSPECT_URL="https://${SSO_HOST}/realms/${REALM}/protocol/openid-connect/token/introspect"
ADMIN_URL="https://${SSO_HOST}/admin/realms/${REALM}"
WORK="$(mktemp -d)"
CID=""; UID_KC=""; GID=""

cleanup() {
  [[ -n "$UID_KC" ]] && kc delete "users/$UID_KC" -r "$REALM" >/dev/null 2>&1 || true
  [[ -n "$CID" ]] && kc delete "clients/$CID" -r "$REALM" >/dev/null 2>&1 || true
  [[ -n "$GID" ]] && kc delete "groups/$GID" -r "$REALM" >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

request_token() {
  local password="$1" secret="$2" output="$3"
  curl -sS -o "$output" -w '%{http_code}' -X POST "$TOKEN_URL" \
    -d grant_type=password -d "client_id=$CLIENT" -d "client_secret=$secret" \
    -d "username=$USER" --data-urlencode "password=$password"
}

request_client_token() {
  local secret="$1" output="$2"
  curl -sS -o "$output" -w '%{http_code}' -X POST "$TOKEN_URL" \
    -d grant_type=client_credentials -d "client_id=$CLIENT" -d "client_secret=$secret"
}

json_token_summary() {
  python3 - "$1" <<'PY'
import json, sys
x=json.load(open(sys.argv[1]))
print('{')
print('  "access_token": "<REDACTED>",')
print(f'  "expires_in": {x.get("expires_in")},')
print(f'  "token_type": "{x.get("token_type")}"')
print('}')
PY
}

token_claim_has_group() {
  python3 - "$1" "$GROUP" <<'PY'
import base64, json, sys
x=json.load(open(sys.argv[1]))['access_token'].split('.')[1]
x += '=' * (-len(x) % 4)
claims=json.loads(base64.urlsafe_b64decode(x))
groups=claims.get('groups', [])
expected=sys.argv[2]
print(str(any(g == expected or g.endswith('/'+expected) for g in groups)).lower())
PY
}

printf 'Evidence execution UTC: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf 'Environment: production support realm; dedicated temporary objects\n'
printf 'Redaction: passwords, client secrets, tokens, generated IDs, and synthetic names are replaced by placeholders.\n'

show_cmd "docker compose --env-file <ENV_FILE> exec -T keycloak kcadm.sh config credentials --server http://localhost:8080 --realm master --user <ADMIN_USER> --password <REDACTED>"
kc config credentials --server http://localhost:8080 --realm master --user "$ADMIN_USER" --password "$ADMIN_PASSWORD" >/dev/null
echo 'Exit code: 0'

show_cmd "kcadm.sh create clients -r $REALM -s clientId=<TEMP_CLIENT> -s publicClient=false -s directAccessGrantsEnabled=true -s serviceAccountsEnabled=true -s secret=<REDACTED> -i"
CID="$(kc create clients -r "$REALM" -s "clientId=$CLIENT" -s enabled=true -s publicClient=false -s directAccessGrantsEnabled=true -s standardFlowEnabled=false -s serviceAccountsEnabled=true -s "secret=$OLD_SECRET" -i)"
echo 'Response: created temporary confidential client; generated ID <REDACTED>'

show_cmd "kcadm.sh create clients/<CLIENT_ID>/protocol-mappers/models -r $REALM -s name=groups -s protocol=openid-connect -s protocolMapper=oidc-group-membership-mapper -s 'config.\"full.path\"=false' -s 'config.\"claim.name\"=groups' -s 'config.\"id.token.claim\"=true' -s 'config.\"access.token.claim\"=true' -s 'config.\"userinfo.token.claim\"=true'"
kc create "clients/$CID/protocol-mappers/models" -r "$REALM" \
  -s name=groups -s protocol=openid-connect -s protocolMapper=oidc-group-membership-mapper \
  -s 'config."full.path"=false' -s 'config."claim.name"=groups' \
  -s 'config."id.token.claim"=true' -s 'config."access.token.claim"=true' \
  -s 'config."userinfo.token.claim"=true' >/dev/null 2>&1
echo 'Response: Created new protocol mapper'

show_cmd "kcadm.sh create groups -r $REALM -s name=<TEMP_GROUP> -i"
GID="$(kc create groups -r "$REALM" -s "name=$GROUP" -i)"
echo 'Response: created temporary group; generated ID <REDACTED>'

show_cmd "kcadm.sh create users -r $REALM -s username=<TEMP_USER> -s email=<SYNTHETIC_EMAIL> -s firstName=Validation -s lastName=User -s emailVerified=true -s enabled=true -i"
UID_KC="$(kc create users -r "$REALM" -s "username=$USER" -s "email=$USER@example.invalid" -s firstName=Validation -s lastName=User -s emailVerified=true -s enabled=true -i)"
echo 'Response: created enabled temporary user; generated ID <REDACTED>'
show_cmd "kcadm.sh update users/<USER_ID> -r $REALM -s 'requiredActions=[]'"
kc update "users/$UID_KC" -r "$REALM" -s 'requiredActions=[]' >/dev/null
echo 'Exit code: 0'
show_cmd "kcadm.sh set-password -r $REALM --userid <USER_ID> --new-password <REDACTED> --temporary=false"
kc set-password -r "$REALM" --userid "$UID_KC" --new-password "$PASSWORD" --temporary=false >/dev/null
echo 'Exit code: 0'

show_cmd "kcadm.sh update users/<USER_ID>/groups/<GROUP_ID> -r $REALM -n"
kc update "users/$UID_KC/groups/$GID" -r "$REALM" -n >/dev/null
echo 'Exit code: 0'

show_cmd "curl -sS -X POST $TOKEN_URL -d grant_type=password -d client_id=<TEMP_CLIENT> -d client_secret=<REDACTED> -d username=<TEMP_USER> --data-urlencode password=<REDACTED>"
status="$(request_token "$PASSWORD" "$OLD_SECRET" "$WORK/user-before.json")"
printf 'HTTP %s\n' "$status"; json_token_summary "$WORK/user-before.json"; [[ "$status" == 200 ]]
claim_before="$(token_claim_has_group "$WORK/user-before.json")"
printf 'Decoded access-token assertion: groups contains <TEMP_GROUP> = %s\n' "$claim_before"; [[ "$claim_before" == true ]]

show_cmd "curl -sS -X POST $TOKEN_URL -d grant_type=password -d client_id=<TEMP_CLIENT> -d client_secret=<REDACTED> -d username=<TEMP_USER> --data-urlencode password=<INCORRECT_PASSWORD>"
status="$(request_token 'deliberately-wrong-password' "$OLD_SECRET" "$WORK/wrong.json")"
printf 'HTTP %s\n' "$status"; cat "$WORK/wrong.json"; echo; [[ "$status" == 400 || "$status" == 401 ]]

show_cmd "kcadm.sh delete users/<USER_ID>/groups/<GROUP_ID> -r $REALM"
kc delete "users/$UID_KC/groups/$GID" -r "$REALM" >/dev/null
echo 'Exit code: 0'
show_cmd "curl -sS -X POST $TOKEN_URL -d grant_type=password -d client_id=<TEMP_CLIENT> -d client_secret=<REDACTED> -d username=<TEMP_USER> --data-urlencode password=<REDACTED> # after group removal"
status="$(request_token "$PASSWORD" "$OLD_SECRET" "$WORK/user-after.json")"
printf 'HTTP %s\n' "$status"; [[ "$status" == 200 ]]
claim_after="$(token_claim_has_group "$WORK/user-after.json")"
printf 'Decoded access-token assertion: groups contains <TEMP_GROUP> = %s\n' "$claim_after"; [[ "$claim_after" == false ]]

show_cmd "curl -sS -X POST $TOKEN_URL -d grant_type=client_credentials -d client_id=<TEMP_CLIENT> -d client_secret=<OLD_SECRET>"
status="$(request_client_token "$OLD_SECRET" "$WORK/client-before.json")"
printf 'HTTP %s\n' "$status"; json_token_summary "$WORK/client-before.json"; [[ "$status" == 200 ]]

show_cmd "kcadm.sh update clients/<CLIENT_ID> -r $REALM -s secret=<NEW_SECRET>"
kc update "clients/$CID" -r "$REALM" -s "secret=$NEW_SECRET" >/dev/null
echo 'Exit code: 0'
show_cmd "curl -sS -X POST $TOKEN_URL -d grant_type=client_credentials -d client_id=<TEMP_CLIENT> -d client_secret=<OLD_SECRET>"
status="$(request_client_token "$OLD_SECRET" "$WORK/client-old.json")"
printf 'HTTP %s\n' "$status"; cat "$WORK/client-old.json"; echo; [[ "$status" == 400 || "$status" == 401 ]]
show_cmd "curl -sS -X POST $TOKEN_URL -d grant_type=client_credentials -d client_id=<TEMP_CLIENT> -d client_secret=<NEW_SECRET>"
status="$(request_client_token "$NEW_SECRET" "$WORK/client-new.json")"
printf 'HTTP %s\n' "$status"; json_token_summary "$WORK/client-new.json"; [[ "$status" == 200 ]]

show_cmd "curl -sS -o /dev/null -w '%{http_code}' $ADMIN_URL"
status="$(curl -sS -o "$WORK/no-auth.json" -w '%{http_code}' "$ADMIN_URL")"
printf 'HTTP %s\n' "$status"; [[ "$status" == 401 ]]

ordinary_token="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["access_token"])' "$WORK/user-after.json")"
show_cmd "curl -sS -o /dev/null -w '%{http_code}' -H 'Authorization: Bearer <REDACTED_TOKEN>' $ADMIN_URL"
status="$(curl -sS -o "$WORK/ordinary-admin.json" -w '%{http_code}' -H "Authorization: Bearer $ordinary_token" "$ADMIN_URL")"
printf 'HTTP %s\n' "$status"; [[ "$status" == 403 ]]

show_cmd "kcadm.sh get realms/$REALM --fields realm,enabled"
kc get "realms/$REALM" --fields realm,enabled | sed '/Logging into /d'
echo 'Exit code: 0'

show_cmd "kcadm.sh create users/<USER_ID>/logout -r $REALM"
kc create "users/$UID_KC/logout" -r "$REALM" >/dev/null
echo 'Exit code: 0'
show_cmd "kcadm.sh update users/<USER_ID> -r $REALM -s enabled=false"
kc update "users/$UID_KC" -r "$REALM" -s enabled=false >/dev/null
echo 'Exit code: 0'
show_cmd "curl -sS -X POST $TOKEN_URL -d grant_type=password -d client_id=<TEMP_CLIENT> -d client_secret=<NEW_SECRET> -d username=<TEMP_USER> --data-urlencode password=<REDACTED> # after disablement"
status="$(request_token "$PASSWORD" "$NEW_SECRET" "$WORK/disabled.json")"
printf 'HTTP %s\n' "$status"; cat "$WORK/disabled.json"; echo; [[ "$status" == 400 || "$status" == 401 ]]

show_cmd "curl -sS -X POST $INTROSPECT_URL -u '<TEMP_CLIENT>:<NEW_SECRET>' -d token=<REDACTED_TOKEN>"
status="$(curl -sS -o "$WORK/introspect.json" -w '%{http_code}' -X POST "$INTROSPECT_URL" -u "$CLIENT:$NEW_SECRET" --data-urlencode "token=$ordinary_token")"
printf 'HTTP %s\n' "$status"
active="$(python3 -c 'import json,sys; print(str(bool(json.load(open(sys.argv[1])).get("active"))).lower())' "$WORK/introspect.json")"
printf '{ "active": %s }\n' "$active"; [[ "$status" == 200 && "$active" == false ]]

show_cmd "kcadm.sh delete users/<USER_ID> -r $REALM; kcadm.sh delete clients/<CLIENT_ID> -r $REALM; kcadm.sh delete groups/<GROUP_ID> -r $REALM"
cleanup
trap - EXIT
UID_KC=""; CID=""; GID=""
echo 'Exit code: 0'

show_cmd "kcadm.sh get users -r $REALM -q username=<TEMP_USER>; kcadm.sh get clients -r $REALM -q clientId=<TEMP_CLIENT>; kcadm.sh get groups -r $REALM -q search=<TEMP_GROUP>"
users_left="$(kc get users -r "$REALM" -q "username=$USER" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')"
clients_left="$(kc get clients -r "$REALM" -q "clientId=$CLIENT" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')"
groups_left="$(kc get groups -r "$REALM" -q "search=$GROUP" | python3 -c 'import json,sys; n=sys.argv[1]; print(sum(x.get("name")==n for x in json.load(sys.stdin)))' "$GROUP")"
printf 'temporary_users_remaining=%s\ntemporary_clients_remaining=%s\ntemporary_groups_remaining=%s\n' "$users_left" "$clients_left" "$groups_left"
[[ "$users_left" == 0 && "$clients_left" == 0 && "$groups_left" == 0 ]]
echo 'Overall result: PASSED'
