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
SSO_HOST="$(env_get SSO_HOST)"; ERP_HOST="$(env_get ERP_HOST)"
ADMIN_USER="$(env_get KEYCLOAK_ADMIN_USER)"; ADMIN_PASSWORD="$(env_get KEYCLOAK_ADMIN_PASSWORD)"
[[ -n "$SSO_HOST" && -n "$ERP_HOST" && -n "$ADMIN_USER" && -n "$ADMIN_PASSWORD" ]] || exit 1
DC=(docker compose --env-file "$ENV_FILE")
KCADM=("${DC[@]}" exec -T keycloak /opt/keycloak/bin/kcadm.sh)
kc() { "${KCADM[@]}" "$@" </dev/null; }
show_cmd() { printf '\n$ %s\n' "$*"; }

printf 'Evidence execution UTC: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf 'Environment: production support stack\n'
printf 'Redaction: administrator credential, generated IDs, usernames, emails, tokens, and secrets are excluded or replaced.\n'

show_cmd "docker compose --env-file <ENV_FILE> exec -T keycloak kcadm.sh config credentials --server http://localhost:8080 --realm master --user <ADMIN_USER> --password <REDACTED>"
kc config credentials --server http://localhost:8080 --realm master --user "$ADMIN_USER" --password "$ADMIN_PASSWORD" >/dev/null
echo 'Exit code: 0'

printf '\n=== Runtime baseline ===\n'
show_cmd "docker compose --env-file <ENV_FILE> exec -T keycloak /opt/keycloak/bin/kc.sh --version"
"${DC[@]}" exec -T keycloak /opt/keycloak/bin/kc.sh --version </dev/null
show_cmd "docker compose --env-file <ENV_FILE> exec -T keycloak-db postgres --version"
"${DC[@]}" exec -T keycloak-db postgres --version </dev/null
show_cmd "docker inspect support-keycloak --format '{{.Config.Image}}'"
docker inspect support-keycloak --format '{{.Config.Image}}'
show_cmd "docker inspect support-keycloak --format '{{json .Config.Cmd}}'"
docker inspect support-keycloak --format '{{json .Config.Cmd}}'
show_cmd "docker port support-keycloak"
ports="$(docker port support-keycloak)"; [[ -n "$ports" ]] && echo "$ports" || echo '<no host-published ports>'
show_cmd "docker logs support-keycloak 2>&1 | grep -E 'Profile .* activated|Running the server in development mode' | tail -n 5"
docker logs support-keycloak 2>&1 | grep -E 'Profile .* activated|Running the server in development mode' | tail -n 5 || true
show_cmd "docker compose --env-file <ENV_FILE> ps keycloak keycloak-db erpnext-backend erpnext-db"
"${DC[@]}" ps keycloak keycloak-db erpnext-backend erpnext-db

printf '\n=== Realm security controls ===\n'
show_cmd "kcadm.sh get realms/$REALM --fields realm,defaultSignatureAlgorithm,accessTokenLifespan,ssoSessionIdleTimeout,ssoSessionMaxLifespan,offlineSessionIdleTimeout,enabled,sslRequired,registrationAllowed,rememberMe,verifyEmail,bruteForceProtected,failureFactor"
kc get "realms/$REALM" --fields realm,defaultSignatureAlgorithm,accessTokenLifespan,ssoSessionIdleTimeout,ssoSessionMaxLifespan,offlineSessionIdleTimeout,enabled,sslRequired,registrationAllowed,rememberMe,verifyEmail,bruteForceProtected,failureFactor
show_cmd "kcadm.sh get authentication/required-actions/CONFIGURE_TOTP -r $REALM --fields alias,enabled,defaultAction"
kc get authentication/required-actions/CONFIGURE_TOTP -r "$REALM" --fields alias,enabled,defaultAction

printf '\n=== Authentication flow ===\n'
show_cmd "kcadm.sh get realms/$REALM --fields browserFlow,directGrantFlow,resetCredentialsFlow,clientAuthenticationFlow"
kc get "realms/$REALM" --fields browserFlow,directGrantFlow,resetCredentialsFlow,clientAuthenticationFlow
show_cmd "kcadm.sh get authentication/flows/browser/executions -r $REALM --fields requirement,displayName,providerId,authenticationFlow,level,index"
kc get authentication/flows/browser/executions -r "$REALM" --fields requirement,displayName,providerId,authenticationFlow,level,index

