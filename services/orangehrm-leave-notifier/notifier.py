#!/usr/bin/env python3

import argparse
import json
import logging
import os
import re
import smtplib
import sqlite3
import ssl
import sys
import time
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from email.message import EmailMessage
from email.utils import parseaddr
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo

import pymysql
from jinja2 import FileSystemLoader, StrictUndefined, select_autoescape
from jinja2.exceptions import TemplateError
from jinja2.sandbox import SandboxedEnvironment
from pymysql.cursors import DictCursor


LOG = logging.getLogger("orangehrm-leave-notifier")
ENV_PATTERN = re.compile(r"\$\{([A-Z_][A-Z0-9_]*)\}")
STATUS_NAMES = {2: "Approved", 3: "Taken"}
WEEKDAYS = ("mon", "tue", "wed", "thu", "fri", "sat", "sun")


@dataclass(frozen=True)
class Period:
    start: date
    end: date


def env(name: str, default: str | None = None, required: bool = False) -> str:
    value = os.getenv(name, default)
    if required and not value:
        raise ValueError(f"Missing required environment variable: {name}")
    return value or ""


def expand_environment(value: Any) -> Any:
    if isinstance(value, dict):
        return {key: expand_environment(item) for key, item in value.items()}
    if isinstance(value, list):
        return [expand_environment(item) for item in value]
    if isinstance(value, str):
        def replace(match: re.Match[str]) -> str:
            name = match.group(1)
            if name not in os.environ:
                raise ValueError(f"Configuration references unset environment variable: {name}")
            return os.environ[name]

        return ENV_PATTERN.sub(replace, value)
    return value


def load_config(path: str) -> dict[str, Any]:
    with open(path, encoding="utf-8") as handle:
        config = expand_environment(json.load(handle))

    rules = config.get("rules")
    if not isinstance(rules, list) or not rules:
        raise ValueError("Configuration must contain at least one rule")

    seen: set[str] = set()
    for rule in rules:
        rule_id = rule.get("id", "")
        if not re.fullmatch(r"[a-z0-9][a-z0-9-]{1,63}", rule_id):
            raise ValueError(f"Invalid rule id: {rule_id!r}")
        if rule_id in seen:
            raise ValueError(f"Duplicate rule id: {rule_id}")
        seen.add(rule_id)
        recipients = rule.get("recipients", [])
        if rule.get("enabled", True) and not recipients:
            raise ValueError(f"Rule {rule_id} has no recipients")
        for recipient in recipients:
            if "@" not in parseaddr(recipient)[1]:
                raise ValueError(f"Rule {rule_id} has invalid recipient: {recipient!r}")
        schedule = rule.get("schedule", {})
        datetime.strptime(schedule.get("time", ""), "%H:%M")
        invalid_days = set(schedule.get("days", [])) - set(WEEKDAYS)
        if invalid_days:
            raise ValueError(f"Rule {rule_id} has invalid schedule days: {sorted(invalid_days)}")
        statuses = rule.get("statuses", [2, 3])
        if not statuses or set(statuses) - STATUS_NAMES.keys():
            raise ValueError(f"Rule {rule_id} statuses must contain only 2 (approved) and/or 3 (taken)")
        templates = rule.get("templates", {})
        if not templates.get("html") or not templates.get("text"):
            raise ValueError(f"Rule {rule_id} must define HTML and text templates")
    return config


class DeliveryLedger:
    def __init__(self, path: str) -> None:
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        self.connection = sqlite3.connect(path)
        self.connection.execute(
            """
            CREATE TABLE IF NOT EXISTS deliveries (
                rule_id TEXT NOT NULL,
                run_date TEXT NOT NULL,
                period_start TEXT NOT NULL,
                period_end TEXT NOT NULL,
                sent_at TEXT NOT NULL,
                row_count INTEGER NOT NULL,
                PRIMARY KEY (rule_id, run_date, period_start, period_end)
            )
            """
        )
        self.connection.commit()

    def delivered(self, rule_id: str, run_date: date, period: Period) -> bool:
        row = self.connection.execute(
            "SELECT 1 FROM deliveries WHERE rule_id = ? AND run_date = ? AND period_start = ? AND period_end = ?",
            (rule_id, run_date.isoformat(), period.start.isoformat(), period.end.isoformat()),
        ).fetchone()
        return row is not None

    def record(self, rule_id: str, run_date: date, period: Period, row_count: int) -> None:
        self.connection.execute(
            """
            INSERT INTO deliveries VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT (rule_id, run_date, period_start, period_end)
            DO UPDATE SET sent_at = excluded.sent_at, row_count = excluded.row_count
            """,
            (
                rule_id,
                run_date.isoformat(),
                period.start.isoformat(),
                period.end.isoformat(),
                datetime.now().astimezone().isoformat(timespec="seconds"),
                row_count,
            ),
        )
        self.connection.commit()


