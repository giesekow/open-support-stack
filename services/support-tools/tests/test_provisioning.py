import base64
import json
import os
import unittest
from datetime import datetime, timezone
from types import SimpleNamespace
from unittest.mock import patch

from app.models import (
    IdentityLink,
    ProvisioningAction,
    ProvisioningAuditEvent,
    ProvisioningExecutionAttempt,
    ProvisioningTarget,
    SourceIdentity,
)
from app.provisioning import (
    ADAPTERS,
    AdapterDecision,
    BookStackAdapter,
    EspoCrmAdapter,
    ErpNextAdapter,
    KeycloakConnector,
    NetBirdAdapter,
    OsTicketAdapter,
    PenpotAdapter,
    ProvisioningError,
    SeafileAdapter,
    SourceUser,
    TargetAdapter,
    VaultwardenAdapter,
    action_dedupe_key,
    execute_action,
    first_attribute,
    is_eligible,
    jit_review_after_days,
    normalized_groups,
    protected_account_reason,
    protection_values,
    redact,
    redact_error,
    retention_policy,
    supersede_obsolete_actions,
    target_state_hash,
    validate_decision,
    writes_allowed,
)


class ProvisioningDomainTests(unittest.TestCase):
    @staticmethod
    def netbird_user_id(subject="user-123", connector="keycloak-connector"):
        raw = bytes([0x0A, len(subject)]) + subject.encode()
        raw += bytes([0x12, len(connector)]) + connector.encode()
        return base64.urlsafe_b64encode(raw).decode().rstrip("=")

    def source(self, **overrides):
        values = {
            "issuer": "https://sso.example.com/realms/support",
            "subject": "user-123",
            "username": "person@example.com",
            "email": "person@example.com",
            "email_verified": True,
            "first_name": "Pat",
            "last_name": "Morgan",
            "enabled": True,
            "groups": ["employees"],
            "attributes": {"employeeNumber": ["EMP-42"]},
            "source_state_hash": "hash-1",
            "last_seen_at": datetime.now(timezone.utc),
            "deleted_at": None,
        }
        values.update(overrides)
        return SourceIdentity(**values)

    def target(self, **overrides):
        values = {
            "id": "bookstack",
            "display_name": "BookStack",
            "strategy": "jit",
            "adapter": "bookstack",
            "enabled": True,
            "dry_run": True,
            "eligibility_groups": ["employees"],
            "settings": {},
            "updated_by": "test",
        }
        values.update(overrides)
        return ProvisioningTarget(**values)

    def test_oidc_state_hash_changes_for_security_relevant_state(self):
        base = SourceUser(
            issuer="https://issuer",
            subject="subject",
            username="person",
            email="person@example.com",
            email_verified=True,
            first_name="Pat",
            last_name="Morgan",
            enabled=True,
            groups=("employees",),
        )
        disabled = SourceUser(**{**base.__dict__, "enabled": False})
        self.assertNotEqual(base.state_hash, disabled.state_hash)

    def test_group_normalization_is_exact(self):
        self.assertEqual(normalized_groups(["/employees", " support-admin "]), {"employees", "support-admin"})
        self.assertTrue(is_eligible(self.source(), self.target()))
        self.assertFalse(is_eligible(self.source(groups=["employees-old"]), self.target()))

    def test_nested_group_membership_includes_parent_path(self):
        self.assertEqual(
            normalized_groups(["/employees/berlin/support"]),
            {"employees", "employees/berlin", "employees/berlin/support"},
        )
        self.assertTrue(is_eligible(self.source(groups=["/employees/berlin"]), self.target()))

    def test_all_required_groups_must_be_present(self):
        target = self.target(eligibility_groups=["employees", "app-bookstack"])
        self.assertFalse(is_eligible(self.source(groups=["employees"]), target))
        self.assertTrue(is_eligible(self.source(groups=["employees", "app-bookstack"]), target))

    def test_restricted_target_requires_employee_and_application_groups(self):
        target = self.target(
            id="netbird",
            eligibility_groups=["employees", "app-netbird"],
        )
        self.assertFalse(is_eligible(self.source(groups=["app-netbird"]), target))
        self.assertFalse(is_eligible(self.source(groups=["employees"]), target))
        self.assertTrue(
            is_eligible(self.source(groups=["employees", "app-netbird"]), target)
        )

    def test_disabled_or_deleted_source_is_ineligible(self):
        self.assertFalse(is_eligible(self.source(enabled=False), self.target()))
        self.assertFalse(is_eligible(self.source(deleted_at=datetime.now(timezone.utc)), self.target()))

    def test_action_dedupe_changes_when_source_or_plan_changes(self):
        source = self.source()
        target = self.target()
        first = action_dedupe_key(source, target, AdapterDecision("planned", "link", details={"id": "1"}))
        second = action_dedupe_key(source, target, AdapterDecision("planned", "link", details={"id": "2"}))
        source.source_state_hash = "hash-2"
        third = action_dedupe_key(source, target, AdapterDecision("planned", "link", details={"id": "1"}))
        target.dry_run = False
        fourth = action_dedupe_key(source, target, AdapterDecision("planned", "link", details={"id": "1"}))
        self.assertNotEqual(first, second)
        self.assertNotEqual(first, third)
        self.assertNotEqual(third, fourth)

    def test_attribute_handles_keycloak_lists(self):
        self.assertEqual(first_attribute({"employeeNumber": ["EMP-42"]}, "employeeNumber"), "EMP-42")
        self.assertEqual(first_attribute({}, "employeeNumber"), "")

    def test_write_gate_defaults_closed(self):
        with patch.dict(os.environ, {}, clear=True):
            self.assertFalse(writes_allowed())
        with patch.dict(os.environ, {"PROVISIONING_ALLOW_WRITES": "true"}, clear=True):
            self.assertTrue(writes_allowed())

    def test_retention_policy_defaults_and_environment_overrides(self):
        names = {
            "PROVISIONING_AUDIT_RETENTION_DAYS",
            "PROVISIONING_OPERATIONAL_LOG_RETENTION_DAYS",
            "PROVISIONING_CLOSED_REVIEW_RETENTION_DAYS",
        }
        environment = {key: value for key, value in os.environ.items() if key not in names}
        with patch.dict(os.environ, environment, clear=True):
            self.assertEqual(
                retention_policy(),
                {
                    "audit_days": 730,
                    "operational_log_days": 90,
                    "closed_review_days": 730,
                    "cleanup": "manual",
                },
            )
        with patch.dict(
            os.environ,
            {
                "PROVISIONING_AUDIT_RETENTION_DAYS": "365",
                "PROVISIONING_OPERATIONAL_LOG_RETENTION_DAYS": "30",
                "PROVISIONING_CLOSED_REVIEW_RETENTION_DAYS": "180",
            },
            clear=True,
        ):
            self.assertEqual(retention_policy()["audit_days"], 365)
            self.assertEqual(retention_policy()["operational_log_days"], 30)
            self.assertEqual(retention_policy()["closed_review_days"], 180)

    def test_retention_policy_rejects_invalid_values(self):
        with patch.dict(
            os.environ,
            {"PROVISIONING_AUDIT_RETENTION_DAYS": "0"},
            clear=True,
        ):
            with self.assertRaisesRegex(RuntimeError, "positive integer"):
                retention_policy()

    def test_jit_review_threshold_defaults_overrides_and_rejects_invalid_values(self):
        environment = {
            key: value
            for key, value in os.environ.items()
            if key != "PROVISIONING_JIT_REVIEW_AFTER_DAYS"
        }
        with patch.dict(os.environ, environment, clear=True):
            self.assertEqual(jit_review_after_days(), 7)
        with patch.dict(
            os.environ,
            {"PROVISIONING_JIT_REVIEW_AFTER_DAYS": "14"},
            clear=True,
        ):
            self.assertEqual(jit_review_after_days(), 14)
        with patch.dict(
            os.environ,
            {"PROVISIONING_JIT_REVIEW_AFTER_DAYS": "0"},
            clear=True,
        ):
            with self.assertRaisesRegex(RuntimeError, "positive integer"):
                jit_review_after_days()

    def test_bookstack_accepts_long_email_before_database_access(self):
        source = self.source(email=("a" * 30) + "@example.com")
        adapter = BookStackAdapter()
        adapter.connect = lambda: (_ for _ in ()).throw(RuntimeError("bookstack-database-reached"))
        with self.assertRaisesRegex(RuntimeError, "bookstack-database-reached"):
            adapter.discover(source, self.target())

    def test_bookstack_disable_revokes_sessions_without_changing_account(self):
        class Cursor:
            rowcount = 0

            def __enter__(self):
                return self

            def __exit__(self, *_):
                return None

            def execute(self, query, _params=None):
                if query.startswith("SELECT u.id"):
                    self.row = {
                        "id": 42,
                        "email": "person@example.com",
                        "external_auth_id": "user-123",
                        "system_name": None,
                        "is_admin": 0,
                    }
                elif query.startswith("DELETE FROM sessions"):
                    self.rowcount = 2

            def fetchone(self):
                return self.row

        class Connection:
            def __init__(self):
                self.cursor_instance = Cursor()
                self.committed = False

            def __enter__(self):
                return self

            def __exit__(self, *_):
                return None

            def cursor(self):
                return self.cursor_instance

            def commit(self):
                self.committed = True

            def rollback(self):
                raise AssertionError("valid session revocation must not roll back")

        adapter = BookStackAdapter()
        connection = Connection()
        adapter.connect = lambda: connection
        adapter.require_columns = lambda *_: None
        result = adapter.disable(
            SimpleNamespace(details={"account_id": "42"}, target_account_id="42"),
            self.source(subject="user-123"),
            self.target(),
        )
        self.assertEqual(result.state, "suspended")
        self.assertEqual(result.target_account_id, "42")
        self.assertEqual(result.details, {"sessions_revoked": 2})
        self.assertTrue(connection.committed)

    def test_vaultwarden_token_keeps_only_access_token(self):
        environment = {
            "PROVISIONING_VAULTWARDEN_CLIENT_ID": "user.service-id",
            "PROVISIONING_VAULTWARDEN_CLIENT_SECRET": "service-secret",
            "PROVISIONING_VAULTWARDEN_ORGANIZATION_ID": "org-id",
            "PROVISIONING_VAULTWARDEN_DEVICE_IDENTIFIER": "device-id",
        }
        with patch.dict(os.environ, environment, clear=False):
            adapter = VaultwardenAdapter()
        requests = []

        def request(method, path, **kwargs):
            requests.append((method, path, kwargs))
            return {
                "access_token": "short-lived-access-token",
                "Key": "encrypted-user-key",
                "PrivateKey": "encrypted-private-key",
                "AccountKeys": {"wrappedPrivateKey": "encrypted"},
            }

        adapter.request = request
        self.assertEqual(adapter.token(), "short-lived-access-token")
        self.assertEqual(requests[0][1], "/identity/connect/token")
        self.assertEqual(requests[0][2]["form"]["grant_type"], "client_credentials")
        self.assertNotIn("password", requests[0][2]["form"])

    def test_vaultwarden_plans_one_zero_access_user_invitation(self):
        adapter = VaultwardenAdapter()
        adapter.members = lambda: []
        result = adapter.discover(
            self.source(groups=["employees", "app-vaultwarden"]),
            self.target(
                id="vaultwarden",
                display_name="Vaultwarden",
                strategy="invitation",
                adapter="vaultwarden",
                eligibility_groups=["employees", "app-vaultwarden"],
            ),
        )
        self.assertEqual(result.state, "planned")
        self.assertEqual(result.action, "create")
        self.assertEqual(result.details["membership_type"], 2)

    def test_vaultwarden_tracks_invited_accepted_and_confirmed_states(self):
        adapter = VaultwardenAdapter()
        target = self.target(id="vaultwarden", adapter="vaultwarden")
        source = self.source()
        base = {
            "id": "membership-id",
            "email": source.email,
            "type": 2,
            "accessAll": False,
            "collections": [],
            "groups": [],
        }
        invited = adapter.decision_for_member({**base, "status": 0}, source, target)
        accepted = adapter.decision_for_member({**base, "status": 1}, source, target)
        confirmed = adapter.decision_for_member({**base, "status": 2}, source, target)
        self.assertEqual(invited.state, "invited")
        self.assertFalse(invited.details["confirmation_required"])
        self.assertEqual(accepted.state, "invited")
        self.assertTrue(accepted.details["confirmation_required"])
        self.assertEqual(confirmed.state, "active")

    def test_vaultwarden_refuses_privilege_or_access_all_drift(self):
        adapter = VaultwardenAdapter()
        target = self.target(id="vaultwarden", adapter="vaultwarden")
        source = self.source()
        base = {
            "id": "membership-id",
            "email": source.email,
            "status": 2,
            "type": 2,
            "accessAll": False,
            "collections": [],
            "groups": [],
        }
        for drift in (
            {"type": 1},
            {"accessAll": True},
        ):
            result = adapter.decision_for_member({**base, **drift}, source, target)
            self.assertEqual(result.state, "conflict")

    def test_vaultwarden_records_owner_managed_collection_access(self):
        adapter = VaultwardenAdapter()
        source = self.source()
        result = adapter.decision_for_member(
            {
                "id": "membership-id",
                "email": source.email,
                "status": 2,
                "type": 2,
                "accessAll": False,
                "collections": [{"id": "approved-collection"}],
                "groups": ["owner-managed-group"],
            },
            source,
            self.target(id="vaultwarden", adapter="vaultwarden"),
        )
        self.assertEqual(result.state, "active")
        self.assertEqual(result.details["collection_count"], 1)
        self.assertEqual(result.details["group_count"], 1)

    def test_vaultwarden_invite_payload_and_readback_are_least_privilege(self):
        adapter = VaultwardenAdapter()
        adapter.organization_id = "org-id"
        adapter.token = lambda: "access-token"
        source = self.source()
        target = self.target(id="vaultwarden", adapter="vaultwarden")
        member = {
            "id": "membership-id",
            "email": source.email,
            "status": 0,
            "type": 2,
            "accessAll": False,
            "collections": [],
            "groups": [],
        }
        member_responses = iter(([], [member]))
        adapter.members = lambda: next(member_responses)
        requests = []
        adapter.request = lambda method, path, **kwargs: requests.append((method, path, kwargs))

        result = adapter.create(SimpleNamespace(), source, target)

        self.assertEqual(result.state, "invited")
        self.assertEqual(result.target_account_id, "membership-id")
        payload = requests[0][2]["payload"]
        self.assertEqual(payload["type"], 2)
        self.assertEqual(payload["groups"], [])
        self.assertEqual(payload["collections"], [])
        self.assertEqual(payload["permissions"], {})

    def test_vaultwarden_disable_removes_only_exact_membership(self):
        adapter = VaultwardenAdapter()
        adapter.organization_id = "org-id"
        adapter.token = lambda: "access-token"
        source = self.source()
        target = self.target(id="vaultwarden", adapter="vaultwarden")
        member = {
            "id": "membership-id",
            "email": source.email,
            "status": 2,
            "type": 2,
            "accessAll": False,
            "collections": [],
            "groups": [],
        }
        member_responses = iter(([member], []))
        adapter.members = lambda: next(member_responses)
        requests = []
        adapter.request = lambda method, path, **kwargs: requests.append((method, path, kwargs))

        result = adapter.disable(
            SimpleNamespace(details={"account_id": "membership-id"}, target_account_id=None),
            source,
            target,
        )

        self.assertEqual(result.state, "suspended")
        self.assertTrue(result.details["personal_vault_preserved"])
        self.assertEqual(requests[0][0], "DELETE")
        self.assertEqual(requests[0][1], "/api/organizations/org-id/users/membership-id")

    def test_redaction_covers_vaultwarden_encryption_fields(self):
        self.assertEqual(
            redact({"Key": "encrypted", "PrivateKey": "private", "AccountKeys": {"x": "y"}}),
            {"Key": "[REDACTED]", "PrivateKey": "[REDACTED]", "AccountKeys": "[REDACTED]"},
        )

    def test_osticket_plans_only_approved_agent_placement(self):
        class Connection:
            def __enter__(self):
                return self

            def __exit__(self, *_):
                return None

        adapter = OsTicketAdapter()
        adapter.connect = lambda: Connection()
        adapter.require_schema = lambda *_: None
        adapter.placement = lambda *_: {
            "department_id": 1,
            "department_name": "Support",
            "role_id": 5,
            "role_name": "Support Agent",
            "permissions": ["ticket.reply"],
        }
        adapter.account_rows = lambda *_: []
        result = adapter.discover(
            self.source(username="pat.morgan"),
            self.target(id="osticket", display_name="osTicket agents", adapter="osticket"),
        )
        self.assertEqual(result.state, "planned")
        self.assertEqual(result.action, "create")
        self.assertEqual(result.details["department_id"], 1)
        self.assertEqual(result.details["role_id"], 5)

    def test_osticket_refuses_email_only_agent_match(self):
        class Connection:
            def __enter__(self):
                return self

            def __exit__(self, *_):
                return None

        adapter = OsTicketAdapter()
        adapter.connect = lambda: Connection()
        adapter.require_schema = lambda *_: None
        adapter.placement = lambda *_: {
            "department_id": 1,
            "department_name": "Support",
            "role_id": 5,
            "role_name": "Support Agent",
            "permissions": ["ticket.reply"],
        }
        adapter.account_rows = lambda *_: [
            {"staff_id": 7, "username": "someone-else", "email": "person@example.com"}
        ]
        result = adapter.discover(
            self.source(username="pat.morgan"),
            self.target(id="osticket", display_name="osTicket agents", adapter="osticket"),
        )
        self.assertEqual(result.state, "conflict")
        self.assertIn("different osTicket username", result.details["reason"])

    def test_osticket_refuses_privileged_or_drifted_agent(self):
        adapter = OsTicketAdapter()
        placement = {
            "department_id": 1,
            "department_name": "Support",
            "role_id": 5,
            "role_name": "Support Agent",
            "permissions": ["ticket.reply"],
        }
        row = {
            "staff_id": 7,
            "dept_id": 1,
            "role_id": 5,
            "username": "pat.morgan",
            "email": "person@example.com",
            "isadmin": 1,
            "passwd": None,
            "team_count": 0,
            "extra_department_count": 0,
        }
        reason = adapter.validate_account(
            row,
            self.source(username="pat.morgan"),
            self.target(id="osticket", display_name="osTicket agents", adapter="osticket"),
            placement,
        )
        self.assertIn("privileged", reason)
        row["isadmin"] = 0
        row["team_count"] = 1
        self.assertIn(
            "team membership",
            adapter.validate_account(
                row,
                self.source(username="pat.morgan"),
                self.target(id="osticket", display_name="osTicket agents", adapter="osticket"),
                placement,
            ),
        )

    def test_osticket_disable_revokes_exact_agent_sessions(self):
        placement = {
            "department_id": 1,
            "department_name": "Support",
            "role_id": 5,
            "role_name": "Support Agent",
            "permissions": ["ticket.reply"],
        }

        class Cursor:
            rowcount = 0

            def __init__(self):
                self.select_count = 0
                self.row = None

            def __enter__(self):
                return self

            def __exit__(self, *_):
                return None

            def execute(self, query, _params=None):
                self.rowcount = 0
                if query.startswith("SELECT s.staff_id"):
                    self.select_count += 1
                    self.row = {
                        "staff_id": 7,
                        "dept_id": 1,
                        "role_id": 5,
                        "username": "pat.morgan",
                        "email": "person@example.com",
                        "isactive": 1 if self.select_count == 1 else 0,
                        "isadmin": 0,
                        "passwd": None,
                        "team_count": 0,
                        "extra_department_count": 0,
                        "api_key_count": 0,
                    }
                elif query.startswith("UPDATE ost_staff"):
                    self.rowcount = 1
                elif query.startswith("DELETE FROM ost_session"):
                    self.rowcount = 2

            def fetchone(self):
                return self.row

        class Connection:
            def __init__(self):
                self.cursor_instance = Cursor()
                self.committed = False

            def __enter__(self):
                return self

            def __exit__(self, *_):
                return None

            def cursor(self):
                return self.cursor_instance

            def commit(self):
                self.committed = True

            def rollback(self):
                raise AssertionError("valid osTicket disable must not roll back")

        adapter = OsTicketAdapter()
        connection = Connection()
        adapter.connect = lambda: connection
        adapter.require_schema = lambda *_: None
        adapter.placement = lambda *_: placement
        result = adapter.disable(
            SimpleNamespace(details={"account_id": "7"}, target_account_id=None),
            self.source(username="pat.morgan"),
            self.target(id="osticket", display_name="osTicket agents", adapter="osticket"),
        )
        self.assertEqual(result.state, "suspended")
        self.assertEqual(result.details["sessions_revoked"], 2)
        self.assertEqual(result.details["team_count"], 0)
        self.assertEqual(result.details["extra_department_count"], 0)
        self.assertTrue(connection.committed)

    def test_espocrm_discovers_exact_subject_after_profile_email_change(self):
        class Connection:
            def __enter__(self):
                return self

            def __exit__(self, *_):
                return None

        adapter = EspoCrmAdapter()
        adapter.connect = lambda: Connection()
        adapter.require_schema = lambda *_: None
        adapter.account_rows = lambda _connection, _source: [
            {
                "id": "espo-user-1",
                "user_name": "user-123",
                "type": "regular",
                "is_active": 1,
                "email": "old@example.com",
                "role_ids": "role-b,role-a",
                "team_ids": "team-a",
            }
        ]
        result = adapter.discover(
            self.source(email="new@example.com"),
            self.target(id="espocrm", display_name="EspoCRM", adapter="espocrm"),
        )
        self.assertEqual(result.state, "active")
        self.assertEqual(result.target_account_id, "espo-user-1")
        self.assertEqual(result.details["external_subject"], "user-123")
        self.assertEqual(result.details["role_ids"], ["role-a", "role-b"])
        self.assertEqual(result.details["team_ids"], ["team-a"])

    def test_espocrm_refuses_email_only_identity_match(self):
        class Connection:
            def __enter__(self):
                return self

            def __exit__(self, *_):
                return None

        adapter = EspoCrmAdapter()
        adapter.connect = lambda: Connection()
        adapter.require_schema = lambda *_: None
        adapter.account_rows = lambda _connection, _source: [
            {
                "id": "espo-user-1",
                "user_name": "different-subject",
                "type": "regular",
                "is_active": 1,
                "email": "person@example.com",
            }
        ]
        result = adapter.discover(
            self.source(),
            self.target(id="espocrm", display_name="EspoCRM", adapter="espocrm"),
        )
        self.assertEqual(result.state, "conflict")
        self.assertIn("another EspoCRM identity", result.details["reason"])

    def test_espocrm_refuses_non_regular_subject_match(self):
        class Connection:
            def __enter__(self):
                return self

            def __exit__(self, *_):
                return None

        adapter = EspoCrmAdapter()
        adapter.connect = lambda: Connection()
        adapter.require_schema = lambda *_: None
        adapter.account_rows = lambda _connection, _source: [
            {
                "id": "espo-admin-1",
                "user_name": "user-123",
                "type": "admin",
                "is_active": 1,
                "email": "person@example.com",
            }
        ]
        result = adapter.discover(
            self.source(),
            self.target(id="espocrm", display_name="EspoCRM", adapter="espocrm"),
        )
        self.assertEqual(result.state, "conflict")
        self.assertIn("privileged", result.details["reason"])

    def test_espocrm_disable_revokes_tokens_and_preserves_authorization(self):
        class Cursor:
            rowcount = 0

            def __init__(self):
                self.select_count = 0
                self.row = None

            def __enter__(self):
                return self

            def __exit__(self, *_):
                return None

            def execute(self, query, _params=None):
                self.rowcount = 0
                if query.startswith("SELECT u.id"):
                    self.select_count += 1
                    self.row = {
                        "id": "espo-user-1",
                        "user_name": "user-123",
                        "type": "regular",
                        "is_active": 1 if self.select_count == 1 else 0,
                        "email": "person@example.com",
                        "role_ids": "role-a",
                        "team_ids": "team-a",
                    }
                elif query.startswith("UPDATE user"):
                    self.rowcount = 1
                elif query.startswith("UPDATE auth_token"):
                    self.rowcount = 2

            def fetchone(self):
                return self.row

        class Connection:
            def __init__(self):
                self.cursor_instance = Cursor()
                self.committed = False

            def __enter__(self):
                return self

            def __exit__(self, *_):
                return None

            def cursor(self):
                return self.cursor_instance

            def commit(self):
                self.committed = True

            def rollback(self):
                raise AssertionError("valid EspoCRM disable must not roll back")

        adapter = EspoCrmAdapter()
        connection = Connection()
        adapter.connect = lambda: connection
        adapter.require_schema = lambda *_: None
        result = adapter.disable(
            SimpleNamespace(details={"account_id": "espo-user-1"}, target_account_id=None),
            self.source(),
            self.target(id="espocrm", display_name="EspoCRM", adapter="espocrm"),
        )
        self.assertEqual(result.state, "suspended")
        self.assertEqual(result.details["tokens_revoked"], 2)
        self.assertEqual(result.details["role_ids"], ["role-a"])
        self.assertEqual(result.details["team_ids"], ["team-a"])
        self.assertTrue(connection.committed)

    def test_espocrm_stops_if_authorization_changes_during_disable(self):
        class Cursor:
            rowcount = 0

            def __init__(self):
                self.select_count = 0

            def __enter__(self):
                return self

            def __exit__(self, *_):
                return None

            def execute(self, query, _params=None):
                self.rowcount = 1 if query.startswith("UPDATE") else 0
                if query.startswith("SELECT u.id"):
                    self.select_count += 1
                    self.row = {
                        "id": "espo-user-1",
                        "user_name": "user-123",
                        "type": "regular",
                        "is_active": 1 if self.select_count == 1 else 0,
                        "email": "person@example.com",
                        "role_ids": "role-a" if self.select_count == 1 else "role-b",
                        "team_ids": "team-a",
                    }

            def fetchone(self):
                return self.row

        class Connection:
            def __init__(self):
                self.cursor_instance = Cursor()
                self.rolled_back = False

            def __enter__(self):
                return self

            def __exit__(self, *_):
                return None

            def cursor(self):
                return self.cursor_instance

            def commit(self):
                raise AssertionError("authorization drift must not commit")

            def rollback(self):
                self.rolled_back = True

        adapter = EspoCrmAdapter()
        connection = Connection()
        adapter.connect = lambda: connection
        adapter.require_schema = lambda *_: None
        with self.assertRaisesRegex(ProvisioningError, "roles or teams changed"):
            adapter.disable(
                SimpleNamespace(details={"account_id": "espo-user-1"}, target_account_id=None),
                self.source(),
                self.target(id="espocrm", display_name="EspoCRM", adapter="espocrm"),
            )
        self.assertTrue(connection.rolled_back)

    def test_erpnext_changed_email_requires_manual_review(self):
        class Cursor:
            def __enter__(self):
                return self

            def __exit__(self, *_):
                return None

            def execute(self, _query, _params=None):
                return None

            def fetchall(self):
                return [
                    {
                        "name": "old@example.com",
                        "email": "old@example.com",
                        "enabled": 1,
                        "user_type": "System User",
                        "social_login_name": "social-1",
                        "userid": "user-123",
                        "is_privileged": 0,
                    }
                ]

        class Connection:
            def __enter__(self):
                return self

            def __exit__(self, *_):
                return None

            def cursor(self):
                return Cursor()

        adapter = ErpNextAdapter()
        adapter.connect = lambda: Connection()
        adapter.require_schema = lambda *_: None
        result = adapter.discover(
            self.source(email="new@example.com"),
            self.target(id="erpnext", adapter="erpnext"),
        )
        self.assertEqual(result.state, "not_ready")
        self.assertEqual(result.action, "manual_review")
        self.assertIn("email migration", result.details["reason"])

    def test_frappe_hr_system_user_disable_revokes_sessions_without_deleting_account(self):
        class Cursor:
            rowcount = 0

            def __enter__(self):
                return self

            def __exit__(self, *_):
                return None

            def execute(self, query, _params=None):
                if query.startswith("SELECT u.name"):
                    self.row = {
                        "name": "person@example.com",
                        "email": "person@example.com",
                        "user_type": "System User",
                        "is_privileged": 0,
                    }
                elif query.startswith("DELETE FROM `tabSessions`"):
                    self.rowcount = 2
                elif query.startswith("UPDATE `tabUser`"):
                    self.rowcount = 1

            def fetchone(self):
                return self.row

            def fetchall(self):
                return [{"sid": "session-1"}, {"sid": "session-2"}]

        class Connection:
            def __init__(self):
                self.cursor_instance = Cursor()
                self.committed = False

            def __enter__(self):
                return self

            def __exit__(self, *_):
                return None

            def cursor(self):
                return self.cursor_instance

            def commit(self):
                self.committed = True

            def rollback(self):
                raise AssertionError("valid ERPNext disable must not roll back")

        adapter = ErpNextAdapter()
        connection = Connection()
        adapter.connect = lambda: connection
        adapter.require_schema = lambda *_: None
        revoked = []
        adapter.revoke_cached_sessions = lambda session_ids: revoked.extend(session_ids)
        result = adapter.disable(
            SimpleNamespace(
                details={"account_id": "person@example.com"},
                target_account_id="person@example.com",
            ),
            self.source(subject="user-123"),
            self.target(id="erpnext", adapter="erpnext"),
        )
        self.assertEqual(result.state, "suspended")
        self.assertEqual(result.details["sessions_revoked"], 2)
        self.assertEqual(revoked, ["session-1", "session-2"])
        self.assertTrue(connection.committed)

    def test_erpnext_link_rechecks_privilege_before_write(self):
        class Cursor:
            rowcount = 0

            def __init__(self):
                self.updated = False

            def __enter__(self):
                return self

            def __exit__(self, *_):
                return None

            def execute(self, query, _params=None):
                if query.startswith("SELECT u.name"):
                    self.row = {
                        "name": "person@example.com",
                        "email": "person@example.com",
                        "user_type": "Website User",
                        "userid": "person@example.com",
                        "is_privileged": 1,
                    }
                elif query.startswith("UPDATE `tabUser Social Login`"):
                    self.updated = True

            def fetchone(self):
                return self.row

        class Connection:
            def __init__(self):
                self.cursor_instance = Cursor()
                self.rolled_back = False

            def __enter__(self):
                return self

            def __exit__(self, *_):
                return None

            def cursor(self):
                return self.cursor_instance

            def commit(self):
                raise AssertionError("privileged link must not commit")

            def rollback(self):
                self.rolled_back = True

        adapter = ErpNextAdapter()
        connection = Connection()
        adapter.connect = lambda: connection
        adapter.require_schema = lambda *_: None
        action = SimpleNamespace(
            details={
                "account_id": "person@example.com",
                "social_login_name": "social-1",
                "legacy_identifier": "person@example.com",
            },
            target_account_id="person@example.com",
        )
        with self.assertRaisesRegex(ProvisioningError, "privileged"):
            adapter.link(
                action,
                self.source(username="person@example.com"),
                self.target(id="erpnext", adapter="erpnext"),
            )
        self.assertTrue(connection.rolled_back)
        self.assertFalse(connection.cursor_instance.updated)

    def test_seafile_changed_email_resolves_by_immutable_subject(self):
        class Connection:
            def __enter__(self):
                return self

            def __exit__(self, *_):
                return None

        adapter = SeafileAdapter()
        adapter.connect = lambda: Connection()
        adapter.require_schema = lambda *_: None
        adapter.account_rows = lambda _connection, _source: [
            {
                "social_id": 7,
                "username": "virtual@keycloak",
                "provider": "keycloak",
                "uid": "user-123",
                "account_id": 42,
                "internal_username": "virtual@keycloak",
                "is_staff": 0,
                "is_active": 1,
                "contact_email": "old@example.com",
                "is_privileged_role": 0,
                "group_count": 0,
                "organization_count": 0,
            }
        ]
        result = adapter.discover(
            self.source(email="new@example.com"),
            self.target(id="seafile", display_name="Seafile", adapter="seafile"),
        )
        self.assertEqual(result.state, "active")
        self.assertEqual(result.target_account_id, "42")
        self.assertEqual(result.target_username, "virtual@keycloak")

    def test_seafile_disable_revokes_tokens_and_encoded_sessions(self):
        encoded_session = base64.urlsafe_b64encode(
            json.dumps({"_auth_user_name": "virtual@keycloak"}).encode()
        ).rstrip(b"=").decode() + ":timestamp:signature"

        class Cursor:
            rowcount = 0

            def __init__(self):
                self.rows = []

            def __enter__(self):
                return self

            def __exit__(self, *_):
                return None

            def execute(self, query, _params=None):
                self.rowcount = 0
                if query.startswith("SELECT eu.id"):
                    self.row = {
                        "account_id": 42,
                        "internal_username": "virtual@keycloak",
                        "is_staff": 0,
                        "contact_email": "person@example.com",
                        "is_privileged_role": 0,
                    }
                elif "DELETE FROM `seahub_db`.`api2_token`" in query:
                    self.rowcount = 1
                elif query.startswith("SELECT session_key"):
                    self.rows = [
                        {"session_key": "ours", "session_data": encoded_session},
                        {
                            "session_key": "theirs",
                            "session_data": base64.urlsafe_b64encode(
                                json.dumps({"login_user": "other@keycloak"}).encode()
                            ).rstrip(b"=").decode()
                            + ":timestamp:signature",
                        },
                    ]
                elif "DELETE FROM `seahub_db`.django_session" in query:
                    self.rowcount = 1

            def fetchone(self):
                return self.row

            def fetchall(self):
                return self.rows

        class Connection:
            def __init__(self):
                self.cursor_instance = Cursor()
                self.committed = False

            def __enter__(self):
                return self

            def __exit__(self, *_):
                return None

            def cursor(self):
                return self.cursor_instance

            def commit(self):
                self.committed = True

            def rollback(self):
                raise AssertionError("valid Seafile disable must not roll back")

        adapter = SeafileAdapter()
        connection = Connection()
        adapter.connect = lambda: connection
        adapter.require_schema = lambda *_: None
        result = adapter.disable(
            SimpleNamespace(details={"account_id": "42"}, target_account_id="42"),
            self.source(subject="user-123"),
            self.target(id="seafile", display_name="Seafile", adapter="seafile"),
        )
        self.assertEqual(result.state, "suspended")
        self.assertEqual(result.details["tokens_revoked"], 1)
        self.assertEqual(result.details["sessions_revoked"], 1)
        self.assertTrue(connection.committed)

    def test_seafile_rejects_unsafe_database_identifier(self):
        with patch.dict(
            os.environ,
            {"PROVISIONING_SEAFILE_CCNET_DB_NAME": "ccnet_db; DROP DATABASE ccnet_db"},
            clear=True,
        ):
            with self.assertRaisesRegex(ProvisioningError, "safe database identifier"):
                _ = SeafileAdapter().ccnet_database

    def test_penpot_linked_profile_email_drift_plans_guarded_update(self):
        class Cursor:
            def __enter__(self):
                return self

            def __exit__(self, *_):
                return None

        class Connection:
            def __enter__(self):
                return self

            def __exit__(self, *_):
                return None

            def cursor(self):
                return Cursor()

        adapter = PenpotAdapter()
        adapter.connect = lambda: Connection()
        adapter.require_schema = lambda *_: None
        adapter.select_profiles = lambda *_args, **_kwargs: [
            {
                "id": "profile-1",
                "email": "old@example.com",
                "fullname": "Pat Morgan",
                "is_active": True,
                "is_blocked": False,
                "auth_backend": "oidc",
                "oidc_subject": "user-123",
                "deleted_at": None,
                "default_project_id": "project-1",
                "default_team_id": "team-1",
                "team_memberships": 1,
                "project_memberships": 0,
                "file_memberships": 0,
            }
        ]
        link = SimpleNamespace(target_account_id="profile-1", target_username="old@example.com")
        result = adapter.discover_linked(
            self.source(email="new@example.com"),
            self.target(id="penpot", display_name="Penpot", adapter="penpot"),
            link,
        )
        self.assertEqual(result.state, "planned")
        self.assertEqual(result.action, "update")
        self.assertEqual(result.target_account_id, "profile-1")
        self.assertEqual(result.details["new_email"], "new@example.com")

    def test_penpot_disable_revokes_exact_sessions_and_tokens(self):
        class Cursor:
            def __init__(self):
                self.rowcount = 0
                self.executions = []

            def __enter__(self):
                return self

            def __exit__(self, *_):
                return None

            def execute(self, query, params=None):
                self.executions.append((query, params))
                if query.startswith("SELECT id,email,is_active"):
                    self.row = {
                        "id": "profile-1",
                        "email": "person@example.com",
                        "is_active": True,
                        "is_blocked": False,
                        "auth_backend": "oidc",
                    }
                    self.rowcount = 1
                elif query.startswith("DELETE FROM http_session_v2"):
                    self.rowcount = 2
                elif query.startswith("DELETE FROM http_session"):
                    self.rowcount = 1
                elif query.startswith("DELETE FROM access_token"):
                    self.rowcount = 1
                else:
                    self.rowcount = 1

            def fetchone(self):
                return self.row

        class Transaction:
            def __enter__(self):
                return self

            def __exit__(self, *_):
                return None

        class Connection:
            def __init__(self):
                self.cursor_instance = Cursor()

            def __enter__(self):
                return self

            def __exit__(self, *_):
                return None

            def cursor(self):
                return self.cursor_instance

            def transaction(self):
                return Transaction()

        adapter = PenpotAdapter()
        connection = Connection()
        adapter.connect = lambda: connection
        adapter.require_schema = lambda *_: None
        result = adapter.disable(
            SimpleNamespace(details={"account_id": "profile-1"}, target_account_id="profile-1"),
            self.source(),
            self.target(id="penpot", display_name="Penpot", adapter="penpot"),
        )
        self.assertEqual(result.state, "suspended")
        self.assertEqual(result.details["sessions_revoked"], 3)
        self.assertEqual(result.details["tokens_revoked"], 1)
        mutation_params = [
            params
            for query, params in connection.cursor_instance.executions
            if query.startswith(("UPDATE profile", "DELETE FROM"))
        ]
        self.assertTrue(all("profile-1" in params for params in mutation_params))

    def test_penpot_refuses_non_oidc_profile(self):
        adapter = PenpotAdapter()
        row = {
            "id": "profile-1",
            "email": "person@example.com",
            "is_active": True,
            "is_blocked": False,
            "auth_backend": "penpot",
            "oidc_subject": "user-123",
            "default_project_id": "project-1",
            "default_team_id": "team-1",
            "team_memberships": 1,
            "project_memberships": 0,
            "file_memberships": 0,
        }
        result = adapter.decision_for_row(
            row,
            self.source(),
            self.target(id="penpot", display_name="Penpot", adapter="penpot"),
        )
        self.assertEqual(result.state, "conflict")
        self.assertIn("not created through OIDC", result.details["reason"])

    def test_netbird_discovers_exact_idp_subject_and_owned_peers(self):
        adapter = NetBirdAdapter()
        account_id = self.netbird_user_id()
        responses = {
            ("GET", "/api/users"): [
                {
                    "id": account_id,
                    "idp_id": "keycloak-connector",
                    "email": "person@example.com",
                    "role": "user",
                    "is_service_user": False,
                    "is_blocked": False,
                    "auto_groups": ["group-1"],
                    "issued": "jwt",
                }
            ],
            ("GET", "/api/peers"): [
                {"id": "peer-2", "user_id": account_id},
                {"id": "peer-other", "user_id": "another-user"},
                {"id": "peer-1", "user_id": account_id},
            ],
            ("GET", "/api/groups"): [
                {"id": "group-1", "name": "app-netbird"}
            ],
        }
        adapter.request = lambda method, path, payload=None: responses[(method, path)]
        result = adapter.discover(
            self.source(),
            self.target(id="netbird", display_name="NetBird", adapter="netbird"),
        )
        self.assertEqual(result.state, "active")
        self.assertEqual(result.target_account_id, account_id)
        self.assertEqual(result.details["owned_peer_ids"], ["peer-1", "peer-2"])

    def test_netbird_refuses_email_only_identity_match(self):
        adapter = NetBirdAdapter()
        adapter.request = lambda *_args, **_kwargs: [
            {
                "id": self.netbird_user_id("different-subject"),
                "idp_id": "keycloak-connector",
                "email": "person@example.com",
                "role": "user",
                "is_service_user": False,
            }
        ]
        result = adapter.discover(
            self.source(),
            self.target(id="netbird", display_name="NetBird", adapter="netbird"),
        )
        self.assertEqual(result.state, "conflict")
        self.assertIn("another NetBird identity", result.details["reason"])

    def test_netbird_pending_approval_requires_manual_review(self):
        adapter = NetBirdAdapter()
        account_id = self.netbird_user_id()
        responses = {
            ("GET", "/api/users"): [
                {
                    "id": account_id,
                    "idp_id": "keycloak-connector",
                    "email": "person@example.com",
                    "role": "user",
                    "is_service_user": False,
                    "is_blocked": True,
                    "pending_approval": True,
                    "auto_groups": ["group-1"],
                }
            ],
            ("GET", "/api/groups"): [{"id": "group-1", "name": "app-netbird"}],
            ("GET", "/api/peers"): [],
        }
        adapter.request = lambda method, path, payload=None: responses[(method, path)]
        result = adapter.discover(
            self.source(),
            self.target(id="netbird", display_name="NetBird", adapter="netbird"),
        )
        self.assertEqual(result.state, "conflict")
        self.assertIn("administrator approval", result.details["reason"])

    def test_netbird_disable_preserves_auto_groups_and_peer_ownership(self):
        adapter = NetBirdAdapter()
        account_id = self.netbird_user_id()
        user = {
            "id": account_id,
            "idp_id": "keycloak-connector",
            "email": "person@example.com",
            "role": "user",
            "is_service_user": False,
            "is_blocked": False,
            "auto_groups": ["group-1"],
            "issued": "jwt",
        }
        writes = []

        def request(method, path, payload=None):
            if method == "GET" and path == "/api/users":
                return [user]
            if method == "GET" and path == "/api/peers":
                return [{"id": "peer-1", "user_id": account_id}]
            if method == "GET" and path == "/api/groups":
                return [{"id": "group-1", "name": "app-netbird"}]
            if method == "PUT":
                writes.append((path, payload))
                return {**user, "is_blocked": True}
            raise AssertionError((method, path))

        adapter.request = request
        result = adapter.disable(
            SimpleNamespace(
                details={"account_id": account_id},
                target_account_id=account_id,
            ),
            self.source(),
            self.target(id="netbird", display_name="NetBird", adapter="netbird"),
        )
        self.assertEqual(result.state, "suspended")
        self.assertTrue(result.details["peer_ownership_preserved"])
        self.assertEqual(
            writes,
            [
                (
                    f"/api/users/{account_id}",
                    {
                        "role": "user",
                        "auto_groups": ["group-1"],
                        "is_blocked": True,
                    },
                )
            ],
        )

    def test_netbird_stops_if_peer_ownership_changes_during_disable(self):
        adapter = NetBirdAdapter()
        account_id = self.netbird_user_id()
        user = {
            "id": account_id,
            "idp_id": "keycloak-connector",
            "email": "person@example.com",
            "role": "user",
            "is_service_user": False,
            "is_blocked": False,
            "auto_groups": ["group-1"],
        }
        peer_reads = 0

        def request(method, path, payload=None):
            nonlocal peer_reads
            if path == "/api/users":
                return [user]
            if path == "/api/peers":
                peer_reads += 1
                return [
                    {
                        "id": "peer-before" if peer_reads == 1 else "peer-after",
                        "user_id": account_id,
                    }
                ]
            if path == "/api/groups":
                return [{"id": "group-1", "name": "app-netbird"}]
            if method == "PUT":
                return {**user, "is_blocked": True}
            raise AssertionError((method, path))

        adapter.request = request
        with self.assertRaisesRegex(ProvisioningError, "peer ownership changed"):
            adapter.disable(
                SimpleNamespace(
                    details={"account_id": account_id},
                    target_account_id=account_id,
                ),
                self.source(),
                self.target(id="netbird", display_name="NetBird", adapter="netbird"),
            )

    def test_target_state_hash_changes_when_execution_controls_change(self):
        target = self.target()
        initial = target_state_hash(target)
        target.dry_run = False
        self.assertNotEqual(initial, target_state_hash(target))

    def test_protected_accounts_are_configurable_and_case_insensitive(self):
        target = self.target(id="bookstack")
        environment = {
            "PROVISIONING_BOOKSTACK_PROTECTED_ACCOUNT_IDS": "1, 42",
            "PROVISIONING_BOOKSTACK_PROTECTED_USERNAMES": "Admin; BREAK-GLASS",
            "PROVISIONING_BOOKSTACK_PROTECTED_EMAILS": "Owner@Example.com",
        }
        with patch.dict(os.environ, environment, clear=True):
            self.assertEqual(protection_values(target, "account_ids"), {"1", "42"})
            self.assertEqual(
                protected_account_reason(target, username="admin"),
                "Target username is protected",
            )
            self.assertEqual(
                protected_account_reason(target, email="owner@example.com"),
                "Target email is protected",
            )
            initial = target_state_hash(target)
            os.environ["PROVISIONING_BOOKSTACK_PROTECTED_ACCOUNT_IDS"] = "1,42,99"
            self.assertNotEqual(initial, target_state_hash(target))

    def test_privileged_target_role_is_always_protected(self):
        self.assertEqual(
            protected_account_reason(self.target(), privileged=True),
            "Target account has a privileged or built-in role",
        )

    def test_sensitive_values_are_redacted_recursively(self):
        payload = {
            "username": "person",
            "password": "do-not-log",
            "nested": {"api_key": "also-secret", "result": "ok"},
        }
        self.assertEqual(redact(payload)["password"], "[REDACTED]")
        self.assertEqual(redact(payload)["nested"]["api_key"], "[REDACTED]")
        self.assertEqual(redact(payload)["nested"]["result"], "ok")
        with patch.dict(os.environ, {"TARGET_CLIENT_SECRET": "secret-value"}, clear=True):
            self.assertNotIn("secret-value", redact_error("request used secret-value"))

    def test_adapter_contract_rejects_unsupported_operation_and_state(self):
        adapter = TargetAdapter()
        target = self.target(adapter="contract")
        with self.assertRaisesRegex(RuntimeError, "does not support operation"):
            adapter.execute(
                ProvisioningAction(action="disable"),
                self.source(),
                target,
            )
        with self.assertRaisesRegex(RuntimeError, "unsupported lifecycle state"):
            validate_decision(adapter, AdapterDecision("invented"))

    def test_adapter_contract_dispatches_supported_operation(self):
        class MockAdapter(TargetAdapter):
            capabilities = frozenset({"discover", "plan", "create", "verify"})

            def discover(self, source, target):
                return AdapterDecision("planned", "create")

            def create(self, action, source, target):
                return AdapterDecision("active", target_account_id="mock-1")

        adapter = MockAdapter()
        result = adapter.execute(
            ProvisioningAction(action="create"),
            self.source(),
            self.target(adapter="mock"),
        )
        self.assertEqual(result.state, "active")
        self.assertEqual(result.target_account_id, "mock-1")

    def test_obsolete_pending_action_is_superseded(self):
        source = self.source()
        source.id = 7
        target = self.target()
        decision = AdapterDecision("planned", "link", details={"id": "current"})
        current_key = action_dedupe_key(source, target, decision)
        old = ProvisioningAction(
            id="old", run_id="run", source_identity_id=7, target_id=target.id,
            action="link", status="planned", dedupe_key="old-key",
            source_state_hash=source.source_state_hash, details={},
        )
        current = ProvisioningAction(
            id="current", run_id="run", source_identity_id=7, target_id=target.id,
            action="link", status="planned", dedupe_key=current_key,
            source_state_hash=source.source_state_hash, details=decision.details,
        )

        class FakeSession:
            def scalars(self, _statement):
                return [old, current]

        supersede_obsolete_actions(FakeSession(), source, target, decision)
        self.assertEqual(old.status, "superseded")
        self.assertEqual(current.status, "planned")


