"""Create automation rule and revision tables.

Revision ID: 0001
Revises:
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision = "0001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "automation_rules",
        sa.Column("id", sa.String(length=64), primary_key=True),
        sa.Column("enabled", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("schedule_days", postgresql.JSONB(), nullable=False),
        sa.Column("schedule_time", sa.Time(), nullable=False),
        sa.Column("start_offset_days", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("period_days", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("statuses", postgresql.JSONB(), nullable=False),
        sa.Column("recipients", postgresql.JSONB(), nullable=False),
        sa.Column("subject", sa.Text(), nullable=False),
        sa.Column("text_template", sa.Text(), nullable=False),
        sa.Column("html_template", sa.Text(), nullable=False),
        sa.Column("send_when_empty", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("include_leave_type", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("filters", postgresql.JSONB(), nullable=False),
        sa.Column("version", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_by", sa.String(length=320), nullable=False),
    )
    op.create_table(
        "automation_rule_revisions",
        sa.Column("id", sa.BigInteger(), primary_key=True, autoincrement=True),
        sa.Column(
            "rule_id",
            sa.String(length=64),
            sa.ForeignKey("automation_rules.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("version", sa.Integer(), nullable=False),
        sa.Column("snapshot", postgresql.JSONB(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("created_by", sa.String(length=320), nullable=False),
        sa.UniqueConstraint("rule_id", "version", name="uq_rule_revision_version"),
    )
    op.create_index("ix_rule_revisions_rule_id", "automation_rule_revisions", ["rule_id"])


def downgrade() -> None:
    op.drop_index("ix_rule_revisions_rule_id", table_name="automation_rule_revisions")
    op.drop_table("automation_rule_revisions")
    op.drop_table("automation_rules")

