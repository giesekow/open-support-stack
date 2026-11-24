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
ADMIN_USER="$(env_get KEYCLOAK_ADMIN_USER)"
ADMIN_PASSWORD="$(env_get KEYCLOAK_ADMIN_PASSWORD)"
[[ -n "$ADMIN_USER" && -n "$ADMIN_PASSWORD" ]] || { echo "Missing Keycloak administrator credentials" >&2; exit 1; }

DC=(docker compose --env-file "$ENV_FILE")
KCADM=("${DC[@]}" exec -T keycloak /opt/keycloak/bin/kcadm.sh)
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
CLIENTS=(support-portal guacamole bookstack osticket espocrm erpnext seafile penpot netbird)

show_cmd() { printf '\n$ %s\n' "$*"; }
kc() { "${KCADM[@]}" "$@" </dev/null; }

capture_state() {
  local output="$1" client
  : >"$WORK/clients.jsonl"
  for client in "${CLIENTS[@]}"; do
    kc get clients -r "$REALM" -q "clientId=$client" \
      --fields clientId,enabled,protocol,publicClient,standardFlowEnabled,directAccessGrantsEnabled,serviceAccountsEnabled,redirectUris,webOrigins \
      >>"$WORK/clients.jsonl"
    printf '\n' >>"$WORK/clients.jsonl"
  done
  python3 - "$WORK/clients.jsonl" "$output" <<'PY'
import json, sys
decoder=json.JSONDecoder()
text=open(sys.argv[1], encoding='utf-8').read()
objects=[]
index=0
while index < len(text):
    while index < len(text) and text[index].isspace():
        index += 1
    if index >= len(text):
        break
    value, index=decoder.raw_decode(text, index)
    objects.extend(value)
objects.sort(key=lambda item: item['clientId'])
with open(sys.argv[2], 'w', encoding='utf-8') as handle:
    json.dump(objects, handle, sort_keys=True, separators=(',', ':'))
    handle.write('\n')
print(f'captured_clients={len(objects)}')
PY
}

printf 'Evidence execution UTC: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf 'Environment: production support realm\n'
printf 'Redaction: administrator credentials and internal object IDs are excluded.\n'

show_cmd "docker compose --env-file <ENV_FILE> exec -T keycloak kcadm.sh config credentials --server http://localhost:8080 --realm master --user <ADMIN_USER> --password <REDACTED>"
kc config credentials --server http://localhost:8080 --realm master --user "$ADMIN_USER" --password "$ADMIN_PASSWORD" >/dev/null 2>&1
echo 'Exit code: 0'

show_cmd "capture normalized managed-client state before synchronization"
capture_state "$WORK/before.json"
before="$(sha256sum "$WORK/before.json" | awk '{print $1}')"
printf 'before_sha256=%s\n' "$before"

show_cmd "./scripts/sync_keycloak_redirects.sh <ENV_FILE>"
./scripts/sync_keycloak_redirects.sh "$ENV_FILE" 2>&1 | sed -E 's|Logging into ([^ ]+) as user .* of realm master|Logging into \1 as user <ADMIN_USER> of realm master|'
echo 'Exit code: 0'
show_cmd "capture normalized managed-client state after synchronization run 1"
capture_state "$WORK/after-1.json"
after1="$(sha256sum "$WORK/after-1.json" | awk '{print $1}')"
printf 'after_run_1_sha256=%s\n' "$after1"

show_cmd "./scripts/sync_keycloak_redirects.sh <ENV_FILE>"
./scripts/sync_keycloak_redirects.sh "$ENV_FILE" 2>&1 | sed -E 's|Logging into ([^ ]+) as user .* of realm master|Logging into \1 as user <ADMIN_USER> of realm master|'
echo 'Exit code: 0'
show_cmd "capture normalized managed-client state after synchronization run 2"
capture_state "$WORK/after-2.json"
after2="$(sha256sum "$WORK/after-2.json" | awk '{print $1}')"
printf 'after_run_2_sha256=%s\n' "$after2"

show_cmd "cmp -s <BEFORE_STATE> <AFTER_RUN_1_STATE>"
cmp -s "$WORK/before.json" "$WORK/after-1.json"
echo 'Exit code: 0; run 1 made no unapproved state change'
show_cmd "cmp -s <AFTER_RUN_1_STATE> <AFTER_RUN_2_STATE>"
cmp -s "$WORK/after-1.json" "$WORK/after-2.json"
echo 'Exit code: 0; run 2 is idempotent'

rm -rf "$WORK"; trap - EXIT
echo 'Temporary local evidence files remaining: 0'
echo 'Overall result: PASSED'
