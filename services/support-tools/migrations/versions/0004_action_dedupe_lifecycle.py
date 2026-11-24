"""Allow dedupe keys to recur across completed lifecycle cycles.

Revision ID: 0004
Revises: 0003
"""

from alembic import op
import sqlalchemy as sa


revision = "0004"
down_revision = "0003"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.drop_constraint(
        "uq_provisioning_action_dedupe",
        "provisioning_actions",
        type_="unique",
    )
    op.create_index(
        "ix_provisioning_actions_dedupe_key",
        "provisioning_actions",
        ["dedupe_key"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index(
        "ix_provisioning_actions_dedupe_key",
        table_name="provisioning_actions",
    )
    op.create_unique_constraint(
        "uq_provisioning_action_dedupe",
        "provisioning_actions",
        ["dedupe_key"],
    )
