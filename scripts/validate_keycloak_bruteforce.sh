#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT_DIR"
ENV_FILE="${1:-.env}"; [[ -f "$ENV_FILE" ]] || exit 1
env_get(){ awk -F= -v k="$1" '$1==k {sub(/^[^=]*=/,"",$0); gsub(/^"|"$/,"",$0); print; exit}' "$ENV_FILE" | tr -d '\r'; }
REALM="$(env_get KEYCLOAK_REALM)"; REALM="${REALM:-support}"; SSO_HOST="$(env_get SSO_HOST)"
ADMIN_USER="$(env_get KEYCLOAK_ADMIN_USER)"; ADMIN_PASSWORD="$(env_get KEYCLOAK_ADMIN_PASSWORD)"
DC=(docker compose --env-file "$ENV_FILE"); KCADM=("${DC[@]}" exec -T keycloak /opt/keycloak/bin/kcadm.sh)
kc(){ "${KCADM[@]}" "$@" </dev/null; }; show_cmd(){ printf '\n$ %s\n' "$*"; }
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"; CLIENT="kc-brute-${STAMP,,}"; USER="kc-brute-${STAMP,,}"
PASSWORD="$(openssl rand -base64 24 | tr -d '\n')Aa1!"; TOKEN_URL="https://$SSO_HOST/realms/$REALM/protocol/openid-connect/token"
WORK="$(mktemp -d)"; CID=''; UID_KC=''
cleanup(){ [[ -n "$UID_KC" ]] && kc delete "users/$UID_KC" -r "$REALM" >/dev/null 2>&1 || true; [[ -n "$CID" ]] && kc delete "clients/$CID" -r "$REALM" >/dev/null 2>&1 || true; rm -rf "$WORK"; }
trap cleanup EXIT
post(){ curl -sS -o "$2" -w '%{http_code}' -X POST "$TOKEN_URL" -d grant_type=password -d "client_id=$CLIENT" -d "username=$USER" --data-urlencode "password=$1"; }

printf 'Evidence execution UTC: %s\nEnvironment: production support realm; dedicated temporary objects\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo 'Redaction: administrator password, test password, tokens, generated IDs, username, and email are replaced.'
show_cmd "docker compose --env-file <ENV_FILE> exec -T keycloak kcadm.sh config credentials --server http://localhost:8080 --realm master --user <ADMIN_USER> --password <REDACTED>"
kc config credentials --server http://localhost:8080 --realm master --user "$ADMIN_USER" --password "$ADMIN_PASSWORD" >/dev/null; echo 'Exit code: 0'
show_cmd "kcadm.sh create clients -r $REALM -s clientId=<TEMP_CLIENT> -s enabled=true -s publicClient=true -s directAccessGrantsEnabled=true -s standardFlowEnabled=false -i"
CID="$(kc create clients -r "$REALM" -s "clientId=$CLIENT" -s enabled=true -s publicClient=true -s directAccessGrantsEnabled=true -s standardFlowEnabled=false -i)"; echo 'Response: created; client ID <REDACTED_ID>'
show_cmd "kcadm.sh create users -r $REALM -s username=<TEMP_USER> -s email=<SYNTHETIC_EMAIL> -s firstName=Validation -s lastName=User -s emailVerified=true -s enabled=true -i"
UID_KC="$(kc create users -r "$REALM" -s "username=$USER" -s "email=$USER@example.invalid" -s firstName=Validation -s lastName=User -s emailVerified=true -s enabled=true -i)"; echo 'Response: created; user ID <REDACTED_ID>'
show_cmd "kcadm.sh update users/<USER_ID> -r $REALM -s 'requiredActions=[]'"
kc update "users/$UID_KC" -r "$REALM" -s 'requiredActions=[]' >/dev/null; echo 'Exit code: 0'
show_cmd "kcadm.sh set-password -r $REALM --userid <USER_ID> --new-password <REDACTED> --temporary=false"
kc set-password -r "$REALM" --userid "$UID_KC" --new-password "$PASSWORD" --temporary=false >/dev/null; echo 'Exit code: 0'
show_cmd "curl -sS -o <TEMP_RESPONSE> -w '%{http_code}' -X POST $TOKEN_URL -d grant_type=password -d client_id=<TEMP_CLIENT> -d username=<TEMP_USER> --data-urlencode password=<CORRECT_PASSWORD>"
status="$(post "$PASSWORD" "$WORK/baseline.json")"; printf 'HTTP %s\n' "$status"; [[ "$status" == 200 ]]; echo '{ "access_token": "<REDACTED_TOKEN>" }'
for n in 1 2 3 4 5; do
  show_cmd "curl -sS -o <TEMP_RESPONSE> -w '%{http_code}' -X POST $TOKEN_URL -d grant_type=password -d client_id=<TEMP_CLIENT> -d username=<TEMP_USER> --data-urlencode password=<INCORRECT_PASSWORD_$n>"
  status="$(post "incorrect-$n" "$WORK/wrong-$n.json")"; printf 'HTTP %s\n' "$status"; cat "$WORK/wrong-$n.json"; echo; [[ "$status" == 400 ]]
