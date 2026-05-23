#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="${1:-.env}"
if [[ "${ENV_FILE}" == "--"* ]]; then
  ENV_FILE=".env"
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing env file ($ENV_FILE) in $ROOT_DIR"
  exit 1
fi

env_get() {
  local key="$1"
  local def="$2"
  local val
  val="$(grep -E "^${key}=" "$ENV_FILE" | head -n1 | cut -d= -f2- || true)"
  if [[ -z "$val" ]]; then
    printf '%s' "$def"
  else
    printf '%s' "$val"
  fi
}

BASE_DOMAIN="$(env_get BASE_DOMAIN "example.com")"
SUPPORT_HOST="$(env_get SUPPORT_HOST "support.${BASE_DOMAIN}")"
SSO_HOST="$(env_get SSO_HOST "sso.${BASE_DOMAIN}")"
VAULT_HOST="$(env_get VAULT_HOST "vault.${BASE_DOMAIN}")"
DOCS_HOST="$(env_get DOCS_HOST "docs.${BASE_DOMAIN}")"
REMOTE_HOST="$(env_get REMOTE_HOST "remote.${BASE_DOMAIN}")"
MESH_HOST="$(env_get MESH_HOST "mesh.${BASE_DOMAIN}")"
MESH_WEB_HOST="$(env_get MESH_WEB_HOST "mesh-web.${BASE_DOMAIN}")"
TICKETS_HOST="$(env_get TICKETS_HOST "tickets.${BASE_DOMAIN}")"
CRM_HOST="$(env_get CRM_HOST "crm.${BASE_DOMAIN}")"
HR_HOST="$(env_get HR_HOST "hr.${BASE_DOMAIN}")"
STATUS_HOST="$(env_get STATUS_HOST "status.${BASE_DOMAIN}")"
KEYCLOAK_REALM="$(env_get KEYCLOAK_REALM "support")"

KUMA_URL="https://${STATUS_HOST}"
KUMA_USERNAME="${UPTIME_KUMA_USERNAME:-}"
KUMA_PASSWORD="${UPTIME_KUMA_PASSWORD:-}"
INTERVAL="${UPTIME_KUMA_INTERVAL_SECONDS:-60}"
TIMEOUT="${UPTIME_KUMA_TIMEOUT_SECONDS:-48}"
MAX_RETRIES="${UPTIME_KUMA_MAX_RETRIES:-2}"
RETRY_INTERVAL="${UPTIME_KUMA_RETRY_INTERVAL_SECONDS:-60}"
IGNORE_TLS="${UPTIME_KUMA_IGNORE_TLS:-true}"
ACCEPTED_STATUSCODES="${UPTIME_KUMA_ACCEPTED_STATUSCODES:-200-399}"

# Prefer values from env file to avoid relying on sourced shell vars
KUMA_USERNAME="$(env_get UPTIME_KUMA_USERNAME "$KUMA_USERNAME")"
KUMA_PASSWORD="$(env_get UPTIME_KUMA_PASSWORD "$KUMA_PASSWORD")"
INTERVAL="$(env_get UPTIME_KUMA_INTERVAL_SECONDS "$INTERVAL")"
TIMEOUT="$(env_get UPTIME_KUMA_TIMEOUT_SECONDS "$TIMEOUT")"
MAX_RETRIES="$(env_get UPTIME_KUMA_MAX_RETRIES "$MAX_RETRIES")"
RETRY_INTERVAL="$(env_get UPTIME_KUMA_RETRY_INTERVAL_SECONDS "$RETRY_INTERVAL")"
IGNORE_TLS="$(env_get UPTIME_KUMA_IGNORE_TLS "$IGNORE_TLS")"
ACCEPTED_STATUSCODES="$(env_get UPTIME_KUMA_ACCEPTED_STATUSCODES "$ACCEPTED_STATUSCODES")"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url) KUMA_URL="${2:-}"; shift 2 ;;
    --username) KUMA_USERNAME="${2:-}"; shift 2 ;;
    --password) KUMA_PASSWORD="${2:-}"; shift 2 ;;
    --interval) INTERVAL="${2:-}"; shift 2 ;;
    --timeout) TIMEOUT="${2:-}"; shift 2 ;;
    --max-retries) MAX_RETRIES="${2:-}"; shift 2 ;;
    --retry-interval) RETRY_INTERVAL="${2:-}"; shift 2 ;;
    --ignore-tls) IGNORE_TLS="${2:-}"; shift 2 ;;
    --accepted-statuscodes) ACCEPTED_STATUSCODES="${2:-}"; shift 2 ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done

