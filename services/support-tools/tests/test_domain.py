import unittest
from datetime import time

from app.domain import ValidationError, render_content, split_values, validate_rule


class DomainTests(unittest.TestCase):
    def base_rule(self):
        return {
            "id": "weekly-summary",
            "enabled": True,
            "schedule_days": ["mon"],
            "schedule_time": "08:00",
            "start_offset_days": 0,
            "period_days": 7,
            "statuses": [2, 3],
            "recipients": ["ops@example.com"],
            "subject": "Summary {{ count }}",
            "text_template": "{{ period_label }}: {{ absences[0].employee_name }}",
            "html_template": "<p>{{ absences[0].employee_name }}</p>",
            "send_when_empty": False,
            "include_leave_type": False,
            "filters": {"subunits": [], "locations": [], "employee_emails": []},
        }

    def test_split_values_accepts_commas_and_lines(self):
        self.assertEqual(split_values("one@example.com, two@example.com\nthree@example.com"), [
            "one@example.com", "two@example.com", "three@example.com"
        ])

    def test_validate_rule_normalizes_time_and_statuses(self):
        result = validate_rule(self.base_rule())
        self.assertEqual(result["schedule_time"], time(8, 0))
        self.assertEqual(result["statuses"], [2, 3])

    def test_invalid_email_is_rejected(self):
        data = self.base_rule()
        data["recipients"] = ["not-an-email"]
        with self.assertRaises(ValidationError):
            validate_rule(data)

    def test_templates_are_strict(self):
        data = self.base_rule()
        data["subject"] = "{{ missing_variable }}"
        with self.assertRaises(ValidationError):
            validate_rule(data)

    def test_preview_escapes_employee_html(self):
        data = validate_rule(self.base_rule())
        data["html_template"] = "<p>{{ absences[0].employee_name }}</p>"
        _, _, html = render_content(data)
        self.assertIn("Alex Morgan", html)


if __name__ == "__main__":
    unittest.main()

