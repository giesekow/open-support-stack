# Identity Provisioning Production Deployment

## Deployment Record

- Date: 2026-10-01
- Scope: Support Tools provisioning module and PostgreSQL migrations
- Production host: support-stack application VM
- Previous schema: `0001`
- Deployed schema: `0004`
- Backup: `backups/support-tools-deploy-20261001T100840Z`

The backup contains the previous compose file, Support Tools source, and a non-empty
PostgreSQL custom-format dump. The production compose update was built from the
deployed file and replaced only the `support-tools` service block, preserving other
production-only changes.

## Verification

- Docker Compose candidate and deployed configuration validated successfully.
- Support Tools rebuilt and started healthy with restart count zero.
- Migrations `0002`, `0003`, and `0004` completed successfully.
- `/internal/healthz` returned `ok`.
- An unauthenticated request to `/automations/` returned HTTP `401`.
- Recent application logs contained no error, exception, or traceback entry.
- All ten provisioning targets were seeded disabled and in dry-run.
- Runtime values are `PROVISIONING_ENABLED=false` and
  `PROVISIONING_ALLOW_WRITES=false`.
- No reconciliation or target write was executed in production.

## Vaultwarden Status

The production organization ID and persistent device UUID are configured. The
dedicated client ID, matching personal API secret, and protected service-account
email are also present. On 2026-10-01, the read-only adapter verification
successfully obtained an API token and listed the configured organization. The
organization contained one member at verification time; no membership was
created, changed, or removed.

The Keycloak source client is configured with only `view-users`, `query-users`,
and `query-groups`. Support Tools remains healthy, provisioning remains globally
disabled, writes remain locked, and every target remains disabled and dry-run.
The Vaultwarden target was independently confirmed as disabled and in dry-run
after credential verification.

## Vaultwarden Admin Token Rotation

On 2026-10-01 the `/admin` token was rotated with
`scripts/rotate_vaultwarden_admin_token.sh`. The previous environment was backed
up under `backups/vaultwarden-admin-token-20261001T112519Z`, and the new plaintext
was written once to an owner-only file under `.secrets/` for transfer into the
approved vault. Verification confirmed:

- plaintext and backup files have mode `600`;
- the running `ADMIN_TOKEN` is an Argon2id PHC string;
- Vaultwarden is healthy and emitted no token-configuration warning;
- `/admin` returns HTTP `200`; and
- unauthenticated `/admin/diagnostics` returns HTTP `401`.