if [[ -z "$KUMA_USERNAME" || -z "$KUMA_PASSWORD" ]]; then
  echo "Usage:"
  echo "  $0 --username <kuma-user> --password <kuma-pass> [--url <https://status...>]"
  echo
  echo "Tip: export UPTIME_KUMA_USERNAME/UPTIME_KUMA_PASSWORD in your shell."
  exit 1
fi

echo "==> Seeding Uptime Kuma monitors at ${KUMA_URL}"

for v in INTERVAL TIMEOUT MAX_RETRIES RETRY_INTERVAL; do
  if ! [[ "${!v}" =~ ^[0-9]+$ ]]; then
    echo "Invalid numeric value for ${v}: ${!v}"
    exit 1
  fi
done

IGNORE_TLS_LC="$(printf '%s' "$IGNORE_TLS" | tr '[:upper:]' '[:lower:]')"
if [[ "$IGNORE_TLS_LC" != "true" && "$IGNORE_TLS_LC" != "false" ]]; then
  echo "Invalid --ignore-tls value: $IGNORE_TLS (expected true|false)"
  exit 1
fi

KUMA_URL="$KUMA_URL" \
KUMA_USERNAME="$KUMA_USERNAME" \
KUMA_PASSWORD="$KUMA_PASSWORD" \
INTERVAL="$INTERVAL" \
TIMEOUT="$TIMEOUT" \
MAX_RETRIES="$MAX_RETRIES" \
RETRY_INTERVAL="$RETRY_INTERVAL" \
IGNORE_TLS="$IGNORE_TLS_LC" \
ACCEPTED_STATUSCODES="$ACCEPTED_STATUSCODES" \
SSO_HOST="$SSO_HOST" \
VAULT_HOST="$VAULT_HOST" \
DOCS_HOST="$DOCS_HOST" \
REMOTE_HOST="$REMOTE_HOST" \
MESH_HOST="$MESH_HOST" \
MESH_WEB_HOST="$MESH_WEB_HOST" \
TICKETS_HOST="$TICKETS_HOST" \
CRM_HOST="$CRM_HOST" \
HR_HOST="$HR_HOST" \
KEYCLOAK_REALM="$KEYCLOAK_REALM" \
docker compose exec -T uptime-kuma node - <<'NODE'
const { io } = require("socket.io-client");

const kumaUrl = process.env.KUMA_URL;
const username = process.env.KUMA_USERNAME;
const password = process.env.KUMA_PASSWORD;
const interval = Number(process.env.INTERVAL || 60);
const timeout = Number(process.env.TIMEOUT || 48);
const maxretries = Number(process.env.MAX_RETRIES || 2);
const retryInterval = Number(process.env.RETRY_INTERVAL || 60);
const ignoreTls = String(process.env.IGNORE_TLS || "true") === "true";
const acceptedStatuscodes = String(process.env.ACCEPTED_STATUSCODES || "200-399")
  .split(",")
  .map((s) => s.trim())
  .filter(Boolean);

const ssoHost = process.env.SSO_HOST;
const vaultHost = process.env.VAULT_HOST;
const docsHost = process.env.DOCS_HOST;
const remoteHost = process.env.REMOTE_HOST;
const meshHost = process.env.MESH_HOST;
const meshWebHost = process.env.MESH_WEB_HOST;
const ticketsHost = process.env.TICKETS_HOST;
const crmHost = process.env.CRM_HOST;
const hrHost = process.env.HR_HOST;
const keycloakRealm = process.env.KEYCLOAK_REALM || "support";

