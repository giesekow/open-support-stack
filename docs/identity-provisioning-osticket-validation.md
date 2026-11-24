# osTicket Agent Provisioning Validation

## Scope

Local validation on 2026-09-29 covered the pinned osTicket 1.17.5 schema,
least-privilege agent placement, account lifecycle, session revocation, cleanup,
and the Keycloak client eligibility gate. Production was not contacted.

The local osTicket installation did not have an OAuth plugin instance configured,
so an end-user browser login remains a deployment acceptance test rather than a
completed local test.

## Approved Placement

- Primary department: `Support`
- Role: `Support Agent`
- Role permissions: `ticket.reply` only
- Team membership: none
- Extra department access: none
- Local password: none
- Administrator access: false
- Eligibility: both `employees` and `app-osticket-agent`

## Commands And Results

```text
$ ./scripts/bootstrap_osticket_provisioning.sh .env
[INFO] Creating osTicket database backup: backups/osticket/pre-provisioning-20260929T150217Z.sql.gz
schema_check
schema-ok
department_id  department_name  role_id  role_name      permissions
1              Support          5        Support Agent  {"ticket.reply":1}
[OK] osTicket provisioning placement is ready; keep the target disabled/dry-run until review
```

The disposable adapter lifecycle produced:

```text
plan=create
created_account_id=2
placement=Support/Support Agent
permissions=ticket.reply
teams=0 extra_departments=0 local_password=null admin=false
disable=suspended sessions_revoked=1
reactivate=active
cleanup=passed
```

The complete provisioning suite then reported:

```text
Ran 65 tests
OK
```

Keycloak client read-back reported:

```text
client=osticket
browser_flow=osticket-agent-eligible-browser
binding_present=true
```

## Safety Findings

- The bundled `manage.php agent import` command is not used because it does not
  assign an explicit approved role.
- The adapter validates schema signature
  `83a22ba22b1a6a624fcb1da03882ac1b` before every operation. An osTicket schema
  change therefore blocks writes until compatibility is reviewed.
- Email-only matches, duplicate matches, administrators, local-password agents,
  team members, extra-department agents, and placement drift stop for review.
- Create, disable, and reactivate are transactional and use read-back checks.
- Disable changes only `ost_staff.isactive` and removes sessions whose
  `ost_session.user_id` is the exact staff ID. Tickets and assignments remain.
- API keys are never created, updated, or deleted by the adapter.
- The bootstrap creates a timestamped database backup before adding or validating
  the approved role.

## Remaining Deployment Test

After configuring the OAuth plugin instance, use a disposable Keycloak user to
prove successful login with both eligibility groups and denial after either group
is removed. Keep the osTicket target disabled and dry-run until that evidence is
approved.
