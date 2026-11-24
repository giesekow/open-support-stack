#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="${1:-.env}"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing env file: $ENV_FILE" >&2
  exit 1
fi

env_get() {
  local key="$1"
  local value
  value="$(awk -F= -v k="$key" '$1==k {sub(/^[^=]*=/, "", $0); print; exit}' "$ENV_FILE" | tr -d '\r')"
  printf '%s' "$value"
}

REALM="$(env_get KEYCLOAK_REALM)"
REALM="${REALM:-support}"
ADMIN_USER="$(env_get KEYCLOAK_ADMIN_USER)"
ADMIN_PASSWORD="$(env_get KEYCLOAK_ADMIN_PASSWORD)"

if [[ -z "$ADMIN_USER" || -z "$ADMIN_PASSWORD" ]]; then
  echo "Missing KEYCLOAK_ADMIN_USER/KEYCLOAK_ADMIN_PASSWORD in $ENV_FILE" >&2
  exit 1
fi

docker compose --env-file "$ENV_FILE" exec -T keycloak \
  /opt/keycloak/bin/kcadm.sh config credentials \
  --server http://localhost:8080 --realm master \
  --user "$ADMIN_USER" --password "$ADMIN_PASSWORD" >/dev/null

docker compose --env-file "$ENV_FILE" exec -T keycloak \
  /opt/keycloak/bin/kcadm.sh update "realms/$REALM" \
  -s bruteForceProtected=true \
  -s permanentLockout=false \
  -s maxFailureWaitSeconds=900 \
  -s minimumQuickLoginWaitSeconds=60 \
  -s waitIncrementSeconds=60 \
  -s quickLoginCheckMilliSeconds=1000 \
  -s maxDeltaTimeSeconds=43200 \
  -s failureFactor=5 >/dev/null

docker compose --env-file "$ENV_FILE" exec -T keycloak \
  /opt/keycloak/bin/kcadm.sh update \
  "authentication/required-actions/CONFIGURE_TOTP" -r "$REALM" \
  -s enabled=true -s defaultAction=false >/dev/null

KEYCLOAK_REALM="$REALM" KEYCLOAK_ENV_FILE="$ENV_FILE" python3 <<'PY'
import json
import os
import subprocess

realm = os.environ["KEYCLOAK_REALM"]
env_file = os.environ["KEYCLOAK_ENV_FILE"]
base = [
    "docker", "compose", "--env-file", env_file, "exec", "-T", "keycloak",
    "/opt/keycloak/bin/kcadm.sh",
]


def run(args, json_output=False):
    process = subprocess.run(base + args, text=True, capture_output=True)
    if process.returncode:
        raise SystemExit(process.stderr.strip() or process.stdout.strip())
    return json.loads(process.stdout) if json_output else process.stdout


def exact_group(name):
    groups = run(["get", "groups", "-r", realm, "-q", f"search={name}"], True)
    group = next((item for item in groups if item.get("name") == name), None)
    if not group:
        raise SystemExit(f"Required group not found: {name}")
    return group

protected_group_names = ("platform-admin", "support-engineer", "support-admin")
assigned_actions = 0
removed_employee_actions = 0
member_counts = {}
protected_user_ids = set()
for group_name in protected_group_names:
    group = exact_group(group_name)
    members = run(["get", f"groups/{group['id']}/members", "-r", realm], True)
    member_counts[group_name] = len(members)
    protected_user_ids.update(member["id"] for member in members)
    for member in members:
        credentials = run(["get", f"users/{member['id']}/credentials", "-r", realm], True)
        if any(item.get("type") == "otp" for item in credentials):
            continue
        user = run(["get", f"users/{member['id']}", "-r", realm], True)
        required = user.get("requiredActions") or []
        if "CONFIGURE_TOTP" in required:
            continue
        required = list(dict.fromkeys(required + ["CONFIGURE_TOTP"]))
        run(["update", f"users/{member['id']}", "-r", realm, "-s", "requiredActions=" + json.dumps(required)])
        assigned_actions += 1

employees_group = exact_group("employees")
employees = run(["get", f"groups/{employees_group['id']}/members", "-r", realm], True)
member_counts["employees"] = len(employees)
for member in employees:
    if member["id"] in protected_user_ids:
        continue
    user = run(["get", f"users/{member['id']}", "-r", realm], True)
    required = user.get("requiredActions") or []
    if "CONFIGURE_TOTP" not in required:
        continue
    required = [action for action in required if action != "CONFIGURE_TOTP"]
    run(["update", f"users/{member['id']}", "-r", realm, "-s", "requiredActions=" + json.dumps(required)])
    removed_employee_actions += 1

platform_group = exact_group("platform-admin")
clients = run(["get", "clients", "-r", realm, "-q", "clientId=realm-management"], True)
realm_management = next((item for item in clients if item.get("clientId") == "realm-management"), None)
if not realm_management:
    raise SystemExit("realm-management client not found")

approved_admin_roles = {
    "manage-clients",
    "manage-events",
    "manage-realm",
    "manage-users",
    "query-clients",
    "query-groups",
    "query-users",
    "view-clients",
    "view-events",
    "view-realm",
    "view-users",
}
existing = run([
    "get",
    f"groups/{platform_group['id']}/role-mappings/clients/{realm_management['id']}",
    "-r", realm,
], True)
existing_names = {item.get("name") for item in existing}
added_roles = 0
for role_name in sorted(approved_admin_roles - existing_names):
    run([
        "add-roles", "-r", realm, "--gid", platform_group["id"],
        "--cclientid", "realm-management", "--rolename", role_name,
    ])
    added_roles += 1

print(f"realm={realm}")
print("brute_force_protection=true")
print("configure_totp_default_action=false")
print("totp_protected_groups=" + ",".join(protected_group_names))
print(f"platform_admin_members={member_counts['platform-admin']}")
print(f"support_engineer_members={member_counts['support-engineer']}")
print(f"support_admin_members={member_counts['support-admin']}")
print(f"employees_members={member_counts['employees']}")
print(f"otp_required_actions_added={assigned_actions}")
print(f"employee_otp_required_actions_removed={removed_employee_actions}")
print(f"delegated_admin_roles_added={added_roles}")
print(f"delegated_admin_roles_expected={len(approved_admin_roles)}")
PY
