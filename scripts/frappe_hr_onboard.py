#!/usr/bin/env python3
"""Idempotently link a Keycloak-created Frappe user to an Employee record."""

import argparse
import json
import os
import sys


BENCH_PATH = "/home/frappe/frappe-bench"
SITES_PATH = f"{BENCH_PATH}/sites"
sys.path.insert(0, BENCH_PATH)
os.chdir(SITES_PATH)

import frappe  # noqa: E402


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--site", required=True)
    parser.add_argument("--email", required=True)
    parser.add_argument("--employee-number", required=True)
    parser.add_argument("--gender", required=True)
    parser.add_argument("--date-of-birth", required=True)
    parser.add_argument("--date-of-joining", required=True)
    parser.add_argument("--company", required=True)
    parser.add_argument("--department", default="")
    parser.add_argument("--designation", default="")
    parser.add_argument("--branch", default="")
    return parser.parse_args()


def require_link(doctype: str, value: str) -> None:
    if value and not frappe.db.exists(doctype, value):
        raise ValueError(f"{doctype} does not exist: {value}")


def comparable(value: object) -> str:
    return "" if value is None else str(value).strip()


def run(args: argparse.Namespace) -> dict[str, str]:
    user_name = frappe.db.get_value("User", {"email": args.email}, "name")
    if not user_name:
        raise ValueError(
            "The Frappe user does not exist. The employee must complete one Keycloak login first."
        )
    if user_name in {"Administrator", "Guest"}:
        raise ValueError("Protected built-in users cannot be onboarded as employees")

    roles = set(frappe.get_roles(user_name))
    if {"Administrator", "System Manager"}.intersection(roles):
        raise ValueError("Privileged Frappe users cannot be modified by this onboarding command")

    for doctype, value in (
        ("Company", args.company),
        ("Gender", args.gender),
        ("Department", args.department),
        ("Designation", args.designation),
        ("Branch", args.branch),
    ):
        require_link(doctype, value)

    matches = {
        value
        for value in (
            frappe.db.get_value("Employee", {"user_id": user_name}, "name"),
            frappe.db.get_value("Employee", {"employee_number": args.employee_number}, "name"),
            frappe.db.get_value("Employee", {"company_email": args.email}, "name"),
        )
        if value
    }
    if len(matches) > 1:
        raise ValueError("Employee identifiers resolve to different records; manual review is required")

    user = frappe.get_doc("User", user_name)
    user.user_type = "System User"
    if not any(row.role == "Employee" for row in user.roles):
        user.append("roles", {"role": "Employee"})
    user.save(ignore_permissions=True)

    if matches:
        employee = frappe.get_doc("Employee", matches.pop())
        immutable_mismatches = {
            "employee_number": (employee.employee_number, args.employee_number),
            "company": (employee.company, args.company),
            "gender": (employee.gender, args.gender),
            "date_of_birth": (employee.date_of_birth, args.date_of_birth),
            "date_of_joining": (employee.date_of_joining, args.date_of_joining),
        }
        conflicts = [
            field
            for field, (current, requested) in immutable_mismatches.items()
            if comparable(current) and comparable(current) != comparable(requested)
        ]
        if conflicts:
            raise ValueError(
                "Existing Employee has conflicting immutable fields: " + ", ".join(conflicts)
            )
    else:
        employee = frappe.new_doc("Employee")
        employee.first_name = user.first_name or args.email.split("@", 1)[0]
        employee.middle_name = user.middle_name
        employee.last_name = user.last_name
        employee.company = args.company
        employee.employee_number = args.employee_number
        employee.gender = args.gender
        employee.date_of_birth = args.date_of_birth
        employee.date_of_joining = args.date_of_joining
        employee.status = "Active"

    employee.user_id = user_name
    employee.company_email = args.email
    employee.prefered_contact_email = "Company Email"
    employee.create_user_permission = 1
    for field in ("department", "designation", "branch"):
        value = getattr(args, field)
        if value:
            setattr(employee, field, value)

    if employee.is_new():
        employee.insert(ignore_permissions=True)
        operation = "created"
    else:
        employee.save(ignore_permissions=True)
        operation = "updated"
    frappe.db.commit()
    return {
        "operation": operation,
        "user": user_name,
        "employee": employee.name,
        "user_type": user.user_type,
        "role": "Employee",
    }


def main() -> int:
    args = arguments()
    frappe.init(site=args.site, sites_path=SITES_PATH)
    frappe.connect()
    try:
        print(json.dumps(run(args), sort_keys=True))
    except Exception:
        frappe.db.rollback()
        raise
    finally:
        frappe.destroy()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
