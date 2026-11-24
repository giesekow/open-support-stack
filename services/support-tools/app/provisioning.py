from __future__ import annotations

import ast
import base64
import hashlib
import json
import os
import re
import secrets
import urllib.error
import urllib.parse
import urllib.request
import uuid
import zlib
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Iterable

import pymysql
import psycopg
import redis
from psycopg.rows import dict_row
from sqlalchemy import select, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from .models import (
    IdentityLink,
    ProvisioningAction,
    ProvisioningAuditEvent,
    ProvisioningExecutionAttempt,
    ProvisioningTarget,
    ReconciliationRun,
    SourceIdentity,
)


TARGET_DEFINITIONS = (
    ("espocrm", "EspoCRM", "jit", "espocrm", ["employees"]),
    ("bookstack", "BookStack", "jit", "bookstack", ["employees"]),
    ("erpnext", "Frappe HR / ERPNext", "jit", "erpnext", ["employees"]),
    ("seafile", "Seafile", "jit", "seafile", ["employees"]),
    ("penpot", "Penpot", "jit", "penpot", ["employees"]),
    ("netbird", "NetBird", "jit", "netbird", ["employees", "app-netbird"]),
    ("guacamole", "Guacamole", "pre_provision", "guacamole", ["employees", "app-guacamole"]),
    ("osticket", "osTicket agents", "pre_provision", "osticket", ["employees", "app-osticket-agent"]),
    ("vaultwarden", "Vaultwarden", "invitation", "vaultwarden", ["employees", "app-vaultwarden"]),
)

ALLOWED_ATTRIBUTES = {
    "employeeNumber",
    "jobTitle",
    "location",
    "subunit",
    "supervisor",
}

LIFECYCLE_STATES = {
    "ineligible",
    "not_ready",
    "planned",
    "awaiting_first_login",
    "invited",
    "active",
    "conflict",
    "suspended",
    "error",
}
MUTATING_ACTIONS = {"create", "create_login", "link", "update", "disable", "reactivate"}
SENSITIVE_KEYS = {
    "password", "secret", "token", "api_key", "apikey", "authorization", "credential",
    "key", "privatekey", "accountkeys", "masterkeyencrypteduserkey", "masterkeywrappeduserkey",
}


class ProvisioningError(RuntimeError):
    pass


