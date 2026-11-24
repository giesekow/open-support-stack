#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="${1:-.env}"
OUTPUT_FILE="${2:-}"
CONTAINER="support-vaultwarden"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing environment file: $ENV_FILE" >&2
  exit 1
fi
for command in docker openssl script awk; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Required command not found: $command" >&2
    exit 1
  fi
done
if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
  echo "Vaultwarden container is not running: $CONTAINER" >&2
  exit 1
fi
if docker exec "$CONTAINER" sh -c \
  'test -f /data/config.json && grep -q '"'"'"admin_token"'"'"' /data/config.json'; then
  echo "Refusing rotation: /data/config.json contains an admin_token override." >&2
  echo "Remove that override through an approved configuration change first." >&2
  exit 1
fi

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_dir="$ROOT_DIR/backups/vaultwarden-admin-token-$timestamp"
mkdir -p "$backup_dir" "$ROOT_DIR/.secrets"
chmod 700 "$backup_dir" "$ROOT_DIR/.secrets"
cp "$ENV_FILE" "$backup_dir/env.before-rotation"
chmod 600 "$backup_dir/env.before-rotation"

if [[ -z "$OUTPUT_FILE" ]]; then
  OUTPUT_FILE="$ROOT_DIR/.secrets/vaultwarden-admin-token-$timestamp.txt"
elif [[ "$OUTPUT_FILE" != /* ]]; then
  OUTPUT_FILE="$ROOT_DIR/$OUTPUT_FILE"
fi
mkdir -p "$(dirname "$OUTPUT_FILE")"
umask 077

token="$(openssl rand -hex 32)"
hash_output="$(
  printf '%s\n%s\n' "$token" "$token" \
    | script -qec "docker exec -it $CONTAINER /vaultwarden hash" /dev/null 2>&1
)"
admin_hash="$(
  printf '%s\n' "$hash_output" \
    | tr -d '\r' \
    | sed -n "s/^ADMIN_TOKEN='\(.*\)'$/\1/p" \
    | tail -n 1
)"
unset hash_output

if [[ "$admin_hash" != '$argon2id$'* ]]; then
  echo "Vaultwarden did not return a valid Argon2id PHC string" >&2
  exit 1
fi

tmp_env="$(mktemp "${ENV_FILE}.XXXXXX")"
cleanup() {
  rm -f "$tmp_env"
  unset token admin_hash
}
rollback() {
  local exit_code=$?
  trap - ERR
  set +e
  echo "Rotation failed; restoring the previous environment file." >&2
  cp "$backup_dir/env.before-rotation" "$ENV_FILE"
  docker compose --env-file "$ENV_FILE" up -d --no-deps --force-recreate vaultwarden >/dev/null 2>&1
  rm -f "$OUTPUT_FILE"
  cleanup
  exit "$exit_code"
}
trap cleanup EXIT

awk -v replacement="VAULTWARDEN_ADMIN_TOKEN='$admin_hash'" '
  BEGIN { replaced = 0 }
  /^VAULTWARDEN_ADMIN_TOKEN=/ { print replacement; replaced = 1; next }
  { print }
  END { if (!replaced) print replacement }
' "$ENV_FILE" > "$tmp_env"
chmod --reference="$ENV_FILE" "$tmp_env"
mv "$tmp_env" "$ENV_FILE"

printf '%s\n' "$token" > "$OUTPUT_FILE"
chmod 600 "$OUTPUT_FILE"

trap rollback ERR
docker compose --env-file "$ENV_FILE" config --quiet
docker compose --env-file "$ENV_FILE" up -d --no-deps --force-recreate vaultwarden >/dev/null

for _ in $(seq 1 45); do
  health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$CONTAINER" 2>/dev/null || true)"
  [[ "$health" == "healthy" || "$health" == "running" ]] && break
  [[ "$health" == "unhealthy" || "$health" == "exited" || "$health" == "dead" ]] && false
  sleep 2
done

runtime_token="$(
  docker inspect "$CONTAINER" --format '{{range .Config.Env}}{{println .}}{{end}}' \
    | sed -n 's/^ADMIN_TOKEN=//p'
)"
[[ "$runtime_token" == '$argon2id$'* ]]
[[ "$runtime_token" != "$token" ]]
if docker logs --since 5m "$CONTAINER" 2>&1 \
  | grep -Eq 'plain text `ADMIN_TOKEN`|configured Argon2 PHC is invalid'; then
  echo "Vaultwarden rejected the rotated ADMIN_TOKEN configuration" >&2
  false
fi

trap - ERR
unset runtime_token token admin_hash
trap - EXIT
cleanup

echo "Vaultwarden admin token rotated successfully."
echo "Plaintext token file (mode 600): $OUTPUT_FILE"
echo "Environment backup (mode 600): $backup_dir/env.before-rotation"
echo "Store the plaintext in the approved vault, test /admin, then securely remove the token file."