def database_connection() -> pymysql.Connection:
    connection = pymysql.connect(
        host=env("ORANGEHRM_DB_HOST", "orangehrm-db"),
        port=int(env("ORANGEHRM_DB_PORT", "3306")),
        user=env("ORANGEHRM_DB_USER", required=True),
        password=env("ORANGEHRM_DB_PASSWORD", required=True),
        database=env("ORANGEHRM_DB_NAME", required=True),
        charset="utf8mb4",
        cursorclass=DictCursor,
        connect_timeout=10,
        read_timeout=30,
        write_timeout=30,
        autocommit=True,
    )
    with connection.cursor() as cursor:
        cursor.execute("SET SESSION TRANSACTION READ ONLY")
    return connection


def fetch_absences(period: Period, statuses: list[int]) -> list[dict[str, Any]]:
    placeholders = ", ".join(["%s"] * len(statuses))
    query = f"""
        SELECT
            l.date AS leave_date,
            l.status,
            l.length_days,
            l.start_time,
            l.end_time,
            e.employee_id,
            e.emp_firstname,
            e.emp_middle_name,
            e.emp_lastname,
            e.emp_work_email,
            lt.name AS leave_type,
            su.name AS subunit,
            GROUP_CONCAT(DISTINCT loc.name ORDER BY loc.name SEPARATOR ', ') AS locations
        FROM ohrm_leave l
        JOIN hs_hr_employee e ON e.emp_number = l.emp_number
        JOIN ohrm_leave_type lt ON lt.id = l.leave_type_id
        LEFT JOIN ohrm_subunit su ON su.id = e.work_station
        LEFT JOIN hs_hr_emp_locations el ON el.emp_number = e.emp_number
        LEFT JOIN ohrm_location loc ON loc.id = el.location_id
        WHERE l.date BETWEEN %s AND %s
          AND l.status IN ({placeholders})
          AND e.termination_id IS NULL
          AND e.purged_at IS NULL
          AND lt.deleted = 0
        GROUP BY
            l.id, l.date, l.status, l.length_days, l.start_time, l.end_time,
            e.employee_id, e.emp_firstname, e.emp_middle_name, e.emp_lastname,
            e.emp_work_email, lt.name, su.name
        ORDER BY l.date, e.emp_lastname, e.emp_firstname
    """
    params: list[Any] = [period.start, period.end, *statuses]
    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(query, params)
            return list(cursor.fetchall())


def normalized_set(values: list[str]) -> set[str]:
    return {value.strip().casefold() for value in values if value.strip()}


def filter_absences(rows: list[dict[str, Any]], filters: dict[str, Any]) -> list[dict[str, Any]]:
    subunits = normalized_set(filters.get("subunits", []))
    locations = normalized_set(filters.get("locations", []))
    employee_emails = normalized_set(filters.get("employee_emails", []))

    filtered = []
    for row in rows:
        if subunits and (row.get("subunit") or "").casefold() not in subunits:
            continue
        row_locations = normalized_set((row.get("locations") or "").split(","))
        if locations and not locations.intersection(row_locations):
            continue
        if employee_emails and (row.get("emp_work_email") or "").casefold() not in employee_emails:
            continue
        filtered.append(row)
    return filtered


def employee_name(row: dict[str, Any]) -> str:
    return " ".join(
        part.strip()
        for part in (row.get("emp_firstname"), row.get("emp_middle_name"), row.get("emp_lastname"))
        if part and part.strip()
    )


def duration(row: dict[str, Any]) -> str:
    if row.get("start_time") is not None and row.get("end_time") is not None:
        return f"{row['start_time']} - {row['end_time']}"
    days = float(row.get("length_days") or 0)
    return f"{days:g} day" + ("" if days == 1 else "s")