class ExecutionSafetyTests(unittest.TestCase):
    def source(self):
        source = SourceIdentity(
            issuer="https://issuer",
            subject="subject",
            username="person@example.com",
            email="person@example.com",
            email_verified=True,
            first_name="Pat",
            last_name="Morgan",
            enabled=True,
            groups=["employees"],
            attributes={},
            source_state_hash="source-hash",
            last_seen_at=datetime.now(timezone.utc),
        )
        source.id = 7
        return source

    def target(self):
        return ProvisioningTarget(
            id="mock",
            display_name="Mock",
            strategy="pre_provision",
            adapter="mock",
            enabled=True,
            dry_run=False,
            eligibility_groups=["employees"],
            settings={"retry_limit": 2},
            updated_by="test",
        )

    def action(self, target):
        return ProvisioningAction(
            id="action-1",
            run_id="run-1",
            source_identity_id=7,
            target_id=target.id,
            action="create",
            status="planned",
            dedupe_key="dedupe",
            source_state_hash="source-hash",
            target_state_hash=target_state_hash(target),
            details={},
            attempt_count=0,
        )

    class FakeSession:
        def __init__(self, action, source, target):
            self.action = action
            self.source = source
            self.target = target
            self.added = []
            self.rollbacks = 0

        def get(self, model, key):
            if model is ProvisioningAction:
                return self.action if key == self.action.id else None
            if model is SourceIdentity:
                return self.source if key == self.source.id else None
            if model is ProvisioningTarget:
                return self.target if key == self.target.id else None
            return None

        def add(self, value):
            self.added.append(value)

        def scalar(self, statement):
            if "provisioning_execution_attempts" not in str(statement):
                return None
            attempts = [
                item for item in self.added if isinstance(item, ProvisioningExecutionAttempt)
            ]
            return attempts[-1] if attempts else None

        def commit(self):
            pass

        def rollback(self):
            self.rollbacks += 1

    def test_successful_execution_is_attributed_and_audited(self):
        class MockAdapter(TargetAdapter):
            capabilities = frozenset({"discover", "plan", "create", "verify"})

            def create(self, action, source, target):
                return AdapterDecision("active", target_account_id="target-1")

        source = self.source()
        target = self.target()
        action = self.action(target)
        session = self.FakeSession(action, source, target)
        with patch.dict(ADAPTERS, {"mock": MockAdapter()}), patch.dict(
            os.environ, {"PROVISIONING_ALLOW_WRITES": "true"}
        ):
            result = execute_action(session, action.id, "admin@example.com", "Approved test")

        self.assertIs(result, action)
        self.assertEqual(action.status, "executed")
        self.assertEqual(action.attempt_count, 1)
        attempts = [item for item in session.added if isinstance(item, ProvisioningExecutionAttempt)]
        self.assertEqual(attempts[0].status, "succeeded")
        self.assertTrue(any(isinstance(item, IdentityLink) for item in session.added))
        self.assertTrue(any(isinstance(item, ProvisioningAuditEvent) for item in session.added))
        with self.assertRaisesRegex(RuntimeError, "not executable"):
            execute_action(session, action.id, "admin@example.com", "Duplicate execution")
        attempts = [item for item in session.added if isinstance(item, ProvisioningExecutionAttempt)]
        self.assertEqual(len(attempts), 1)

    def test_failed_execution_becomes_retryable_then_manual_review(self):
        class FailingAdapter(TargetAdapter):
            capabilities = frozenset({"discover", "plan", "create", "verify"})

            def create(self, action, source, target):
                raise RuntimeError("request failed with sensitive-value")

        source = self.source()
        target = self.target()
        action = self.action(target)
        session = self.FakeSession(action, source, target)
        environment = {
            "PROVISIONING_ALLOW_WRITES": "true",
            "MOCK_CLIENT_SECRET": "sensitive-value",
        }
        with patch.dict(ADAPTERS, {"mock": FailingAdapter()}), patch.dict(
            os.environ, environment
        ):
            with self.assertRaises(RuntimeError):
                execute_action(session, action.id, "admin@example.com", "First try")
            self.assertEqual(action.status, "retryable")
            self.assertEqual(action.last_error, "request failed with [REDACTED]")

            with self.assertRaises(RuntimeError):
                execute_action(session, action.id, "admin@example.com", "Second try")

        self.assertEqual(action.status, "manual_review")
        self.assertEqual(action.attempt_count, 2)

    def test_changed_target_configuration_makes_plan_stale(self):
        source = self.source()
        target = self.target()
        action = self.action(target)
        target.settings = {"retry_limit": 3}
        session = self.FakeSession(action, source, target)
        with patch.dict(os.environ, {"PROVISIONING_ALLOW_WRITES": "true"}):
            with self.assertRaisesRegex(RuntimeError, "configuration changed"):
                execute_action(session, action.id, "admin@example.com", "Execute")
        self.assertEqual(action.status, "stale")
        self.assertFalse(
            any(isinstance(item, ProvisioningExecutionAttempt) for item in session.added)
        )


