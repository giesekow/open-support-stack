#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
ENV_FILE="${1:-.env}"
MANUAL_PORT="${2:-}"
[[ -f "$ENV_FILE" ]] || { echo "Missing env file: $ENV_FILE" >&2; exit 1; }
if [[ -n "$MANUAL_PORT" && ! "$MANUAL_PORT" =~ ^[0-9]+$ ]]; then
  echo "Manual restore port must be numeric" >&2
  exit 1
fi
if [[ -n "$MANUAL_PORT" && ( "$MANUAL_PORT" -lt 1024 || "$MANUAL_PORT" -gt 65535 ) ]]; then
  echo "Manual restore port must be between 1024 and 65535" >&2
  exit 1
fi

env_get() {
  awk -F= -v k="$1" '$1==k {sub(/^[^=]*=/, "", $0); gsub(/^"|"$/, "", $0); print; exit}' "$ENV_FILE" | tr -d '\r'
}

VAULT_URL="$(env_get VAULTWARDEN_DOMAIN)"
[[ "$VAULT_URL" == https://* ]] || { echo "VAULTWARDEN_DOMAIN must use HTTPS" >&2; exit 1; }
IMAGE="$(docker inspect support-vaultwarden --format '{{.Config.Image}}')"
SOURCE_VOLUME="$(docker inspect support-vaultwarden --format '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Name}}{{end}}{{end}}')"
[[ -n "$SOURCE_VOLUME" ]] || { echo "Vaultwarden /data volume was not found" >&2; exit 1; }

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_DIR="$ROOT_DIR/backups/vaultwarden-validation-$STAMP"
RESTORE_VOLUME="vaultwarden-validation-${STAMP,,}"
RESTORE_NETWORK="vaultwarden-validation-${STAMP,,}"
RESTORE_CONTAINER="vaultwarden-validation-${STAMP,,}"
TEMP_DB="$(mktemp)"
RESTORE_DOMAIN="http://vaultwarden-validation.local"
if [[ -n "$MANUAL_PORT" ]]; then
  RESTORE_DOMAIN="http://localhost:$MANUAL_PORT"
fi

show_cmd() { printf '\n$ %s\n' "$*"; }
cleanup() {
  docker rm -f "$RESTORE_CONTAINER" >/dev/null 2>&1 || true
  docker volume rm "$RESTORE_VOLUME" >/dev/null 2>&1 || true
  docker network rm "$RESTORE_NETWORK" >/dev/null 2>&1 || true
  rm -f "$TEMP_DB"
}
trap cleanup EXIT
umask 077
mkdir -p "$BACKUP_DIR"

printf 'Evidence execution UTC: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf 'Environment: production backup with isolated restore target\n'
printf 'Backup directory: backups/vaultwarden-validation-%s\n' "$STAMP"
printf 'Redaction: vault contents, account identifiers, credentials, tokens, SMTP settings, and encryption material are excluded.\n'

show_cmd "docker exec support-vaultwarden /vaultwarden backup"
backup_output="$(docker exec support-vaultwarden /vaultwarden backup 2>&1)"
printf '%s\n' "$backup_output" | sed -E "s/db_[0-9_]+\.sqlite3/<ONLINE_BACKUP_FILE>/g"
backup_file="$(printf '%s\n' "$backup_output" | sed -nE "s/.*Backup to 'data\/(db_[0-9_]+\.sqlite3)'.*/\1/p")"
[[ -n "$backup_file" ]]

show_cmd "docker cp support-vaultwarden:/data/<ONLINE_BACKUP_FILE> <BACKUP_DIRECTORY>/db.sqlite3"
docker cp "support-vaultwarden:/data/$backup_file" "$BACKUP_DIR/db.sqlite3" >/dev/null
echo 'Exit code: 0'
show_cmd "docker exec support-vaultwarden rm -f /data/<ONLINE_BACKUP_FILE>"
docker exec support-vaultwarden rm -f "/data/$backup_file"
echo 'Exit code: 0'
show_cmd "docker run --rm -v <VAULTWARDEN_DATA_VOLUME>:/source:ro -v <BACKUP_DIRECTORY>:/backup $IMAGE sh -lc 'cd /source && tar --exclude=db.sqlite3 --exclude=db.sqlite3-shm --exclude=db.sqlite3-wal --exclude=db_*.sqlite3 -czf /backup/data-files.tar.gz .'"
docker run --rm -v "$SOURCE_VOLUME:/source:ro" -v "$BACKUP_DIR:/backup" "$IMAGE" sh -lc \
  'cd /source && tar --exclude=db.sqlite3 --exclude=db.sqlite3-shm --exclude=db.sqlite3-wal --exclude=db_*.sqlite3 -czf /backup/data-files.tar.gz .'
echo 'Exit code: 0'
show_cmd "tar -czf <BACKUP_DIRECTORY>/stack-config.tar.gz <ENV_FILE> docker-compose.yml nginx/templates"
tar -czf "$BACKUP_DIR/stack-config.tar.gz" "$ENV_FILE" docker-compose.yml nginx/templates
echo 'Exit code: 0'
show_cmd "docker run --rm -v <BACKUP_DIRECTORY>:/backup $IMAGE sh -lc 'chown -R <DEPLOY_UID>:<DEPLOY_GID> /backup && chmod -R go-rwx /backup'"
docker run --rm -v "$BACKUP_DIR:/backup" "$IMAGE" sh -lc "chown -R $(id -u):$(id -g) /backup && chmod -R go-rwx /backup"
echo 'Exit code: 0'
chmod -R go-rwx "$BACKUP_DIR"

show_cmd "stat -c '%a %U:%G %n' <BACKUP_DIRECTORY> <BACKUP_DIRECTORY>/*"
stat -c '%a %U:%G %n' "$BACKUP_DIR" "$BACKUP_DIR"/* | sed "s#$BACKUP_DIR#<BACKUP_DIRECTORY>#g"
show_cmd "sha256sum <BACKUP_DIRECTORY>/db.sqlite3 <BACKUP_DIRECTORY>/data-files.tar.gz <BACKUP_DIRECTORY>/stack-config.tar.gz"
sha256sum "$BACKUP_DIR/db.sqlite3" "$BACKUP_DIR/data-files.tar.gz" "$BACKUP_DIR/stack-config.tar.gz" | sed "s#$BACKUP_DIR#<BACKUP_DIRECTORY>#g"
show_cmd "python3 -c 'run SQLite integrity_check and print aggregate counts only' <BACKUP_DIRECTORY>/db.sqlite3"
python3 - "$BACKUP_DIR/db.sqlite3" <<'PY'
import sqlite3, sys
db=sqlite3.connect(f'file:{sys.argv[1]}?mode=ro', uri=True)
assert db.execute('pragma integrity_check').fetchone()[0] == 'ok'
print('integrity_check=ok')
for table in ('users','organizations','collections','ciphers','users_organizations'):
    print(f'{table}_count={db.execute("select count(*) from "+table).fetchone()[0]}')
PY
show_cmd "tar -tzf <BACKUP_DIRECTORY>/data-files.tar.gz >/dev/null && tar -tzf <BACKUP_DIRECTORY>/stack-config.tar.gz >/dev/null"
tar -tzf "$BACKUP_DIR/data-files.tar.gz" >/dev/null
tar -tzf "$BACKUP_DIR/stack-config.tar.gz" >/dev/null
echo 'Exit code: 0'

show_cmd "docker volume create <RESTORE_VOLUME>"
docker volume create "$RESTORE_VOLUME" >/dev/null
echo 'Exit code: 0'
show_cmd "docker run --rm -v <RESTORE_VOLUME>:/data -v <BACKUP_DIRECTORY>:/backup:ro $IMAGE sh -lc 'tar -xzf /backup/data-files.tar.gz -C /data && cp /backup/db.sqlite3 /data/db.sqlite3 && rm -f /data/db.sqlite3-shm /data/db.sqlite3-wal'"
docker run --rm -v "$RESTORE_VOLUME:/data" -v "$BACKUP_DIR:/backup:ro" "$IMAGE" sh -lc \
  'tar -xzf /backup/data-files.tar.gz -C /data && cp /backup/db.sqlite3 /data/db.sqlite3 && rm -f /data/db.sqlite3-shm /data/db.sqlite3-wal'
echo 'Exit code: 0'
show_cmd "docker network create --internal <RESTORE_NETWORK>"
docker network create --internal "$RESTORE_NETWORK" >/dev/null
echo 'Exit code: 0'
show_cmd "docker run -d --name <RESTORE_CONTAINER> --network <RESTORE_NETWORK> -v <RESTORE_VOLUME>:/data -e DOMAIN=<RESTORE_DOMAIN> -e SIGNUPS_ALLOWED=false -e INVITATIONS_ALLOWED=false -e ADMIN_TOKEN=<REDACTED> $IMAGE"
docker run -d --name "$RESTORE_CONTAINER" --network "$RESTORE_NETWORK" -v "$RESTORE_VOLUME:/data" \
  -e "DOMAIN=$RESTORE_DOMAIN" -e SIGNUPS_ALLOWED=false -e INVITATIONS_ALLOWED=false \
  -e "ADMIN_TOKEN=$(openssl rand -hex 32)" "$IMAGE" >/dev/null
echo 'Exit code: 0'

ready=false
for _ in $(seq 1 60); do
  if docker logs "$RESTORE_CONTAINER" 2>&1 | grep -q 'Rocket has launched'; then ready=true; break; fi
  sleep 1
done
[[ "$ready" == true ]] || { docker logs "$RESTORE_CONTAINER" >&2; exit 1; }
show_cmd "docker logs <RESTORE_CONTAINER> 2>&1 | grep -E 'Vaultwarden|Rocket has launched' | tail -n 8"
docker logs "$RESTORE_CONTAINER" 2>&1 | grep -E 'Vaultwarden|Rocket has launched' | tail -n 8
restore_ip="$(docker inspect "$RESTORE_CONTAINER" --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')"
show_cmd "curl -sS -o /dev/null -w '%{http_code}' -H 'Host: vaultwarden-validation.local' http://<RESTORE_IP>/alive"
status="$(curl -sS -o /dev/null -w '%{http_code}' -H 'Host: vaultwarden-validation.local' "http://$restore_ip/alive")"
printf 'HTTP %s\n' "$status"; [[ "$status" == 200 ]]
show_cmd "docker port <RESTORE_CONTAINER>"
ports="$(docker port "$RESTORE_CONTAINER")"; [[ -n "$ports" ]] && echo "$ports" || echo '<no host-published ports>'

show_cmd "docker cp <RESTORE_CONTAINER>:/data/db.sqlite3 <TEMP_DB>"
docker cp "$RESTORE_CONTAINER:/data/db.sqlite3" "$TEMP_DB" >/dev/null
echo 'Exit code: 0'
show_cmd "python3 -c 'run restored SQLite integrity_check and print aggregate counts only' <TEMP_DB>"
python3 - "$TEMP_DB" <<'PY'
import sqlite3, sys
db=sqlite3.connect(f'file:{sys.argv[1]}?mode=ro', uri=True)
assert db.execute('pragma integrity_check').fetchone()[0] == 'ok'
print('integrity_check=ok')
for table in ('users','organizations','collections','ciphers','users_organizations'):
    print(f'{table}_count={db.execute("select count(*) from "+table).fetchone()[0]}')
PY

if [[ -n "$MANUAL_PORT" ]]; then
  rm -f "$TEMP_DB"
  show_cmd "docker compose --env-file <ENV_FILE> ps vaultwarden"
  docker compose --env-file "$ENV_FILE" ps vaultwarden
  show_cmd "curl -sS -o /dev/null -w '%{http_code}' $VAULT_URL/alive"
  status="$(curl -sS -o /dev/null -w '%{http_code}' "$VAULT_URL/alive")"; printf 'HTTP %s\n' "$status"; [[ "$status" == 200 ]]

  trap - EXIT
  printf 'Protected backup retained at: backups/vaultwarden-validation-%s\n' "$STAMP"
  echo 'Manual restore has no host-published port.'
  printf 'SSH tunnel: ssh -L %s:%s:80 <deployment-host>\n' "$MANUAL_PORT" "$restore_ip"
  printf 'Open locally: http://localhost:%s\n' "$MANUAL_PORT"
  printf 'Restore container: %s\n' "$RESTORE_CONTAINER"
  printf 'Restore volume: %s\n' "$RESTORE_VOLUME"
  printf 'Restore network: %s\n' "$RESTORE_NETWORK"
  printf 'Cleanup: docker rm -f %s && docker volume rm %s && docker network rm %s\n' \
    "$RESTORE_CONTAINER" "$RESTORE_VOLUME" "$RESTORE_NETWORK"
  echo 'Infrastructure restore result: PASSED'
  echo 'Encrypted-data usability result: READY FOR MANUAL LOGIN AND ITEM/PERMISSION CHECK'
  exit 0
fi

show_cmd "docker rm -f <RESTORE_CONTAINER> && docker volume rm <RESTORE_VOLUME> && docker network rm <RESTORE_NETWORK> && rm -f <TEMP_DB>"
docker rm -f "$RESTORE_CONTAINER" >/dev/null
docker volume rm "$RESTORE_VOLUME" >/dev/null
docker network rm "$RESTORE_NETWORK" >/dev/null
rm -f "$TEMP_DB"
echo 'Exit code: 0'
show_cmd "verify isolated resources are absent"
remaining_containers="$(docker ps -a --filter "name=^/${RESTORE_CONTAINER}$" --format '{{.Names}}')"
remaining_volumes="$(docker volume ls --filter "name=^${RESTORE_VOLUME}$" --format '{{.Name}}')"
remaining_networks="$(docker network ls --filter "name=^${RESTORE_NETWORK}$" --format '{{.Name}}')"
printf 'remaining_containers=%s\n' "${remaining_containers:-0}"
printf 'remaining_volumes=%s\n' "${remaining_volumes:-0}"
printf 'remaining_networks=%s\n' "${remaining_networks:-0}"
[[ -z "$remaining_containers" && -z "$remaining_volumes" && -z "$remaining_networks" ]]

show_cmd "docker compose --env-file <ENV_FILE> ps vaultwarden"
docker compose --env-file "$ENV_FILE" ps vaultwarden
show_cmd "curl -sS -o /dev/null -w '%{http_code}' $VAULT_URL/alive"
status="$(curl -sS -o /dev/null -w '%{http_code}' "$VAULT_URL/alive")"; printf 'HTTP %s\n' "$status"; [[ "$status" == 200 ]]

trap - EXIT
printf 'Protected backup retained at: backups/vaultwarden-validation-%s\n' "$STAMP"
echo 'Infrastructure restore result: PASSED'
echo 'Encrypted-data usability result: PENDING MANUAL LOGIN AND ITEM/PERMISSION CHECK'
