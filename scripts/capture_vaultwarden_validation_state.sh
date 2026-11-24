#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
ENV_FILE="${1:-.env}"
[[ -f "$ENV_FILE" ]] || { echo "Missing env file: $ENV_FILE" >&2; exit 1; }

env_get() {
  awk -F= -v k="$1" '$1==k {sub(/^[^=]*=/, "", $0); gsub(/^"|"$/, "", $0); print; exit}' "$ENV_FILE" | tr -d '\r'
}

VAULT_URL="$(env_get VAULTWARDEN_DOMAIN)"
[[ "$VAULT_URL" == https://* ]] || { echo "VAULTWARDEN_DOMAIN must use HTTPS" >&2; exit 1; }
VAULT_HOST="${VAULT_URL#https://}"
VAULT_HOST="${VAULT_HOST%%/*}"
show_cmd() { printf '\n$ %s\n' "$*"; }

printf 'Evidence execution UTC: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf 'Environment: production Vaultwarden service\n'
printf 'Redaction: administrative token, SMTP identity/password, vault data, account identifiers, and host paths are excluded.\n'

show_cmd "docker exec support-vaultwarden /vaultwarden --version"
docker exec support-vaultwarden /vaultwarden --version
show_cmd "docker inspect support-vaultwarden --format '{{.Config.Image}}'"
docker inspect support-vaultwarden --format '{{.Config.Image}}'
show_cmd "docker port support-vaultwarden"
ports="$(docker port support-vaultwarden)"; [[ -n "$ports" ]] && echo "$ports" || echo '<no host-published ports>'
show_cmd "docker inspect support-vaultwarden --format '{{range .Mounts}}{{.Type}} {{.Name}} -> {{.Destination}} rw={{.RW}}{{println}}{{end}}'"
docker inspect support-vaultwarden --format '{{range .Mounts}}{{.Type}} {{.Name}} -> {{.Destination}} rw={{.RW}}{{println}}{{end}}'

show_cmd "docker inspect support-vaultwarden --format '{{json .Config.Env}}' | verify selected controls without printing secrets"
docker inspect support-vaultwarden --format '{{json .Config.Env}}' | python3 -c '
import json, sys
values=dict(item.split("=",1) for item in json.load(sys.stdin) if "=" in item)
print("DOMAIN="+values.get("DOMAIN",""))
print("SIGNUPS_ALLOWED="+values.get("SIGNUPS_ALLOWED",""))
print("INVITATIONS_ALLOWED="+values.get("INVITATIONS_ALLOWED",""))
admin=values.get("ADMIN_TOKEN","")
print("ADMIN_TOKEN_CONFIGURED="+str(bool(admin)).lower())
print("ADMIN_TOKEN_ARGON2ID="+str(admin.startswith("$argon2id$")).lower())
print("SMTP_HOST_CONFIGURED="+str(bool(values.get("SMTP_HOST",""))).lower())
print("SMTP_USERNAME_CONFIGURED="+str(bool(values.get("SMTP_USERNAME",""))).lower())
print("SMTP_PASSWORD_CONFIGURED="+str(bool(values.get("SMTP_PASSWORD",""))).lower())
print("SMTP_FROM_CONFIGURED="+str(bool(values.get("SMTP_FROM",""))).lower())
'
show_cmd "stat -c '%a %U:%G <ENV_FILE>' <ENV_FILE>"
stat -c '%a %U:%G <ENV_FILE>' "$ENV_FILE"

show_cmd "curl -fsS $VAULT_URL/api/config | python3 -c 'print selected public configuration fields as JSON'"
curl -fsS "$VAULT_URL/api/config" | python3 -c '
import json, sys
x=json.load(sys.stdin)
print(json.dumps({
  "environment": {key:x["environment"].get(key) for key in ("vault","api","identity","notifications")},
  "settings": {"disableUserRegistration":x["settings"].get("disableUserRegistration")},
  "server": {"name":x["server"].get("name")},
}, indent=2, sort_keys=True))
'

show_cmd "curl -sS -o /dev/null -w '%{http_code}' $VAULT_URL/api/sync"
status="$(curl -sS -o /dev/null -w '%{http_code}' "$VAULT_URL/api/sync")"; printf 'HTTP %s\n' "$status"; [[ "$status" == 401 ]]
for path in /data/db.sqlite3 /db.sqlite3 /config.json; do
  show_cmd "curl -sS -o /dev/null -w '%{http_code}' $VAULT_URL$path"
  status="$(curl -sS -o /dev/null -w '%{http_code}' "$VAULT_URL$path")"; printf 'HTTP %s\n' "$status"; [[ "$status" == 404 ]]
done
show_cmd "curl -sS -o /dev/null -w '%{http_code}' $VAULT_URL/admin/diagnostics"
status="$(curl -sS -o /dev/null -w '%{http_code}' "$VAULT_URL/admin/diagnostics")"; printf 'HTTP %s\n' "$status"; [[ "$status" == 401 ]]

show_cmd "curl -sS -D - -o /dev/null http://$VAULT_HOST/"
curl -sS -D - -o /dev/null "http://$VAULT_HOST/" | sed -n '1,8p'
show_cmd "openssl s_client -connect $VAULT_HOST:443 -servername $VAULT_HOST -verify_return_error </dev/null 2>&1 | grep -E 'subject=|issuer=|Verification:|Verify return code'"
openssl s_client -connect "$VAULT_HOST:443" -servername "$VAULT_HOST" -verify_return_error </dev/null 2>&1 | grep -E 'subject=|issuer=|Verification:|Verify return code'

show_cmd "test -f docs/vaultwarden_operations.md"
test -f docs/vaultwarden_operations.md
echo 'Exit code: 0'
show_cmd "grep required operating topics in docs/vaultwarden_operations.md"
for topic in 'Do not place' 'Offboarding' 'synchronized to an offline' 'Backup and restore' 'Updates' 'Organization sharing' 'Recovery'; do
  grep -qi "$topic" docs/vaultwarden_operations.md
  printf '%s: documented\n' "$topic"
done

echo 'Overall result: PASSED'
