import os
import tempfile
import unittest
from datetime import date, datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import notifier


class NotifierTests(unittest.TestCase):
    def test_environment_expansion(self):
        os.environ["TEST_RECIPIENT"] = "hr@example.com"
        self.assertEqual(
            notifier.expand_environment({"recipients": ["${TEST_RECIPIENT}"]}),
            {"recipients": ["hr@example.com"]},
        )

    def test_rule_period(self):
        period = notifier.rule_period(
            {"id": "tomorrow", "start_offset_days": 1, "days": 2},
            date(2026, 9, 19),
        )
        self.assertEqual(period.start, date(2026, 9, 20))
        self.assertEqual(period.end, date(2026, 9, 21))

    def test_weekday_schedule(self):
        rule = {"enabled": True, "schedule": {"days": ["mon"], "time": "08:00"}}
        tz = ZoneInfo("Europe/Berlin")
        self.assertTrue(notifier.is_due(rule, datetime(2026, 9, 21, 8, 1, tzinfo=tz)))
        self.assertFalse(notifier.is_due(rule, datetime(2026, 9, 21, 7, 59, tzinfo=tz)))
        self.assertFalse(notifier.is_due(rule, datetime(2026, 9, 22, 9, 0, tzinfo=tz)))

    def test_filters_match_subunit_location_and_email(self):
        rows = [
            {"subunit": "Support", "locations": "Berlin, Hamburg", "emp_work_email": "one@example.com"},
            {"subunit": "Finance", "locations": "Berlin", "emp_work_email": "two@example.com"},
        ]
        result = notifier.filter_absences(
            rows,
            {"subunits": ["support"], "locations": ["hamburg"], "employee_emails": ["ONE@example.com"]},
        )
        self.assertEqual(result, rows[:1])

    def test_delivery_ledger_prevents_duplicate(self):
        with tempfile.TemporaryDirectory() as directory:
            ledger = notifier.DeliveryLedger(str(Path(directory) / "ledger.sqlite3"))
            period = notifier.Period(date(2026, 9, 19), date(2026, 9, 19))
            self.assertFalse(ledger.delivered("daily-summary", date(2026, 9, 19), period))
            ledger.record("daily-summary", date(2026, 9, 19), period, 2)
            self.assertTrue(ledger.delivered("daily-summary", date(2026, 9, 19), period))
            ledger.record("daily-summary", date(2026, 9, 19), period, 3)
            row_count = ledger.connection.execute("SELECT row_count FROM deliveries").fetchone()[0]
            self.assertEqual(row_count, 3)

    def test_jinja_templates_escape_html_and_render_text(self):
        with tempfile.TemporaryDirectory() as directory:
            Path(directory, "summary.html.j2").write_text("<p>{{ absences[0].employee_name }}</p>")
            Path(directory, "summary.txt.j2").write_text("{{ absences[0].employee_name }}")
            renderer = notifier.TemplateRenderer(directory)
            rule = {
                "id": "daily-summary",
                "subject": "Summary: {{ count }}",
                "templates": {"html": "summary.html.j2", "text": "summary.txt.j2"},
                "include_leave_type": False,
            }
            rows = [{
                "leave_date": date(2026, 9, 19),
                "status": 2,
                "length_days": 1,
                "start_time": None,
                "end_time": None,
                "employee_id": "EMP-1",
                "emp_firstname": "<Alex>",
                "emp_middle_name": "",
                "emp_lastname": "Example",
                "emp_work_email": "alex@example.com",
                "leave_type": "Sensitive leave",
                "subunit": "Support",
                "locations": "Berlin",
            }]
            subject, text_body, html_body = renderer.render(
                rule,
                notifier.Period(date(2026, 9, 19), date(2026, 9, 19)),
                rows,
                datetime(2026, 9, 19, 8, 0, tzinfo=ZoneInfo("Europe/Berlin")),
            )
            self.assertEqual(subject, "Summary: 1")
            self.assertIn("<Alex> Example", text_body)
            self.assertIn("&lt;Alex&gt; Example", html_body)
            self.assertNotIn("Sensitive leave", str(notifier.template_context(rule, notifier.Period(date(2026, 9, 19), date(2026, 9, 19)), rows, datetime.now())))


if __name__ == "__main__":
    unittest.main()