printf '\n=== Privileged MFA and delegated roles ===\n'
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
show_cmd "kcadm.sh get groups -r $REALM --fields id,name"
kc get groups -r "$REALM" --fields id,name >"$work/groups.json"
python3 - "$work/groups.json" <<'PY'
import json,sys
names=sorted(x['name'] for x in json.load(open(sys.argv[1])))
print('Response group names: '+', '.join(names))
PY
for group in platform-admin support-engineer; do
  gid="$(python3 - "$work/groups.json" "$group" <<'PY'
import json,sys
print(next(x['id'] for x in json.load(open(sys.argv[1])) if x['name']==sys.argv[2]))
PY
)"
  show_cmd "kcadm.sh get groups/<${group^^}_GROUP_ID>/members -r $REALM --fields id,enabled,requiredActions"
  kc get "groups/$gid/members" -r "$REALM" --fields id,enabled,requiredActions >"$work/$group-members.json"
  python3 - "$work/$group-members.json" "$group" <<'PY'
import json,sys
x=json.load(open(sys.argv[1])); g=sys.argv[2]
print(f'{g}_members={len(x)}')
print(f'{g}_enabled={sum(bool(u.get("enabled")) for u in x)}')
print(f'{g}_totp_actions_pending={sum("CONFIGURE_TOTP" in (u.get("requiredActions") or []) for u in x)}')
PY
  : >"$work/$group-creds.jsonl"
  while IFS= read -r uid; do
    show_cmd "kcadm.sh get users/<USER_ID>/credentials -r $REALM --fields type"
    kc get "users/$uid/credentials" -r "$REALM" --fields type >>"$work/$group-creds.jsonl"; echo >>"$work/$group-creds.jsonl"
  done < <(python3 - "$work/$group-members.json" <<'PY'
import json,sys
for x in json.load(open(sys.argv[1])): print(x['id'])
PY
)
  python3 - "$work/$group-creds.jsonl" "$group" <<'PY'
import sys
s=open(sys.argv[1]).read(); print(f'{sys.argv[2]}_otp_credentials={s.count(chr(34)+"type"+chr(34)+" : "+chr(34)+"otp"+chr(34))}')
PY
done
rm_client="$(kc get clients -r "$REALM" -q clientId=realm-management --fields id | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["id"])')"
pa_gid="$(python3 - "$work/groups.json" <<'PY'
import json,sys
print(next(x['id'] for x in json.load(open(sys.argv[1])) if x['name']=='platform-admin'))
PY
)"
show_cmd "kcadm.sh get groups/<PLATFORM_ADMIN_GROUP_ID>/role-mappings/clients/<REALM_MANAGEMENT_CLIENT_ID> -r $REALM --fields name"
kc get "groups/$pa_gid/role-mappings/clients/$rm_client" -r "$REALM" --fields name >"$work/roles.json"
python3 - "$work/roles.json" <<'PY'
import json,sys
names=sorted(x['name'] for x in json.load(open(sys.argv[1])))
print('delegated_role_count='+str(len(names)))
print('delegated_roles='+','.join(names))
print('realm_admin_assigned='+str('realm-admin' in names).lower())
print('impersonation_assigned='+str('impersonation' in names).lower())
PY

printf '\n=== Clock and session baseline ===\n'
show_cmd "timedatectl show --property=NTPSynchronized --value"
timedatectl show --property=NTPSynchronized --value
show_cmd "host_epoch=\$(date -u +%s); container_epoch=\$(docker exec support-keycloak date -u +%s); echo host_epoch=<VALUE> container_epoch=<VALUE> delta_seconds=<VALUE>"
host_epoch="$(date -u +%s)"; container_epoch="$(docker exec support-keycloak date -u +%s)"; delta=$((host_epoch-container_epoch)); (( delta < 0 )) && delta=$((-delta))
printf 'host_epoch=%s container_epoch=%s delta_seconds=%s\n' "$host_epoch" "$container_epoch" "$delta"

printf '\n=== Public exposure and TLS ===\n'
show_cmd "curl -fsS https://$SSO_HOST/realms/$REALM/.well-known/openid-configuration | python3 -c 'import json,sys; x=json.load(sys.stdin); [print(f\"{k}={x[k]}\") for k in (\"issuer\",\"authorization_endpoint\",\"token_endpoint\",\"jwks_uri\")]'"
curl -fsS "https://$SSO_HOST/realms/$REALM/.well-known/openid-configuration" | python3 -c 'import json,sys; x=json.load(sys.stdin); [print(f"{k}={x[k]}") for k in ("issuer","authorization_endpoint","token_endpoint","jwks_uri")]'
show_cmd "curl -sS -D - -o /dev/null http://$SSO_HOST/realms/$REALM/.well-known/openid-configuration"
curl -sS -D - -o /dev/null "http://$SSO_HOST/realms/$REALM/.well-known/openid-configuration" | sed -n '1,8p'
show_cmd "openssl s_client -connect $SSO_HOST:443 -servername $SSO_HOST -verify_return_error </dev/null 2>&1 | grep -E 'subject=|issuer=|Verification:|Verify return code'"
openssl s_client -connect "$SSO_HOST:443" -servername "$SSO_HOST" -verify_return_error </dev/null 2>&1 | grep -E 'subject=|issuer=|Verification:|Verify return code'