done
show_cmd "kcadm.sh get attack-detection/brute-force/users/<USER_ID> -r $REALM --fields disabled,numFailures"
kc get "attack-detection/brute-force/users/$UID_KC" -r "$REALM" --fields disabled,numFailures >"$WORK/attack.json"; cat "$WORK/attack.json"
disabled="$(python3 -c 'import json,sys; print(str(bool(json.load(open(sys.argv[1])).get("disabled"))).lower())' "$WORK/attack.json")"; [[ "$disabled" == true ]]
show_cmd "curl -sS -o <TEMP_RESPONSE> -w '%{http_code}' -X POST $TOKEN_URL -d grant_type=password -d client_id=<TEMP_CLIENT> -d username=<TEMP_USER> --data-urlencode password=<CORRECT_PASSWORD> # while locked"
status="$(post "$PASSWORD" "$WORK/locked.json")"; printf 'HTTP %s\n' "$status"; cat "$WORK/locked.json"; echo; [[ "$status" == 400 ]]
show_cmd "kcadm.sh delete attack-detection/brute-force/users/<USER_ID> -r $REALM"
kc delete "attack-detection/brute-force/users/$UID_KC" -r "$REALM" >/dev/null; echo 'Exit code: 0'
show_cmd "curl -sS -o <TEMP_RESPONSE> -w '%{http_code}' -X POST $TOKEN_URL -d grant_type=password -d client_id=<TEMP_CLIENT> -d username=<TEMP_USER> --data-urlencode password=<CORRECT_PASSWORD> # after unlock"
status="$(post "$PASSWORD" "$WORK/recovered.json")"; printf 'HTTP %s\n' "$status"; [[ "$status" == 200 ]]; echo '{ "access_token": "<REDACTED_TOKEN>" }'
show_cmd "kcadm.sh delete users/<USER_ID> -r $REALM; kcadm.sh delete clients/<CLIENT_ID> -r $REALM"
cleanup; trap - EXIT; UID_KC=''; CID=''; echo 'Exit code: 0'
show_cmd "kcadm.sh get users -r $REALM -q username=<TEMP_USER>; kcadm.sh get clients -r $REALM -q clientId=<TEMP_CLIENT>"
users_left="$(kc get users -r "$REALM" -q "username=$USER" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')"
clients_left="$(kc get clients -r "$REALM" -q "clientId=$CLIENT" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')"
printf 'temporary_users_remaining=%s\ntemporary_clients_remaining=%s\n' "$users_left" "$clients_left"; [[ "$users_left" == 0 && "$clients_left" == 0 ]]
echo 'Overall result: PASSED'
