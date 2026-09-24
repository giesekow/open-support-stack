import os
import smtplib
import secrets
from contextlib import asynccontextmanager
from typing import Any, Generator
from urllib.parse import quote

from fastapi import Depends, FastAPI, Form, HTTPException, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from sqlalchemy import select, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session
from starlette.middleware.sessions import SessionMiddleware

from .database import SessionLocal
from .domain import (
    WEEKDAYS,
    ValidationError,
    add_revision,
    apply_data,
    publish_runtime,
    render_content,
    seed_from_files,
    send_test_email,
    split_values,
    validate_rule,
)
from .models import AutomationRule, AutomationRuleRevision


BASE_PATH = "/automations"


def database_session() -> Generator[Session, None, None]:
    session = SessionLocal()
    try:
        yield session
    finally:
        session.close()


def actor(request: Request) -> dict[str, str]:
    email = request.headers.get("x-auth-request-email", "").strip()
    username = request.headers.get("x-auth-request-user", "").strip()
    if not email and os.getenv("SUPPORT_TOOLS_DEV_AUTH_BYPASS", "false").lower() == "true":
        email = os.getenv("SUPPORT_TOOLS_DEV_USER_EMAIL", "developer@example.com")
        username = os.getenv("SUPPORT_TOOLS_DEV_USER_NAME", "Local developer")
    if not email:
        raise HTTPException(status_code=401, detail="Authenticated email header is missing")
    return {"email": email, "name": username or email}


def csrf_token(request: Request) -> str:
    token = request.session.get("csrf_token")
    if not token:
        token = secrets.token_urlsafe(32)
        request.session["csrf_token"] = token
    return token


def verify_csrf(request: Request, submitted: str) -> None:
    expected = request.session.get("csrf_token", "")
    if not expected or not secrets.compare_digest(expected, submitted or ""):
        raise HTTPException(status_code=403, detail="Invalid CSRF token")


def redirect(path: str, message: str = "") -> RedirectResponse:
    target = f"{BASE_PATH}{path}"
    if message:
        target += f"?message={quote(message)}"
    return RedirectResponse(target, status_code=303)


def form_data(form: Any, rule_id: str | None = None) -> dict[str, Any]:
    return {
        "id": rule_id or str(form.get("id", "")),
        "enabled": form.get("enabled") == "on",
        "schedule_days": form.getlist("schedule_days"),
        "schedule_time": str(form.get("schedule_time", "")),
        "start_offset_days": str(form.get("start_offset_days", "0")),
        "period_days": str(form.get("period_days", "1")),
        "statuses": form.getlist("statuses"),
        "recipients": split_values(str(form.get("recipients", ""))),
        "subject": str(form.get("subject", "")),
        "text_template": str(form.get("text_template", "")),
        "html_template": str(form.get("html_template", "")),
        "send_when_empty": form.get("send_when_empty") == "on",
        "include_leave_type": form.get("include_leave_type") == "on",
        "filters": {
            "subunits": split_values(str(form.get("filter_subunits", ""))),
            "locations": split_values(str(form.get("filter_locations", ""))),
            "employee_emails": split_values(str(form.get("filter_employee_emails", ""))),
        },
    }


def page_context(request: Request, current_actor: dict[str, str], **extra: Any) -> dict[str, Any]:
    return {
        "request": request,
        "actor": current_actor,
        "csrf_token": csrf_token(request),
        "base_path": BASE_PATH,
        "message": request.query_params.get("message", ""),
        **extra,
    }


@asynccontextmanager
async def lifespan(_: FastAPI):
    with SessionLocal() as session:
        seed_from_files(session)
    yield


app = FastAPI(title="Support Tools", docs_url=None, redoc_url=None, openapi_url=None, lifespan=lifespan)
app.add_middleware(
    SessionMiddleware,
    secret_key=os.environ["SUPPORT_TOOLS_SESSION_SECRET"],
    same_site="lax",
    https_only=os.getenv("SUPPORT_TOOLS_COOKIE_SECURE", "true").lower() == "true",
)
app.mount(f"{BASE_PATH}/static", StaticFiles(directory="app/static"), name="static")
templates = Jinja2Templates(directory="app/templates")


@app.get(f"{BASE_PATH}/healthz")
def health(session: Session = Depends(database_session)) -> dict[str, str]:
    session.execute(text("SELECT 1"))
    return {"status": "ok"}