class TemplateRenderer:
    def __init__(self, template_directory: str) -> None:
        loader = FileSystemLoader(template_directory, followlinks=False)
        common = {
            "loader": loader,
            "undefined": StrictUndefined,
            "trim_blocks": True,
            "lstrip_blocks": True,
        }
        self.html_environment = SandboxedEnvironment(
            **common,
            autoescape=select_autoescape(enabled_extensions=("html", "html.j2"), default_for_string=True),
        )
        self.text_environment = SandboxedEnvironment(**common, autoescape=False)

    def render(
        self,
        rule: dict[str, Any],
        period: Period,
        rows: list[dict[str, Any]],
        generated_at: datetime,
    ) -> tuple[str, str, str]:
        context = template_context(rule, period, rows, generated_at)
        subject_template = self.text_environment.from_string(
            rule.get("subject", "Employee absence summary: {{ period_label }}")
        )
        subject = " ".join(subject_template.render(context).splitlines()).strip()
        if not subject:
            raise ValueError(f"Rule {rule['id']} rendered an empty subject")

        templates = rule["templates"]
        text_body = self.text_environment.get_template(templates["text"]).render(context).strip() + "\n"
        html_body = self.html_environment.get_template(templates["html"]).render(context).strip()
        return subject, text_body, html_body


def template_context(
    rule: dict[str, Any],
    period: Period,
    rows: list[dict[str, Any]],
    generated_at: datetime,
) -> dict[str, Any]:
    period_label = period.start.strftime("%d %b %Y")
    if period.end != period.start:
        period_label += f" - {period.end.strftime('%d %b %Y')}"
    absences = []
    for row in rows:
        locations = [item.strip() for item in (row.get("locations") or "").split(",") if item.strip()]
        absences.append(
            {
                "date": row["leave_date"].isoformat(),
                "date_label": row["leave_date"].strftime("%d %b %Y"),
                "employee_id": row.get("employee_id") or "",
                "employee_name": employee_name(row),
                "employee_email": row.get("emp_work_email") or "",
                "type_label": str(row["leave_type"]) if rule.get("include_leave_type", False) else "Leave",
                "duration": duration(row),
                "subunit": row.get("subunit") or "-",
                "locations": locations,
                "locations_label": ", ".join(locations) if locations else "-",
                "status": STATUS_NAMES.get(int(row["status"]), str(row["status"])),
            }
        )
    return {
        "rule": {"id": rule["id"]},
        "period": {"start": period.start.isoformat(), "end": period.end.isoformat()},
        "period_label": period_label,
        "count": len(absences),
        "generated_at": generated_at.isoformat(timespec="seconds"),
        "absences": absences,
    }


def send_email(recipients: list[str], subject: str, text_body: str, html_body: str) -> None:
    message = EmailMessage()
    message["From"] = env("ORANGEHRM_LEAVE_NOTIFIER_SMTP_FROM", required=True)
    message["To"] = ", ".join(recipients)
    message["Subject"] = subject
    message.set_content(text_body)
    message.add_alternative(html_body, subtype="html")

    host = env("ORANGEHRM_LEAVE_NOTIFIER_SMTP_HOST", required=True)
    port = int(env("ORANGEHRM_LEAVE_NOTIFIER_SMTP_PORT", "587"))
    security = env("ORANGEHRM_LEAVE_NOTIFIER_SMTP_SECURITY", "starttls").lower()
    username = env("ORANGEHRM_LEAVE_NOTIFIER_SMTP_USERNAME")
    password = env("ORANGEHRM_LEAVE_NOTIFIER_SMTP_PASSWORD")
    context = ssl.create_default_context()

    if security in {"tls", "force_tls"}:
        client: smtplib.SMTP = smtplib.SMTP_SSL(host, port, timeout=30, context=context)
    elif security in {"starttls", "off", "none"}:
        client = smtplib.SMTP(host, port, timeout=30)
    else:
        raise ValueError("SMTP security must be one of: off, none, starttls, tls, force_tls")

    with client:
        if security == "starttls":
            client.starttls(context=context)
        if username:
            client.login(username, password)
        client.send_message(message)


def rule_period(rule: dict[str, Any], run_date: date) -> Period:
    start = run_date + timedelta(days=int(rule.get("start_offset_days", 0)))
    days = int(rule.get("days", 1))
    if days < 1 or days > 366:
        raise ValueError(f"Rule {rule['id']} days must be between 1 and 366")
    return Period(start, start + timedelta(days=days - 1))


def is_due(rule: dict[str, Any], now: datetime) -> bool:
    if not rule.get("enabled", True):
        return False
    schedule = rule["schedule"]
    if WEEKDAYS[now.weekday()] not in schedule.get("days", WEEKDAYS):
        return False
    scheduled_time = datetime.strptime(schedule["time"], "%H:%M").time()
    return now.time() >= scheduled_time


