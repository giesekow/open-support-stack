import json
import os
import re
import smtplib
import ssl
from datetime import date, datetime, time, timedelta
from email.message import EmailMessage
from pathlib import Path
from tempfile import NamedTemporaryFile
from typing import Any, Iterable

from email_validator import EmailNotValidError, validate_email
from jinja2 import StrictUndefined, TemplateError, select_autoescape
from jinja2.sandbox import SandboxedEnvironment
from sqlalchemy import select
from sqlalchemy.orm import Session

from .models import AutomationRule, AutomationRuleRevision


WEEKDAYS = ("mon", "tue", "wed", "thu", "fri", "sat", "sun")
STATUS_NAMES = {2: "Approved", 3: "Taken"}
RULE_ID_PATTERN = re.compile(r"[a-z0-9][a-z0-9-]{1,63}")


class ValidationError(ValueError):
    pass


def split_values(raw: str) -> list[str]:
    return [item.strip() for item in re.split(r"[,\n]", raw or "") if item.strip()]


def sample_context(rule_id: str = "sample-rule") -> dict[str, Any]:
    start = date.today() + timedelta(days=1)
    end = start + timedelta(days=4)
    return {
        "rule": {"id": rule_id},
        "period": {"start": start.isoformat(), "end": end.isoformat()},
        "period_label": f"{start.strftime('%d %b %Y')} - {end.strftime('%d %b %Y')}",
        "count": 2,
        "generated_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "absences": [
            {
                "date": start.isoformat(),
                "date_label": start.strftime("%d %b %Y"),
                "employee_id": "EMP-1042",
                "employee_name": "Alex Morgan",
                "employee_email": "alex.morgan@example.com",
                "type_label": "Leave",
                "duration": "1 day",
                "subunit": "Customer Support",
                "locations": ["Berlin"],
                "locations_label": "Berlin",
                "status": "Approved",
            },
            {
                "date": (start + timedelta(days=2)).isoformat(),
                "date_label": (start + timedelta(days=2)).strftime("%d %b %Y"),
                "employee_id": "EMP-1088",
                "employee_name": "Sam Rivera",
                "employee_email": "sam.rivera@example.com",
                "type_label": "Leave",
                "duration": "0.5 days",
                "subunit": "Engineering",
                "locations": ["Hamburg", "Remote"],
                "locations_label": "Hamburg, Remote",
                "status": "Taken",
            },
        ],
    }


def template_environments() -> tuple[SandboxedEnvironment, SandboxedEnvironment]:
    common = {"undefined": StrictUndefined, "trim_blocks": True, "lstrip_blocks": True}
    text = SandboxedEnvironment(**common, autoescape=False)
    html = SandboxedEnvironment(
        **common,
        autoescape=select_autoescape(enabled_extensions=("html", "html.j2"), default_for_string=True),
    )
    return text, html


def render_content(rule: AutomationRule | dict[str, Any]) -> tuple[str, str, str]:
    rule_id = rule.id if isinstance(rule, AutomationRule) else rule["id"]
    subject_source = rule.subject if isinstance(rule, AutomationRule) else rule["subject"]
    text_source = rule.text_template if isinstance(rule, AutomationRule) else rule["text_template"]
    html_source = rule.html_template if isinstance(rule, AutomationRule) else rule["html_template"]
    context = sample_context(rule_id)
    text_env, html_env = template_environments()
    try:
        subject = " ".join(text_env.from_string(subject_source).render(context).splitlines()).strip()
        text_body = text_env.from_string(text_source).render(context).strip() + "\n"
        html_body = html_env.from_string(html_source).render(context).strip()
    except TemplateError as exc:
        raise ValidationError(f"Template validation failed: {exc}") from exc
    if not subject:
        raise ValidationError("The rendered subject cannot be empty")
    return subject, text_body, html_body


