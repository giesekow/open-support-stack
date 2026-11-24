#!/bin/sh
set -eu

settings=/shared/seafile/conf/seahub_settings.py

for attempt in 1 2 3 4 5 6 7 8 9 10; do
    [ -f "$settings" ] && break
    [ "$attempt" -lt 10 ] || {
        echo "Seafile settings file was not created: $settings" >&2
        exit 1
    }
    sleep 2
done

python3 - "$settings" <<'PY'
import os
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
required = (
    "FILES_HOST",
    "SSO_HOST",
    "KEYCLOAK_REALM",
    "SEAFILE_OIDC_CLIENT_ID",
    "SEAFILE_OIDC_CLIENT_SECRET",
)
missing = [name for name in required if not os.environ.get(name, "").strip()]
if missing:
    raise SystemExit(f"Missing Seafile OIDC environment values: {', '.join(missing)}")

files_host = os.environ["FILES_HOST"].strip()
sso_host = os.environ["SSO_HOST"].strip()
realm = os.environ["KEYCLOAK_REALM"].strip()
client_id = os.environ["SEAFILE_OIDC_CLIENT_ID"].strip()
client_secret = os.environ["SEAFILE_OIDC_CLIENT_SECRET"]
begin = "# BEGIN support-stack managed Seafile OIDC"
end = "# END support-stack managed Seafile OIDC"

content = path.read_text(encoding="utf-8")
content = re.sub(
    rf"\n?{re.escape(begin)}.*?{re.escape(end)}\n?",
    "\n",
    content,
    flags=re.DOTALL,
)
content = re.sub(
    r"(?m)^(SERVICE_URL|FILE_SERVER_ROOT|CSRF_TRUSTED_ORIGINS)\s*=.*(?:\n|$)",
    "",
    content,
)

public_base = f"https://{files_host}"
issuer_base = f"https://{sso_host}/realms/{realm}"
internal_base = f"http://keycloak:8080/realms/{realm}"
block = f"""
{begin}
SERVICE_URL = {public_base!r}
FILE_SERVER_ROOT = {(public_base + '/seafhttp')!r}
CSRF_TRUSTED_ORIGINS = [{public_base!r}]

ENABLE_OAUTH = True
OAUTH_CREATE_UNKNOWN_USER = True
OAUTH_ACTIVATE_USER_AFTER_CREATION = True
OAUTH_ENABLE_INSECURE_TRANSPORT = True
OAUTH_CLIENT_ID = {client_id!r}
OAUTH_CLIENT_SECRET = {client_secret!r}
OAUTH_REDIRECT_URL = {(public_base + '/oauth/callback/')!r}
OAUTH_PROVIDER = 'keycloak'
OAUTH_PROVIDER_DOMAIN = 'keycloak'
OAUTH_AUTHORIZATION_URL = {(issuer_base + '/protocol/openid-connect/auth')!r}
OAUTH_TOKEN_URL = {(internal_base + '/protocol/openid-connect/token')!r}
OAUTH_USER_INFO_URL = {(internal_base + '/protocol/openid-connect/userinfo')!r}
OAUTH_SCOPE = ['openid', 'profile', 'email']
OAUTH_ATTRIBUTE_MAP = {{
    'sub': (True, 'uid'),
    'name': (False, 'name'),
    'email': (False, 'contact_email'),
}}
{end}
"""
path.write_text(content.rstrip() + "\n" + block.lstrip(), encoding="utf-8")
PY

echo "Configured Seafile OAuth for ${SSO_HOST}"