@dataclass(frozen=True)
class SourceUser:
    issuer: str
    subject: str
    username: str
    email: str | None
    email_verified: bool
    first_name: str
    last_name: str
    enabled: bool
    groups: tuple[str, ...]
    attributes: dict[str, Any] = field(default_factory=dict)

    @property
    def state_hash(self) -> str:
        payload = {
            "issuer": self.issuer,
            "subject": self.subject,
            "username": self.username,
            "email": self.email,
            "email_verified": self.email_verified,
            "first_name": self.first_name,
            "last_name": self.last_name,
            "enabled": self.enabled,
            "groups": sorted(self.groups),
            "attributes": self.attributes,
        }
        return hashlib.sha256(json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


@dataclass(frozen=True)
class AdapterDecision:
    state: str
    action: str | None = None
    target_account_id: str | None = None
    target_username: str | None = None
    details: dict[str, Any] = field(default_factory=dict)


class KeycloakConnector:
    def __init__(self) -> None:
        self.base_url = os.getenv("PROVISIONING_KEYCLOAK_URL", "http://keycloak:8080").rstrip("/")
        self.realm = os.getenv("KEYCLOAK_REALM", "support")
        self.client_id = os.getenv("PROVISIONING_KEYCLOAK_CLIENT_ID", "support-tools-provisioning")
        self.client_secret = os.getenv("PROVISIONING_KEYCLOAK_CLIENT_SECRET", "")
        self.timeout = int(os.getenv("PROVISIONING_HTTP_TIMEOUT_SECONDS", "20"))

    @property
    def issuer(self) -> str:
        configured = os.getenv("PROVISIONING_KEYCLOAK_ISSUER", "").strip()
        return configured or f"{self.base_url}/realms/{self.realm}"

    def _request(self, url: str, *, token: str | None = None, data: bytes | None = None) -> Any:
        headers = {"Accept": "application/json"}
        if token:
            headers["Authorization"] = f"Bearer {token}"
        if data is not None:
            headers["Content-Type"] = "application/x-www-form-urlencoded"
        request = urllib.request.Request(url, data=data, headers=headers)
        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                return json.load(response)
        except urllib.error.HTTPError as exc:
            body = exc.read(512).decode("utf-8", errors="replace")
            raise ProvisioningError(f"Keycloak request failed with HTTP {exc.code}: {body}") from exc
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
            raise ProvisioningError(f"Keycloak request failed: {exc}") from exc

    def token(self) -> str:
        if not self.client_secret:
            raise ProvisioningError("PROVISIONING_KEYCLOAK_CLIENT_SECRET is not configured")
        data = urllib.parse.urlencode(
            {
                "grant_type": "client_credentials",
                "client_id": self.client_id,
                "client_secret": self.client_secret,
            }
        ).encode()
        payload = self._request(f"{self.base_url}/realms/{self.realm}/protocol/openid-connect/token", data=data)
        token = payload.get("access_token")
        if not token:
            raise ProvisioningError("Keycloak token response did not contain an access token")
        return str(token)

    def fetch_users(self) -> list[SourceUser]:
        token = self.token()
        users: list[SourceUser] = []
        first = 0
        page_size = 100
        while True:
            query = urllib.parse.urlencode({"first": first, "max": page_size, "briefRepresentation": "false"})
            page = self._request(
                f"{self.base_url}/admin/realms/{self.realm}/users?{query}", token=token
            )
            if not isinstance(page, list):
                raise ProvisioningError("Unexpected Keycloak users response")
            for raw in page:
                subject = str(raw.get("id", "")).strip()
                if not subject:
                    continue
                group_rows = self._request(
                    f"{self.base_url}/admin/realms/{self.realm}/users/{urllib.parse.quote(subject)}/groups",
                    token=token,
                )
                groups = tuple(
                    sorted(
                        {
                            str(group.get("path") or group.get("name") or "").strip().lstrip("/")
                            for group in group_rows
                            if str(group.get("path") or group.get("name") or "").strip()
                        }
                    )
                )
                attributes = {
                    key: value
                    for key, value in (raw.get("attributes") or {}).items()
                    if key in ALLOWED_ATTRIBUTES
                }
                email = str(raw.get("email") or "").strip().lower() or None
                users.append(
                    SourceUser(
                        issuer=self.issuer,
                        subject=subject,
                        username=str(raw.get("username") or "").strip(),
                        email=email,
                        email_verified=bool(raw.get("emailVerified", False)),
                        first_name=str(raw.get("firstName") or "").strip(),
                        last_name=str(raw.get("lastName") or "").strip(),
                        enabled=bool(raw.get("enabled", False)),
                        groups=groups,
                        attributes=attributes,
                    )
                )
            if len(page) < page_size:
                break
            first += page_size
        return users


class TargetAdapter:
    capabilities = frozenset({"discover", "plan", "verify"})

    def supports(self, operation: str) -> bool:
        return operation in self.capabilities

    def discover(self, source: SourceIdentity, target: ProvisioningTarget) -> AdapterDecision:
        raise NotImplementedError

    def plan(self, source: SourceIdentity, target: ProvisioningTarget) -> AdapterDecision:
        return self.discover(source, target)

    def discover_linked(
        self,
        source: SourceIdentity,
        target: ProvisioningTarget,
        link: IdentityLink | None,
    ) -> AdapterDecision:
        return self.discover(source, target)

    def create(
        self, action: ProvisioningAction, source: SourceIdentity, target: ProvisioningTarget
    ) -> AdapterDecision:
        raise ProvisioningError(f"Adapter '{target.adapter}' has no create implementation")

    def link(
        self, action: ProvisioningAction, source: SourceIdentity, target: ProvisioningTarget
    ) -> AdapterDecision:
        raise ProvisioningError(f"Adapter '{target.adapter}' has no link implementation")

    def update(
        self, action: ProvisioningAction, source: SourceIdentity, target: ProvisioningTarget
    ) -> AdapterDecision:
        raise ProvisioningError(f"Adapter '{target.adapter}' has no update implementation")

    def disable(
        self, action: ProvisioningAction, source: SourceIdentity, target: ProvisioningTarget
    ) -> AdapterDecision:
        raise ProvisioningError(f"Adapter '{target.adapter}' has no disable implementation")

    def reactivate(
        self, action: ProvisioningAction, source: SourceIdentity, target: ProvisioningTarget
    ) -> AdapterDecision:
        raise ProvisioningError(f"Adapter '{target.adapter}' has no reactivate implementation")

    def verify(
        self, action: ProvisioningAction, source: SourceIdentity, target: ProvisioningTarget
    ) -> AdapterDecision:
        return self.discover(source, target)

    def execute(
        self, action: ProvisioningAction, source: SourceIdentity, target: ProvisioningTarget
    ) -> AdapterDecision:
        if not self.supports(action.action):
            raise ProvisioningError(
                f"Adapter '{target.adapter}' does not support operation '{action.action}'"
            )
        operation = getattr(self, action.action, None)
        if operation is None:
            raise ProvisioningError(f"Adapter '{target.adapter}' has no write implementation")
        return operation(action, source, target)

    def health(self, target: ProvisioningTarget) -> dict[str, Any]:
        return {
            "status": "ready",
            "adapter": target.adapter,
            "capabilities": sorted(self.capabilities),
        }


def validate_decision(adapter: TargetAdapter, decision: AdapterDecision) -> AdapterDecision:
    if decision.state not in LIFECYCLE_STATES:
        raise ProvisioningError(f"Adapter returned unsupported lifecycle state '{decision.state}'")
    if decision.action and decision.action in MUTATING_ACTIONS and not adapter.supports(decision.action):
        raise ProvisioningError(
            f"Adapter planned unsupported operation '{decision.action}'"
        )
    return decision


class ManualAdapter(TargetAdapter):
    def discover(self, source: SourceIdentity, target: ProvisioningTarget) -> AdapterDecision:
        return AdapterDecision(
            state="not_ready",
            action="manual_review",
            details={"reason": f"The {target.display_name} adapter is registered but not implemented"},
        )


class MariaDbAdapter(TargetAdapter):
    env_prefix = ""

    def health(self, target: ProvisioningTarget) -> dict[str, Any]:
        missing = [
            f"{self.env_prefix}_{name}"
            for name in ("DB_HOST", "DB_USER", "DB_PASSWORD", "DB_NAME")
            if not os.getenv(f"{self.env_prefix}_{name}", "")
        ]
        return {
            "status": "ready" if not missing else "not_configured",
            "adapter": target.adapter,
            "capabilities": sorted(self.capabilities),
            "missing": missing,
        }

    def connect(self):
        def required(name: str) -> str:
            value = os.getenv(f"{self.env_prefix}_{name}", "")
            if not value:
                raise ProvisioningError(f"{self.env_prefix}_{name} is not configured")
            return value

        return pymysql.connect(
            host=required("DB_HOST"),
            port=int(os.getenv(f"{self.env_prefix}_DB_PORT", "3306")),
            user=required("DB_USER"),
            password=required("DB_PASSWORD"),
            database=required("DB_NAME"),
            connect_timeout=10,
            read_timeout=15,
            write_timeout=15,
            autocommit=False,
            cursorclass=pymysql.cursors.DictCursor,
        )

    @staticmethod
    def require_columns(connection, table: str, required: set[str]) -> None:
        with connection.cursor() as cursor:
            cursor.execute(
                "SELECT COLUMN_NAME FROM information_schema.COLUMNS "
                "WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = %s",
                (table,),
            )
            columns = {row["COLUMN_NAME"] for row in cursor.fetchall()}
        missing = required - columns
        if missing:
            raise ProvisioningError(
                f"Schema guard failed for {table}; missing columns: {', '.join(sorted(missing))}"
            )


def protection_values(target: ProvisioningTarget, kind: str) -> set[str]:
    setting_name = f"protected_{kind}"
    configured = (target.settings or {}).get(setting_name, [])
    if isinstance(configured, str):
        values = re.split(r"[,;\n]", configured)
    else:
        values = [str(value) for value in configured]
    target_prefix = re.sub(r"[^A-Z0-9]", "_", target.id.upper())
    environment = os.getenv(
        f"PROVISIONING_{target_prefix}_PROTECTED_{kind.upper()}", ""
    )
    values.extend(re.split(r"[,;\n]", environment))
    normalized = {str(value).strip() for value in values if str(value).strip()}
    if kind in {"usernames", "emails"}:
        return {value.casefold() for value in normalized}
    return normalized


def protected_account_reason(
    target: ProvisioningTarget,
    *,
    account_id: str | int | None = None,
    username: str | None = None,
    email: str | None = None,
    privileged: bool = False,
) -> str | None:
    if privileged:
        return "Target account has a privileged or built-in role"
    if account_id is not None and str(account_id) in protection_values(target, "account_ids"):
        return "Target account ID is protected"
    if username and username.strip().casefold() in protection_values(target, "usernames"):
        return "Target username is protected"
    if email and email.strip().casefold() in protection_values(target, "emails"):
        return "Target email is protected"
    return None


class BookStackAdapter(MariaDbAdapter):
    env_prefix = "PROVISIONING_BOOKSTACK"
    capabilities = frozenset({"discover", "plan", "link", "disable", "reactivate", "verify"})

    def discover(self, source: SourceIdentity, target: ProvisioningTarget) -> AdapterDecision:
        if not source.email or not source.email_verified:
            return AdapterDecision("not_ready", details={"reason": "Verified email is required"})
        protected_reason = protected_account_reason(
            target, username=source.username, email=source.email
        )
        if protected_reason:
            return AdapterDecision("conflict", details={"reason": protected_reason})
        with self.connect() as connection:
            self.require_columns(connection, "users", {"id", "email", "external_auth_id"})
            with connection.cursor() as cursor:
                cursor.execute(
                    "SELECT u.id, u.email, u.external_auth_id, u.system_name, "
                    "EXISTS(SELECT 1 FROM role_user ru JOIN roles r ON r.id=ru.role_id "
                    "WHERE ru.user_id=u.id AND r.system_name='admin') AS is_admin "
                    "FROM users u WHERE u.external_auth_id = %s OR LOWER(u.email) = LOWER(%s) "
                    "ORDER BY u.id",
                    (source.subject, source.email),
                )
                rows = cursor.fetchall()
        for row in rows:
            protected_reason = protected_account_reason(
                target,
                account_id=row["id"],
                username=row.get("email"),
                email=row.get("email"),
                privileged=bool(row.get("system_name")) or bool(row.get("is_admin")),
            )
            if protected_reason:
                return AdapterDecision("conflict", details={"reason": protected_reason})
        by_subject = [row for row in rows if row.get("external_auth_id") == source.subject]
        if len(by_subject) == 1:
            row = by_subject[0]
            return AdapterDecision("active", target_account_id=str(row["id"]), target_username=row["email"])
        if len(by_subject) > 1:
            return AdapterDecision("conflict", details={"reason": "Multiple accounts use this external subject"})
        by_email = [row for row in rows if str(row.get("email", "")).lower() == source.email.lower()]
        if len(by_email) > 1:
            return AdapterDecision("conflict", details={"reason": "Multiple accounts use this email"})
        if len(by_email) == 1:
            row = by_email[0]
            external_id = str(row.get("external_auth_id") or "")
            if external_id and external_id != source.subject:
                return AdapterDecision(
                    "conflict",
                    details={"reason": "Existing email is linked to another external subject"},
                )
            return AdapterDecision(
                "planned",
                action="link",
                target_account_id=str(row["id"]),
                target_username=row["email"],
                details={"account_id": str(row["id"]), "email": source.email},
            )
        return AdapterDecision(
            "awaiting_first_login",
            action="verify_after_login",
            details={"email": source.email},
        )

    def link(
        self, action: ProvisioningAction, source: SourceIdentity, target: ProvisioningTarget
    ) -> AdapterDecision:
        account_id = str(action.details.get("account_id", ""))
        if not account_id:
            raise ProvisioningError("BookStack action has no account ID")
        protected_reason = protected_account_reason(
            target, account_id=account_id, username=source.username, email=source.email
        )
        if protected_reason:
            raise ProvisioningError(protected_reason)
        with self.connect() as connection:
            self.require_columns(connection, "users", {"id", "email", "external_auth_id"})
            with connection.cursor() as cursor:
                cursor.execute(
                    "SELECT u.system_name, EXISTS(SELECT 1 FROM role_user ru "
                    "JOIN roles r ON r.id=ru.role_id WHERE ru.user_id=u.id "
                    "AND r.system_name='admin') AS is_admin FROM users u WHERE u.id=%s",
                    (account_id,),
                )
                row = cursor.fetchone()
                if not row or row.get("system_name") or row.get("is_admin"):
                    connection.rollback()
                    raise ProvisioningError("BookStack account is missing or protected")
                cursor.execute(
                    "UPDATE users SET external_auth_id=%s WHERE id=%s AND LOWER(email)=LOWER(%s) "
                    "AND (external_auth_id IS NULL OR external_auth_id='')",
                    (source.subject, account_id, source.email),
                )
                if cursor.rowcount != 1:
                    connection.rollback()
                    raise ProvisioningError("BookStack account changed after planning; no update applied")
            connection.commit()
        return AdapterDecision("active", target_account_id=account_id, target_username=source.email)

    def disable(
        self, action: ProvisioningAction, source: SourceIdentity, target: ProvisioningTarget
    ) -> AdapterDecision:
        account_id = str(action.details.get("account_id") or action.target_account_id or "")
        if not account_id:
            raise ProvisioningError("BookStack action has no account ID")
        with self.connect() as connection:
            self.require_columns(connection, "users", {"id", "email", "external_auth_id"})
            self.require_columns(connection, "sessions", {"user_id"})
            with connection.cursor() as cursor:
                cursor.execute(
                    "SELECT u.id,u.email,u.external_auth_id,u.system_name,"
                    "EXISTS(SELECT 1 FROM role_user ru JOIN roles r ON r.id=ru.role_id "
                    "WHERE ru.user_id=u.id AND r.system_name='admin') AS is_admin "
                    "FROM users u WHERE u.id=%s",
                    (account_id,),
                )
                row = cursor.fetchone()
                if not row or row.get("external_auth_id") != source.subject:
                    connection.rollback()
                    raise ProvisioningError("BookStack identity changed after planning; no update applied")
                protected_reason = protected_account_reason(
                    target,
                    account_id=row["id"],
                    username=row.get("email"),
                    email=row.get("email"),
                    privileged=bool(row.get("system_name")) or bool(row.get("is_admin")),
                )
                if protected_reason:
                    connection.rollback()
                    raise ProvisioningError(protected_reason)
                cursor.execute("DELETE FROM sessions WHERE user_id=%s", (account_id,))
                sessions_revoked = cursor.rowcount
            connection.commit()
        return AdapterDecision(
            "suspended",
            target_account_id=account_id,
            target_username=row["email"],
            details={"sessions_revoked": sessions_revoked},
        )

    def reactivate(
        self, action: ProvisioningAction, source: SourceIdentity, target: ProvisioningTarget
    ) -> AdapterDecision:
        result = self.discover(source, target)
        account_id = str(action.details.get("account_id") or action.target_account_id or "")
        if result.state != "active" or not result.target_account_id:
            raise ProvisioningError("BookStack account is not ready for reactivation")
        if account_id and result.target_account_id != account_id:
            raise ProvisioningError("BookStack identity changed after planning; no update applied")
        return result


class EspoCrmAdapter(MariaDbAdapter):
    env_prefix = "PROVISIONING_ESPOCRM"
    capabilities = frozenset({"discover", "plan", "disable", "reactivate", "verify"})

    def require_schema(self, connection) -> None:
        self.require_columns(
            connection,
            "user",
            {"id", "deleted", "user_name", "type", "is_active", "first_name", "last_name"},
        )
        self.require_columns(
            connection,
            "auth_token",
            {"id", "deleted", "is_active", "user_id"},
        )
        self.require_columns(
            connection,
            "entity_email_address",
            {"entity_id", "email_address_id", "entity_type", "primary", "deleted"},
        )
        self.require_columns(connection, "email_address", {"id", "name", "lower", "deleted"})
        self.require_columns(connection, "role_user", {"role_id", "user_id", "deleted"})
        self.require_columns(connection, "team_user", {"team_id", "user_id", "deleted"})

    @staticmethod
    def relation_ids(value: Any) -> tuple[str, ...]:
        return tuple(sorted(item for item in str(value or "").split(",") if item))

    @staticmethod
    def account_select() -> str:
        return (
            "SELECT u.id,u.user_name,u.type,u.is_active,u.deleted,u.first_name,u.last_name,"
            "(SELECT ea.name FROM entity_email_address eea "
            "JOIN email_address ea ON ea.id=eea.email_address_id AND ea.deleted=0 "
            "WHERE eea.entity_id=u.id AND eea.entity_type='User' "
            "AND eea.primary=1 AND eea.deleted=0 LIMIT 1) AS email,"
            "(SELECT GROUP_CONCAT(ru.role_id ORDER BY ru.role_id SEPARATOR ',') "
            "FROM role_user ru WHERE ru.user_id=u.id AND ru.deleted=0) AS role_ids,"
            "(SELECT GROUP_CONCAT(tu.team_id ORDER BY tu.team_id SEPARATOR ',') "
            "FROM team_user tu WHERE tu.user_id=u.id AND tu.deleted=0) AS team_ids "
            "FROM user u "
        )

    def account_details(self, row: dict[str, Any]) -> dict[str, Any]:
        role_ids = self.relation_ids(row.get("role_ids"))
        team_ids = self.relation_ids(row.get("team_ids"))
        return {
            "account_id": str(row["id"]),
            "external_subject": str(row["user_name"]),
            "email": str(row.get("email") or ""),
            "role_count": len(role_ids),
            "role_ids": list(role_ids),
            "team_count": len(team_ids),
            "team_ids": list(team_ids),
        }

    def account_rows(
        self, connection, source: SourceIdentity
    ) -> list[dict[str, Any]]:
        with connection.cursor() as cursor:
            cursor.execute(
                self.account_select()
                + "WHERE u.deleted=0 AND (u.user_name=%s OR EXISTS ("
                "SELECT 1 FROM entity_email_address eea2 "
                "JOIN email_address ea2 ON ea2.id=eea2.email_address_id AND ea2.deleted=0 "
                "WHERE eea2.entity_id=u.id AND eea2.entity_type='User' "
                "AND eea2.deleted=0 AND ea2.lower=LOWER(%s))) ORDER BY u.id",
                (source.subject, source.email),
            )
            return list(cursor.fetchall())

    def discover(self, source: SourceIdentity, target: ProvisioningTarget) -> AdapterDecision:
        if not source.email or not source.email_verified:
            return AdapterDecision("not_ready", details={"reason": "Verified email is required"})
        protected_reason = protected_account_reason(
            target, username=source.username, email=source.email
        )
        if protected_reason:
            return AdapterDecision("conflict", details={"reason": protected_reason})
        with self.connect() as connection:
            self.require_schema(connection)
            rows = self.account_rows(connection, source)
        by_subject = [row for row in rows if str(row.get("user_name") or "") == source.subject]
        if len(by_subject) > 1:
            return AdapterDecision(
                "conflict", details={"reason": "Multiple EspoCRM users use this Keycloak subject"}
            )
        if by_subject:
            row = by_subject[0]
            if any(str(other.get("id")) != str(row.get("id")) for other in rows):
                return AdapterDecision(
                    "conflict",
                    details={"reason": "Keycloak email belongs to another EspoCRM user"},
                )
            protected_reason = protected_account_reason(
                target,
                account_id=row["id"],
                username=row.get("user_name"),
                email=row.get("email"),
                privileged=str(row.get("type") or "") != "regular",
            )
            if protected_reason:
                return AdapterDecision("conflict", details={"reason": protected_reason})
            suspended = not bool(row.get("is_active"))
            return AdapterDecision(
                "suspended" if suspended else "active",
                action="reactivate" if suspended else None,
                target_account_id=str(row["id"]),
                target_username=str(row["user_name"]),
                details=self.account_details(row),
            )
        if rows:
            return AdapterDecision(
                "conflict",
                details={"reason": "Verified email belongs to another EspoCRM identity"},
            )
        return AdapterDecision(
            "awaiting_first_login",
            action="verify_after_login",
            details={"email": source.email},
        )

    def disable(
        self, action: ProvisioningAction, source: SourceIdentity, target: ProvisioningTarget
    ) -> AdapterDecision:
        return self._set_active(action, source, target, active=False)

    def reactivate(
        self, action: ProvisioningAction, source: SourceIdentity, target: ProvisioningTarget
    ) -> AdapterDecision:
        return self._set_active(action, source, target, active=True)

    def _set_active(
        self,
        action: ProvisioningAction,
        source: SourceIdentity,
        target: ProvisioningTarget,
        *,
        active: bool,
    ) -> AdapterDecision:
        account_id = str(action.details.get("account_id") or action.target_account_id or "")
        if not account_id:
            raise ProvisioningError("EspoCRM action has no account ID")
        with self.connect() as connection:
            self.require_schema(connection)
            with connection.cursor() as cursor:
                cursor.execute(
                    self.account_select()
                    + "WHERE u.id=%s AND u.user_name=%s AND u.deleted=0 FOR UPDATE",
                    (account_id, source.subject),
                )
                row = cursor.fetchone()
                protected_reason = protected_account_reason(
                    target,
                    account_id=account_id,
                    username=row.get("user_name") if row else None,
                    email=row.get("email") if row else None,
                    privileged=not row or str(row.get("type") or "") != "regular",
                )
                if protected_reason:
                    connection.rollback()
                    raise ProvisioningError(protected_reason)
                role_ids_before = self.relation_ids(row.get("role_ids"))
                team_ids_before = self.relation_ids(row.get("team_ids"))
                cursor.execute(
                    "UPDATE user SET is_active=%s,modified_at=UTC_TIMESTAMP() "
                    "WHERE id=%s AND user_name=%s AND type='regular' AND deleted=0",
                    (1 if active else 0, account_id, source.subject),
                )
                if cursor.rowcount != 1:
                    connection.rollback()
                    raise ProvisioningError(
                        "EspoCRM identity changed after planning; no update applied"
                    )
                tokens_revoked = 0
                if not active:
                    cursor.execute(
                        "UPDATE auth_token SET is_active=0,modified_at=UTC_TIMESTAMP() "
                        "WHERE user_id=%s AND deleted=0 AND is_active=1",
                        (account_id,),
                    )
                    tokens_revoked = cursor.rowcount
                cursor.execute(
                    self.account_select() + "WHERE u.id=%s AND u.deleted=0",
                    (account_id,),
                )
                updated = cursor.fetchone()
                if not updated or bool(updated.get("is_active")) != active:
                    connection.rollback()
                    raise ProvisioningError("EspoCRM did not confirm the requested active state")
                if (
                    self.relation_ids(updated.get("role_ids")) != role_ids_before
                    or self.relation_ids(updated.get("team_ids")) != team_ids_before
                ):
                    connection.rollback()
                    raise ProvisioningError(
                        "EspoCRM roles or teams changed during user lifecycle update"
                    )
            connection.commit()
        return AdapterDecision(
            "active" if active else "suspended",
            target_account_id=account_id,
            target_username=str(updated["user_name"]),
            details={
                **self.account_details(updated),
                "tokens_revoked": tokens_revoked,
                "roles_preserved": True,
                "teams_preserved": True,
            },
        )


class ErpNextAdapter(MariaDbAdapter):
    env_prefix = "PROVISIONING_ERPNEXT"
    capabilities = frozenset({"discover", "plan", "link", "disable", "reactivate", "verify"})

    def site_config(self) -> dict[str, Any]:
        sites_dir = Path(os.getenv("PROVISIONING_ERPNEXT_SITES_DIR", "/erpnext-sites"))
        site_name = os.getenv("PROVISIONING_ERPNEXT_SITE_NAME", "").strip()
        if not site_name:
            raise ProvisioningError("PROVISIONING_ERPNEXT_SITE_NAME is not configured")
        config_path = sites_dir / site_name / "site_config.json"
        try:
            config = json.loads(config_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            raise ProvisioningError(f"Cannot read ERPNext site configuration: {config_path}") from error
        if not config.get("db_name") or not config.get("db_password"):
            raise ProvisioningError("ERPNext site configuration has no database credentials")
        return config

    def health(self, target: ProvisioningTarget) -> dict[str, Any]:
        missing = [
            name
            for name in ("PROVISIONING_ERPNEXT_SITE_NAME", "PROVISIONING_ERPNEXT_SITES_DIR")
            if not os.getenv(name, "")
        ]
        if not missing:
            try:
                self.site_config()
            except ProvisioningError:
                missing.append("readable ERPNext site_config.json")
        return {
            "status": "ready" if not missing else "not_configured",
            "adapter": target.adapter,
            "capabilities": sorted(self.capabilities),
            "missing": missing,
        }

    def connect(self):
        config = self.site_config()
        return pymysql.connect(
            host=os.getenv("PROVISIONING_ERPNEXT_DB_HOST", "erpnext-db"),
            port=int(os.getenv("PROVISIONING_ERPNEXT_DB_PORT", "3306")),
            user=str(config["db_name"]),
            password=str(config["db_password"]),
            database=str(config["db_name"]),
            connect_timeout=10,
            read_timeout=15,
            write_timeout=15,
            autocommit=False,
            cursorclass=pymysql.cursors.DictCursor,
        )

    def revoke_cached_sessions(self, session_ids: list[str]) -> None:
        if not session_ids:
            return
        database_name = str(self.site_config()["db_name"])
        cache = redis.Redis(
            host=os.getenv("PROVISIONING_ERPNEXT_REDIS_HOST", "erpnext-redis-cache"),
            port=int(os.getenv("PROVISIONING_ERPNEXT_REDIS_PORT", "6379")),
            socket_connect_timeout=5,
            socket_timeout=5,
        )
        pipeline = cache.pipeline(transaction=True)
        pipeline.hdel(f"{database_name}|session", *session_ids)
        pipeline.hdel(f"{database_name}|last_db_session_update", *session_ids)
        pipeline.execute()

    def require_schema(self, connection) -> None:
        self.require_columns(connection, "tabUser", {"name", "email", "enabled", "user_type"})
        self.require_columns(
            connection,
            "tabUser Social Login",
            {"name", "parent", "parenttype", "parentfield", "provider", "userid"},
        )
        self.require_columns(connection, "tabHas Role", {"parent", "parenttype", "role"})
        self.require_columns(connection, "tabSessions", {"user"})

    @staticmethod
    def is_privileged(row: dict[str, Any]) -> bool:
        return bool(row.get("is_privileged")) or row.get("name") in {"Administrator", "Guest"}

    def discover(self, source: SourceIdentity, target: ProvisioningTarget) -> AdapterDecision:
        if not source.email or not source.email_verified:
            return AdapterDecision("not_ready", details={"reason": "Verified email is required"})
        protected_reason = protected_account_reason(
            target, username=source.username, email=source.email
        )
        if protected_reason:
            return AdapterDecision("conflict", details={"reason": protected_reason})
        with self.connect() as connection:
            self.require_schema(connection)
            with connection.cursor() as cursor:
                cursor.execute(
                    "SELECT u.name,u.email,u.enabled,u.user_type,sl.name AS social_login_name,"
                    "sl.userid,EXISTS(SELECT 1 FROM `tabHas Role` hr WHERE hr.parent=u.name "
                    "AND hr.parenttype='User' AND hr.role IN ('Administrator','System Manager')) "
                    "AS is_privileged FROM `tabUser` u LEFT JOIN `tabUser Social Login` sl "
                    "ON sl.parent=u.name AND sl.parenttype='User' AND sl.provider='keycloak' "
                    "WHERE sl.userid=%s OR LOWER(u.email)=LOWER(%s) ORDER BY u.name",
                    (source.subject, source.email),
                )
                rows = cursor.fetchall()
        by_subject = [row for row in rows if str(row.get("userid") or "") == source.subject]
        if len(by_subject) > 1:
            return AdapterDecision(
                "conflict", details={"reason": "Multiple ERPNext users use this Keycloak subject"}
            )
        if by_subject:
            row = by_subject[0]
            protected_reason = protected_account_reason(
                target,
                account_id=row["name"],
                username=row["name"],
                email=row.get("email"),
                privileged=self.is_privileged(row),
            )
            if protected_reason:
                return AdapterDecision("conflict", details={"reason": protected_reason})
            if str(row.get("email") or "").casefold() != source.email.casefold():
                return AdapterDecision(
                    "not_ready",
                    action="manual_review",
                    target_account_id=str(row["name"]),
                    target_username=str(row["email"]),
                    details={
                        "reason": "Keycloak email changed; ERPNext email migration must be reviewed before login",
                        "account_id": str(row["name"]),
                    },
                )
            if row.get("user_type") not in {"Website User", "System User"}:
                return AdapterDecision(
                    "conflict",
                    details={"reason": "Frappe account has an unsupported user type"},
                )
            suspended = not bool(row.get("enabled"))
            return AdapterDecision(
                "suspended" if suspended else "active",
                action="reactivate" if suspended else None,
                target_account_id=str(row["name"]),
                target_username=str(row["email"]),
                details={
                    "account_id": str(row["name"]),
                    "social_login": "keycloak",
                    "user_type": str(row["user_type"]),
                },
            )

        by_email = [
            row
            for row in rows
            if str(row.get("email") or "").casefold() == source.email.casefold()
        ]
        if len(by_email) > 1:
            return AdapterDecision(
                "conflict", details={"reason": "Multiple ERPNext users match this email"}
            )
        if by_email:
            row = by_email[0]
            if self.is_privileged(row):
                return AdapterDecision(
                    "conflict", details={"reason": "ERPNext email belongs to a privileged account"}
                )
            existing_id = str(row.get("userid") or "")
            if existing_id:
                if existing_id != source.username:
                    return AdapterDecision(
                        "conflict",
                        details={"reason": "ERPNext email is linked to another external identity"},
                    )
                return AdapterDecision(
                    "planned",
                    action="link",
                    target_account_id=str(row["name"]),
                    target_username=str(row["email"]),
                    details={
                        "account_id": str(row["name"]),
                        "social_login_name": str(row["social_login_name"]),
                        "legacy_identifier": existing_id,
                    },
                )
        return AdapterDecision(
            "awaiting_first_login",
            action="verify_after_login",
            details={"email": source.email},
        )

    def link(
        self, action: ProvisioningAction, source: SourceIdentity, target: ProvisioningTarget
    ) -> AdapterDecision:
        account_id = str(action.details.get("account_id") or action.target_account_id or "")
        social_login_name = str(action.details.get("social_login_name") or "")
        legacy_identifier = str(action.details.get("legacy_identifier") or "")
        if not account_id or not social_login_name or legacy_identifier != source.username:
            raise ProvisioningError("ERPNext legacy-link migration is incomplete or stale")
        with self.connect() as connection:
            self.require_schema(connection)
            with connection.cursor() as cursor:
                cursor.execute(
                    "SELECT u.name,u.email,u.user_type,sl.userid,"
                    "EXISTS(SELECT 1 FROM `tabHas Role` hr WHERE hr.parent=u.name "
                    "AND hr.parenttype='User' AND hr.role IN ('Administrator','System Manager')) "
                    "AS is_privileged FROM `tabUser` u JOIN `tabUser Social Login` sl "
                    "ON sl.parent=u.name AND sl.parenttype='User' AND sl.provider='keycloak' "
                    "WHERE sl.name=%s AND u.name=%s FOR UPDATE",
                    (social_login_name, account_id),
                )
                row = cursor.fetchone()
                protected_reason = protected_account_reason(
                    target,
                    account_id=account_id,
                    username=account_id,
                    email=row.get("email") if row else None,
                    privileged=self.is_privileged(row or {}),
                )
                valid = (
                    row
                    and row.get("user_type") in {"Website User", "System User"}
                    and str(row.get("userid") or "") == legacy_identifier
                    and str(row.get("email") or "").casefold() == source.email.casefold()
                    and not protected_reason
                )
                if not valid:
                    connection.rollback()
                    raise ProvisioningError(
                        protected_reason
                        or "ERPNext legacy link changed after planning; no update applied"
                    )
                cursor.execute(
                    "UPDATE `tabUser Social Login` SET userid=%s "
                    "WHERE name=%s AND parent=%s AND parenttype='User' "
                    "AND provider='keycloak' AND userid=%s",
                    (source.subject, social_login_name, account_id, legacy_identifier),
                )
                if cursor.rowcount != 1:
                    connection.rollback()
                    raise ProvisioningError("ERPNext legacy link changed after planning; no update applied")
            connection.commit()
        return AdapterDecision(
            "active",
            target_account_id=account_id,
            target_username=source.email,
            details={"account_id": account_id, "social_login": "keycloak"},
        )

    def disable(
        self, action: ProvisioningAction, source: SourceIdentity, target: ProvisioningTarget
    ) -> AdapterDecision:
        return self._set_enabled(action, source, target, enabled=False)

    def reactivate(
        self, action: ProvisioningAction, source: SourceIdentity, target: ProvisioningTarget
    ) -> AdapterDecision:
        return self._set_enabled(action, source, target, enabled=True)

    def _set_enabled(
        self,
        action: ProvisioningAction,
        source: SourceIdentity,
        target: ProvisioningTarget,
        *,
        enabled: bool,
    ) -> AdapterDecision:
        account_id = str(action.details.get("account_id") or action.target_account_id or "")
        if not account_id:
            raise ProvisioningError("ERPNext action has no account ID")
        with self.connect() as connection:
            self.require_schema(connection)
            with connection.cursor() as cursor:
                cursor.execute(
                    "SELECT u.name,u.email,u.user_type,EXISTS(SELECT 1 FROM `tabHas Role` hr "
                    "WHERE hr.parent=u.name AND hr.parenttype='User' "
                    "AND hr.role IN ('Administrator','System Manager')) AS is_privileged "
                    "FROM `tabUser` u JOIN `tabUser Social Login` sl ON sl.parent=u.name "
                    "AND sl.parenttype='User' AND sl.provider='keycloak' "
                    "WHERE u.name=%s AND sl.userid=%s FOR UPDATE",
                    (account_id, source.subject),
                )
                row = cursor.fetchone()
                if (
                    not row
                    or row.get("user_type") not in {"Website User", "System User"}
                    or self.is_privileged(row)
                ):
                    connection.rollback()
                    raise ProvisioningError("ERPNext identity changed or is protected; no update applied")
                protected_reason = protected_account_reason(
                    target,
                    account_id=row["name"],
                    username=row["name"],
                    email=row.get("email"),
                )
                if protected_reason:
                    connection.rollback()
                    raise ProvisioningError(protected_reason)
                if enabled and str(row.get("email") or "").casefold() != source.email.casefold():
                    connection.rollback()
                    raise ProvisioningError(
                        "ERPNext email changed; reviewed migration is required before reactivation"
                    )
                cursor.execute(
                    "UPDATE `tabUser` SET enabled=%s WHERE name=%s",
                    (1 if enabled else 0, account_id),
                )
                sessions_revoked = 0
                if not enabled:
                    cursor.execute("SELECT sid FROM `tabSessions` WHERE user=%s", (account_id,))
                    session_ids = [str(item["sid"]) for item in cursor.fetchall()]
                    cursor.execute("DELETE FROM `tabSessions` WHERE user=%s", (account_id,))
                    sessions_revoked = cursor.rowcount
                    self.revoke_cached_sessions(session_ids)
            connection.commit()
        return AdapterDecision(
            "active" if enabled else "suspended",
            target_account_id=account_id,
            target_username=str(row["email"]),
            details={"account_id": account_id, "sessions_revoked": sessions_revoked},
        )


class SeafileAdapter(MariaDbAdapter):
    env_prefix = "PROVISIONING_SEAFILE"
    capabilities = frozenset({"discover", "plan", "disable", "reactivate", "verify"})

    @property
    def ccnet_database(self) -> str:
        return self.database_name("PROVISIONING_SEAFILE_CCNET_DB_NAME", "ccnet_db")

    @property
    def seahub_database(self) -> str:
        return self.database_name("PROVISIONING_SEAFILE_SEAHUB_DB_NAME", "seahub_db")

    @staticmethod
    def database_name(environment_name: str, default: str) -> str:
        value = os.getenv(environment_name, default)
        if not re.fullmatch(r"[A-Za-z0-9_]+", value):
            raise ProvisioningError(f"{environment_name} is not a safe database identifier")
        return value

    @property
    def provider(self) -> str:
        return os.getenv("PROVISIONING_SEAFILE_OAUTH_PROVIDER", "keycloak")

    def health(self, target: ProvisioningTarget) -> dict[str, Any]:
        missing = []
        try:
            self.database_config()
        except ProvisioningError:
            missing.append("readable Seafile DATABASES configuration")
        return {
            "status": "ready" if not missing else "not_configured",
            "adapter": target.adapter,
            "capabilities": sorted(self.capabilities),
            "missing": missing,
        }

    def connect(self):
        config = self.database_config()
        return pymysql.connect(
            host=str(config["HOST"]),
            port=int(config.get("PORT", 3306)),
            user=str(config["USER"]),
            password=str(config["PASSWORD"]),
            database=self.ccnet_database,
            connect_timeout=10,
            read_timeout=15,
            write_timeout=15,
            autocommit=False,
            cursorclass=pymysql.cursors.DictCursor,
        )

    @staticmethod
    def database_config() -> dict[str, Any]:
        config_path = Path(
            os.getenv(
                "PROVISIONING_SEAFILE_CONFIG_FILE",
                "/seafile-shared/seafile/conf/seahub_settings.py",
            )
        )
        try:
            tree = ast.parse(config_path.read_text(encoding="utf-8"))
            assignment = next(
                node
                for node in tree.body
                if isinstance(node, ast.Assign)
                and any(getattr(target, "id", "") == "DATABASES" for target in node.targets)
            )
            config = ast.literal_eval(assignment.value)["default"]
        except (OSError, StopIteration, SyntaxError, ValueError, KeyError, TypeError) as error:
            raise ProvisioningError(
                f"Cannot read Seafile database configuration: {config_path}"
            ) from error
        required = {"HOST", "USER", "PASSWORD"}
        if required - set(config):
            raise ProvisioningError("Seafile DATABASES configuration is incomplete")
        return config

    @staticmethod
    def require_schema_columns(
        connection, schema: str, table: str, required: set[str]
    ) -> None:
        with connection.cursor() as cursor:
            cursor.execute(
                "SELECT COLUMN_NAME FROM information_schema.COLUMNS "
                "WHERE TABLE_SCHEMA=%s AND TABLE_NAME=%s",
                (schema, table),
            )
            columns = {row["COLUMN_NAME"] for row in cursor.fetchall()}
        missing = required - columns
        if missing:
            raise ProvisioningError(
                f"Schema guard failed for {schema}.{table}; missing columns: "
                f"{', '.join(sorted(missing))}"
            )

    def require_schema(self, connection) -> None:
        checks = (
            (self.ccnet_database, "EmailUser", {"id", "email", "is_staff", "is_active"}),
            (self.ccnet_database, "UserRole", {"email", "role"}),
            (self.ccnet_database, "GroupUser", {"user_name"}),
            (self.ccnet_database, "OrgUser", {"email"}),
            (
                self.seahub_database,
                "social_auth_usersocialauth",
                {"id", "username", "provider", "uid"},
            ),
            (self.seahub_database, "profile_profile", {"user", "contact_email"}),
            (self.seahub_database, "django_session", {"session_key", "session_data"}),
            (self.seahub_database, "api2_token", {"user"}),
            (self.seahub_database, "api2_tokenv2", {"user"}),
            (self.seahub_database, "base_clientlogintoken", {"username"}),
            (self.seahub_database, "base_clientssotoken", {"username"}),
            (self.seahub_database, "base_devicetoken", {"user"}),
        )
        for schema, table, columns in checks:
            self.require_schema_columns(connection, schema, table, columns)

    @staticmethod
    def decode_session(data: str) -> Any | None:
        try:
            payload = data.split(":", 1)[0]
            compressed = payload.startswith(".")
            payload = payload[1:] if compressed else payload
            payload += "=" * (-len(payload) % 4)
            decoded = base64.urlsafe_b64decode(payload.encode("ascii"))
            if compressed:
                decoded = zlib.decompress(decoded)
            return json.loads(decoded.decode("utf-8"))
        except (ValueError, TypeError, UnicodeDecodeError, zlib.error):
            return None

    @classmethod
    def session_belongs_to(cls, data: str, username: str) -> bool:
        session = cls.decode_session(data)
        if not isinstance(session, dict):
            return False
        return any(
            session.get(key) == username
            for key in ("_auth_user_name", "login_user", "username", "_auth_user_id")
        )

    def account_rows(self, connection, source: SourceIdentity) -> list[dict[str, Any]]:
        ccnet = f"`{self.ccnet_database}`"
        seahub = f"`{self.seahub_database}`"
        with connection.cursor() as cursor:
            cursor.execute(
                f"SELECT sa.id AS social_id,sa.username,sa.provider,sa.uid,"
                f"eu.id AS account_id,eu.email AS internal_username,eu.is_staff,eu.is_active,"
                f"p.contact_email,"
                f"EXISTS(SELECT 1 FROM {ccnet}.UserRole ur WHERE ur.email=eu.email "
                f"AND LOWER(ur.role) IN ('admin','administrator')) AS is_privileged_role,"
                f"(SELECT COUNT(*) FROM {ccnet}.GroupUser gu WHERE gu.user_name=eu.email) "
                f"AS group_count,(SELECT COUNT(*) FROM {ccnet}.OrgUser ou "
                f"WHERE ou.email=eu.email) AS organization_count "
                f"FROM {seahub}.social_auth_usersocialauth sa "
                f"JOIN {ccnet}.EmailUser eu ON eu.email=sa.username "
                f"LEFT JOIN {seahub}.profile_profile p ON p.user=sa.username "
                f"WHERE (sa.provider=%s AND sa.uid=%s) "
                f"OR LOWER(p.contact_email)=LOWER(%s) ORDER BY sa.id",
                (self.provider, source.subject, source.email),
            )
            return cursor.fetchall()

    @staticmethod
    def is_privileged(row: dict[str, Any]) -> bool:
        return bool(row.get("is_staff")) or bool(row.get("is_privileged_role"))

    def discover(self, source: SourceIdentity, target: ProvisioningTarget) -> AdapterDecision:
        if not source.email or not source.email_verified:
            return AdapterDecision("not_ready", details={"reason": "Verified email is required"})
        protected_reason = protected_account_reason(
            target, username=source.username, email=source.email
        )
        if protected_reason:
            return AdapterDecision("conflict", details={"reason": protected_reason})
        with self.connect() as connection:
            self.require_schema(connection)
            rows = self.account_rows(connection, source)
        by_subject = [
            row
            for row in rows
            if row.get("provider") == self.provider and str(row.get("uid") or "") == source.subject
        ]
        if len(by_subject) > 1:
            return AdapterDecision(
                "conflict", details={"reason": "Multiple Seafile users use this Keycloak subject"}
            )
        if by_subject:
            row = by_subject[0]
            if any(other.get("account_id") != row.get("account_id") for other in rows):
                return AdapterDecision(
                    "conflict",
                    details={"reason": "Keycloak email belongs to another Seafile identity"},
                )
            protected_reason = protected_account_reason(
                target,
                account_id=row["account_id"],
                username=row["internal_username"],
                email=row.get("contact_email"),
                privileged=self.is_privileged(row),
            )
            if protected_reason:
                return AdapterDecision("conflict", details={"reason": protected_reason})
            suspended = not bool(row.get("is_active"))
            return AdapterDecision(
                "suspended" if suspended else "active",
                action="reactivate" if suspended else None,
                target_account_id=str(row["account_id"]),
                target_username=str(row["internal_username"]),
                details={
                    "account_id": str(row["account_id"]),
                    "contact_email": row.get("contact_email"),
                    "groups": int(row.get("group_count") or 0),
                    "organizations": int(row.get("organization_count") or 0),
                    "provider": self.provider,
                },
            )
        if rows:
            return AdapterDecision(
                "conflict",
                details={"reason": "Verified email belongs to another Seafile identity"},
            )
        return AdapterDecision(
            "awaiting_first_login",
            action="verify_after_login",
            details={"email": source.email},
        )

    def disable(
        self, action: ProvisioningAction, source: SourceIdentity, target: ProvisioningTarget
    ) -> AdapterDecision:
        return self._set_active(action, source, target, active=False)

    def reactivate(
        self, action: ProvisioningAction, source: SourceIdentity, target: ProvisioningTarget
    ) -> AdapterDecision:
        return self._set_active(action, source, target, active=True)

    def _set_active(
        self,
        action: ProvisioningAction,
        source: SourceIdentity,
        target: ProvisioningTarget,
        *,
        active: bool,
    ) -> AdapterDecision:
        account_id = str(action.details.get("account_id") or action.target_account_id or "")
        if not account_id:
            raise ProvisioningError("Seafile action has no account ID")
        ccnet = f"`{self.ccnet_database}`"
        seahub = f"`{self.seahub_database}`"
        with self.connect() as connection:
            self.require_schema(connection)
            with connection.cursor() as cursor:
                cursor.execute(
                    f"SELECT eu.id AS account_id,eu.email AS internal_username,"
                    f"eu.is_staff,p.contact_email,"
                    f"EXISTS(SELECT 1 FROM {ccnet}.UserRole ur WHERE ur.email=eu.email "
                    f"AND LOWER(ur.role) IN ('admin','administrator')) AS is_privileged_role "
                    f"FROM {seahub}.social_auth_usersocialauth sa "
                    f"JOIN {ccnet}.EmailUser eu ON eu.email=sa.username "
                    f"LEFT JOIN {seahub}.profile_profile p ON p.user=sa.username "
                    f"WHERE eu.id=%s AND sa.provider=%s AND sa.uid=%s FOR UPDATE",
                    (account_id, self.provider, source.subject),
                )
                row = cursor.fetchone()
                if not row:
                    connection.rollback()
                    raise ProvisioningError("Seafile identity changed after planning; no update applied")
                protected_reason = protected_account_reason(
                    target,
                    account_id=row["account_id"],
                    username=row["internal_username"],
                    email=row.get("contact_email"),
                    privileged=self.is_privileged(row),
                )
                if protected_reason:
                    connection.rollback()
                    raise ProvisioningError(protected_reason)
                cursor.execute(
                    f"UPDATE {ccnet}.EmailUser SET is_active=%s WHERE id=%s",
                    (1 if active else 0, account_id),
                )
                sessions_revoked = 0
                tokens_revoked = 0
                if not active:
                    username = str(row["internal_username"])
                    token_tables = (
                        ("api2_token", "user"),
                        ("api2_tokenv2", "user"),
                        ("base_clientlogintoken", "username"),
                        ("base_clientssotoken", "username"),
                        ("base_devicetoken", "user"),
                    )
                    for table, column in token_tables:
                        cursor.execute(
                            f"DELETE FROM {seahub}.`{table}` WHERE `{column}`=%s",
                            (username,),
                        )
                        tokens_revoked += cursor.rowcount
                    cursor.execute(
                        f"SELECT session_key,session_data FROM {seahub}.django_session"
                    )
                    session_keys = [
                        item["session_key"]
                        for item in cursor.fetchall()
                        if self.session_belongs_to(item["session_data"], username)
                    ]
                    if session_keys:
                        placeholders = ",".join(["%s"] * len(session_keys))
                        cursor.execute(
                            f"DELETE FROM {seahub}.django_session "
                            f"WHERE session_key IN ({placeholders})",
                            tuple(session_keys),
                        )
                        sessions_revoked = cursor.rowcount
            connection.commit()
        return AdapterDecision(
            "active" if active else "suspended",
            target_account_id=account_id,
            target_username=str(row["internal_username"]),
            details={
                "account_id": account_id,
                "sessions_revoked": sessions_revoked,
                "tokens_revoked": tokens_revoked,
            },
        )


class PenpotAdapter(TargetAdapter):
    capabilities = frozenset(
        {"discover", "plan", "update", "disable", "reactivate", "verify"}
    )

    @staticmethod
    def database_url() -> str:
        value = os.getenv("PROVISIONING_PENPOT_DATABASE_URL", "").strip()
        if not value:
            raise ProvisioningError("PROVISIONING_PENPOT_DATABASE_URL is not configured")
        return value

    def connect(self):
        return psycopg.connect(self.database_url(), row_factory=dict_row, connect_timeout=10)

    def health(self, target: ProvisioningTarget) -> dict[str, Any]:
        configured = bool(os.getenv("PROVISIONING_PENPOT_DATABASE_URL", "").strip())
        return {
            "status": "ready" if configured else "not_configured",
            "adapter": target.adapter,
            "capabilities": sorted(self.capabilities),
            "missing": [] if configured else ["PROVISIONING_PENPOT_DATABASE_URL"],
        }

    @staticmethod
    def require_schema(connection) -> None:
        required = {
            "profile": {
                "id",
                "email",
                "fullname",
                "is_active",
                "is_blocked",
                "auth_backend",
                "props",
                "deleted_at",
                "default_project_id",
                "default_team_id",
            },
            "http_session": {"id", "profile_id"},
            "http_session_v2": {"id", "profile_id"},
            "access_token": {"id", "profile_id"},
            "team_profile_rel": {"profile_id", "team_id", "is_owner", "is_admin"},
            "project_profile_rel": {"profile_id", "project_id"},
            "file_profile_rel": {"profile_id", "file_id", "is_owner"},
        }
        with connection.cursor() as cursor:
            for table, columns in required.items():
                cursor.execute(
                    "SELECT column_name FROM information_schema.columns "
                    "WHERE table_schema=current_schema() AND table_name=%s",
                    (table,),
                )
                available = {row["column_name"] for row in cursor.fetchall()}
                missing = columns - available
                if missing:
                    raise ProvisioningError(
                        f"Schema guard failed for {table}; missing columns: "
                        f"{', '.join(sorted(missing))}"
                    )

    @staticmethod
    def row_details(row: dict[str, Any]) -> dict[str, Any]:
        return {
            "account_id": str(row["id"]),
            "auth_backend": row.get("auth_backend"),
            "oidc_subject": row.get("oidc_subject"),
            "default_project_id": str(row["default_project_id"]),
            "default_team_id": str(row["default_team_id"]),
            "team_memberships": int(row.get("team_memberships") or 0),
            "project_memberships": int(row.get("project_memberships") or 0),
            "file_memberships": int(row.get("file_memberships") or 0),
        }

    @staticmethod
    def select_profiles(
        cursor,
        *,
        profile_id: str | None = None,
        subject: str | None = None,
        email: str | None = None,
    ):
        if profile_id:
            predicate = "p.id=%s"
            values = (profile_id,)
        else:
            predicate = "(p.props->>'~:oidc/sub'=%s OR LOWER(p.email)=LOWER(%s))"
            values = (subject, email)
        cursor.execute(
            "SELECT p.id,p.email,p.fullname,p.is_active,p.is_blocked,p.auth_backend,"
            "p.deleted_at,p.default_project_id,p.default_team_id,"
            "p.props->>'~:oidc/sub' AS oidc_subject,"
            "(SELECT COUNT(*) FROM team_profile_rel tpr WHERE tpr.profile_id=p.id) "
            "AS team_memberships,"
            "(SELECT COUNT(*) FROM project_profile_rel ppr WHERE ppr.profile_id=p.id) "
            "AS project_memberships,"
            "(SELECT COUNT(*) FROM file_profile_rel fpr WHERE fpr.profile_id=p.id) "
            "AS file_memberships "
            f"FROM profile p WHERE {predicate} AND p.deleted_at IS NULL ORDER BY p.created_at",
            values,
        )
        return cursor.fetchall()

    def decision_for_row(
        self,
        row: dict[str, Any],
        source: SourceIdentity,
        target: ProvisioningTarget,
    ) -> AdapterDecision:
        protected_reason = protected_account_reason(
            target,
            account_id=row["id"],
            username=row["email"],
            email=row["email"],
        )
        if protected_reason:
            return AdapterDecision("conflict", details={"reason": protected_reason})
        if str(row.get("auth_backend") or "").lower() != "oidc":
            return AdapterDecision(
                "conflict",
                details={"reason": "Matching Penpot profile was not created through OIDC"},
            )
        if str(row.get("oidc_subject") or "") != source.subject:
            return AdapterDecision(
                "conflict",
                details={"reason": "Penpot OIDC subject does not match Keycloak subject"},
            )
        if bool(row.get("is_blocked")):
            return AdapterDecision(
                "conflict",
                target_account_id=str(row["id"]),
                target_username=str(row["email"]),
                details={
                    **self.row_details(row),
                    "reason": "Penpot profile is blocked; manual review is required",
                },
            )
        suspended = not bool(row.get("is_active"))
        expected_name = " ".join(
            value for value in (source.first_name, source.last_name) if value
        ) or source.email
        if not suspended and (
            str(row["email"]).lower() != str(source.email).lower()
            or str(row["fullname"]) != expected_name
        ):
            return AdapterDecision(
                "planned",
                action="update",
                target_account_id=str(row["id"]),
                target_username=str(row["email"]),
                details={
                    **self.row_details(row),
                    "old_email": str(row["email"]),
                    "new_email": str(source.email),
                    "new_fullname": expected_name,
                },
            )
        return AdapterDecision(
            "suspended" if suspended else "active",
            action="reactivate" if suspended else None,
            target_account_id=str(row["id"]),
            target_username=str(row["email"]),
            details=self.row_details(row),
        )

    def discover(self, source: SourceIdentity, target: ProvisioningTarget) -> AdapterDecision:
        if not source.email or not source.email_verified:
            return AdapterDecision("not_ready", details={"reason": "Verified email is required"})
        protected_reason = protected_account_reason(
            target, username=source.username, email=source.email
        )
        if protected_reason:
            return AdapterDecision("conflict", details={"reason": protected_reason})
        with self.connect() as connection:
            self.require_schema(connection)
            with connection.cursor() as cursor:
                rows = self.select_profiles(
                    cursor, subject=source.subject, email=source.email
                )
        by_subject = [
            row for row in rows if str(row.get("oidc_subject") or "") == source.subject
        ]
        if len(by_subject) > 1:
            return AdapterDecision(
                "conflict", details={"reason": "Multiple Penpot profiles use this OIDC subject"}
            )
        if by_subject:
            row = by_subject[0]
            if any(other["id"] != row["id"] for other in rows):
                return AdapterDecision(
                    "conflict",
                    details={"reason": "Keycloak email belongs to another Penpot profile"},
                )
            return self.decision_for_row(row, source, target)
        if rows:
            return AdapterDecision(
                "conflict",
                details={"reason": "Verified email belongs to another Penpot identity"},
            )
        return AdapterDecision(
            "awaiting_first_login",
            action="verify_after_login",
            details={"email": source.email},
        )

    def discover_linked(
        self,
        source: SourceIdentity,
        target: ProvisioningTarget,
        link: IdentityLink | None,
    ) -> AdapterDecision:
        if link is None:
            return self.discover(source, target)
        with self.connect() as connection:
            self.require_schema(connection)
            with connection.cursor() as cursor:
                rows = self.select_profiles(cursor, profile_id=link.target_account_id)
        if len(rows) != 1:
            return AdapterDecision(
                "conflict",
                target_account_id=link.target_account_id,
                target_username=link.target_username,
                details={"reason": "Linked Penpot profile is missing or ambiguous"},
            )
        row = rows[0]
        if str(row.get("oidc_subject") or "") != source.subject:
            return AdapterDecision(
                "conflict",
                target_account_id=str(row["id"]),
                target_username=str(row["email"]),
                details={
                    **self.row_details(row),
                    "reason": "Linked Penpot profile has a different OIDC subject",
                },
            )
        if not source.email_verified:
            return AdapterDecision(
                "not_ready",
                target_account_id=str(row["id"]),
                target_username=str(row["email"]),
                details={"reason": "Verified email is required"},
            )
        return self.decision_for_row(row, source, target)

    def update(
        self, action: ProvisioningAction, source: SourceIdentity, target: ProvisioningTarget
    ) -> AdapterDecision:
        account_id = str(action.details.get("account_id") or action.target_account_id or "")
        old_email = str(action.details.get("old_email") or "")
        new_email = str(action.details.get("new_email") or source.email or "")
        new_fullname = str(action.details.get("new_fullname") or "").strip()
        if not account_id or not old_email or not new_email or not source.email_verified:
            raise ProvisioningError("Penpot update is missing guarded identity fields")
        with self.connect() as connection:
            self.require_schema(connection)
            with connection.transaction(), connection.cursor() as cursor:
                cursor.execute(
                    "SELECT id,email,auth_backend,is_blocked,props->>'~:oidc/sub' AS oidc_subject "
                    "FROM profile WHERE id=%s AND deleted_at IS NULL FOR UPDATE",
                    (account_id,),
                )
                row = cursor.fetchone()
                if (
                    not row
                    or str(row.get("oidc_subject") or "") != source.subject
                    or str(row["email"]).lower() != old_email.lower()
                ):
                    raise ProvisioningError(
                        "Penpot identity changed after planning; no update applied"
                    )
                protected_reason = protected_account_reason(
                    target,
                    account_id=row["id"],
                    username=row["email"],
                    email=row["email"],
                )
                if protected_reason:
                    raise ProvisioningError(protected_reason)
                if str(row.get("auth_backend") or "").lower() != "oidc" or row["is_blocked"]:
                    raise ProvisioningError("Penpot profile is not eligible for automated update")
                cursor.execute(
                    "SELECT id FROM profile WHERE LOWER(email)=LOWER(%s) "
                    "AND deleted_at IS NULL AND id<>%s FOR UPDATE",
                    (new_email, account_id),
                )
                if cursor.fetchone():
                    raise ProvisioningError("New email belongs to another Penpot profile")
                cursor.execute(
                    "UPDATE profile SET email=%s,fullname=%s,modified_at=clock_timestamp() "
                    "WHERE id=%s AND props->>'~:oidc/sub'=%s",
                    (new_email, new_fullname, account_id, source.subject),
                )
                if cursor.rowcount != 1:
                    raise ProvisioningError("Penpot guarded profile update was not applied")
        return AdapterDecision(
            "active",
            target_account_id=account_id,
            target_username=new_email,
            details={"account_id": account_id, "email": new_email},
        )

    def disable(
        self, action: ProvisioningAction, source: SourceIdentity, target: ProvisioningTarget
    ) -> AdapterDecision:
        return self._set_active(action, source, target, active=False)

    def reactivate(
        self, action: ProvisioningAction, source: SourceIdentity, target: ProvisioningTarget
    ) -> AdapterDecision:
        return self._set_active(action, source, target, active=True)

    def _set_active(
        self,
        action: ProvisioningAction,
        source: SourceIdentity,
        target: ProvisioningTarget,
        *,
        active: bool,
    ) -> AdapterDecision:
        account_id = str(action.details.get("account_id") or action.target_account_id or "")
        if not account_id:
            raise ProvisioningError("Penpot action has no account ID")
        with self.connect() as connection:
            self.require_schema(connection)
            with connection.transaction(), connection.cursor() as cursor:
                cursor.execute(
                    "SELECT id,email,is_active,is_blocked,auth_backend FROM profile "
                    "WHERE id=%s AND props->>'~:oidc/sub'=%s "
                    "AND deleted_at IS NULL FOR UPDATE",
                    (account_id, source.subject),
                )
                row = cursor.fetchone()
                if not row:
                    raise ProvisioningError("Penpot identity changed after planning; no update applied")
                protected_reason = protected_account_reason(
                    target,
                    account_id=row["id"],
                    username=row["email"],
                    email=row["email"],
                )
                if protected_reason:
                    raise ProvisioningError(protected_reason)
                if str(row.get("auth_backend") or "").lower() != "oidc":
                    raise ProvisioningError("Penpot profile is not an OIDC-managed account")
                if active and bool(row.get("is_blocked")):
                    raise ProvisioningError("Blocked Penpot profile requires manual review")
                cursor.execute(
                    "UPDATE profile SET is_active=%s,modified_at=clock_timestamp() WHERE id=%s",
                    (active, account_id),
                )
                sessions_revoked = 0
                tokens_revoked = 0
                if not active:
                    for table in ("http_session", "http_session_v2"):
                        cursor.execute(f"DELETE FROM {table} WHERE profile_id=%s", (account_id,))
                        sessions_revoked += cursor.rowcount
                    cursor.execute("DELETE FROM access_token WHERE profile_id=%s", (account_id,))
                    tokens_revoked = cursor.rowcount
        return AdapterDecision(
            "active" if active else "suspended",
            target_account_id=account_id,
            target_username=str(row["email"]),
            details={
                "account_id": account_id,
                "sessions_revoked": sessions_revoked,
                "tokens_revoked": tokens_revoked,
            },
        )


class NetBirdAdapter(TargetAdapter):
    capabilities = frozenset({"discover", "plan", "disable", "reactivate", "verify"})

    def __init__(self) -> None:
        self.base_url = os.getenv(
            "PROVISIONING_NETBIRD_API_URL", "http://netbird-server"
        ).rstrip("/")
        self.token = os.getenv("PROVISIONING_NETBIRD_API_TOKEN", "").strip()
        self.timeout = int(os.getenv("PROVISIONING_HTTP_TIMEOUT_SECONDS", "20"))

    def health(self, target: ProvisioningTarget) -> dict[str, Any]:
        missing = [] if self.token else ["PROVISIONING_NETBIRD_API_TOKEN"]
        return {
            "status": "ready" if not missing else "not_configured",
            "adapter": target.adapter,
            "capabilities": sorted(self.capabilities),
            "missing": missing,
        }

    def request(
        self,
        method: str,
        path: str,
        payload: dict[str, Any] | None = None,
    ) -> Any:
        if not self.token:
            raise ProvisioningError("PROVISIONING_NETBIRD_API_TOKEN is not configured")
        data = None if payload is None else json.dumps(payload).encode()
        headers = {
            "Accept": "application/json",
            "Authorization": f"Token {self.token}",
        }
        if data is not None:
            headers["Content-Type"] = "application/json"
        request = urllib.request.Request(
            f"{self.base_url}{path}", data=data, headers=headers, method=method
        )
        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                body = response.read()
                return json.loads(body) if body else None
        except urllib.error.HTTPError as exc:
            body = exc.read(512).decode("utf-8", errors="replace")
            raise ProvisioningError(
                f"NetBird request failed with HTTP {exc.code}: {body}"
            ) from exc
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
            raise ProvisioningError(f"NetBird request failed: {exc}") from exc

    def users(self) -> list[dict[str, Any]]:
        users = self.request("GET", "/api/users")
        if not isinstance(users, list):
            raise ProvisioningError("Unexpected NetBird users response")
        return users

    def owned_peers(self, account_id: str) -> tuple[str, ...]:
        peers = self.request("GET", "/api/peers")
        if not isinstance(peers, list):
            raise ProvisioningError("Unexpected NetBird peers response")
        return tuple(
            sorted(
                str(peer["id"])
                for peer in peers
                if str(peer.get("user_id") or "") == account_id and peer.get("id")
            )
        )

    @staticmethod
    def external_identity(user_id: str) -> tuple[str, str]:
        try:
            padded = user_id + "=" * (-len(user_id) % 4)
            raw = base64.urlsafe_b64decode(padded)
            values: dict[int, str] = {}
            position = 0
            while position < len(raw):
                key = raw[position]
                position += 1
                field_number = key >> 3
                wire_type = key & 7
                if wire_type != 2:
                    raise ValueError("unsupported wire type")
                length = 0
                shift = 0
                while True:
                    byte = raw[position]
                    position += 1
                    length |= (byte & 0x7F) << shift
                    if byte < 0x80:
                        break
                    shift += 7
                values[field_number] = raw[position : position + length].decode()
                position += length
            subject = values.get(1, "")
            connector = values.get(2, "")
            if not subject or not connector:
                raise ValueError("missing identity component")
            return subject, connector
        except (ValueError, UnicodeDecodeError, IndexError, base64.binascii.Error) as exc:
            raise ProvisioningError(
                "NetBird user ID does not contain a supported external identity"
            ) from exc

    def auto_group_names(self, user: dict[str, Any]) -> tuple[str, ...]:
        groups = self.request("GET", "/api/groups")
        if not isinstance(groups, list):
            raise ProvisioningError("Unexpected NetBird groups response")
        names_by_id = {
            str(group.get("id")): str(group.get("name") or "")
            for group in groups
            if group.get("id")
        }
        group_ids = tuple(sorted(str(value) for value in user.get("auto_groups") or []))
        missing = [group_id for group_id in group_ids if group_id not in names_by_id]
        if missing:
            raise ProvisioningError("NetBird user references an unknown auto group")
        return tuple(sorted(names_by_id[group_id] for group_id in group_ids))

    @staticmethod
    def user_details(
        user: dict[str, Any],
        peer_ids: tuple[str, ...],
        external_subject: str,
        connector_id: str,
        auto_group_names: tuple[str, ...],
    ) -> dict[str, Any]:
        return {
            "account_id": str(user["id"]),
            "external_subject": external_subject,
            "connector_id": connector_id,
            "role": str(user.get("role") or ""),
            "issued": str(user.get("issued") or ""),
            "auto_groups": list(auto_group_names),
            "owned_peer_count": len(peer_ids),
            "owned_peer_ids": list(peer_ids),
        }

    def decision_for_user(
        self,
        user: dict[str, Any],
        source: SourceIdentity,
        target: ProvisioningTarget,
    ) -> AdapterDecision:
        account_id = str(user.get("id") or "")
        email = str(user.get("email") or "").strip().lower()
        external_subject, connector_id = self.external_identity(account_id)
        auto_group_names = self.auto_group_names(user)
        peer_ids = self.owned_peers(account_id)
        details = self.user_details(
            user, peer_ids, external_subject, connector_id, auto_group_names
        )
        protected_reason = protected_account_reason(
            target, account_id=account_id, username=email, email=email
        )
        if protected_reason:
            return AdapterDecision("conflict", details={**details, "reason": protected_reason})
        if bool(user.get("is_service_user")) or str(user.get("role") or "") != "user":
            return AdapterDecision(
                "conflict",
                target_account_id=account_id,
                target_username=email,
                details={
                    **details,
                    "reason": "NetBird identity is not an ordinary user account",
                },
            )
        if bool(user.get("pending_approval")):
            return AdapterDecision(
                "conflict",
                target_account_id=account_id,
                target_username=email,
                details={
                    **details,
                    "reason": "NetBird user requires administrator approval",
                },
            )
        if external_subject != source.subject or str(user.get("idp_id") or "") != connector_id:
            return AdapterDecision(
                "conflict",
                target_account_id=account_id,
                target_username=email,
                details={**details, "reason": "NetBird IdP ID does not match Keycloak subject"},
            )
        expected_group = os.getenv(
            "PROVISIONING_NETBIRD_JWT_ALLOW_GROUP", "app-netbird"
        ).strip()
        if auto_group_names != (expected_group,):
            return AdapterDecision(
                "conflict",
                target_account_id=account_id,
                target_username=email,
                details={
                    **details,
                    "reason": "NetBird synchronized groups do not match the approved group",
                },
            )
        suspended = bool(user.get("is_blocked"))
        return AdapterDecision(
            "suspended" if suspended else "active",
            action="reactivate" if suspended else None,
            target_account_id=account_id,
            target_username=email,
            details=details,
        )

    def discover(self, source: SourceIdentity, target: ProvisioningTarget) -> AdapterDecision:
        if not source.email or not source.email_verified:
            return AdapterDecision("not_ready", details={"reason": "Verified email is required"})
        protected_reason = protected_account_reason(
            target, username=source.username, email=source.email
        )
        if protected_reason:
            return AdapterDecision("conflict", details={"reason": protected_reason})
        users = self.users()
        subject_matches = []
        for user in users:
            try:
                external_subject, connector_id = self.external_identity(str(user.get("id") or ""))
            except ProvisioningError:
                continue
            if (
                external_subject == source.subject
                and str(user.get("idp_id") or "") == connector_id
            ):
                subject_matches.append(user)
        if len(subject_matches) > 1:
            return AdapterDecision(
                "conflict", details={"reason": "Multiple NetBird users use this IdP ID"}
            )
        email_matches = [
            user
            for user in users
            if str(user.get("email") or "").strip().lower() == source.email.lower()
        ]
        if subject_matches:
            user = subject_matches[0]
            if any(other.get("id") != user.get("id") for other in email_matches):
                return AdapterDecision(
                    "conflict",
                    details={"reason": "Keycloak email belongs to another NetBird user"},
                )
            return self.decision_for_user(user, source, target)
        if email_matches:
            return AdapterDecision(
                "conflict",
                details={"reason": "Verified email belongs to another NetBird identity"},
            )
        return AdapterDecision(
            "awaiting_first_login",
            action="verify_after_login",
            details={"email": source.email},
        )

    def discover_linked(
        self,
        source: SourceIdentity,
        target: ProvisioningTarget,
        link: IdentityLink | None,
    ) -> AdapterDecision:
        if link is None:
            return self.discover(source, target)
        users = [
            user for user in self.users() if str(user.get("id") or "") == link.target_account_id
        ]
        if len(users) != 1:
            return AdapterDecision(
                "conflict",
                target_account_id=link.target_account_id,
                target_username=link.target_username,
                details={"reason": "Linked NetBird user is missing or ambiguous"},
            )
        if not source.email_verified:
            return AdapterDecision(
                "not_ready",
                target_account_id=link.target_account_id,
                target_username=link.target_username,
                details={"reason": "Verified email is required"},
            )
        return self.decision_for_user(users[0], source, target)

    def disable(
        self, action: ProvisioningAction, source: SourceIdentity, target: ProvisioningTarget
    ) -> AdapterDecision:
        return self._set_blocked(action, source, target, blocked=True)

    def reactivate(
        self, action: ProvisioningAction, source: SourceIdentity, target: ProvisioningTarget
    ) -> AdapterDecision:
        return self._set_blocked(action, source, target, blocked=False)

    def _set_blocked(
        self,
        action: ProvisioningAction,
        source: SourceIdentity,
        target: ProvisioningTarget,
        *,
        blocked: bool,
    ) -> AdapterDecision:
        account_id = str(action.details.get("account_id") or action.target_account_id or "")
        if not account_id:
            raise ProvisioningError("NetBird action has no account ID")
        matches = [user for user in self.users() if str(user.get("id") or "") == account_id]
        if len(matches) != 1:
            raise ProvisioningError("NetBird identity changed after planning; no update applied")
        user = matches[0]
        email = str(user.get("email") or "").strip().lower()
        external_subject, connector_id = self.external_identity(account_id)
        if (
            external_subject != source.subject
            or str(user.get("idp_id") or "") != connector_id
        ):
            raise ProvisioningError("NetBird IdP ID changed after planning; no update applied")
        protected_reason = protected_account_reason(
            target, account_id=account_id, username=email, email=email
        )
        if protected_reason:
            raise ProvisioningError(protected_reason)
        if bool(user.get("is_service_user")) or str(user.get("role") or "") != "user":
            raise ProvisioningError("NetBird identity is not an ordinary user account")
        if bool(user.get("pending_approval")):
            raise ProvisioningError("NetBird user requires administrator approval")
        auto_group_names_before = self.auto_group_names(user)
        expected_group = os.getenv(
            "PROVISIONING_NETBIRD_JWT_ALLOW_GROUP", "app-netbird"
        ).strip()
        if auto_group_names_before != (expected_group,):
            raise ProvisioningError(
                "NetBird synchronized groups do not match the approved group"
            )
        peer_ids_before = self.owned_peers(account_id)
        updated = self.request(
            "PUT",
            f"/api/users/{urllib.parse.quote(account_id, safe='')}",
            {
                "role": "user",
                "auto_groups": list(user.get("auto_groups") or []),
                "is_blocked": blocked,
            },
        )
        if not isinstance(updated, dict) or bool(updated.get("is_blocked")) != blocked:
            raise ProvisioningError("NetBird did not confirm the requested blocked state")
        updated_subject, updated_connector = self.external_identity(
            str(updated.get("id") or "")
        )
        if (
            updated_subject != source.subject
            or str(updated.get("idp_id") or "") != updated_connector
        ):
            raise ProvisioningError("NetBird returned a different IdP identity after update")
        peer_ids_after = self.owned_peers(account_id)
        if peer_ids_after != peer_ids_before:
            raise ProvisioningError(
                "NetBird peer ownership changed during user lifecycle update"
            )
        auto_group_names = self.auto_group_names(updated)
        if auto_group_names != auto_group_names_before:
            raise ProvisioningError(
                "NetBird synchronized groups changed during user lifecycle update"
            )
        return AdapterDecision(
            "suspended" if blocked else "active",
            target_account_id=account_id,
            target_username=email,
            details={
                **self.user_details(
                    updated,
                    peer_ids_after,
                    updated_subject,
                    updated_connector,
                    auto_group_names,
                ),
                "peer_ownership_preserved": True,
            },
        )


class VaultwardenAdapter(TargetAdapter):
    capabilities = frozenset({"discover", "plan", "create", "disable", "reactivate", "verify"})

    USER_TYPE = 2
    STATUS_REVOKED = -1
    STATUS_INVITED = 0
    STATUS_ACCEPTED = 1
    STATUS_CONFIRMED = 2

    def __init__(self) -> None:
        self.base_url = os.getenv(
            "PROVISIONING_VAULTWARDEN_API_URL", "http://vaultwarden"
        ).rstrip("/")
        self.client_id = os.getenv("PROVISIONING_VAULTWARDEN_CLIENT_ID", "").strip()
        self.client_secret = os.getenv("PROVISIONING_VAULTWARDEN_CLIENT_SECRET", "")
        self.organization_id = os.getenv(
            "PROVISIONING_VAULTWARDEN_ORGANIZATION_ID", ""
        ).strip()
        self.device_identifier = os.getenv(
            "PROVISIONING_VAULTWARDEN_DEVICE_IDENTIFIER", ""
        ).strip()
        self.timeout = int(os.getenv("PROVISIONING_HTTP_TIMEOUT_SECONDS", "20"))

    def health(self, target: ProvisioningTarget) -> dict[str, Any]:
        configured = {
            "PROVISIONING_VAULTWARDEN_CLIENT_ID": self.client_id,
            "PROVISIONING_VAULTWARDEN_CLIENT_SECRET": self.client_secret,
            "PROVISIONING_VAULTWARDEN_ORGANIZATION_ID": self.organization_id,
            "PROVISIONING_VAULTWARDEN_DEVICE_IDENTIFIER": self.device_identifier,
        }
        missing = [name for name, value in configured.items() if not value]
        return {
            "status": "ready" if not missing else "not_configured",
            "adapter": target.adapter,
            "capabilities": sorted(self.capabilities),
            "missing": missing,
        }

    def request(
        self,
        method: str,
        path: str,
        *,
        token: str | None = None,
        payload: dict[str, Any] | None = None,
        form: dict[str, str] | None = None,
    ) -> Any:
        if payload is not None and form is not None:
            raise ProvisioningError("Vaultwarden request cannot contain JSON and form data")
        data = None
        headers = {"Accept": "application/json"}
        if payload is not None:
            data = json.dumps(payload).encode()
            headers["Content-Type"] = "application/json"
        elif form is not None:
            data = urllib.parse.urlencode(form).encode()
            headers["Content-Type"] = "application/x-www-form-urlencoded"
        if token:
            headers["Authorization"] = f"Bearer {token}"
        request = urllib.request.Request(
            f"{self.base_url}{path}", data=data, headers=headers, method=method
        )
        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                body = response.read()
                return json.loads(body) if body else None
        except urllib.error.HTTPError as exc:
            body = exc.read(512).decode("utf-8", errors="replace")
            raise ProvisioningError(
                f"Vaultwarden request failed with HTTP {exc.code}: {body}"
            ) from exc
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
            raise ProvisioningError(f"Vaultwarden request failed: {exc}") from exc

    def token(self) -> str:
        if not all(
            (self.client_id, self.client_secret, self.organization_id, self.device_identifier)
        ):
            raise ProvisioningError("Vaultwarden provisioning credentials are not configured")
        response = self.request(
            "POST",
            "/identity/connect/token",
            form={
                "grant_type": "client_credentials",
                "client_id": self.client_id,
                "client_secret": self.client_secret,
                "scope": "api",
                "device_identifier": self.device_identifier,
                "device_name": "support-tools-provisioning",
                "device_type": "14",
            },
        )
        # The response also contains encryption material. Never retain or return it.
        access_token = response.get("access_token") if isinstance(response, dict) else None
        if not access_token:
            raise ProvisioningError("Vaultwarden token response did not contain an access token")
        return str(access_token)

    def members(self) -> list[dict[str, Any]]:
        org_id = urllib.parse.quote(self.organization_id, safe="")
        response = self.request(
            "GET",
            f"/api/organizations/{org_id}/users?includeCollections=true&includeGroups=true",
            token=self.token(),
        )
        members = response.get("data") if isinstance(response, dict) else None
        if not isinstance(members, list):
            raise ProvisioningError("Unexpected Vaultwarden organization-members response")
        return members

    @staticmethod
    def member_value(member: dict[str, Any], name: str, default: Any = None) -> Any:
        for key, value in member.items():
            if str(key).casefold() == name.casefold():
                return value
        return default

    @classmethod
    def member_id(cls, member: dict[str, Any]) -> str:
        return str(cls.member_value(member, "id", "") or "")

    @classmethod
    def member_email(cls, member: dict[str, Any]) -> str:
        return str(cls.member_value(member, "email", "") or "").strip().casefold()

    @classmethod
    def membership_details(cls, member: dict[str, Any]) -> dict[str, Any]:
        return {
            "account_id": cls.member_id(member),
            "membership_status": int(cls.member_value(member, "status", -999)),
            "membership_type": int(cls.member_value(member, "type", -999)),
            "access_all": bool(cls.member_value(member, "accessAll", False)),
            "collection_count": len(cls.member_value(member, "collections", []) or []),
            "group_count": len(cls.member_value(member, "groups", []) or []),
        }

    def decision_for_member(
        self,
        member: dict[str, Any],
        source: SourceIdentity,
        target: ProvisioningTarget,
    ) -> AdapterDecision:
        details = self.membership_details(member)
        account_id = details["account_id"]
        email = self.member_email(member)
        protected_reason = protected_account_reason(
            target,
            account_id=account_id,
            username=email,
            email=email,
            privileged=details["membership_type"] != self.USER_TYPE,
        )
        if protected_reason:
            return AdapterDecision("conflict", details={**details, "reason": protected_reason})
        if not account_id or email != str(source.email or "").casefold():
            return AdapterDecision(
                "conflict",
                target_account_id=account_id or None,
                target_username=email or None,
                details={**details, "reason": "Vaultwarden membership identity does not match"},
            )
        if details["access_all"]:
            return AdapterDecision(
                "conflict",
                target_account_id=account_id,
                target_username=email,
                details={
                    **details,
                    "reason": "Vaultwarden membership has disallowed access-all privilege",
                },
            )
        status = details["membership_status"]
        if status == self.STATUS_CONFIRMED:
            return AdapterDecision(
                "active", target_account_id=account_id, target_username=email, details=details
            )
        if status in {self.STATUS_INVITED, self.STATUS_ACCEPTED}:
            return AdapterDecision(
                "invited",
                target_account_id=account_id,
                target_username=email,
                details={
                    **details,
                    "confirmation_required": status == self.STATUS_ACCEPTED,
                },
            )
        if status == self.STATUS_REVOKED:
            return AdapterDecision(
                "suspended",
                action="reactivate",
                target_account_id=account_id,
                target_username=email,
                details=details,
            )
        return AdapterDecision(
            "conflict",
            target_account_id=account_id,
            target_username=email,
            details={**details, "reason": "Unknown Vaultwarden membership status"},
        )

    def discover(self, source: SourceIdentity, target: ProvisioningTarget) -> AdapterDecision:
        if not source.email or not source.email_verified:
            return AdapterDecision("not_ready", details={"reason": "Verified email is required"})
        protected_reason = protected_account_reason(
            target, username=source.username, email=source.email
        )
        if protected_reason:
            return AdapterDecision("conflict", details={"reason": protected_reason})
        matches = [member for member in self.members() if self.member_email(member) == source.email.casefold()]
        if len(matches) > 1:
            return AdapterDecision(
                "conflict", details={"reason": "Multiple Vaultwarden memberships use this email"}
            )
        if matches:
            return self.decision_for_member(matches[0], source, target)
        return AdapterDecision(
            "planned",
            action="create",
            target_username=source.email,
            details={"email": source.email, "membership_type": self.USER_TYPE},
        )

    def discover_linked(
        self,
        source: SourceIdentity,
        target: ProvisioningTarget,
        link: IdentityLink | None,
    ) -> AdapterDecision:
        if not link or not link.target_account_id:
            return self.discover(source, target)
        matches = [
            member for member in self.members() if self.member_id(member) == link.target_account_id
        ]
        if len(matches) == 1:
            return self.decision_for_member(matches[0], source, target)
        if len(matches) > 1:
            return AdapterDecision(
                "conflict", details={"reason": "Duplicate Vaultwarden membership ID"}
            )
        return AdapterDecision(
            "planned",
            action="reactivate",
            target_account_id=link.target_account_id,
            target_username=source.email,
            details={
                "account_id": link.target_account_id,
                "email": source.email,
                "reason": "Previous organization membership is absent",
            },
        )

    def invite(
        self, source: SourceIdentity, target: ProvisioningTarget
    ) -> AdapterDecision:
        if not source.email or not source.email_verified:
            raise ProvisioningError("Verified email is required for a Vaultwarden invitation")
        protected_reason = protected_account_reason(
            target, username=source.username, email=source.email
        )
        if protected_reason:
            raise ProvisioningError(protected_reason)
        if any(self.member_email(member) == source.email.casefold() for member in self.members()):
            raise ProvisioningError("Vaultwarden membership appeared after planning; no invitation sent")
        org_id = urllib.parse.quote(self.organization_id, safe="")
        self.request(
            "POST",
            f"/api/organizations/{org_id}/users/invite",
            token=self.token(),
            payload={
                "emails": [source.email],
                "groups": [],
                "type": self.USER_TYPE,
                "collections": [],
                "permissions": {},
            },
        )
        matches = [member for member in self.members() if self.member_email(member) == source.email.casefold()]
        if len(matches) != 1:
            raise ProvisioningError("Vaultwarden invitation read-back did not find one membership")
        decision = self.decision_for_member(matches[0], source, target)
        if decision.state not in {"invited", "active"}:
            raise ProvisioningError("Vaultwarden invitation read-back failed the approved baseline")
        return decision

    def create(
        self, action: ProvisioningAction, source: SourceIdentity, target: ProvisioningTarget
    ) -> AdapterDecision:
        return self.invite(source, target)

    def disable(
        self, action: ProvisioningAction, source: SourceIdentity, target: ProvisioningTarget
    ) -> AdapterDecision:
        account_id = str(action.details.get("account_id") or action.target_account_id or "")
        if not account_id:
            raise ProvisioningError("Vaultwarden action has no organization-membership ID")
        matches = [member for member in self.members() if self.member_id(member) == account_id]
        if not matches:
            return AdapterDecision(
                "suspended",
                target_account_id=account_id,
                target_username=source.email,
                details={"membership_removed": True, "already_absent": True},
            )
        if len(matches) != 1:
            raise ProvisioningError("Vaultwarden organization-membership ID is not unique")
        decision = self.decision_for_member(matches[0], source, target)
        if decision.state == "conflict":
            raise ProvisioningError(str(decision.details.get("reason") or "Unsafe membership"))
        org_id = urllib.parse.quote(self.organization_id, safe="")
        member_id = urllib.parse.quote(account_id, safe="")
        self.request(
            "DELETE",
            f"/api/organizations/{org_id}/users/{member_id}",
            token=self.token(),
        )
        if any(self.member_id(member) == account_id for member in self.members()):
            raise ProvisioningError("Vaultwarden membership still exists after removal")
        return AdapterDecision(
            "suspended",
            target_account_id=account_id,
            target_username=source.email,
            details={"membership_removed": True, "personal_vault_preserved": True},
        )

    def reactivate(
        self, action: ProvisioningAction, source: SourceIdentity, target: ProvisioningTarget
    ) -> AdapterDecision:
        account_id = str(action.details.get("account_id") or action.target_account_id or "")
        matches = [member for member in self.members() if self.member_id(member) == account_id]
        if matches:
            decision = self.decision_for_member(matches[0], source, target)
            if decision.state != "suspended":
                return decision
            self.disable(action, source, target)
        return self.invite(source, target)


class OsTicketAdapter(MariaDbAdapter):
    env_prefix = "PROVISIONING_OSTICKET"
    capabilities = frozenset({"discover", "plan", "create", "disable", "reactivate", "verify"})

    @property
    def department_name(self) -> str:
        return os.getenv("PROVISIONING_OSTICKET_DEPARTMENT_NAME", "Support").strip()

    @property
    def role_name(self) -> str:
        return os.getenv("PROVISIONING_OSTICKET_ROLE_NAME", "Support Agent").strip()

    @property
    def expected_schema_signature(self) -> str:
        return os.getenv(
            "PROVISIONING_OSTICKET_SCHEMA_SIGNATURE",
            "83a22ba22b1a6a624fcb1da03882ac1b",
        ).strip()

    @staticmethod
    def username(source: SourceIdentity) -> str:
        return (source.username or "").strip()

    @staticmethod
    def permission_names(value: Any) -> tuple[str, ...]:
        try:
            parsed = json.loads(str(value or "{}"))
        except (TypeError, ValueError, json.JSONDecodeError) as error:
            raise ProvisioningError("osTicket role permissions are not valid JSON") from error
        if not isinstance(parsed, dict):
            raise ProvisioningError("osTicket role permissions are not an object")
        return tuple(sorted(str(key) for key, enabled in parsed.items() if bool(enabled)))

    def require_schema(self, connection) -> None:
        checks = (
            (
                "ost_staff",
                {
                    "staff_id", "dept_id", "role_id", "username", "firstname", "lastname",
                    "passwd", "backend", "email", "isactive", "isadmin", "assigned_only",
                    "created", "updated",
                },
            ),
            ("ost_department", {"id", "name"}),
            ("ost_role", {"id", "name", "permissions"}),
            ("ost_team_member", {"team_id", "staff_id"}),
            ("ost_staff_dept_access", {"staff_id", "dept_id", "role_id"}),
            ("ost_session", {"session_id", "user_id"}),
            ("ost_api_key", {"id"}),
            ("ost_config", {"namespace", "key", "value"}),
        )
        for table, columns in checks:
            self.require_columns(connection, table, columns)
        with connection.cursor() as cursor:
            cursor.execute(
                "SELECT value FROM ost_config WHERE namespace='core' AND `key`='schema_signature'"
            )
            row = cursor.fetchone()
        actual = str(row.get("value") if row else "")
        if not self.expected_schema_signature or actual != self.expected_schema_signature:
            raise ProvisioningError(
                "osTicket schema signature is not the approved 1.17.5 baseline; writes are blocked"
            )

    def placement(self, connection) -> dict[str, Any]:
        with connection.cursor() as cursor:
            cursor.execute(
                "SELECT id,name FROM ost_department WHERE name=%s ORDER BY id",
                (self.department_name,),
            )
            departments = list(cursor.fetchall())
            cursor.execute(
                "SELECT id,name,permissions FROM ost_role WHERE name=%s ORDER BY id",
                (self.role_name,),
            )
            roles = list(cursor.fetchall())
        if len(departments) != 1:
            raise ProvisioningError(
                f"osTicket requires exactly one department named '{self.department_name}'"
            )
        if len(roles) != 1:
            raise ProvisioningError(
                f"osTicket requires exactly one role named '{self.role_name}'"
            )
        permissions = self.permission_names(roles[0].get("permissions"))
        if permissions != ("ticket.reply",):
            raise ProvisioningError(
                "osTicket Support Agent role must grant only ticket.reply"
            )
        return {
            "department_id": int(departments[0]["id"]),
            "department_name": str(departments[0]["name"]),
            "role_id": int(roles[0]["id"]),
            "role_name": str(roles[0]["name"]),
            "permissions": list(permissions),
        }

    @staticmethod
    def account_details(row: dict[str, Any], placement: dict[str, Any]) -> dict[str, Any]:
        return {
            "account_id": str(row["staff_id"]),
            "department_id": int(row["dept_id"]),
            "department_name": placement["department_name"],
            "role_id": int(row["role_id"]),
            "role_name": placement["role_name"],
            "team_count": int(row.get("team_count") or 0),
            "extra_department_count": int(row.get("extra_department_count") or 0),
            "api_key_count": int(row.get("api_key_count") or 0),
        }

    @staticmethod
    def account_select() -> str:
        return (
            "SELECT s.staff_id,s.dept_id,s.role_id,s.username,s.firstname,s.lastname,"
            "s.email,s.isactive,s.isadmin,s.passwd,s.backend,s.assigned_only,"
            "(SELECT COUNT(*) FROM ost_team_member tm WHERE tm.staff_id=s.staff_id) AS team_count,"
            "(SELECT COUNT(*) FROM ost_staff_dept_access da WHERE da.staff_id=s.staff_id) "
            "AS extra_department_count,"
            "(SELECT COUNT(*) FROM ost_api_key) AS api_key_count FROM ost_staff s "
        )

    def account_rows(self, connection, source: SourceIdentity) -> list[dict[str, Any]]:
        with connection.cursor() as cursor:
            cursor.execute(
                self.account_select()
                + "WHERE LOWER(s.username)=LOWER(%s) OR LOWER(s.email)=LOWER(%s) "
                "ORDER BY s.staff_id",
                (self.username(source), source.email),
            )
            return list(cursor.fetchall())

    def validate_account(
        self,
        row: dict[str, Any],
        source: SourceIdentity,
        target: ProvisioningTarget,
        placement: dict[str, Any],
    ) -> str | None:
        protected_reason = protected_account_reason(
            target,
            account_id=row.get("staff_id"),
            username=row.get("username"),
            email=row.get("email"),
            privileged=bool(row.get("isadmin")),
        )
        if protected_reason:
            return protected_reason
        if int(row.get("dept_id") or 0) != placement["department_id"]:
            return "osTicket agent is not in the approved primary department"
        if int(row.get("role_id") or 0) != placement["role_id"]:
            return "osTicket agent does not have the approved role"
        if int(row.get("team_count") or 0) != 0:
            return "osTicket agent has team membership requiring manual review"
        if int(row.get("extra_department_count") or 0) != 0:
            return "osTicket agent has extra department access requiring manual review"
        if row.get("passwd"):
            return "osTicket agent has a local password requiring manual review"
        if str(row.get("email") or "").casefold() != str(source.email or "").casefold():
            return "osTicket username belongs to an agent with another email"
        return None

    def discover(self, source: SourceIdentity, target: ProvisioningTarget) -> AdapterDecision:
        username = self.username(source)
        if not source.email or not source.email_verified:
            return AdapterDecision("not_ready", details={"reason": "Verified email is required"})
        if not username or not source.first_name or not source.last_name:
            return AdapterDecision(
                "not_ready",
                details={"reason": "preferred_username, first name, and last name are required"},
            )
        if len(username) > 32:
            return AdapterDecision(
                "not_ready", details={"reason": "preferred_username exceeds 32 characters"}
            )
        protected_reason = protected_account_reason(
            target, username=username, email=source.email
        )
        if protected_reason:
            return AdapterDecision("conflict", details={"reason": protected_reason})
        with self.connect() as connection:
            self.require_schema(connection)
            placement = self.placement(connection)
            rows = self.account_rows(connection, source)
        by_username = [
            row for row in rows if str(row.get("username") or "").casefold() == username.casefold()
        ]
        if len(by_username) > 1:
            return AdapterDecision(
                "conflict", details={"reason": "Multiple osTicket agents use preferred_username"}
            )
        if by_username:
            row = by_username[0]
            if any(str(other["staff_id"]) != str(row["staff_id"]) for other in rows):
                return AdapterDecision(
                    "conflict", details={"reason": "Verified email belongs to another osTicket agent"}
                )
            reason = self.validate_account(row, source, target, placement)
            if reason:
                return AdapterDecision("conflict", details={"reason": reason})
            suspended = not bool(row.get("isactive"))
            return AdapterDecision(
                "suspended" if suspended else "active",
                action="reactivate" if suspended else None,
                target_account_id=str(row["staff_id"]),
                target_username=str(row["username"]),
                details=self.account_details(row, placement),
            )
        if rows:
            return AdapterDecision(
                "conflict",
                details={"reason": "Verified email belongs to a different osTicket username"},
            )
        return AdapterDecision(
            "planned",
            action="create",
            target_username=username,
            details={
                "username": username,
                "email": source.email,
                "department_id": placement["department_id"],
                "role_id": placement["role_id"],
            },
        )

    def create(
        self, action: ProvisioningAction, source: SourceIdentity, target: ProvisioningTarget
    ) -> AdapterDecision:
        username = self.username(source)
        with self.connect() as connection:
            self.require_schema(connection)
            placement = self.placement(connection)
            with connection.cursor() as cursor:
                cursor.execute(
                    "SELECT staff_id FROM ost_staff WHERE LOWER(username)=LOWER(%s) "
                    "OR LOWER(email)=LOWER(%s) FOR UPDATE",
                    (username, source.email),
                )
                if cursor.fetchone():
                    connection.rollback()
                    raise ProvisioningError("osTicket agent appeared after planning; no insert applied")
                if (
                    int(action.details.get("department_id") or 0) != placement["department_id"]
                    or int(action.details.get("role_id") or 0) != placement["role_id"]
                ):
                    connection.rollback()
                    raise ProvisioningError("osTicket placement changed after planning; no insert applied")
                cursor.execute(
                    "INSERT INTO ost_staff "
                    "(dept_id,role_id,username,firstname,lastname,passwd,backend,email,signature,"
                    "isactive,isadmin,isvisible,onvacation,assigned_only,show_assigned_tickets,"
                    "created,updated) VALUES (%s,%s,%s,%s,%s,NULL,%s,%s,'',1,0,1,0,0,1,UTC_TIMESTAMP(),UTC_TIMESTAMP())",
                    (
                        placement["department_id"],
                        placement["role_id"],
                        username,
                        source.first_name,
                        source.last_name,
                        os.getenv("PROVISIONING_OSTICKET_AUTH_BACKEND", "").strip() or None,
                        source.email,
                    ),
                )
                account_id = str(cursor.lastrowid)
                cursor.execute(
                    self.account_select() + "WHERE s.staff_id=%s FOR UPDATE", (account_id,)
                )
                row = cursor.fetchone()
                reason = self.validate_account(row or {}, source, target, placement)
                if reason:
                    connection.rollback()
                    raise ProvisioningError(f"osTicket create verification failed: {reason}")
            connection.commit()
        return AdapterDecision(
            "active",
            target_account_id=account_id,
            target_username=username,
            details=self.account_details(row, placement),
        )

    def disable(
        self, action: ProvisioningAction, source: SourceIdentity, target: ProvisioningTarget
    ) -> AdapterDecision:
        return self._set_active(action, source, target, active=False)

    def reactivate(
        self, action: ProvisioningAction, source: SourceIdentity, target: ProvisioningTarget
    ) -> AdapterDecision:
        return self._set_active(action, source, target, active=True)

    def _set_active(
        self,
        action: ProvisioningAction,
        source: SourceIdentity,
        target: ProvisioningTarget,
        *,
        active: bool,
    ) -> AdapterDecision:
        account_id = str(action.details.get("account_id") or action.target_account_id or "")
        if not account_id:
            raise ProvisioningError("osTicket action has no account ID")
        with self.connect() as connection:
            self.require_schema(connection)
            placement = self.placement(connection)
            with connection.cursor() as cursor:
                cursor.execute(
                    self.account_select()
                    + "WHERE s.staff_id=%s AND LOWER(s.username)=LOWER(%s) FOR UPDATE",
                    (account_id, self.username(source)),
                )
                row = cursor.fetchone()
                reason = self.validate_account(row or {}, source, target, placement)
                if reason:
                    connection.rollback()
                    raise ProvisioningError(reason)
                cursor.execute(
                    "UPDATE ost_staff SET isactive=%s,updated=UTC_TIMESTAMP() "
                    "WHERE staff_id=%s AND isadmin=0",
                    (1 if active else 0, account_id),
                )
                if cursor.rowcount != 1:
                    connection.rollback()
                    raise ProvisioningError("osTicket agent changed after planning; no update applied")
                sessions_revoked = 0
                if not active:
                    cursor.execute("DELETE FROM ost_session WHERE user_id=%s", (account_id,))
                    sessions_revoked = cursor.rowcount
                cursor.execute(self.account_select() + "WHERE s.staff_id=%s", (account_id,))
                updated = cursor.fetchone()
                reason = self.validate_account(updated or {}, source, target, placement)
                if reason or bool(updated.get("isactive")) != active:
                    connection.rollback()
                    raise ProvisioningError(
                        "osTicket lifecycle read-back failed; no update applied"
                    )
            connection.commit()
        return AdapterDecision(
            "active" if active else "suspended",
            target_account_id=account_id,
            target_username=self.username(source),
            details={
                **self.account_details(updated, placement),
                "sessions_revoked": sessions_revoked,
            },
        )


class GuacamoleAdapter(TargetAdapter):
    capabilities = frozenset(
        {"discover", "plan", "create", "disable", "reactivate", "verify"}
    )

    @staticmethod
    def database_url() -> str:
        value = os.getenv("PROVISIONING_GUACAMOLE_DATABASE_URL", "").strip()
        if not value:
            raise ProvisioningError("PROVISIONING_GUACAMOLE_DATABASE_URL is not configured")
        return value

    def connect(self):
        return psycopg.connect(self.database_url(), row_factory=dict_row, connect_timeout=10)

    def health(self, target: ProvisioningTarget) -> dict[str, Any]:
        configured = bool(os.getenv("PROVISIONING_GUACAMOLE_DATABASE_URL", "").strip())
        return {
            "status": "ready" if configured else "not_configured",
            "adapter": target.adapter,
            "capabilities": sorted(self.capabilities),
            "missing": [] if configured else ["PROVISIONING_GUACAMOLE_DATABASE_URL"],
        }

    @staticmethod
    def username(source: SourceIdentity) -> str:
        return (source.username or source.email or "").strip()

    @staticmethod
    def require_schema(connection) -> None:
        required = {
            "guacamole_entity": {"entity_id", "name", "type"},
            "guacamole_user": {
                "user_id",
                "entity_id",
                "password_hash",
                "password_salt",
                "password_date",
                "disabled",
                "expired",
                "full_name",
                "email_address",
            },
            "guacamole_system_permission": {"entity_id", "permission"},
        }
        with connection.cursor() as cursor:
            for table, columns in required.items():
                cursor.execute(
                    "SELECT column_name FROM information_schema.columns "
                    "WHERE table_schema=current_schema() AND table_name=%s",
                    (table,),
                )
                available = {row["column_name"] for row in cursor.fetchall()}
                missing = columns - available
                if missing:
                    raise ProvisioningError(
                        f"Schema guard failed for {table}; missing columns: "
                        f"{', '.join(sorted(missing))}"
                    )

    def discover(self, source: SourceIdentity, target: ProvisioningTarget) -> AdapterDecision:
        username = self.username(source)
        if not username:
            return AdapterDecision("not_ready", details={"reason": "preferred_username is required"})
        if len(username) > 128:
            return AdapterDecision(
                "not_ready", details={"reason": "preferred_username exceeds 128 characters"}
            )
        protected_reason = protected_account_reason(
            target, username=username, email=source.email
        )
        if protected_reason:
            return AdapterDecision("conflict", details={"reason": protected_reason})
        with self.connect() as connection:
            self.require_schema(connection)
            with connection.cursor() as cursor:
                cursor.execute(
                    "SELECT e.entity_id,e.name,u.user_id,u.disabled,u.expired,"
                    "EXISTS(SELECT 1 FROM guacamole_system_permission p "
                    "WHERE p.entity_id=e.entity_id AND p.permission='ADMINISTER') AS is_admin "
                    "FROM guacamole_entity e JOIN guacamole_user u ON u.entity_id=e.entity_id "
                    "WHERE e.type='USER' AND LOWER(e.name)=LOWER(%s) ORDER BY e.entity_id",
                    (username,),
                )
                rows = cursor.fetchall()
        if len(rows) > 1:
            return AdapterDecision(
                "conflict", details={"reason": "Multiple Guacamole users match preferred_username"}
            )
        if rows:
            row = rows[0]
            protected_reason = protected_account_reason(
                target,
                account_id=row["entity_id"],
                username=row["name"],
                email=source.email,
                privileged=bool(row["is_admin"]),
            )
            if protected_reason:
                return AdapterDecision("conflict", details={"reason": protected_reason})
            suspended = bool(row["disabled"]) or bool(row["expired"])
            return AdapterDecision(
                "suspended" if suspended else "active",
                action="reactivate" if suspended else None,
                target_account_id=str(row["entity_id"]),
                target_username=row["name"],
                details={
                    "entity_id": int(row["entity_id"]),
                    "user_id": int(row["user_id"]),
                },
            )
        return AdapterDecision(
            "planned",
            action="create",
            target_username=username,
            details={"username": username, "email": source.email or ""},
        )

    def execute(
        self, action: ProvisioningAction, source: SourceIdentity, target: ProvisioningTarget
    ) -> AdapterDecision:
        if action.action not in {"create", "disable", "reactivate"}:
            raise ProvisioningError(f"Unsupported Guacamole action: {action.action}")
        username = self.username(source)
        protected_reason = protected_account_reason(
            target,
            account_id=action.details.get("entity_id"),
            username=username,
            email=source.email,
        )
        if protected_reason:
            raise ProvisioningError(protected_reason)
        with self.connect() as connection:
            self.require_schema(connection)
            with connection.transaction(), connection.cursor() as cursor:
                if action.action == "create":
                    cursor.execute(
                        "SELECT entity_id FROM guacamole_entity "
                        "WHERE type='USER' AND LOWER(name)=LOWER(%s) FOR UPDATE",
                        (username,),
                    )
                    if cursor.fetchone():
                        raise ProvisioningError(
                            "Guacamole identity appeared after planning; no insert applied"
                        )
                    cursor.execute(
                        "INSERT INTO guacamole_entity(name,type) VALUES (%s,'USER') "
                        "RETURNING entity_id",
                        (username,),
                    )
                    entity_id = int(cursor.fetchone()["entity_id"])
                    cursor.execute(
                        "INSERT INTO guacamole_user "
                        "(entity_id,password_hash,password_salt,password_date,disabled,expired,"
                        "full_name,email_address) VALUES (%s,%s,%s,CURRENT_TIMESTAMP,FALSE,FALSE,%s,%s) "
                        "RETURNING user_id",
                        (
                            entity_id,
                            secrets.token_bytes(32),
                            secrets.token_bytes(32),
                            " ".join(
                                value for value in (source.first_name, source.last_name) if value
                            ),
                            source.email,
                        ),
                    )
                    cursor.fetchone()
                else:
                    entity_id = int(action.details.get("entity_id") or 0)
                    disabled = action.action == "disable"
                    cursor.execute(
                        "UPDATE guacamole_user u SET disabled=%s,expired=FALSE "
                        "FROM guacamole_entity e WHERE u.entity_id=e.entity_id "
                        "AND e.entity_id=%s AND e.type='USER' AND LOWER(e.name)=LOWER(%s) "
                        "AND NOT EXISTS(SELECT 1 FROM guacamole_system_permission p "
                        "WHERE p.entity_id=e.entity_id AND p.permission='ADMINISTER')",
                        (disabled, entity_id, username),
                    )
                    if cursor.rowcount != 1:
                        raise ProvisioningError(
                            "Guacamole identity changed or is protected; no update applied"
                        )
        return AdapterDecision(
            "suspended" if action.action == "disable" else "active",
            target_account_id=str(entity_id),
            target_username=username,
            details={"entity_id": entity_id},
        )


def first_attribute(attributes: dict[str, Any], name: str) -> str:
    value = attributes.get(name, "")
    if isinstance(value, list):
        value = value[0] if value else ""
    return str(value).strip()


ADAPTERS: dict[str, TargetAdapter] = {
    "manual": ManualAdapter(),
    "bookstack": BookStackAdapter(),
    "espocrm": EspoCrmAdapter(),
    "erpnext": ErpNextAdapter(),
    "seafile": SeafileAdapter(),
    "penpot": PenpotAdapter(),
    "netbird": NetBirdAdapter(),
    "vaultwarden": VaultwardenAdapter(),
    "osticket": OsTicketAdapter(),
    "guacamole": GuacamoleAdapter(),
}


def seed_targets(session: Session) -> None:
    existing = {target.id: target for target in session.scalars(select(ProvisioningTarget))}
    for target_id, display_name, strategy, adapter, groups in TARGET_DEFINITIONS:
        settings = {
            "retry_limit": 3,
            "retry_base_seconds": 2,
            "rate_limit_per_minute": 60,
        }
        if target_id in existing:
            target = existing[target_id]
            merged = {**settings, **(target.settings or {})}
            if merged != target.settings:
                target.settings = merged
            if (
                target.adapter == "manual"
                and adapter != "manual"
                and str(target.updated_by).startswith("system:")
            ):
                target.adapter = adapter
                target.strategy = strategy
                target.updated_by = "system:adapter-upgrade"
            # Tighten only the original generated restricted default. Never overwrite
            # an administrator-customized eligibility policy.
            if len(groups) == 2 and normalized_groups(target.eligibility_groups) == {groups[1]}:
                target.eligibility_groups = groups
                target.updated_by = "system:restricted-group-policy"
            continue
        session.add(
            ProvisioningTarget(
                id=target_id,
                display_name=display_name,
                strategy=strategy,
                adapter=adapter,
                enabled=False,
                dry_run=True,
                eligibility_groups=groups,
                settings=settings,
                updated_by="system:initial-import",
            )
        )
    session.commit()


def normalized_groups(groups: Iterable[str]) -> set[str]:
    normalized: set[str] = set()
    for group in groups:
        path = str(group).strip().strip("/")
        if not path:
            continue
        parts = [part for part in path.split("/") if part]
        normalized.update("/".join(parts[:index]) for index in range(1, len(parts) + 1))
    return normalized


def is_eligible(source: SourceIdentity, target: ProvisioningTarget) -> bool:
    required = normalized_groups(target.eligibility_groups)
    actual = normalized_groups(source.groups)
    return source.enabled and source.deleted_at is None and bool(required) and required.issubset(actual)


def target_state_hash(target: ProvisioningTarget) -> str:
    payload = {
        "id": target.id,
        "adapter": target.adapter,
        "enabled": target.enabled,
        "dry_run": target.dry_run,
        "eligibility_groups": sorted(normalized_groups(target.eligibility_groups)),
        "settings": target.settings,
        "protected_accounts": {
            "account_ids": sorted(protection_values(target, "account_ids")),
            "usernames": sorted(protection_values(target, "usernames")),
            "emails": sorted(protection_values(target, "emails")),
        },
    }
    return hashlib.sha256(
        json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()


def redact(value: Any) -> Any:
    if isinstance(value, dict):
        return {
            str(key): ("[REDACTED]" if str(key).lower() in SENSITIVE_KEYS else redact(item))
            for key, item in value.items()
        }
    if isinstance(value, list):
        return [redact(item) for item in value]
    if isinstance(value, tuple):
        return [redact(item) for item in value]
    return value


def redact_error(error: Exception | str) -> str:
    message = str(error)
    for name, value in os.environ.items():
        normalized_name = name.lower()
        if value and len(value) >= 6 and any(part in normalized_name for part in SENSITIVE_KEYS):
            message = message.replace(value, "[REDACTED]")
    return message[:500]


def audit(
    session: Session,
    event_type: str,
    actor: str,
    correlation_id: str,
    *,
    target_id: str | None = None,
    source_identity_id: int | None = None,
    action_id: str | None = None,
    payload: dict[str, Any] | None = None,
) -> None:
    session.add(
        ProvisioningAuditEvent(
            event_type=event_type,
            actor=actor,
            target_id=target_id,
            source_identity_id=source_identity_id,
            action_id=action_id,
            correlation_id=correlation_id,
            payload=payload or {},
        )
    )


def upsert_source_identities(session: Session, users: list[SourceUser], seen_at: datetime) -> list[SourceIdentity]:
    records: list[SourceIdentity] = []
    seen_keys: set[tuple[str, str]] = set()
    for user in users:
        seen_keys.add((user.issuer, user.subject))
        record = session.scalar(
            select(SourceIdentity).where(
                SourceIdentity.issuer == user.issuer,
                SourceIdentity.subject == user.subject,
            )
        )
        if record is None:
            record = SourceIdentity(
                issuer=user.issuer,
                subject=user.subject,
                username=user.username,
                source_state_hash=user.state_hash,
                last_seen_at=seen_at,
            )
            session.add(record)
        record.username = user.username
        record.email = user.email
        record.email_verified = user.email_verified
        record.first_name = user.first_name
        record.last_name = user.last_name
        record.enabled = user.enabled
        record.groups = list(user.groups)
        record.attributes = user.attributes
        record.source_state_hash = user.state_hash
        record.last_seen_at = seen_at
        record.deleted_at = None
        records.append(record)
    session.flush()

    existing = list(session.scalars(select(SourceIdentity).where(SourceIdentity.deleted_at.is_(None))))
    for record in existing:
        if (record.issuer, record.subject) not in seen_keys:
            record.enabled = False
            record.deleted_at = seen_at
            record.source_state_hash = hashlib.sha256(
                f"{record.issuer}:{record.subject}:deleted:{seen_at.isoformat()}".encode()
            ).hexdigest()
            if record not in records:
                records.append(record)

    # Keep deleted sources in reconciliation until every linked target confirms
    # suspension. This allows an approved offboarding plan to be regenerated if
    # execution controls change after the deletion was first observed.
    unresolved_deleted = list(
        session.scalars(
            select(SourceIdentity)
            .join(IdentityLink, IdentityLink.source_identity_id == SourceIdentity.id)
            .where(
                SourceIdentity.deleted_at.is_not(None),
                IdentityLink.state != "suspended",
            )
        ).unique()
    )
    for record in unresolved_deleted:
        if record not in records:
            records.append(record)
    return records


def action_dedupe_key(source: SourceIdentity, target: ProvisioningTarget, decision: AdapterDecision) -> str:
    payload = {
        "issuer": source.issuer,
        "subject": source.subject,
        "source_state_hash": source.source_state_hash,
        "target": target.id,
        "target_state_hash": target_state_hash(target),
        "action": decision.action,
        "details": decision.details,
    }
    return hashlib.sha256(json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


ACTION_DEDUPE_ACTIVE_STATUSES = (
    "planned",
    "retryable",
    "manual_review",
    "awaiting_first_login",
    "not_ready",
    "conflict",
    "approved",
    "executing",
)


def record_action(
    session: Session,
    run: ReconciliationRun,
    source: SourceIdentity,
    target: ProvisioningTarget,
    decision: AdapterDecision,
) -> ProvisioningAction | None:
    action_name = decision.action
    if not action_name and decision.state in {"conflict", "not_ready"}:
        action_name = "manual_review"
    if not action_name:
        return None
    dedupe_key = action_dedupe_key(source, target, decision)
    # Historical actions are immutable evidence. Only live work is deduplicated;
    # a later lifecycle cycle may legitimately require the same action again.
    existing = session.scalar(
        select(ProvisioningAction)
        .where(
            ProvisioningAction.dedupe_key == dedupe_key,
            ProvisioningAction.status.in_(ACTION_DEDUPE_ACTIVE_STATUSES),
        )
        .order_by(ProvisioningAction.created_at.desc())
        .limit(1)
    )
    if existing:
        return existing
    status = "conflict" if decision.state == "conflict" else decision.state
    action = ProvisioningAction(
        id=str(uuid.uuid4()),
        run_id=run.id,
        source_identity_id=source.id,
        target_id=target.id,
        action=action_name,
        status=status,
        dedupe_key=dedupe_key,
        source_state_hash=source.source_state_hash,
        target_state_hash=target_state_hash(target),
        details=redact(decision.details),
    )
    session.add(action)
    run.planned_count += int(status in {"planned", "awaiting_first_login", "not_ready"})
    run.conflict_count += int(status == "conflict")
    return action


def supersede_obsolete_actions(
    session: Session,
    source: SourceIdentity,
    target: ProvisioningTarget,
    decision: AdapterDecision,
) -> None:
    current_key = action_dedupe_key(source, target, decision) if decision.action else None
    pending = session.scalars(
        select(ProvisioningAction).where(
            ProvisioningAction.source_identity_id == source.id,
            ProvisioningAction.target_id == target.id,
            ProvisioningAction.status.in_(
                ("planned", "retryable", "manual_review", "awaiting_first_login", "not_ready", "conflict")
            ),
        )
    )
    for action in pending:
        if action.dedupe_key != current_key:
            action.status = "superseded"


def upsert_link(
    session: Session,
    source: SourceIdentity,
    target: ProvisioningTarget,
    decision: AdapterDecision,
    now: datetime,
) -> IdentityLink | None:
    if not decision.target_account_id:
        return None
    account_link = session.scalar(
        select(IdentityLink).where(
            IdentityLink.target_id == target.id,
            IdentityLink.target_account_id == decision.target_account_id,
        )
    )
    if account_link is not None and account_link.source_identity_id != source.id:
        raise ProvisioningError("Target account is already linked to another source identity")
    link = session.scalar(
        select(IdentityLink).where(
            IdentityLink.source_identity_id == source.id,
            IdentityLink.target_id == target.id,
        )
    )
    if link is None:
        link = IdentityLink(
            source_identity_id=source.id,
            target_id=target.id,
            target_account_id=decision.target_account_id,
            state=decision.state,
        )
        session.add(link)
    link.target_account_id = decision.target_account_id
    link.target_username = decision.target_username
    link.state = decision.state
    link.metadata_json = decision.details
    link.verified_at = now
    return link


def reconciliation_enabled() -> bool:
    return os.getenv("PROVISIONING_ENABLED", "false").lower() == "true"


def writes_allowed() -> bool:
    return os.getenv("PROVISIONING_ALLOW_WRITES", "false").lower() == "true"


def positive_environment_integer(name: str, default: int) -> int:
    raw_value = os.getenv(name, str(default)).strip()
    try:
        value = int(raw_value)
    except ValueError as error:
        raise RuntimeError(f"{name} must be a positive integer") from error
    if value < 1:
        raise RuntimeError(f"{name} must be a positive integer")
    return value


def jit_review_after_days() -> int:
    return positive_environment_integer("PROVISIONING_JIT_REVIEW_AFTER_DAYS", 7)


def retention_policy() -> dict[str, int | str]:
    settings = {
        "audit_days": ("PROVISIONING_AUDIT_RETENTION_DAYS", 730),
        "operational_log_days": ("PROVISIONING_OPERATIONAL_LOG_RETENTION_DAYS", 90),
        "closed_review_days": ("PROVISIONING_CLOSED_REVIEW_RETENTION_DAYS", 730),
    }
    policy: dict[str, int | str] = {"cleanup": "manual"}
    for key, (name, default) in settings.items():
        policy[key] = positive_environment_integer(name, default)
    return policy


def escalate_stale_jit_actions(
    session: Session,
    *,
    now: datetime,
    actor: str,
    correlation_id: str,
) -> int:
    review_after_days = jit_review_after_days()
    cutoff = now - timedelta(days=review_after_days)
    actions = list(
        session.scalars(
            select(ProvisioningAction).where(
                ProvisioningAction.status == "awaiting_first_login",
                ProvisioningAction.created_at <= cutoff,
            )
        )
    )
    for action in actions:
        source = session.get(SourceIdentity, action.source_identity_id)
        target = session.get(ProvisioningTarget, action.target_id)
        if source is None or target is None or not target.enabled or not is_eligible(source, target):
            action.status = "superseded"
            audit(
                session,
                "jit.first_login_wait_cancelled",
                actor,
                correlation_id,
                target_id=action.target_id,
                source_identity_id=action.source_identity_id,
                action_id=action.id,
                payload={"reason": "Source is no longer eligible or target is disabled"},
            )
            continue
        action.status = "manual_review"
        action.reason = (
            f"No first login detected within {review_after_days} days; "
            "account remains eligible and unchanged"
        )
        audit(
            session,
            "jit.first_login_review_required",
            actor,
            correlation_id,
            target_id=action.target_id,
            source_identity_id=action.source_identity_id,
            action_id=action.id,
            payload={
                "review_after_days": review_after_days,
                "awaiting_since": action.created_at.isoformat(),
            },
        )
    return len(actions)


def provisioning_health(session: Session) -> dict[str, Any]:
    targets = list(
        session.scalars(select(ProvisioningTarget).where(ProvisioningTarget.enabled.is_(True)))
    )
    target_health: dict[str, dict[str, Any]] = {}
    ready = True
    for target in targets:
        adapter = ADAPTERS.get(target.adapter)
        if adapter is None:
            status = {
                "status": "unsupported_adapter",
                "adapter": target.adapter,
                "capabilities": [],
            }
        else:
            status = adapter.health(target)
        target_health[target.id] = status
        ready = ready and status["status"] == "ready"

    last_run = session.scalar(
        select(ReconciliationRun).order_by(ReconciliationRun.started_at.desc()).limit(1)
    )
    scheduler_enabled = reconciliation_enabled()
    scheduler_status = "disabled"
    if scheduler_enabled:
        scheduler_status = "ready"
        if last_run and last_run.status == "running":
            scheduler_status = "running"
        elif last_run and last_run.status == "failed":
            scheduler_status = "degraded"
            ready = False

    return {
        "status": "ready" if ready else "degraded",
        "database": "ready",
        "scheduler": scheduler_status,
        "writes": "enabled" if writes_allowed() else "locked",
        "jit_review_after_days": jit_review_after_days(),
        "retention": retention_policy(),
        "targets": target_health,
        "last_run": (
            {
                "id": last_run.id,
                "status": last_run.status,
                "completed_at": last_run.completed_at.isoformat()
                if last_run.completed_at
                else None,
            }
            if last_run
            else None
        ),
    }


def reconcile(
    session: Session,
    *,
    actor: str,
    trigger: str,
    connector: KeycloakConnector | None = None,
) -> ReconciliationRun:
    run = ReconciliationRun(id=str(uuid.uuid4()), trigger=trigger, status="running", actor=actor)
    session.add(run)
    session.commit()
    correlation_id = run.id
    locked = bool(session.scalar(text("SELECT pg_try_advisory_lock(731942861)")))
    if not locked:
        run.status = "skipped_locked"
        run.completed_at = datetime.now(timezone.utc)
        run.summary = {"reason": "Another reconciliation is already running"}
        session.commit()
        return run
    try:
        users = (connector or KeycloakConnector()).fetch_users()
        now = datetime.now(timezone.utc)
        sources = upsert_source_identities(session, users, now)
        run.source_count = len(users)
        targets = list(session.scalars(select(ProvisioningTarget).where(ProvisioningTarget.enabled.is_(True))))
        target_summary: dict[str, dict[str, int]] = {}
        for target in targets:
            adapter = ADAPTERS.get(target.adapter, ADAPTERS["manual"])
            counts = {
                "active": 0,
                "planned": 0,
                "waiting": 0,
                "conflict": 0,
                "not_ready": 0,
                "errors": 0,
            }
            for source in sources:
                link = session.scalar(
                    select(IdentityLink).where(
                        IdentityLink.source_identity_id == source.id,
                        IdentityLink.target_id == target.id,
                    )
                )
                if not is_eligible(source, target):
                    supersede_obsolete_actions(
                        session,
                        source,
                        target,
                        AdapterDecision("ineligible"),
                    )
                    if link and link.state != "suspended":
                        if adapter.supports("disable"):
                            decision = AdapterDecision(
                                "planned",
                                action="disable",
                                target_account_id=link.target_account_id,
                                target_username=link.target_username,
                                details={"account_id": link.target_account_id, "reason": "Eligibility removed"},
                            )
                        else:
                            decision = AdapterDecision(
                                "not_ready",
                                action="manual_review",
                                target_account_id=link.target_account_id,
                                target_username=link.target_username,
                                details={
                                    "account_id": link.target_account_id,
                                    "reason": "Eligibility removed; adapter cannot disable automatically",
                                },
                            )
                        supersede_obsolete_actions(session, source, target, decision)
                        record_action(session, run, source, target, decision)
                        if decision.state == "not_ready":
                            counts["not_ready"] += 1
                        else:
                            counts["planned"] += 1
                    continue
                try:
                    decision = validate_decision(
                        adapter, adapter.discover_linked(source, target, link)
                    )
                    supersede_obsolete_actions(session, source, target, decision)
                    try:
                        upsert_link(session, source, target, decision, now)
                    except ProvisioningError as exc:
                        decision = AdapterDecision(
                            "conflict",
                            action="manual_review",
                            target_account_id=decision.target_account_id,
                            target_username=decision.target_username,
                            details={"reason": redact_error(exc)},
                        )
                        supersede_obsolete_actions(session, source, target, decision)
                    record_action(session, run, source, target, decision)
                    if decision.state == "awaiting_first_login":
                        counts["waiting"] += 1
                    elif decision.state in counts:
                        counts[decision.state] += 1
                except Exception as exc:
                    run.error_count += 1
                    counts["errors"] += 1
                    audit(
                        session,
                        "adapter.error",
                        actor,
                        correlation_id,
                        target_id=target.id,
                        source_identity_id=source.id,
                        payload={"error": redact_error(exc)},
                    )
            target_summary[target.id] = counts
        # Session autoflush is disabled; persist lifecycle decisions before the
        # aging query so newly superseded actions cannot be escalated.
        session.flush()
        jit_escalated = escalate_stale_jit_actions(
            session,
            now=now,
            actor=actor,
            correlation_id=correlation_id,
        )
        run.status = "completed_with_errors" if run.error_count else "completed"
        run.summary = {"targets": target_summary, "jit_escalated": jit_escalated}
        run.completed_at = datetime.now(timezone.utc)
        audit(
            session,
            "reconciliation.completed",
            actor,
            correlation_id,
            payload={
                "source_count": run.source_count,
                "planned_count": run.planned_count,
                "conflict_count": run.conflict_count,
                "error_count": run.error_count,
                "jit_escalated": jit_escalated,
            },
        )
        session.commit()
        return run
    except Exception as exc:
        session.rollback()
        run = session.get(ReconciliationRun, run.id)
        if run:
            run.status = "failed"
            run.error_count += 1
            run.completed_at = datetime.now(timezone.utc)
            run.summary = {"error": redact_error(exc)}
            audit(session, "reconciliation.failed", actor, correlation_id, payload=run.summary)
            session.commit()
        raise
    finally:
        session.execute(text("SELECT pg_advisory_unlock(731942861)"))
        session.commit()


def execute_action(session: Session, action_id: str, actor: str, reason: str) -> ProvisioningAction:
    action = session.get(ProvisioningAction, action_id)
    if not action:
        raise ProvisioningError("Action not found")
    if action.status not in {"planned", "retryable"}:
        raise ProvisioningError(f"Action is not executable from state '{action.status}'")
    if not reason.strip():
        raise ProvisioningError("An approval reason is required")
    target = session.get(ProvisioningTarget, action.target_id)
    source = session.get(SourceIdentity, action.source_identity_id)
    if not target or not source:
        raise ProvisioningError("Action source or target no longer exists")
    if not target.enabled:
        raise ProvisioningError("Target is disabled")
    if source.source_state_hash != action.source_state_hash:
        action.status = "stale"
        session.commit()
        raise ProvisioningError("Source identity changed after planning; reconcile again")
    if action.target_state_hash and target_state_hash(target) != action.target_state_hash:
        action.status = "stale"
        session.commit()
        raise ProvisioningError("Target configuration changed after planning; reconcile again")
    if target.dry_run:
        raise ProvisioningError("Target is in dry-run mode")
    if not writes_allowed():
        raise ProvisioningError("Global write gate PROVISIONING_ALLOW_WRITES is disabled")
    if not is_eligible(source, target) and action.action != "disable":
        raise ProvisioningError("Source identity is no longer eligible")

    adapter = ADAPTERS.get(target.adapter, ADAPTERS["manual"])
    if not adapter.supports(action.action):
        raise ProvisioningError(
            f"Adapter '{target.adapter}' does not support operation '{action.action}'"
        )
    action.approved_by = actor
    action.approved_at = datetime.now(timezone.utc)
    action.reason = reason.strip()
    action.attempt_count += 1
    action.last_error = None
    attempt = ProvisioningExecutionAttempt(
        action_id=action.id,
        attempt_number=action.attempt_count,
        status="running",
        actor=actor,
        correlation_id=action.run_id,
    )
    action.status = "executing"
    session.add(attempt)
    session.commit()
    try:
        result = validate_decision(adapter, adapter.execute(action, source, target))
        upsert_link(session, source, target, result, datetime.now(timezone.utc))
        action.status = "executed"
        action.executed_at = datetime.now(timezone.utc)
        attempt.status = "succeeded"
        attempt.result = redact(
            {
                "state": result.state,
                "target_account_id": result.target_account_id,
                "target_username": result.target_username,
                "details": result.details,
            }
        )
        attempt.completed_at = datetime.now(timezone.utc)
        audit(
            session,
            "action.executed",
            actor,
            action.run_id,
            target_id=target.id,
            source_identity_id=source.id,
            action_id=action.id,
            payload={"action": action.action, "reason": reason.strip(), "result": result.state},
        )
        session.commit()
        return action
    except Exception as exc:
        session.rollback()
        action = session.get(ProvisioningAction, action_id)
        if action:
            retry_limit = max(1, int(target.settings.get("retry_limit", 3)))
            action.status = "retryable" if action.attempt_count < retry_limit else "manual_review"
            action.reason = reason.strip()
            action.last_error = redact_error(exc)
            attempt = session.scalar(
                select(ProvisioningExecutionAttempt).where(
                    ProvisioningExecutionAttempt.action_id == action.id,
                    ProvisioningExecutionAttempt.attempt_number == action.attempt_count,
                )
            )
            if attempt:
                attempt.status = "failed"
                attempt.error = redact_error(exc)
                attempt.completed_at = datetime.now(timezone.utc)
            audit(
                session,
                "action.failed",
                actor,
                action.run_id,
                target_id=action.target_id,
                source_identity_id=action.source_identity_id,
                action_id=action.id,
                payload={"action": action.action, "error": redact_error(exc)},
            )
            session.commit()
        raise
