#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_DIR="$ROOT_DIR/config/osticket/plugins/auth-oauth2"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$ROOT_DIR/config/osticket/plugins"

docker run --rm -v "$TMP_DIR:/tmp/work" alpine:3.20 sh -lc '
  apk add --no-cache wget tar >/dev/null
  wget -qO /tmp/work/plugins.tar.gz https://codeload.github.com/osTicket/osTicket-plugins/tar.gz/refs/heads/develop
  tar -xzf /tmp/work/plugins.tar.gz -C /tmp/work
'

rm -rf "$PLUGIN_DIR"
cp -R "$TMP_DIR/osTicket-plugins-develop/auth-oauth2" "$PLUGIN_DIR"

# Ensure container picks up plugin files.
docker compose up -d osticket >/dev/null

echo "Installed auth-oauth2 plugin source into: $PLUGIN_DIR"
echo "Next: Admin Panel -> Manage -> Plugins -> Add New Plugin -> OAuth2 Client"