printf '\n=== Exact managed-client callbacks ===\n'
clients=(support-portal guacamole bookstack osticket espocrm erpnext seafile penpot netbird)
http_count=0; wildcard_count=0
for client in "${clients[@]}"; do
  show_cmd "kcadm.sh get clients -r $REALM -q clientId=$client --fields clientId,redirectUris,webOrigins"
  kc get clients -r "$REALM" -q "clientId=$client" --fields clientId,redirectUris,webOrigins >"$work/client.json"
  cat "$work/client.json"
  read -r h w < <(python3 - "$work/client.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1]))[0]; v=x.get('redirectUris',[])+x.get('webOrigins',[])
print(sum(y.startswith('http://') for y in v),sum('*' in y for y in v))
PY
)
  http_count=$((http_count+h)); wildcard_count=$((wildcard_count+w))
done
printf 'managed_client_http_entries=%s\nmanaged_client_wildcard_entries=%s\n' "$http_count" "$wildcard_count"
[[ "$http_count" == 0 && "$wildcard_count" == 0 ]]

auth="https://$SSO_HOST/realms/$REALM/protocol/openid-connect/auth"
check_redirect() {
  local client="$1" uri="$2" good bad
  show_cmd "curl -sS -o /dev/null -w '%{http_code}' --get $auth --data-urlencode client_id=$client --data-urlencode response_type=code --data-urlencode scope=openid --data-urlencode redirect_uri=$uri"
  good="$(curl -sS -o /dev/null -w '%{http_code}' --get "$auth" --data-urlencode "client_id=$client" --data-urlencode response_type=code --data-urlencode scope=openid --data-urlencode "redirect_uri=$uri")"
  printf 'HTTP %s\n' "$good"
  show_cmd "curl -sS -o /dev/null -w '%{http_code}' --get $auth --data-urlencode client_id=$client --data-urlencode response_type=code --data-urlencode scope=openid --data-urlencode redirect_uri=${uri%/}-invalid"
  bad="$(curl -sS -o /dev/null -w '%{http_code}' --get "$auth" --data-urlencode "client_id=$client" --data-urlencode response_type=code --data-urlencode scope=openid --data-urlencode "redirect_uri=${uri%/}-invalid")"
  printf 'HTTP %s\n' "$bad"
  { [[ "$good" == 200 ]] || [[ "$good" == 302 ]]; } && [[ "$bad" == 400 ]]
}
check_redirect support-portal 'https://internal-support.bonescreen.de/oauth2/callback'
check_redirect guacamole 'https://remote.internal-support.bonescreen.de/guacamole/'
check_redirect bookstack 'https://docs.internal-support.bonescreen.de/oidc/callback'
check_redirect osticket 'https://tickets.internal-support.bonescreen.de/api/auth/oauth2'
check_redirect espocrm 'https://crm.internal-support.bonescreen.de/oauth-callback.php'
check_redirect erpnext 'https://erp.internal-support.bonescreen.de/api/method/frappe.integrations.oauth2_logins.login_via_keycloak'
check_redirect seafile 'https://files.internal-support.bonescreen.de/oauth/callback/'
check_redirect penpot 'https://penpot.internal-support.bonescreen.de/api/auth/oidc/callback'
check_redirect netbird 'https://mesh.internal-support.bonescreen.de/oauth2/callback/keycloak-daohd4p1qqbc73bvu0ig'

printf '\n=== Frappe HR / ERPNext runtime ===\n'
show_cmd "curl -fsS https://$ERP_HOST/api/method/ping"
curl -fsS "https://$ERP_HOST/api/method/ping"
show_cmd "docker compose --env-file <ENV_FILE> exec -T erpnext-backend bench --site <SITE> list-apps"
"${DC[@]}" exec -T erpnext-backend bench --site "$(env_get ERPNEXT_SITE_NAME)" list-apps

rm -rf "$work"; trap - EXIT
echo 'Overall result: PASSED'
