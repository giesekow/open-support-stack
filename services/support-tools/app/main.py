import os
import smtplib
import secrets
import asyncio
import logging
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

from .access import authorize_actor
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
from .models import (
    AutomationRule,
    AutomationRuleRevision,
    IdentityLink,
    ProvisioningAction,
    ProvisioningAuditEvent,
    ProvisioningTarget,
    ReconciliationRun,
    SourceIdentity,
)
from .provisioning import (
    ProvisioningError,
    execute_action,
    jit_review_after_days,
    reconcile,
    reconciliation_enabled,
    provisioning_health,
    retention_policy,
    seed_targets,
    writes_allowed,
)


BASE_PATH = "/automations"
logger = logging.getLogger("support-tools")


def database_session() -> Generator[Session, None, None]:
    session = SessionLocal()
    try:
        yield session
    finally:
        session.close()


def actor(request: Request) -> dict[str, str]:
    email = request.headers.get("x-auth-request-email", "").strip()
    username = request.headers.get("x-auth-request-user", "").strip()
    groups = request.headers.get("x-auth-request-groups", "").strip()
    allowed_group = os.getenv("SUPPORT_TOOLS_ALLOWED_GROUP", "support-admin")
    if not email and os.getenv("SUPPORT_TOOLS_DEV_AUTH_BYPASS", "false").lower() == "true":
        email = os.getenv("SUPPORT_TOOLS_DEV_USER_EMAIL", "developer@example.com")
        username = os.getenv("SUPPORT_TOOLS_DEV_USER_NAME", "Local developer")
        groups = allowed_group
    return authorize_actor(email, username, groups, allowed_group)


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
        "page_section": "automations",
        **extra,
    }


async def provisioning_scheduler() -> None:
    interval = max(60, int(os.getenv("PROVISIONING_INTERVAL_SECONDS", "300")))
    while True:
        await asyncio.sleep(interval)
        if not reconciliation_enabled():
            continue
        try:
            await asyncio.to_thread(run_scheduled_reconciliation)
        except Exception:
            logger.exception("Scheduled identity reconciliation failed")


def run_scheduled_reconciliation() -> None:
    with SessionLocal() as session:
        reconcile(session, actor="system:scheduler", trigger="scheduled")


@asynccontextmanager
async def lifespan(_: FastAPI):
    retention_policy()
    jit_review_after_days()
    with SessionLocal() as session:
        seed_from_files(session)
        seed_targets(session)
    task = asyncio.create_task(provisioning_scheduler())
    try:
        yield
    finally:
        task.cancel()
        try:
            await task
        except asyncio.CancelledError:
            pass


app = FastAPI(title="Support Tools", docs_url=None, redoc_url=None, openapi_url=None, lifespan=lifespan)
app.add_middleware(
    SessionMiddleware,
    secret_key=os.environ["SUPPORT_TOOLS_SESSION_SECRET"],
    same_site="lax",
    https_only=os.getenv("SUPPORT_TOOLS_COOKIE_SECURE", "true").lower() == "true",
)
app.mount(f"{BASE_PATH}/static", StaticFiles(directory="app/static"), name="static")
templates = Jinja2Templates(directory="app/templates")


def database_health(session: Session) -> dict[str, str]:
    session.execute(text("SELECT 1"))
    return {"status": "ok"}


@app.get("/internal/healthz")
def internal_health(session: Session = Depends(database_session)) -> dict[str, str]:
    return database_health(session)


@app.get("/internal/readyz")
def internal_readiness(session: Session = Depends(database_session)) -> dict[str, Any]:
    database_health(session)
    return provisioning_health(session)


@app.get(f"{BASE_PATH}/healthz")
def health(
    session: Session = Depends(database_session),
    _: dict[str, str] = Depends(actor),
) -> dict[str, str]:
    return database_health(session)


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
        "statuses": ["Approved"],
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


@app.get(f"{BASE_PATH}/provisioning", response_class=HTMLResponse)
def provisioning_dashboard(
    request: Request,
    session: Session = Depends(database_session),
    current_actor: dict[str, str] = Depends(actor),
) -> HTMLResponse:
    targets = list(session.scalars(select(ProvisioningTarget).order_by(ProvisioningTarget.display_name)))
    runs = list(
        session.scalars(select(ReconciliationRun).order_by(ReconciliationRun.started_at.desc()).limit(10))
    )
    actions = list(
        session.scalars(select(ProvisioningAction).order_by(ProvisioningAction.created_at.desc()).limit(50))
    )
    sources = {
        source.id: source
        for source in session.scalars(
            select(SourceIdentity).where(SourceIdentity.id.in_([action.source_identity_id for action in actions]))
        )
    } if actions else {}
    return templates.TemplateResponse(
        request=request,
        name="provisioning.html",
        context=page_context(
            request,
            current_actor,
            page_section="provisioning",
            targets=targets,
            runs=runs,
            actions=actions,
            sources=sources,
            module_enabled=reconciliation_enabled(),
            global_writes_allowed=writes_allowed(),
        ),
    )


