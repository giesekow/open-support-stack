# Frappe HR Cutover Runbook

## Scope

Frappe HR replaces OrangeHRM while sharing the existing ERPNext site, database, authentication client, and URL. The former HR hostname redirects to ERPNext. OrangeHRM containers are removed from normal Compose operation; their volumes remain temporarily for export and rollback.

## Data Ownership

- Keycloak owns authentication, verified email, names, and application eligibility.
- Frappe `User` owns application access and roles.
- Frappe HR `Employee` owns employee number, company, employment dates, department, designation, branch, approvers, leave, attendance, payroll, and expense history.
- Support Tools owns automation rules and immutable rule revisions.

Keycloak login alone does not create an `Employee`. This is deliberate: HR values must never be guessed from identity claims.

## Local Bootstrap

```bash
docker compose --env-file .env stop frappe-hr-leave-notifier
docker compose --env-file .env --profile bootstrap up erpnext-configurator
docker compose --env-file .env --profile bootstrap run --rm erpnext-create-site
docker compose --env-file .env up -d \
  erpnext-backend erpnext-websocket erpnext-queue-short erpnext-queue-long \
  erpnext-scheduler erpnext-frontend support-tools-db support-tools \
  frappe-hr-leave-notifier
./scripts/configure_frappe_hr.sh .env
```

Bootstrap is safe to rerun and reads the actual database name from the site's
`site_config.json`. It recreates a dedicated notifier account with only `SELECT`
on that database, so keep the notifier stopped until bootstrap succeeds. The
notifier discovers the one schema visible to that account; it does not receive
the Frappe site's full database credentials.

The site creation task always migrates ERPNext before installing HRMS, then migrates again. This avoids installing HRMS against an older ERPNext schema.

## Production Environment Merge

Do not replace the active production environment file with a development or
workstation copy. Preserve all existing production values, especially proxy/TLS
mode, database passwords, session secrets, OIDC client secrets, and administrative
tokens. Add only reviewed variables that are absent from production, then run the
new preflight and Compose rendering against that merged candidate before changing
containers:

```bash
./scripts/preflight_production.sh <production-env-file>
docker compose --env-file <production-env-file> config --quiet
```

Back up the original environment file with mode `600`. The currently deployed
host uses `.env`; `.env.production` is the workstation source template and must
not be copied over `.env` wholesale.

## Pre-Cutover Backup And Export

1. Announce an OrangeHRM, ERPNext, and Support Tools change freeze.
2. Create one coordinated, timestamped backup set containing:
   - the active environment, Compose file, service source, and configuration;
   - an OrangeHRM database dump plus the OrangeHRM data volume;
   - an ERPNext database dump plus the complete `erpnext-sites` volume;
   - a Support Tools PostgreSQL dump plus `support-tools-runtime`;
   - the notifier delivery ledger volume.
3. Record checksums, restrict the backup directory to the deployment operator,
   and verify each database archive before proceeding. Migration `0005` is an
   intentionally irreversible data cutover; rollback restores this coordinated
   set rather than running `alembic downgrade`.
4. Stop the OrangeHRM application and database containers. The export helper
   refuses to attach the data volume while another container is using it.
5. Export the legacy records:

```bash
./scripts/export_orangehrm_for_frappe_hr.sh <production-env-file>
```

6. Verify `SHA256SUMS`, restrict the output directory, and record the evidence location.
7. Reconcile employee number, verified work email, name, gender, date of birth, joining date, company, subunit-to-department, and location-to-branch mappings.
8. Configure Frappe master data before onboarding: Company, Gender, Department, Designation, Branch, Holiday List, Leave Types, Leave Policies, and expense approvers.

The pinned HRMS bundle was rehearsed on 2026-11-24 against an isolated clone of
the production Frappe `15.107.2` / ERPNext `15.108.0` database and site files.
Migration completed at Frappe `15.122.0`, ERPNext `15.121.6`, and HRMS `15.64.3`.
No rehearsal resources or production data copies were retained.

## Scoped Production Rollout