class KeycloakConnectorTests(unittest.TestCase):
    def test_fetch_users_paginates_and_normalizes_groups(self):
        connector = KeycloakConnector()
        connector.realm = "support"
        connector.base_url = "http://keycloak:8080"
        responses = [
            [
                {
                    "id": "abc",
                    "username": "Person",
                    "email": "PERSON@EXAMPLE.COM",
                    "emailVerified": True,
                    "firstName": "Pat",
                    "lastName": "Morgan",
                    "enabled": True,
                    "attributes": {"employeeNumber": ["EMP-42"], "unapproved": ["secret"]},
                }
            ],
            [{"name": "employees", "path": "/employees"}],
        ]
        connector.token = lambda: "token"
        connector._request = lambda *args, **kwargs: responses.pop(0)
        users = connector.fetch_users()
        self.assertEqual(len(users), 1)
        self.assertEqual(users[0].email, "person@example.com")
        self.assertEqual(users[0].groups, ("employees",))
        self.assertEqual(users[0].attributes, {"employeeNumber": ["EMP-42"]})

    def test_missing_client_secret_fails_closed(self):
        with patch.dict(os.environ, {"PROVISIONING_KEYCLOAK_CLIENT_SECRET": ""}, clear=True):
            connector = KeycloakConnector()
            with self.assertRaisesRegex(RuntimeError, "not configured"):
                connector.token()


if __name__ == "__main__":
    unittest.main()
