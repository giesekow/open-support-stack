#!/usr/bin/env python3
"""Apply idempotent security and approval defaults to a Frappe HR site."""

import argparse
import json
import os
import sys


BENCH_PATH = "/home/frappe/frappe-bench"
SITES_PATH = f"{BENCH_PATH}/sites"
sys.path.insert(0, BENCH_PATH)
os.chdir(SITES_PATH)

import frappe  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--site", required=True)
    args = parser.parse_args()

    frappe.init(site=args.site, sites_path=SITES_PATH)
    frappe.connect()
    try:
        if not frappe.db.exists("DocType", "HR Settings"):
            raise RuntimeError("HRMS is not installed on this site")

        settings = frappe.get_single("HR Settings")
        desired = {
            "expense_approver_mandatory_in_expense_claim": 1,
            "leave_approver_mandatory_in_leave_application": 1,
            "prevent_self_leave_approval": 1,
            "prevent_self_expense_approval": 1,
            "send_leave_notification": 1,
        }
        changed = []
        for field, value in desired.items():
            if settings.get(field) != value:
                settings.set(field, value)
                changed.append(field)
        settings.save(ignore_permissions=True)
        frappe.db.commit()
        print(json.dumps({"changed": changed, "settings": desired}, sort_keys=True))
    except Exception:
        frappe.db.rollback()
        raise
    finally:
        frappe.destroy()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
