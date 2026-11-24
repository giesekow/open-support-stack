"""Create identity provisioning control-plane tables.

Revision ID: 0002
Revises: 0001
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision = "0002"
down_revision = "0001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "provisioning_targets",
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column("display_name", sa.String(120), nullable=False),
        sa.Column("strategy", sa.String(32), nullable=False),
        sa.Column("adapter", sa.String(64), nullable=False),
        sa.Column("enabled", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("dry_run", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("eligibility_groups", postgresql.JSONB(), nullable=False, server_default="[]"),
        sa.Column("settings", postgresql.JSONB(), nullable=False, server_default="{}"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_by", sa.String(320), nullable=False, server_default="system"),
    )
    op.create_table(
        "provisioning_source_identities",
        sa.Column("id", sa.BigInteger(), primary_key=True, autoincrement=True),
        sa.Column("issuer", sa.String(512), nullable=False),
        sa.Column("subject", sa.String(128), nullable=False),
        sa.Column("username", sa.String(320), nullable=False),
        sa.Column("email", sa.String(320), nullable=True),
        sa.Column("email_verified", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("first_name", sa.String(200), nullable=False, server_default=""),
        sa.Column("last_name", sa.String(200), nullable=False, server_default=""),
        sa.Column("enabled", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("groups", postgresql.JSONB(), nullable=False, server_default="[]"),
        sa.Column("attributes", postgresql.JSONB(), nullable=False, server_default="{}"),
        sa.Column("source_state_hash", sa.String(64), nullable=False),
        sa.Column("last_seen_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.UniqueConstraint("issuer", "subject", name="uq_source_identity_issuer_subject"),
    )
    op.create_table(
        "provisioning_runs",
        sa.Column("id", sa.String(36), primary_key=True),
        sa.Column("trigger", sa.String(32), nullable=False),
        sa.Column("status", sa.String(32), nullable=False),
        sa.Column("actor", sa.String(320), nullable=False),
        sa.Column("source_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("planned_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("conflict_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("error_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("summary", postgresql.JSONB(), nullable=False, server_default="{}"),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_table(
        "provisioning_identity_links",
        sa.Column("id", sa.BigInteger(), primary_key=True, autoincrement=True),
        sa.Column("source_identity_id", sa.BigInteger(), sa.ForeignKey("provisioning_source_identities.id", ondelete="CASCADE"), nullable=False),
        sa.Column("target_id", sa.String(64), sa.ForeignKey("provisioning_targets.id", ondelete="CASCADE"), nullable=False),
        sa.Column("target_account_id", sa.String(255), nullable=False),
        sa.Column("target_username", sa.String(320), nullable=True),
        sa.Column("state", sa.String(32), nullable=False),
        sa.Column("metadata", postgresql.JSONB(), nullable=False, server_default="{}"),
        sa.Column("linked_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("verified_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.UniqueConstraint("source_identity_id", "target_id", name="uq_identity_link_source_target"),
        sa.UniqueConstraint("target_id", "target_account_id", name="uq_identity_link_target_account"),
    )
    op.create_index("ix_identity_links_source", "provisioning_identity_links", ["source_identity_id"])
    op.create_index("ix_identity_links_target", "provisioning_identity_links", ["target_id"])
    op.create_table(
        "provisioning_actions",
        sa.Column("id", sa.String(36), primary_key=True),
        sa.Column("run_id", sa.String(36), sa.ForeignKey("provisioning_runs.id", ondelete="CASCADE"), nullable=False),
        sa.Column("source_identity_id", sa.BigInteger(), sa.ForeignKey("provisioning_source_identities.id", ondelete="CASCADE"), nullable=False),
        sa.Column("target_id", sa.String(64), sa.ForeignKey("provisioning_targets.id", ondelete="CASCADE"), nullable=False),
        sa.Column("action", sa.String(32), nullable=False),
        sa.Column("status", sa.String(32), nullable=False),
        sa.Column("dedupe_key", sa.String(64), nullable=False),
        sa.Column("source_state_hash", sa.String(64), nullable=False),
        sa.Column("details", postgresql.JSONB(), nullable=False, server_default="{}"),
        sa.Column("reason", sa.Text(), nullable=True),
        sa.Column("approved_by", sa.String(320), nullable=True),
        sa.Column("approved_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("executed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.UniqueConstraint("dedupe_key", name="uq_provisioning_action_dedupe"),
    )
    op.create_index("ix_provisioning_actions_run", "provisioning_actions", ["run_id"])
    op.create_index("ix_provisioning_actions_source", "provisioning_actions", ["source_identity_id"])
    op.create_index("ix_provisioning_actions_target", "provisioning_actions", ["target_id"])
    op.create_table(
        "provisioning_audit_events",
        sa.Column("id", sa.BigInteger(), primary_key=True, autoincrement=True),
        sa.Column("event_type", sa.String(64), nullable=False),
        sa.Column("actor", sa.String(320), nullable=False),
        sa.Column("target_id", sa.String(64), nullable=True),
        sa.Column("source_identity_id", sa.BigInteger(), nullable=True),
        sa.Column("action_id", sa.String(36), nullable=True),
        sa.Column("correlation_id", sa.String(36), nullable=False),
        sa.Column("payload", postgresql.JSONB(), nullable=False, server_default="{}"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
    )
    op.create_index("ix_provisioning_audit_event_type", "provisioning_audit_events", ["event_type"])
    op.create_index("ix_provisioning_audit_correlation", "provisioning_audit_events", ["correlation_id"])


def downgrade() -> None:
    op.drop_index("ix_provisioning_audit_correlation", table_name="provisioning_audit_events")
    op.drop_index("ix_provisioning_audit_event_type", table_name="provisioning_audit_events")
    op.drop_table("provisioning_audit_events")
    op.drop_index("ix_provisioning_actions_target", table_name="provisioning_actions")
    op.drop_index("ix_provisioning_actions_source", table_name="provisioning_actions")
    op.drop_index("ix_provisioning_actions_run", table_name="provisioning_actions")
    op.drop_table("provisioning_actions")
    op.drop_index("ix_identity_links_target", table_name="provisioning_identity_links")
    op.drop_index("ix_identity_links_source", table_name="provisioning_identity_links")
    op.drop_table("provisioning_identity_links")
    op.drop_table("provisioning_runs")
    op.drop_table("provisioning_source_identities")
    op.drop_table("provisioning_targets")
