#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
ENV_FILE="${1:-.env}"
BACKUP_DIR="${2:-}"
[[ -f "$ENV_FILE" ]] || { echo "Missing env file: $ENV_FILE" >&2; exit 1; }
[[ -n "$BACKUP_DIR" && -d "$BACKUP_DIR" ]] || { echo "Usage: $0 <env-file> <backup-directory>" >&2; exit 1; }
DB_ARCHIVE="$BACKUP_DIR/keycloak.sql.gz"
CONFIG_ARCHIVE="$BACKUP_DIR/config.tar.gz"
[[ -f "$DB_ARCHIVE" && -f "$CONFIG_ARCHIVE" ]] || { echo "Required backup archives are missing" >&2; exit 1; }

env_get() {
  awk -F= -v k="$1" '$1==k {sub(/^[^=]*=/, "", $0); gsub(/^"|"$/, "", $0); print; exit}' "$ENV_FILE" | tr -d '\r'
}

DB_NAME="$(env_get KEYCLOAK_DB_NAME)"; DB_NAME="${DB_NAME:-keycloak}"
DB_USER="$(env_get KEYCLOAK_DB_USER)"; DB_USER="${DB_USER:-keycloak}"
ADMIN_USER="$(env_get KEYCLOAK_ADMIN_USER)"
ADMIN_PASSWORD="$(env_get KEYCLOAK_ADMIN_PASSWORD)"
REALM="$(env_get KEYCLOAK_REALM)"; REALM="${REALM:-support}"
SSO_HOST="$(env_get SSO_HOST)"
KEYCLOAK_IMAGE="$(env_get KEYCLOAK_IMAGE)"
[[ -n "$ADMIN_USER" && -n "$ADMIN_PASSWORD" && -n "$SSO_HOST" && -n "$KEYCLOAK_IMAGE" ]] || { echo "Missing required Keycloak settings" >&2; exit 1; }

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
NETWORK="kc-restore-${STAMP,,}"
DB_CONTAINER="kc-restore-db-${STAMP,,}"
KC_CONTAINER="kc-restore-app-${STAMP,,}"
DB_PASSWORD="$(openssl rand -hex 24)"

show_cmd() { printf '\n$ %s\n' "$*"; }
cleanup() {
  docker rm -f "$KC_CONTAINER" "$DB_CONTAINER" >/dev/null 2>&1 || true
  docker network rm "$NETWORK" >/dev/null 2>&1 || true
}
trap cleanup EXIT

printf 'Evidence execution UTC: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf 'Environment: isolated Docker restore rehearsal on the production host\n'
printf 'Backup directory: %s\n' "${BACKUP_DIR/#$ROOT_DIR\//}"
printf 'Redaction: passwords, administrator identity, generated container IDs, and internal object IDs are excluded.\n'

show_cmd "sha256sum <BACKUP_DIRECTORY>/keycloak.sql.gz <BACKUP_DIRECTORY>/config.tar.gz"
sha256sum "$DB_ARCHIVE" "$CONFIG_ARCHIVE" | sed "s#${BACKUP_DIR}/#<BACKUP_DIRECTORY>/#"
show_cmd "gzip -t <BACKUP_DIRECTORY>/keycloak.sql.gz"
gzip -t "$DB_ARCHIVE"
echo 'Exit code: 0'
show_cmd "tar -tzf <BACKUP_DIRECTORY>/config.tar.gz >/dev/null"
tar -tzf "$CONFIG_ARCHIVE" >/dev/null
echo 'Exit code: 0'

show_cmd "docker network create <RESTORE_NETWORK>"
docker network create "$NETWORK" >/dev/null
echo 'Exit code: 0'
show_cmd "docker run -d --name <RESTORE_DB_CONTAINER> --network <RESTORE_NETWORK> -e POSTGRES_DB=$DB_NAME -e POSTGRES_USER=$DB_USER -e POSTGRES_PASSWORD=<REDACTED> postgres:16"
docker run -d --name "$DB_CONTAINER" --network "$NETWORK" \
  -e "POSTGRES_DB=$DB_NAME" -e "POSTGRES_USER=$DB_USER" -e "POSTGRES_PASSWORD=$DB_PASSWORD" postgres:16 >/dev/null
echo 'Exit code: 0'

show_cmd "docker exec <RESTORE_DB_CONTAINER> pg_isready -U $DB_USER -d $DB_NAME"
for _ in $(seq 1 60); do
  if docker exec "$DB_CONTAINER" pg_isready -U "$DB_USER" -d "$DB_NAME" >/dev/null 2>&1; then break; fi
  sleep 1
done
docker exec "$DB_CONTAINER" pg_isready -U "$DB_USER" -d "$DB_NAME"

show_cmd "gzip -dc <BACKUP_DIRECTORY>/keycloak.sql.gz | docker exec -i <RESTORE_DB_CONTAINER> psql -v ON_ERROR_STOP=1 -U $DB_USER -d $DB_NAME"
gzip -dc "$DB_ARCHIVE" | docker exec -i "$DB_CONTAINER" psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" >/dev/null
echo 'Exit code: 0'