def validate_rule(data: dict[str, Any]) -> dict[str, Any]:
    rule_id = str(data.get("id", "")).strip().lower()
    if not RULE_ID_PATTERN.fullmatch(rule_id):
        raise ValidationError("Rule ID must be 2-64 lowercase letters, numbers, or hyphens")

    schedule_days = list(dict.fromkeys(data.get("schedule_days", [])))
    invalid_days = set(schedule_days) - set(WEEKDAYS)
    if not schedule_days or invalid_days:
        raise ValidationError("Choose at least one valid schedule day")
    try:
        schedule_time = time.fromisoformat(str(data.get("schedule_time", "")))
    except ValueError as exc:
        raise ValidationError("Schedule time must use HH:MM format") from exc

    recipients = list(dict.fromkeys(data.get("recipients", [])))
    if data.get("enabled", True) and not recipients:
        raise ValidationError("Enabled rules need at least one recipient")
    for recipient in recipients:
        try:
            validate_email(recipient, check_deliverability=False)
        except EmailNotValidError as exc:
            raise ValidationError(f"Invalid recipient: {recipient}") from exc

    period_days = int(data.get("period_days", 1))
    start_offset_days = int(data.get("start_offset_days", 0))
    if not 1 <= period_days <= 366:
        raise ValidationError("Period length must be between 1 and 366 days")
    if not -366 <= start_offset_days <= 366:
        raise ValidationError("Start offset must be between -366 and 366 days")

    statuses = sorted({int(item) for item in data.get("statuses", [])})
    if not statuses or set(statuses) - STATUS_NAMES.keys():
        raise ValidationError("Choose Approved, Taken, or both")

    filters = data.get("filters", {})
    normalized = {
        "id": rule_id,
        "enabled": bool(data.get("enabled", False)),
        "schedule_days": schedule_days,
        "schedule_time": schedule_time,
        "start_offset_days": start_offset_days,
        "period_days": period_days,
        "statuses": statuses,
        "recipients": recipients,
        "subject": str(data.get("subject", "")).strip(),
        "text_template": str(data.get("text_template", "")),
        "html_template": str(data.get("html_template", "")),
        "send_when_empty": bool(data.get("send_when_empty", False)),
        "include_leave_type": bool(data.get("include_leave_type", False)),
        "filters": {
            "subunits": list(dict.fromkeys(filters.get("subunits", []))),
            "locations": list(dict.fromkeys(filters.get("locations", []))),
            "employee_emails": list(dict.fromkeys(filters.get("employee_emails", []))),
        },
    }
    if not normalized["subject"]:
        raise ValidationError("Subject is required")
    if not normalized["text_template"].strip() or not normalized["html_template"].strip():
        raise ValidationError("Both text and HTML templates are required")
    render_content(normalized)
    return normalized


def rule_snapshot(rule: AutomationRule) -> dict[str, Any]:
    return {
        "id": rule.id,
        "enabled": rule.enabled,
        "schedule_days": rule.schedule_days,
        "schedule_time": rule.schedule_time.strftime("%H:%M"),
        "start_offset_days": rule.start_offset_days,
        "period_days": rule.period_days,
        "statuses": rule.statuses,
        "recipients": rule.recipients,
        "subject": rule.subject,
        "text_template": rule.text_template,
        "html_template": rule.html_template,
        "send_when_empty": rule.send_when_empty,
        "include_leave_type": rule.include_leave_type,
        "filters": rule.filters,
    }


def apply_data(rule: AutomationRule, data: dict[str, Any], actor: str) -> None:
    rule.enabled = data["enabled"]
    rule.schedule_days = data["schedule_days"]
    rule.schedule_time = data["schedule_time"]
    rule.start_offset_days = data["start_offset_days"]
    rule.period_days = data["period_days"]
    rule.statuses = data["statuses"]
    rule.recipients = data["recipients"]
    rule.subject = data["subject"]
    rule.text_template = data["text_template"]
    rule.html_template = data["html_template"]
    rule.send_when_empty = data["send_when_empty"]
    rule.include_leave_type = data["include_leave_type"]
    rule.filters = data["filters"]
    rule.updated_by = actor


def add_revision(session: Session, rule: AutomationRule, actor: str) -> None:
    session.add(
        AutomationRuleRevision(
            rule_id=rule.id,
            version=rule.version,
            snapshot=rule_snapshot(rule),
            created_by=actor,
        )
    )