@app.get(BASE_PATH, response_class=HTMLResponse)
@app.get(f"{BASE_PATH}/", response_class=HTMLResponse)
def automation_list(
    request: Request,
    session: Session = Depends(database_session),
    current_actor: dict[str, str] = Depends(actor),
) -> HTMLResponse:
    rules = list(session.scalars(select(AutomationRule).order_by(AutomationRule.id)))
    return templates.TemplateResponse(
        request=request,
        name="list.html",
        context=page_context(request, current_actor, rules=rules),
    )


@app.get(f"{BASE_PATH}/new", response_class=HTMLResponse)
def automation_new(request: Request, current_actor: dict[str, str] = Depends(actor)) -> HTMLResponse:
    defaults = {
        "id": "",
        "enabled": True,
        "schedule_days": ["mon", "tue", "wed", "thu", "fri"],
        "schedule_time": "08:00",
        "start_offset_days": 0,
        "period_days": 1,
        "statuses": [2, 3],
        "recipients": [],
        "subject": "Employee absence summary: {{ period_label }} ({{ count }})",
        "text_template": "Employee absence summary\n{{ period_label }}\n\n{% for absence in absences %}- {{ absence.date_label }}: {{ absence.employee_name }} | {{ absence.duration }}\n{% else %}No employees are absent for this period.\n{% endfor %}",
        "html_template": "<h1>Employee absence summary</h1><p>{{ period_label }}</p>{% for absence in absences %}<p><strong>{{ absence.employee_name }}</strong> - {{ absence.duration }}</p>{% else %}<p>No employees are absent for this period.</p>{% endfor %}",
        "send_when_empty": False,
        "include_leave_type": False,
        "filters": {"subunits": [], "locations": [], "employee_emails": []},
    }
    return templates.TemplateResponse(
        request=request,
        name="form.html",
        context=page_context(request, current_actor, rule=defaults, weekdays=WEEKDAYS, editing=False, error=""),
    )


@app.post(f"{BASE_PATH}/new")
async def automation_create(
    request: Request,
    session: Session = Depends(database_session),
    current_actor: dict[str, str] = Depends(actor),
):
    form = await request.form()
    verify_csrf(request, str(form.get("csrf_token", "")))
    raw = form_data(form)
    try:
        data = validate_rule(raw)
        rule = AutomationRule(id=data["id"], version=1, updated_by=current_actor["email"])
        apply_data(rule, data, current_actor["email"])
        session.add(rule)
        session.flush()
        add_revision(session, rule, current_actor["email"])
        session.commit()
        publish_runtime(session)
    except (ValidationError, ValueError, IntegrityError) as exc:
        session.rollback()
        error = "A rule with this ID already exists" if isinstance(exc, IntegrityError) else str(exc)
        return templates.TemplateResponse(
            request=request,
            name="form.html",
            context=page_context(request, current_actor, rule=raw, weekdays=WEEKDAYS, editing=False, error=error),
            status_code=422,
        )
    return redirect(f"/{rule.id}/edit", "Automation created and published")


@app.get(f"{BASE_PATH}/{{rule_id}}/edit", response_class=HTMLResponse)
def automation_edit(
    rule_id: str,
    request: Request,
    session: Session = Depends(database_session),
    current_actor: dict[str, str] = Depends(actor),
) -> HTMLResponse:
    rule = session.get(AutomationRule, rule_id)
    if not rule:
        raise HTTPException(status_code=404, detail="Automation not found")
    return templates.TemplateResponse(
        request=request,
        name="form.html",
        context=page_context(request, current_actor, rule=rule, weekdays=WEEKDAYS, editing=True, error=""),
    )


@app.post(f"{BASE_PATH}/{{rule_id}}/edit")
async def automation_update(
    rule_id: str,
    request: Request,
    session: Session = Depends(database_session),
    current_actor: dict[str, str] = Depends(actor),
):
    rule = session.get(AutomationRule, rule_id)
    if not rule:
        raise HTTPException(status_code=404, detail="Automation not found")
    form = await request.form()
    verify_csrf(request, str(form.get("csrf_token", "")))
    raw = form_data(form, rule_id)
    try:
        data = validate_rule(raw)
        rule.version += 1
        apply_data(rule, data, current_actor["email"])
        add_revision(session, rule, current_actor["email"])
        session.commit()
        publish_runtime(session)
    except (ValidationError, ValueError) as exc:
        session.rollback()
        return templates.TemplateResponse(
            request=request,
            name="form.html",
            context=page_context(request, current_actor, rule=raw, weekdays=WEEKDAYS, editing=True, error=str(exc)),
            status_code=422,
        )
    return redirect(f"/{rule_id}/edit", "Changes saved and published")


