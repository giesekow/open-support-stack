#!/usr/bin/env python3
"""Create the least-privilege database account used by the leave notifier."""

import json
import os
import re
from pathlib import Path

import pymysql


def required(name: str) -> str:
    value = os.getenv(name, "")
    if not value:
        raise ValueError(f"Missing required environment variable: {name}")
    return value


def main() -> int:
    site_config_path = os.getenv("ERPNEXT_SITE_CONFIG", "")
    if site_config_path and Path(site_config_path).is_file():
        with open(site_config_path, encoding="utf-8") as handle:
            database = str(json.load(handle).get("db_name", ""))
        if not database:
            raise ValueError(f"Missing db_name in site config: {site_config_path}")
    else:
        database = required("ERPNEXT_DB_NAME")
    username = required("FRAPPE_HR_NOTIFIER_DB_USER")
    password = required("FRAPPE_HR_NOTIFIER_DB_PASSWORD")
    if not re.fullmatch(r"[A-Za-z0-9_]+", database):
        raise ValueError("ERPNEXT_DB_NAME contains unsupported characters")
    if not re.fullmatch(r"[A-Za-z0-9_]+", username):
        raise ValueError("FRAPPE_HR_NOTIFIER_DB_USER contains unsupported characters")

    connection = pymysql.connect(
        host=os.getenv("FRAPPE_HR_DB_HOST", "erpnext-db"),
        port=int(os.getenv("FRAPPE_HR_DB_PORT", "3306")),
        user="root",
        password=required("ERPNEXT_DB_ROOT_PASSWORD"),
        autocommit=True,
    )
    try:
        with connection.cursor() as cursor:
            account = f"'{username}'@'%'"
            parameterized_account = account.replace("%", "%%")
            # Recreate the account so an earlier accidental grant cannot survive.
            cursor.execute(f"DROP USER IF EXISTS {account}")
            cursor.execute(
                f"CREATE USER {parameterized_account} IDENTIFIED BY %s", (password,)
            )
            cursor.execute(f"GRANT SELECT ON `{database}`.* TO {account}")
    finally:
        connection.close()

    print(f"Configured read-only database account {username} for {database}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
