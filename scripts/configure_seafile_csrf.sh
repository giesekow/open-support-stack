#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="${1:-.env}"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "[FAIL] Missing env file: $ENV_FILE"
  exit 1
fi

env_get() {
  local key="$1"
  local def="$2"
  local val
  val="$(awk -F= -v k="$key" '$1==k {sub(/^[^=]*=/, "", $0); print; exit}' "$ENV_FILE" | tr -d '\r')"
  if [[ -z "$val" ]]; then
    printf '%s' "$def"
  else
    printf '%s' "$val"
  fi
}

FILES_HOST="$(env_get FILES_HOST "files.example.com")"
SERVICE_URL="https://${FILES_HOST}"
FILE_SERVER_ROOT="https://${FILES_HOST}/seafhttp"
CSRF_ORIGIN="https://${FILES_HOST}"
SETTINGS_FILE="/shared/seafile/conf/seahub_settings.py"

echo "==> Configuring Seafile web origin settings (${FILES_HOST})"

for i in 1 2 3 4 5; do
  if docker compose --env-file "$ENV_FILE" exec -T seafile sh -lc "test -f '$SETTINGS_FILE'"; then
    break
  fi
  if [[ "$i" -eq 5 ]]; then
    echo "[FAIL] Seafile settings file not found after waiting: $SETTINGS_FILE"
    exit 1
  fi
  sleep 4
done

docker compose --env-file "$ENV_FILE" exec -T seafile sh -lc "
set -e
f='$SETTINGS_FILE'
tmp=\"\$(mktemp)\"

grep -vE '^(SERVICE_URL|FILE_SERVER_ROOT|CSRF_TRUSTED_ORIGINS)\\s*=' \"\$f\" > \"\$tmp\" || true
{
  cat \"\$tmp\"
  printf '\nSERVICE_URL = %s\n' \"'${SERVICE_URL}'\"
  printf 'FILE_SERVER_ROOT = %s\n' \"'${FILE_SERVER_ROOT}'\"
  printf 'CSRF_TRUSTED_ORIGINS = %s\n' \"['${CSRF_ORIGIN}']\"
} > \"\$f\"
rm -f \"\$tmp\"
"

echo "[OK] Seafile settings updated in $SETTINGS_FILE"
echo "     SERVICE_URL=${SERVICE_URL}"
echo "     FILE_SERVER_ROOT=${FILE_SERVER_ROOT}"
echo "     CSRF_TRUSTED_ORIGINS=['${CSRF_ORIGIN}']"