show_cmd "docker run -d --name <RESTORE_KEYCLOAK_CONTAINER> --network <RESTORE_NETWORK> -e KC_DB=postgres -e KC_DB_URL_HOST=<RESTORE_DB_CONTAINER> -e KC_DB_URL_PORT=5432 -e KC_DB_URL_DATABASE=$DB_NAME -e KC_DB_USERNAME=$DB_USER -e KC_DB_PASSWORD=<REDACTED> $KEYCLOAK_IMAGE start --http-enabled=true --hostname=http://keycloak-validation.local --hostname-strict=true"
docker run -d --name "$KC_CONTAINER" --network "$NETWORK" \
  -e KC_DB=postgres -e "KC_DB_URL_HOST=$DB_CONTAINER" -e KC_DB_URL_PORT=5432 \
  -e "KC_DB_URL_DATABASE=$DB_NAME" -e "KC_DB_USERNAME=$DB_USER" -e "KC_DB_PASSWORD=$DB_PASSWORD" \
  "$KEYCLOAK_IMAGE" start --http-enabled=true --hostname=http://keycloak-validation.local --hostname-strict=true >/dev/null
echo 'Exit code: 0'

show_cmd "docker logs <RESTORE_KEYCLOAK_CONTAINER> 2>&1 | grep -E 'Updating database|Migrating to|Keycloak .* started|Profile prod activated'"
ready=false
for _ in $(seq 1 120); do
  if docker logs "$KC_CONTAINER" 2>&1 | grep -q 'Keycloak .* started'; then ready=true; break; fi
  if ! docker inspect "$KC_CONTAINER" --format '{{.State.Running}}' 2>/dev/null | grep -q true; then
    docker logs "$KC_CONTAINER" 2>&1 >&2
    exit 1
  fi
  sleep 1
done
[[ "$ready" == true ]] || { docker logs "$KC_CONTAINER" 2>&1 >&2; exit 1; }
docker logs "$KC_CONTAINER" 2>&1 | grep -E 'Updating database|Migrating to|Keycloak .* started|Profile prod activated' || true

container_ip="$(docker inspect "$KC_CONTAINER" --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')"
show_cmd "curl -sS -o /dev/null -w '%{http_code}' -H 'Host: keycloak-validation.local' http://<RESTORE_KEYCLOAK_IP>:8080/realms/$REALM/.well-known/openid-configuration"
http_status="$(curl -sS -o /dev/null -w '%{http_code}' -H 'Host: keycloak-validation.local' "http://$container_ip:8080/realms/$REALM/.well-known/openid-configuration")"
printf 'HTTP %s\n' "$http_status"
[[ "$http_status" == 200 ]]

show_cmd "docker exec <RESTORE_KEYCLOAK_CONTAINER> /opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080 --realm master --user <ADMIN_USER> --password <REDACTED>"
docker exec "$KC_CONTAINER" /opt/keycloak/bin/kcadm.sh config credentials \
  --server http://localhost:8080 --realm master --user "$ADMIN_USER" --password "$ADMIN_PASSWORD" >/dev/null 2>&1
echo 'Exit code: 0'
show_cmd "docker exec <RESTORE_KEYCLOAK_CONTAINER> /opt/keycloak/bin/kcadm.sh get realms/$REALM --fields realm,enabled"
docker exec "$KC_CONTAINER" /opt/keycloak/bin/kcadm.sh get "realms/$REALM" --fields realm,enabled

show_cmd "docker port <RESTORE_KEYCLOAK_CONTAINER>"
ports="$(docker port "$KC_CONTAINER")"
[[ -n "$ports" ]] && echo "$ports" || echo '<no host-published ports>'

show_cmd "docker rm -f <RESTORE_KEYCLOAK_CONTAINER> <RESTORE_DB_CONTAINER>"
docker rm -f "$KC_CONTAINER" "$DB_CONTAINER" >/dev/null
echo 'Exit code: 0'
show_cmd "docker network rm <RESTORE_NETWORK>"
docker network rm "$NETWORK" >/dev/null
echo 'Exit code: 0'

show_cmd "docker ps -a --filter name=^/<RESTORE_CONTAINER_PREFIX> --format '{{.Names}}'"
remaining_containers="$(docker ps -a --filter "name=^/kc-restore-.*-${STAMP,,}$" --format '{{.Names}}')"
[[ -n "$remaining_containers" ]] && echo "$remaining_containers" || echo '<none>'
show_cmd "docker network ls --filter name=^<RESTORE_NETWORK>$ --format '{{.Name}}'"
remaining_networks="$(docker network ls --filter "name=^${NETWORK}$" --format '{{.Name}}')"
[[ -n "$remaining_networks" ]] && echo "$remaining_networks" || echo '<none>'
[[ -z "$remaining_containers" && -z "$remaining_networks" ]]

show_cmd "docker compose --env-file <ENV_FILE> ps keycloak keycloak-db"
docker compose --env-file "$ENV_FILE" ps keycloak keycloak-db
show_cmd "curl -sS -o /dev/null -w '%{http_code}' https://$SSO_HOST/realms/$REALM/.well-known/openid-configuration"
production_status="$(curl -sS -o /dev/null -w '%{http_code}' "https://$SSO_HOST/realms/$REALM/.well-known/openid-configuration")"
printf 'HTTP %s\n' "$production_status"
[[ "$production_status" == 200 ]]

trap - EXIT
echo 'Overall result: PASSED'
