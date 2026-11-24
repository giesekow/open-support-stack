"""Add provisioning stale-plan and execution-attempt controls.

Revision ID: 0003
Revises: 0002
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "0003"
down_revision = "0002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("provisioning_actions", sa.Column("target_state_hash", sa.String(64), nullable=False, server_default=""))
    op.add_column("provisioning_actions", sa.Column("attempt_count", sa.Integer(), nullable=False, server_default="0"))
    op.add_column("provisioning_actions", sa.Column("last_error", sa.Text(), nullable=True))
    op.create_table(
        "provisioning_execution_attempts",
        sa.Column("id", sa.BigInteger(), primary_key=True, autoincrement=True),
        sa.Column("action_id", sa.String(36), sa.ForeignKey("provisioning_actions.id", ondelete="CASCADE"), nullable=False),
        sa.Column("attempt_number", sa.Integer(), nullable=False),
        sa.Column("status", sa.String(32), nullable=False),
        sa.Column("actor", sa.String(320), nullable=False),
        sa.Column("correlation_id", sa.String(36), nullable=False),
        sa.Column("error", sa.Text(), nullable=True),
        sa.Column("result", postgresql.JSONB(), nullable=False, server_default="{}"),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.UniqueConstraint("action_id", "attempt_number", name="uq_provisioning_attempt_number"),
    )
    op.create_index("ix_provisioning_attempt_action", "provisioning_execution_attempts", ["action_id"])
    op.create_index("ix_provisioning_attempt_correlation", "provisioning_execution_attempts", ["correlation_id"])


def downgrade() -> None:
    op.drop_index("ix_provisioning_attempt_correlation", table_name="provisioning_execution_attempts")
    op.drop_index("ix_provisioning_attempt_action", table_name="provisioning_execution_attempts")
    op.drop_table("provisioning_execution_attempts")
    op.drop_column("provisioning_actions", "last_error")
    op.drop_column("provisioning_actions", "attempt_count")
    op.drop_column("provisioning_actions", "target_state_hash")