@app.post(f"{BASE_PATH}/provisioning/reconcile")
def provisioning_reconcile(
    request: Request,
    csrf_token_form: str = Form(alias="csrf_token"),
    session: Session = Depends(database_session),
    current_actor: dict[str, str] = Depends(actor),
):
    verify_csrf(request, csrf_token_form)
    try:
        run = reconcile(session, actor=current_actor["email"], trigger="manual")
    except ProvisioningError as exc:
        return redirect("/provisioning", f"Reconciliation failed: {exc}")
    except Exception as exc:
        logger.exception("Manual identity reconciliation failed")
        return redirect("/provisioning", f"Reconciliation failed: {exc}")
    return redirect(
        "/provisioning",
        f"Run {run.id[:8]} {run.status}: {run.source_count} identities, {run.planned_count} planned",
    )


@app.post(f"{BASE_PATH}/provisioning/targets/{{target_id}}")
async def provisioning_target_update(
    target_id: str,
    request: Request,
    session: Session = Depends(database_session),
    current_actor: dict[str, str] = Depends(actor),
):
    form = await request.form()
    verify_csrf(request, str(form.get("csrf_token", "")))
    target = session.get(ProvisioningTarget, target_id)
    if not target:
        raise HTTPException(status_code=404, detail="Provisioning target not found")
    groups = [item.strip().lstrip("/") for item in str(form.get("eligibility_groups", "")).split(",") if item.strip()]
    if not groups:
        return redirect("/provisioning", f"{target.display_name} needs at least one eligibility group")
    target.enabled = form.get("enabled") == "on"
    target.dry_run = form.get("dry_run") == "on"
    target.eligibility_groups = list(dict.fromkeys(groups))
    target.updated_by = current_actor["email"]
    session.add(
        ProvisioningAuditEvent(
            event_type="target.configuration.updated",
            actor=current_actor["email"],
            target_id=target.id,
            correlation_id=secrets.token_hex(18),
            payload={"enabled": target.enabled, "dry_run": target.dry_run, "groups": target.eligibility_groups},
        )
    )
    session.commit()
    return redirect("/provisioning", f"{target.display_name} configuration saved")


@app.post(f"{BASE_PATH}/provisioning/actions/{{action_id}}/execute")
async def provisioning_action_execute(
    action_id: str,
    request: Request,
    session: Session = Depends(database_session),
    current_actor: dict[str, str] = Depends(actor),
):
    form = await request.form()
    verify_csrf(request, str(form.get("csrf_token", "")))
    try:
        action = execute_action(session, action_id, current_actor["email"], str(form.get("reason", "")))
    except (ProvisioningError, ValueError) as exc:
        return redirect("/provisioning", f"Action was not executed: {exc}")
    except Exception as exc:
        logger.exception("Provisioning action failed")
        return redirect("/provisioning", f"Action failed safely: {exc}")
    return redirect("/provisioning", f"Action {action.id[:8]} executed")


@app.get(f"{BASE_PATH}/provisioning/identities/{{identity_id}}", response_class=HTMLResponse)
def provisioning_identity_detail(
    identity_id: int,
    request: Request,
    session: Session = Depends(database_session),
    current_actor: dict[str, str] = Depends(actor),
) -> HTMLResponse:
    identity = session.get(SourceIdentity, identity_id)
    if not identity:
        raise HTTPException(status_code=404, detail="Source identity not found")
    links = list(session.scalars(select(IdentityLink).where(IdentityLink.source_identity_id == identity.id)))
    actions = list(
        session.scalars(
            select(ProvisioningAction)
            .where(ProvisioningAction.source_identity_id == identity.id)
            .order_by(ProvisioningAction.created_at.desc())
            .limit(50)
        )
    )
    return templates.TemplateResponse(
        request=request,
        name="provisioning_identity.html",
        context=page_context(
            request,
            current_actor,
            page_section="provisioning",
            identity=identity,
            links=links,
            actions=actions,
        ),
    )