@app.post(f"{BASE_PATH}/{{rule_id}}/toggle")
def automation_toggle(
    rule_id: str,
    request: Request,
    csrf_token_form: str = Form(alias="csrf_token"),
    session: Session = Depends(database_session),
    current_actor: dict[str, str] = Depends(actor),
):
    verify_csrf(request, csrf_token_form)
    rule = session.get(AutomationRule, rule_id)
    if not rule:
        raise HTTPException(status_code=404, detail="Automation not found")
    rule.enabled = not rule.enabled
    rule.version += 1
    rule.updated_by = current_actor["email"]
    add_revision(session, rule, current_actor["email"])
    session.commit()
    publish_runtime(session)
    state = "enabled" if rule.enabled else "disabled"
    return redirect("", f"{rule.id} {state}")


@app.get(f"{BASE_PATH}/{{rule_id}}/preview", response_class=HTMLResponse)
def automation_preview(
    rule_id: str,
    request: Request,
    session: Session = Depends(database_session),
    current_actor: dict[str, str] = Depends(actor),
) -> HTMLResponse:
    rule = session.get(AutomationRule, rule_id)
    if not rule:
        raise HTTPException(status_code=404, detail="Automation not found")
    subject, text_body, html_body = render_content(rule)
    return templates.TemplateResponse(
        request=request,
        name="preview.html",
        context=page_context(
            request,
            current_actor,
            rule=rule,
            subject=subject,
            text_body=text_body,
            html_body=html_body,
            error="",
        ),
    )


@app.post(f"{BASE_PATH}/{{rule_id}}/test-email")
def automation_test_email(
    rule_id: str,
    request: Request,
    recipient: str = Form(),
    csrf_token_form: str = Form(alias="csrf_token"),
    session: Session = Depends(database_session),
    current_actor: dict[str, str] = Depends(actor),
):
    verify_csrf(request, csrf_token_form)
    rule = session.get(AutomationRule, rule_id)
    if not rule:
        raise HTTPException(status_code=404, detail="Automation not found")
    try:
        send_test_email(rule, recipient)
    except (ValidationError, OSError, smtplib.SMTPException) as exc:
        subject, text_body, html_body = render_content(rule)
        return templates.TemplateResponse(
            request=request,
            name="preview.html",
            context=page_context(
                request,
                current_actor,
                rule=rule,
                subject=subject,
                text_body=text_body,
                html_body=html_body,
                error=f"Test delivery failed: {exc}",
            ),
            status_code=502,
        )
    return redirect(f"/{rule_id}/preview", f"Test email sent to {recipient}")


@app.get(f"{BASE_PATH}/{{rule_id}}/history", response_class=HTMLResponse)
def automation_history(
    rule_id: str,
    request: Request,
    session: Session = Depends(database_session),
    current_actor: dict[str, str] = Depends(actor),
) -> HTMLResponse:
    rule = session.get(AutomationRule, rule_id)
    if not rule:
        raise HTTPException(status_code=404, detail="Automation not found")
    revisions = list(
        session.scalars(
            select(AutomationRuleRevision)
            .where(AutomationRuleRevision.rule_id == rule_id)
            .order_by(AutomationRuleRevision.version.desc())
        )
    )
    return templates.TemplateResponse(
        request=request,
        name="history.html",
        context=page_context(request, current_actor, rule=rule, revisions=revisions),
    )


@app.post(f"{BASE_PATH}/{{rule_id}}/restore/{{revision_id}}")
def automation_restore(
    rule_id: str,
    revision_id: int,
    request: Request,
    csrf_token_form: str = Form(alias="csrf_token"),
    session: Session = Depends(database_session),
    current_actor: dict[str, str] = Depends(actor),
):
    verify_csrf(request, csrf_token_form)
    rule = session.get(AutomationRule, rule_id)
    revision = session.get(AutomationRuleRevision, revision_id)
    if not rule or not revision or revision.rule_id != rule_id:
        raise HTTPException(status_code=404, detail="Revision not found")
    data = validate_rule(revision.snapshot)
    rule.version += 1
    apply_data(rule, data, current_actor["email"])
    add_revision(session, rule, current_actor["email"])
    session.commit()
    publish_runtime(session)
    return redirect(f"/{rule_id}/history", f"Version {revision.version} restored as version {rule.version}")

