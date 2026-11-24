"""Migrate leave rules and provisioning targets from OrangeHRM to Frappe HR.

Revision ID: 0005
Revises: 0004
"""

from alembic import op


revision = "0005"
down_revision = "0004"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        WITH migrated AS (
            UPDATE automation_rules AS rule
            SET statuses = '["Approved"]'::jsonb,
                version = GREATEST(
                    rule.version,
                    COALESCE(
                        (
                            SELECT MAX(revision.version)
                            FROM automation_rule_revisions AS revision
                            WHERE revision.rule_id = rule.id
                        ),
                        0
                    )
                ) + 1,
                updated_at = NOW(),
                updated_by = 'system:frappe-hr-cutover'
            WHERE rule.statuses IS DISTINCT FROM '["Approved"]'::jsonb
            RETURNING rule.*
        )
        INSERT INTO automation_rule_revisions (
            rule_id,
            version,
            snapshot,
            created_by
        )
        SELECT
            id,
            version,
            jsonb_build_object(
                'id', id,
                'enabled', enabled,
                'schedule_days', schedule_days,
                'schedule_time', TO_CHAR(schedule_time, 'HH24:MI'),
                'start_offset_days', start_offset_days,
                'period_days', period_days,
                'statuses', statuses,
                'recipients', recipients,
                'subject', subject,
                'text_template', text_template,
                'html_template', html_template,
                'send_when_empty', send_when_empty,
                'include_leave_type', include_leave_type,
                'filters', filters
            ),
            'system:frappe-hr-cutover'
        FROM migrated
        """
    )
    op.execute(
        "UPDATE provisioning_targets SET enabled = false, dry_run = true, "
        "display_name = 'OrangeHRM (retired)', updated_by = 'system:frappe-hr-cutover' "
        "WHERE id = 'orangehrm'"
    )
    op.execute(
        "UPDATE provisioning_targets SET display_name = 'Frappe HR / ERPNext', "
        "eligibility_groups = '[\"employees\"]'::jsonb, "
        "updated_by = 'system:frappe-hr-cutover' WHERE id = 'erpnext'"
    )


def downgrade() -> None:
    raise RuntimeError(
        "Frappe HR cutover data migration is irreversible; restore the coordinated "
        "pre-cutover Support Tools and HR backups instead"
    )