def run_rule(
    rule: dict[str, Any],
    run_date: date,
    ledger: DeliveryLedger,
    renderer: TemplateRenderer,
    force: bool,
    dry_run: bool,
    validate_only: bool,
    send_empty_override: bool,
) -> bool:
    period = rule_period(rule, run_date)
    if ledger.delivered(rule["id"], run_date, period) and not force:
        LOG.info("Skipping rule %s: already delivered for %s", rule["id"], run_date)
        return False

    rows = filter_absences(fetch_absences(period, rule.get("statuses", [2, 3])), rule.get("filters", {}))
    send_empty = send_empty_override or rule.get("send_when_empty", False)
    if not rows and not send_empty:
        LOG.info("Rule %s found no matching absences; no email sent", rule["id"])
        return False

    subject, text_body, html_body = renderer.render(rule, period, rows, datetime.now().astimezone())
    if validate_only:
        LOG.info("Validated rule %s with %d matching absence row(s); no email sent", rule["id"], len(rows))
        return True
    if dry_run:
        print(f"Subject: {subject}\nTo: {', '.join(rule['recipients'])}\n\n{text_body}")
        return True

    send_email(rule["recipients"], subject, text_body, html_body)
    ledger.record(rule["id"], run_date, period, len(rows))
    LOG.info("Sent rule %s to %d recipient(s) with %d absence row(s)", rule["id"], len(rule["recipients"]), len(rows))
    return True


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Send scheduled OrangeHRM leave summaries")
    parser.add_argument("--once", action="store_true", help="Check due rules once and exit")
    parser.add_argument("--run-now", action="store_true", help="Run selected enabled rules regardless of schedule")
    parser.add_argument("--rule", action="append", default=[], help="Limit execution to a rule id; may be repeated")
    parser.add_argument("--date", help="Use a specific run date in YYYY-MM-DD format")
    parser.add_argument("--force", action="store_true", help="Send even if the rule was already delivered")
    parser.add_argument("--dry-run", action="store_true", help="Print the generated plain-text email without sending")
    parser.add_argument(
        "--validate-only",
        action="store_true",
        help="Validate the database query and templates without printing employee data or sending email",
    )
    parser.add_argument("--send-empty", action="store_true", help="Send even if no matching leave exists")
    return parser.parse_args()


def execute(
    config: dict[str, Any],
    ledger: DeliveryLedger,
    renderer: TemplateRenderer,
    args: argparse.Namespace,
    now: datetime,
) -> int:
    run_date = date.fromisoformat(args.date) if args.date else now.date()
    selected = set(args.rule)
    matched = 0
    for rule in config["rules"]:
        if selected and rule["id"] not in selected:
            continue
        matched += 1
        if not rule.get("enabled", True):
            LOG.info("Skipping disabled rule %s", rule["id"])
            continue
        if not args.run_now and not is_due(rule, now):
            continue
        run_rule(
            rule,
            run_date,
            ledger,
            renderer,
            args.force,
            args.dry_run,
            args.validate_only,
            args.send_empty,
        )
    if selected and matched != len(selected):
        missing = selected - {rule["id"] for rule in config["rules"]}
        raise ValueError(f"Unknown rule id(s): {', '.join(sorted(missing))}")
    return 0


def main() -> int:
    logging.basicConfig(
        level=os.getenv("LOG_LEVEL", "INFO").upper(),
        format="%(asctime)s %(levelname)s %(message)s",
    )
    args = parse_arguments()
    config_path = env("ORANGEHRM_LEAVE_NOTIFIER_CONFIG", "/config/leave-notifications.json")
    template_directory = env("ORANGEHRM_LEAVE_NOTIFIER_TEMPLATE_DIR", "/config/templates")
    ledger = DeliveryLedger(env("ORANGEHRM_LEAVE_NOTIFIER_LEDGER", "/data/deliveries.sqlite3"))

    def load_runtime() -> tuple[dict[str, Any], ZoneInfo, TemplateRenderer]:
        config = load_config(config_path)
        timezone = ZoneInfo(env("TZ", config.get("timezone", "UTC")))
        return config, timezone, TemplateRenderer(template_directory)

    if args.once or args.run_now:
        config, timezone, renderer = load_runtime()
        return execute(config, ledger, renderer, args, datetime.now(timezone))

    interval = max(15, int(env("ORANGEHRM_LEAVE_NOTIFIER_INTERVAL_SECONDS", "60")))
    LOG.info("Scheduler started; configuration reload interval is %d seconds", interval)
    while True:
        try:
            config, timezone, renderer = load_runtime()
            execute(config, ledger, renderer, args, datetime.now(timezone))
        except Exception:
            LOG.exception("Scheduled notification cycle failed")
        time.sleep(interval)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, OSError, TemplateError, pymysql.MySQLError, sqlite3.Error, json.JSONDecodeError) as exc:
        LOG.error("%s", exc)
        raise SystemExit(1)
