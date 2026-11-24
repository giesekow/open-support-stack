import unittest

from fastapi import HTTPException

from app.access import authorize_actor, parse_groups


class AccessTests(unittest.TestCase):
    def test_parse_groups_normalizes_paths_and_whitespace(self):
        self.assertEqual(
            parse_groups("/support-engineer, support-admin, /auditor"),
            {"support-engineer", "support-admin", "auditor"},
        )

    def test_support_admin_is_allowed(self):
        self.assertEqual(
            authorize_actor(
                "admin@example.com",
                "Admin User",
                "support-engineer,support-admin",
                "support-admin",
            ),
            {"email": "admin@example.com", "name": "Admin User"},
        )

    def test_non_admin_is_forbidden(self):
        with self.assertRaises(HTTPException) as context:
            authorize_actor(
                "engineer@example.com",
                "Support Engineer",
                "support-engineer",
                "support-admin",
            )
        self.assertEqual(context.exception.status_code, 403)

    def test_missing_identity_is_unauthorized(self):
        with self.assertRaises(HTTPException) as context:
            authorize_actor("", "", "support-admin", "support-admin")
        self.assertEqual(context.exception.status_code, 401)


if __name__ == "__main__":
    unittest.main()