def runtime_rule(rule: AutomationRule) -> dict[str, Any]:
    return {
        "id": rule.id,
        "enabled": rule.enabled,
        "schedule": {"days": rule.schedule_days, "time": rule.schedule_time.strftime("%H:%M")},
        "start_offset_days": rule.start_offset_days,
        "days": rule.period_days,
        "statuses": rule.statuses,
        "recipients": rule.recipients,
        "subject": rule.subject,
        "templates": {"html": f"{rule.id}.html.j2", "text": f"{rule.id}.txt.j2"},
        "send_when_empty": rule.send_when_empty,
        "include_leave_type": rule.include_leave_type,
        "filters": rule.filters,
    }


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, delete=False) as handle:
        handle.write(content)
        temporary = Path(handle.name)
    os.chmod(temporary, 0o644)
    os.replace(temporary, path)


def publish_runtime(session: Session) -> None:
    runtime = Path(os.getenv("SUPPORT_TOOLS_RUNTIME_DIR", "/runtime"))
    rules = list(session.scalars(select(AutomationRule).order_by(AutomationRule.id)))
    for rule in rules:
        atomic_write(runtime / "templates" / f"{rule.id}.txt.j2", rule.text_template)
        atomic_write(runtime / "templates" / f"{rule.id}.html.j2", rule.html_template)
    payload = {
        "timezone": os.getenv("TZ", "Europe/Berlin"),
        "rules": [runtime_rule(rule) for rule in rules],
    }
    atomic_write(runtime / "leave-notifications.json", json.dumps(payload, indent=2) + "\n")


def seed_from_files(session: Session) -> None:
    if session.scalar(select(AutomationRule.id).limit(1)) is not None:
        publish_runtime(session)
        return

    seed_dir = Path(os.getenv("SUPPORT_TOOLS_SEED_DIR", "/seed"))
    with (seed_dir / "leave-notifications.json").open(encoding="utf-8") as handle:
        config = json.load(handle)
    recipient_fallback = os.getenv("ORANGEHRM_LEAVE_NOTIFIER_RECIPIENT", "")
    for source in config.get("rules", []):
        recipients = [recipient_fallback if item == "${ORANGEHRM_LEAVE_NOTIFIER_RECIPIENT}" else item for item in source["recipients"]]
        data = validate_rule(
            {
                "id": source["id"],
                "enabled": source.get("enabled", True),
                "schedule_days": source["schedule"]["days"],
                "schedule_time": source["schedule"]["time"],
                "start_offset_days": source.get("start_offset_days", 0),
                "period_days": source.get("days", 1),
                "statuses": source.get("statuses", [2, 3]),
                "recipients": recipients,
                "subject": source["subject"],
                "text_template": (seed_dir / "templates" / source["templates"]["text"]).read_text(encoding="utf-8"),
                "html_template": (seed_dir / "templates" / source["templates"]["html"]).read_text(encoding="utf-8"),
                "send_when_empty": source.get("send_when_empty", False),
                "include_leave_type": source.get("include_leave_type", False),
                "filters": source.get("filters", {}),
            }
        )
        rule = AutomationRule(id=data["id"], version=1, updated_by="system:initial-import")
        apply_data(rule, data, "system:initial-import")
        session.add(rule)
        session.flush()
        add_revision(session, rule, "system:initial-import")
    session.commit()
    publish_runtime(session)


def send_test_email(rule: AutomationRule, recipient: str) -> None:
    try:
        recipient = validate_email(recipient, check_deliverability=False).normalized
    except EmailNotValidError as exc:
        raise ValidationError(f"Invalid test recipient: {recipient}") from exc

    subject, text_body, html_body = render_content(rule)
    message = EmailMessage()
    message["From"] = os.environ["SMTP_FROM"]
    message["To"] = recipient
    message["Subject"] = f"[TEST] {subject}"
    message.set_content(text_body)
    message.add_alternative(html_body, subtype="html")

    host = os.environ["SMTP_HOST"]
    port = int(os.getenv("SMTP_PORT", "587"))
    security = os.getenv("SMTP_SECURITY", "starttls").lower()
    username = os.getenv("SMTP_USER", "")
    password = os.getenv("SMTP_PASS", "")
    context = ssl.create_default_context()
    if security in {"tls", "force_tls"}:
        client: smtplib.SMTP = smtplib.SMTP_SSL(host, port, timeout=30, context=context)
    elif security in {"starttls", "off", "none"}:
        client = smtplib.SMTP(host, port, timeout=30)
    else:
        raise ValidationError("Unsupported SMTP security mode")
    with client:
        if security == "starttls":
            client.starttls(context=context)
        if username:
            client.login(username, password)
        client.send_message(message)