Do not run an unscoped `docker compose up -d` for this cutover. The stack includes
other services whose tagged images and configuration are outside this change.
After the backup/export and code synchronization, deploy only the reviewed scope:

```bash
ENV_FILE=.env

docker compose --env-file "$ENV_FILE" build \
  support-tools frappe-hr-leave-notifier
docker compose --env-file "$ENV_FILE" pull erpnext-backend

docker compose --env-file "$ENV_FILE" stop frappe-hr-leave-notifier
docker compose --env-file "$ENV_FILE" --profile bootstrap run --rm \
  erpnext-create-site

docker compose --env-file "$ENV_FILE" up -d \
  erpnext-backend erpnext-websocket erpnext-queue-short erpnext-queue-long \
  erpnext-scheduler erpnext-frontend support-tools-db support-tools \
  frappe-hr-leave-notifier nginx

./scripts/sync_keycloak_redirects.sh "$ENV_FILE"
./scripts/configure_erpnext_oidc.sh "$ENV_FILE"
./scripts/configure_frappe_hr.sh "$ENV_FILE"
```

The retired OrangeHRM containers must already be stopped before source
synchronization and removed only after their export and coordinated backup are
verified. Do not use `--remove-orphans`; retained rollback volumes must not be
deleted. Start unrelated services only if their own reviewed change requires it.

## Employee Onboarding

1. Add the Keycloak user to `employees`.
2. Have the user complete one Frappe HR/ERPNext Keycloak login.
3. Link the reviewed employee data:

```bash
./scripts/onboard_frappe_hr_employee.sh --env-file .env.production \
  --email employee@example.com --employee-number EMP-0001 \
  --gender Female --date-of-birth 1990-01-01 \
  --date-of-joining 2026-01-01 --company "Bonescreen GmbH" \
  --department Support --designation Engineer --branch Berlin
```

The command is idempotent, rejects privileged users, detects identifier conflicts, and grants only the `Employee` role. Assign leave and expense approvers through reviewed Frappe HR configuration.

## Leave And Expense Migration

1. Import opening leave allocations rather than replaying unapproved requests.
2. Preserve historical leave exports as controlled records; import history only when reporting requirements justify it.
3. Create or map Expense Claim Types and cost centers.
4. Confirm employees can create Expense Claims and attach receipts/invoices.
5. Confirm expense and leave approvers are mandatory and self-approval is prevented:

```bash
./scripts/configure_frappe_hr.sh .env.production
```

## Validation

```bash
docker compose --env-file .env.production exec -T erpnext-backend \
  bench --site "$ERPNEXT_SITE_NAME" list-apps
docker compose --env-file .env.production run --rm frappe-hr-leave-notifier \
  --run-now --rule daily-absence-summary --send-empty --validate-only --force
docker compose --env-file .env.production logs --tail=100 \
  erpnext-backend erpnext-scheduler frappe-hr-leave-notifier support-tools
```

Acceptance requires `frappe`, `erpnext`, and `hrms`; successful Keycloak login; least-privilege Employee access; leave request/approval; expense claim with attachment and approval; notifier validation; and reconciled employee/leave counts.

Verify notifier database isolation as part of deployment evidence: effective
schema privileges must contain exactly `SELECT` on the Frappe site schema, a
leave-table read must succeed, and a controlled create-table probe must fail
with a database permission error.

```bash
./scripts/verify_frappe_hr_notifier_db.sh .env.production
```

The verifier reports only the schema privilege, record count, and denied-write
error code; it does not print database credentials or password hashes.

## Rollback And Retirement

If validation fails, stop writes to Frappe HR, restore the pre-cutover ERPNext backup when required, and restart the previously pinned OrangeHRM deployment against its retained volumes. Do not run both systems as writable HR masters.

After formal acceptance and the approved retention period, archive the checksummed export according to the HR data-retention policy, remove OrangeHRM secrets, delete the retained OrangeHRM volumes, and update the tool-validation inventory. Historical validation evidence must not be rewritten.