const defaults = [
  { name: "Keycloak OIDC Discovery", url: `https://${ssoHost}/realms/${keycloakRealm}/.well-known/openid-configuration` },
  { name: "Vaultwarden", url: `https://${vaultHost}/` },
  { name: "BookStack", url: `https://${docsHost}/` },
  { name: "Guacamole", url: `https://${remoteHost}/guacamole/` },
  { name: "Headscale API", url: `https://${meshHost}/health` },
  { name: "Headscale UI", url: `https://${meshWebHost}/` },
  { name: "osTicket", url: `https://${ticketsHost}/` },
  { name: "EspoCRM", url: `https://${crmHost}/` },
  { name: "OrangeHRM", url: `https://${hrHost}/` },
];

function emitAck(socket, event, ...args) {
  return new Promise((resolve) => {
    socket.emit(event, ...args, (res) => resolve(res));
  });
}

async function main() {
  const socket = io(kumaUrl, {
    transports: ["websocket"],
    timeout: 15000,
    rejectUnauthorized: false,
    autoConnect: true,
  });

  await new Promise((resolve, reject) => {
    socket.once("connect", resolve);
    socket.once("connect_error", reject);
  });

  const loginRes = await emitAck(socket, "login", { username, password });
  if (!loginRes?.ok) {
    if (loginRes?.tokenRequired) {
      throw new Error("Kuma user has 2FA enabled; script login requires a non-2FA service user.");
    }
    throw new Error(`Kuma login failed: ${loginRes?.msg || "unknown error"}`);
  }

  const needSetup = await emitAck(socket, "needSetup");
  if (needSetup === true) {
    throw new Error("Uptime Kuma is not initialized yet. Complete first-time setup in UI, then rerun.");
  }

  const monitorListPromise = new Promise((resolve) => {
    socket.once("monitorList", (list) => resolve(list || {}));
  });
  const listAck = await emitAck(socket, "getMonitorList");
  if (!listAck?.ok) {
    throw new Error(`getMonitorList failed: ${listAck?.msg || "unknown error"}`);
  }
  const monitorList = await monitorListPromise;
  const existingNames = new Set(Object.values(monitorList).map((m) => m?.name).filter(Boolean));
  const existingUrls = new Set(Object.values(monitorList).map((m) => m?.url).filter(Boolean));

  let added = 0;
  let skipped = 0;

  for (const item of defaults) {
    if (existingNames.has(item.name)) {
      console.log(`[SKIP] ${item.name} already exists`);
      skipped += 1;
      continue;
    }
    if (existingUrls.has(item.url)) {
      console.log(`[SKIP] URL already monitored: ${item.url}`);
      skipped += 1;
      continue;
    }

    const monitor = {
      type: "http",
      name: item.name,
      url: item.url,
      method: "GET",
      interval,
      timeout,
      maxretries,
      retryInterval,
      resendInterval: 0,
      maxredirects: 10,
      accepted_statuscodes: acceptedStatuscodes,
      ignoreTls,
      upsideDown: false,
      invertKeyword: false,
      dns_resolve_type: "A",
      dns_resolve_server: "1.1.1.1",
      active: true,
      notificationIDList: {},
      kafkaProducerBrokers: [],
      kafkaProducerSaslOptions: {},
    };

    const addRes = await emitAck(socket, "add", monitor);
    if (!addRes?.ok) {
      console.log(`[FAIL] ${item.name}: ${addRes?.msg || "unknown error"}`);
      continue;
    }
    console.log(`[ADD] ${item.name} -> monitorID ${addRes.monitorID}`);
    added += 1;
  }

  socket.disconnect();
  console.log(`Done. Added: ${added}, Skipped: ${skipped}`);
}

main().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
NODE
