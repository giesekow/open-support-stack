import os
import unittest
from datetime import datetime, timedelta, timezone
from unittest.mock import patch

from sqlalchemy import func, select, text

from app.database import SessionLocal
from app.models import (
    IdentityLink,
    ProvisioningAction,
    ProvisioningAuditEvent,
    ProvisioningExecutionAttempt,
    ProvisioningTarget,
    ReconciliationRun,
    SourceIdentity,
)
from app.provisioning import (
    ADAPTERS,
    AdapterDecision,
    GuacamoleAdapter,
    SourceUser,
    TargetAdapter,
    reconcile,
    seed_targets,
)


@unittest.skipUnless(
    os.getenv("PROVISIONING_INTEGRATION_TEST") == "1",
    "requires a disposable PostgreSQL database",
)
class ReconciliationIntegrationTests(unittest.TestCase):
    def setUp(self):
        with SessionLocal() as session:
            session.execute(
                text(
                    "TRUNCATE provisioning_execution_attempts, provisioning_audit_events, "
                    "provisioning_actions, provisioning_identity_links, provisioning_runs, "
                    "provisioning_source_identities, provisioning_targets RESTART IDENTITY CASCADE"
                )
            )
            session.commit()

    @staticmethod
    def user(subject="subject-1", groups=("employees",), enabled=True):
        return SourceUser(
            issuer="https://sso.example.com/realms/support",
            subject=subject,
            username="person@example.com",
            email="person@example.com",
            email_verified=True,
            first_name="Pat",
            last_name="Morgan",
            enabled=enabled,
            groups=groups,
            attributes={"employeeNumber": ["EMP-42"]},
        )

    @staticmethod
    def target(target_id="mock", adapter="integration"):
        return ProvisioningTarget(
            id=target_id,
            display_name=target_id.title(),
            strategy="pre_provision",
            adapter=adapter,
            enabled=True,
            dry_run=True,
            eligibility_groups=["employees"],
            settings={"retry_limit": 2},
            updated_by="test",
        )

    @staticmethod
    def connector(users):
        class Connector:
            def fetch_users(self):
                return users

        return Connector()

    def test_full_scan_lifecycle_and_identity_recreation_fail_closed(self):
        class StatefulAdapter(TargetAdapter):
            capabilities = frozenset(
                {"discover", "plan", "create", "update", "disable", "reactivate", "verify"}
            )

            def __init__(self):
                self.account_by_email = {}

            def discover(self, source, target):
                account = self.account_by_email.get(source.email)
                if account:
                    return AdapterDecision(
                        "active",
                        target_account_id=account,
                        target_username=source.email,
                    )
                return AdapterDecision(
                    "planned",
                    action="create",
                    details={"email": source.email},
                )

        adapter = StatefulAdapter()
        target = self.target()

        with SessionLocal() as session, patch.dict(ADAPTERS, {"integration": adapter}):
            session.add(target)
            session.commit()

            first = reconcile(
                session,
                actor="test",
                trigger="integration",
                connector=self.connector([self.user()]),
            )
            self.assertEqual(first.status, "completed")
            self.assertEqual(first.planned_count, 1)
            self.assertEqual(
                session.scalar(select(func.count()).select_from(ProvisioningAction)), 1
            )

            source = session.scalar(
                select(SourceIdentity).where(SourceIdentity.subject == "subject-1")
            )
            first_action = session.scalar(select(ProvisioningAction))
            first_action.status = "executed"
            adapter.account_by_email[source.email] = "account-1"
            session.add(
                IdentityLink(
                    source_identity_id=source.id,
                    target_id=target.id,
                    target_account_id="account-1",
                    target_username=source.email,
                    state="active",
                    verified_at=datetime.now(timezone.utc),
                )
            )
            session.commit()

            unchanged = reconcile(
                session,
                actor="test",
                trigger="integration",
                connector=self.connector([self.user()]),
            )
            self.assertEqual(unchanged.planned_count, 0)
            self.assertEqual(
                session.scalar(select(func.count()).select_from(ProvisioningAction)), 1
            )

            removed = reconcile(
                session,
                actor="test",
                trigger="integration",
                connector=self.connector([self.user(groups=())]),
            )
            disable = session.scalar(
                select(ProvisioningAction)
                .where(ProvisioningAction.action == "disable")
                .order_by(ProvisioningAction.created_at.desc())
            )
            self.assertEqual(removed.planned_count, 1)
            self.assertIsNotNone(disable)
            self.assertEqual(disable.status, "planned")

            deleted = reconcile(
                session,
                actor="test",
                trigger="integration",
                connector=self.connector([]),
            )
            source = session.scalar(
                select(SourceIdentity).where(SourceIdentity.subject == "subject-1")
            )
            self.assertIsNotNone(source.deleted_at)
            self.assertFalse(source.enabled)
            self.assertEqual(deleted.planned_count, 1)
            deleted_disable = session.scalar(
                select(ProvisioningAction)
                .where(
                    ProvisioningAction.source_identity_id == source.id,
                    ProvisioningAction.action == "disable",
                    ProvisioningAction.status == "planned",
                )
                .order_by(ProvisioningAction.created_at.desc())
            )
            self.assertIsNotNone(deleted_disable)

            # Execution-control changes stale the reviewed action. A deleted
            # source with a non-suspended link must remain reconcilable so a
            # fresh offboarding action can be approved and executed.
            target.dry_run = False
            session.commit()
            deleted_retry = reconcile(
                session,
                actor="test",
                trigger="integration",
                connector=self.connector([]),
            )
            retry_disable = session.scalar(
                select(ProvisioningAction)
                .where(
                    ProvisioningAction.source_identity_id == source.id,
                    ProvisioningAction.action == "disable",
                    ProvisioningAction.status == "planned",
                )
                .order_by(ProvisioningAction.created_at.desc())
            )
            self.assertEqual(deleted_retry.planned_count, 1)
            self.assertIsNotNone(retry_disable)

            # Returning to a previously used target state must create a new
            # lifecycle action, not revive or silently reuse audit history.
            target.dry_run = True
            session.commit()
            returned_state = reconcile(
                session,
                actor="test",
                trigger="integration",
                connector=self.connector([]),
            )
            returned_disable = session.scalar(
                select(ProvisioningAction)
                .where(
                    ProvisioningAction.source_identity_id == source.id,
                    ProvisioningAction.action == "disable",
                    ProvisioningAction.status == "planned",
                )
                .order_by(ProvisioningAction.created_at.desc())
            )
            self.assertEqual(returned_state.planned_count, 1)
            self.assertIsNotNone(returned_disable)
            self.assertNotEqual(returned_disable.id, deleted_disable.id)
            self.assertEqual(returned_disable.dedupe_key, deleted_disable.dedupe_key)

            recreated = reconcile(
                session,
                actor="test",
                trigger="integration",
                connector=self.connector([self.user(subject="subject-2")]),
            )
            identities = list(
                session.scalars(select(SourceIdentity).order_by(SourceIdentity.subject))
            )
            links = list(session.scalars(select(IdentityLink)))
            self.assertEqual([identity.subject for identity in identities], ["subject-1", "subject-2"])
            self.assertEqual(len(links), 1)
            self.assertEqual(links[0].source_identity_id, identities[0].id)
            conflict = session.scalar(
                select(ProvisioningAction)
                .where(
                    ProvisioningAction.source_identity_id == identities[1].id,
                    ProvisioningAction.status == "conflict",
                )
            )
            self.assertEqual(recreated.status, "completed")
            self.assertEqual(recreated.error_count, 0)
            self.assertEqual(recreated.conflict_count, 1)
            self.assertIsNotNone(conflict)
            self.assertEqual(conflict.action, "manual_review")

    def test_target_failure_does_not_block_other_target(self):
        class HealthyAdapter(TargetAdapter):
            capabilities = frozenset({"discover", "plan", "create", "verify"})

            def discover(self, source, target):
                return AdapterDecision(
                    "planned",
                    action="create",
                    details={"email": source.email},
                )

        class FailingAdapter(TargetAdapter):
            def discover(self, source, target):
                raise RuntimeError("target unavailable")

        with SessionLocal() as session, patch.dict(
            ADAPTERS,
            {
                "healthy-integration": HealthyAdapter(),
                "failing-integration": FailingAdapter(),
            },
        ):
            session.add(self.target("healthy", "healthy-integration"))
            session.add(self.target("broken", "failing-integration"))
            session.commit()

            run = reconcile(
                session,
                actor="test",
                trigger="integration",
                connector=self.connector([self.user()]),
            )

            actions = list(session.scalars(select(ProvisioningAction)))
            errors = list(
                session.scalars(
                    select(ProvisioningAuditEvent).where(
                        ProvisioningAuditEvent.event_type == "adapter.error"
                    )
                )
            )
            self.assertEqual(run.status, "completed_with_errors")
            self.assertEqual(run.error_count, 1)
            self.assertEqual(len(actions), 1)
            self.assertEqual(actions[0].target_id, "healthy")
            self.assertEqual(len(errors), 1)
            self.assertEqual(errors[0].target_id, "broken")

    def test_stale_jit_waiting_action_escalates_once_without_changing_eligibility(self):
        class JitAdapter(TargetAdapter):
            capabilities = frozenset({"discover", "verify"})

            def discover(self, source, target):
                return AdapterDecision(
                    "awaiting_first_login",
                    action="verify_first_login",
                    target_username=source.email,
                    details={"email": source.email},
                )

        target = self.target("jit-target", "jit-integration")
        target.strategy = "jit"
        environment = {"PROVISIONING_JIT_REVIEW_AFTER_DAYS": "7"}
        with SessionLocal() as session, patch.dict(
            ADAPTERS,
            {"jit-integration": JitAdapter()},
        ), patch.dict(os.environ, environment, clear=False):
            session.add(target)
            session.commit()

            first = reconcile(
                session,
                actor="test",
                trigger="integration",
                connector=self.connector([self.user()]),
            )
            action = session.scalar(select(ProvisioningAction))
            self.assertEqual(action.status, "awaiting_first_login")
            self.assertEqual(first.summary["jit_escalated"], 0)
            action.created_at = datetime.now(timezone.utc) - timedelta(days=8)
            session.commit()

            second = reconcile(
                session,
                actor="test",
                trigger="integration",
                connector=self.connector([self.user()]),
            )
            session.refresh(action)
            source = session.scalar(select(SourceIdentity))
            events = list(
                session.scalars(
                    select(ProvisioningAuditEvent).where(
                        ProvisioningAuditEvent.event_type
                        == "jit.first_login_review_required"
                    )
                )
            )
            self.assertEqual(second.summary["jit_escalated"], 1)
            self.assertEqual(action.status, "manual_review")
            self.assertIn("account remains eligible and unchanged", action.reason)
            self.assertTrue(source.enabled)
            self.assertEqual(source.groups, ["employees"])
            self.assertEqual(len(events), 1)

            third = reconcile(
                session,
                actor="test",
                trigger="integration",
                connector=self.connector([self.user()]),
            )
            self.assertEqual(third.summary["jit_escalated"], 0)
            self.assertEqual(
                session.scalar(
                    select(func.count())
                    .select_from(ProvisioningAuditEvent)
                    .where(
                        ProvisioningAuditEvent.event_type
                        == "jit.first_login_review_required"
                    )
                ),
                1,
            )

    def test_jit_waiting_action_is_superseded_when_eligibility_is_removed(self):
        class JitAdapter(TargetAdapter):
            capabilities = frozenset({"discover", "verify"})

            def discover(self, source, target):
                return AdapterDecision(
                    "awaiting_first_login",
                    action="verify_first_login",
                    details={"email": source.email},
                )

        target = self.target("jit-target", "jit-integration")
        target.strategy = "jit"
        with SessionLocal() as session, patch.dict(
            ADAPTERS,
            {"jit-integration": JitAdapter()},
        ), patch.dict(
            os.environ,
            {"PROVISIONING_JIT_REVIEW_AFTER_DAYS": "7"},
            clear=False,
        ):
            session.add(target)
            session.commit()
            reconcile(
                session,
                actor="test",
                trigger="integration",
                connector=self.connector([self.user()]),
            )
            action = session.scalar(select(ProvisioningAction))
            action.created_at = datetime.now(timezone.utc) - timedelta(days=8)
            session.commit()

            run = reconcile(
                session,
                actor="test",
                trigger="integration",
                connector=self.connector([self.user(groups=())]),
            )
            session.refresh(action)
            self.assertEqual(action.status, "superseded")
            self.assertEqual(run.summary["jit_escalated"], 0)
            self.assertEqual(
                session.scalar(
                    select(func.count())
                    .select_from(ProvisioningAuditEvent)
                    .where(
                        ProvisioningAuditEvent.event_type
                        == "jit.first_login_review_required"
                    )
                ),
                0,
            )

    def test_guacamole_lifecycle_has_no_password_or_permission_grant(self):
        with SessionLocal() as session:
            session.execute(text("DROP TABLE IF EXISTS guacamole_system_permission"))
            session.execute(text("DROP TABLE IF EXISTS guacamole_user"))
            session.execute(text("DROP TABLE IF EXISTS guacamole_entity"))
            session.execute(
                text(
                    "CREATE TABLE guacamole_entity ("
                    "entity_id serial PRIMARY KEY,name varchar(128) NOT NULL,"
                    "type varchar(32) NOT NULL,UNIQUE(type,name))"
                )
            )
            session.execute(
                text(
                    "CREATE TABLE guacamole_user ("
                    "user_id serial PRIMARY KEY,entity_id integer NOT NULL UNIQUE "
                    "REFERENCES guacamole_entity(entity_id) ON DELETE CASCADE,"
                    "password_hash bytea NOT NULL,password_salt bytea,"
                    "password_date timestamptz NOT NULL,disabled boolean NOT NULL DEFAULT FALSE,"
                    "expired boolean NOT NULL DEFAULT FALSE,full_name varchar(256),"
                    "email_address varchar(256))"
                )
            )
            session.execute(
                text(
                    "CREATE TABLE guacamole_system_permission ("
                    "entity_id integer NOT NULL REFERENCES guacamole_entity(entity_id) ON DELETE CASCADE,"
                    "permission varchar(32) NOT NULL,PRIMARY KEY(entity_id,permission))"
                )
            )
            session.commit()

        database_url = os.environ["DATABASE_URL"].replace(
            "postgresql+psycopg://", "postgresql://", 1
        )
        environment = {
            "PROVISIONING_GUACAMOLE_DATABASE_URL": database_url,
            "PROVISIONING_GUACAMOLE_PROTECTED_USERNAMES": "guacadmin",
        }
        adapter = GuacamoleAdapter()
        target = self.target("guacamole", "guacamole")
        target.settings = {"retry_limit": 2}

        with SessionLocal() as session:
            source = SourceIdentity(
                issuer="https://sso.example.com/realms/support",
                subject="guac-subject",
                username="person@example.com",
                email="person@example.com",
                email_verified=True,
                first_name="Pat",
                last_name="Morgan",
                enabled=True,
                groups=["employees", "app-guacamole"],
                attributes={},
                source_state_hash="guac-hash",
                last_seen_at=datetime.now(timezone.utc),
            )
            with patch.dict(os.environ, environment, clear=False):
                planned = adapter.discover(source, target)
                self.assertEqual((planned.state, planned.action), ("planned", "create"))
                action = ProvisioningAction(action="create", details=planned.details)
                created = adapter.execute(action, source, target)
                self.assertEqual(created.state, "active")
                active = adapter.discover(source, target)
                self.assertEqual(active.target_account_id, created.target_account_id)

                stored = session.execute(
                    text(
                        "SELECT octet_length(u.password_hash),octet_length(u.password_salt),"
                        "COUNT(p.permission) FROM guacamole_user u "
                        "LEFT JOIN guacamole_system_permission p ON p.entity_id=u.entity_id "
                        "WHERE u.entity_id=:entity_id GROUP BY u.user_id"
                    ),
                    {"entity_id": int(created.target_account_id)},
                ).one()
                self.assertEqual(stored, (32, 32, 0))

                lifecycle_details = {"entity_id": int(created.target_account_id)}
                disabled = adapter.execute(
                    ProvisioningAction(action="disable", details=lifecycle_details),
                    source,
                    target,
                )
                self.assertEqual(disabled.state, "suspended")
                self.assertEqual(adapter.discover(source, target).state, "suspended")
                reactivated = adapter.execute(
                    ProvisioningAction(action="reactivate", details=lifecycle_details),
                    source,
                    target,
                )
                self.assertEqual(reactivated.state, "active")

                entity_id = session.execute(
                    text(
                        "INSERT INTO guacamole_entity(name,type) VALUES "
                        "('breakglass','USER') RETURNING entity_id"
                    )
                ).scalar_one()
                session.execute(
                    text(
                        "INSERT INTO guacamole_user "
                        "(entity_id,password_hash,password_salt,password_date) "
                        "VALUES (:entity_id,decode('00','hex'),NULL,CURRENT_TIMESTAMP)"
                    ),
                    {"entity_id": entity_id},
                )
                session.execute(
                    text(
                        "INSERT INTO guacamole_system_permission(entity_id,permission) "
                        "VALUES (:entity_id,'ADMINISTER')"
                    ),
                    {"entity_id": entity_id},
                )
                session.commit()
                source.username = "breakglass"
                source.email = "breakglass@example.com"
                self.assertEqual(adapter.discover(source, target).state, "conflict")

    def test_system_owned_manual_target_upgrades_to_implemented_adapter(self):
        with SessionLocal() as session:
            for target_id in ("guacamole", "vaultwarden"):
                target = self.target(target_id, "manual")
                target.updated_by = "system:initial-import"
                session.add(target)
            session.commit()
            seed_targets(session)
            for target_id in ("guacamole", "vaultwarden"):
                upgraded = session.get(ProvisioningTarget, target_id)
                self.assertEqual(upgraded.adapter, target_id)
                self.assertEqual(upgraded.updated_by, "system:adapter-upgrade")
                self.assertTrue(upgraded.dry_run)


if __name__ == "__main__":
    unittest.main()
