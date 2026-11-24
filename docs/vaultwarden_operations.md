# Vaultwarden Operating Guide

## Scope and permitted use

Vaultwarden is used for support-team credentials and controlled organization
collections. Store only the information needed to identify and use an approved
credential. Do not place customer personal data, product records, recovery
exports, private keys, or other unnecessary sensitive content in free-text
notes.

## User onboarding

1. Use an individual account for every person. Shared user accounts are not
   permitted.
2. Keep public registration disabled in production.
3. An organization owner invites the approved email address and assigns only
   the collections required for the user's role.
4. The invited user accepts the invitation, verifies access, and enables the
   approved account-protection controls.
5. A second organization owner confirms the membership and collection scope.

## Organization sharing

- Put shared credentials in organization collections, not another user's
  personal vault.
- Grant collection access according to least privilege. Use read-only access
  where updates are not required.
- Review organization owners, members, and collection assignments
  periodically and after role changes.
- Never send vault passwords, recovery codes, or exported vault files by email
  or chat.

## Recovery

- Users must keep account recovery information in an approved location that is
  separate from the account it recovers.
- Organization owners can restore access to organization items by replacing a
  member, but they cannot decrypt a lost personal vault.
- Do not disable security controls merely to work around a lost password or
  second factor. Escalate recovery to the system owner.

## Admin token rotation

The instance administration page at `/admin` is separate from organization
Owner/Admin roles. Rotate its token from the deployment host with:

```bash
./scripts/rotate_vaultwarden_admin_token.sh .env
```

The script creates a random 64-character token, hashes it with Vaultwarden's
Argon2id `bitwarden` preset, backs up the previous environment file, recreates
only Vaultwarden, and verifies that the running container received a valid PHC
string. It refuses to continue if `/data/config.json` overrides `admin_token`.

The plaintext is never printed. It is written once to the owner-only path shown
by the command under `.secrets/`. Store that value immediately in the approved
vault, verify login at `https://vault.internal-support.bonescreen.de/admin`, and
then securely remove the plaintext file. Never enter the Argon2 hash on the
login page; enter the plaintext token that was hashed.

## Keycloak SSO

Configure Vaultwarden's SSO authority as the HTTPS Keycloak realm URL, without
the discovery suffix:

```text
https://sso.support.bonescreen.de/realms/support
```

Do not use HTTP. A redirect from HTTP to HTTPS is not accepted as an OIDC
discovery response. In the local environment, Keycloak uses the stack's private
CA. The Vaultwarden service therefore mounts `nginx/certs/support-stack-ca.crt`
and builds an augmented CA bundle at startup through `SSL_CERT_FILE`. This keeps
the normal public trust roots while adding trust for local stack certificates.
Never work around a discovery failure by disabling certificate verification.

When production nginx runs in HTTP-only mode behind a TLS-terminating reverse
proxy, Docker's nginx network alias would otherwise resolve the public SSO
hostname directly to nginx, where port `443` is not listening. Set
`SSO_INTERNAL_PROXY_IP` to the reverse proxy's internal address. Vaultwarden's
service-specific host override then keeps the public HTTPS issuer and valid TLS
while routing discovery through that proxy. Do not set this to the Keycloak
container address because Keycloak listens on internal HTTP port `8080`, not
HTTPS port `443`.

After changing the authority or certificates, recreate Vaultwarden and verify
discovery from the same container network and trust context used by the service:

```bash
docker compose --env-file .env up -d --force-recreate vaultwarden
docker exec support-vaultwarden sh -c \
  'SSL_CERT_FILE=/tmp/support-stack-ca-bundle.crt curl --silent --show-error \
  --output /dev/null --write-out "HTTP %{http_code}; TLS verify %{ssl_verify_result}\n" \
  https://sso.support.bonescreen.de/realms/support/.well-known/openid-configuration'
```

Expected result: `HTTP 200; TLS verify 0`. If discovery still fails, inspect
`docker logs support-vaultwarden` for the underlying TLS or OIDC error before
changing configuration.

## Development email

The local stack sends mail to Mailpit on port `1025` without TLS or SMTP
authentication. Keep these local values in `.env`:

```dotenv
SMTP_HOST=mailpit
SMTP_PORT=1025
SMTP_SECURITY=off
SMTP_USER=
SMTP_PASS=
SMTP_AUTH_MECHANISM=
```

Empty authentication settings are intentional. Vaultwarden distinguishes
between authentication variables being absent and being present with empty
values. The Compose startup command therefore unsets `SMTP_USERNAME`,
`SMTP_PASSWORD`, and `SMTP_AUTH_MECHANISM` before starting Vaultwarden when the
username is empty. Otherwise Vaultwarden can report `No compatible
authentication mechanism was found` even when the mechanism itself is blank.

Vaultwarden settings saved through its admin page are stored in
`/data/config.json` and override matching environment variables. Remove old
`smtp_username`, `smtp_password`, and `smtp_auth_mechanism` values there, or
clear all three in the admin page, when switching to Mailpit.

## Offboarding

1. Remove the person from every organization and collection immediately.
2. Disable or delete the Vaultwarden account according to the retention
   decision and revoke active sessions/devices where available.
3. Rotate credentials the person could retrieve, especially customer and
   privileged credentials.
4. Record completion in the approved offboarding record.

Removing server access does not erase data already synchronized to an offline
client. Rotation of exposed credentials and management of the former user's
device are therefore required offboarding controls.

## Backup and restore

Create a protected backup before upgrades and on the approved schedule:

```bash
./scripts/validate_vaultwarden_backup_restore.sh .env
```

The procedure uses Vaultwarden's online SQLite backup, preserves required data
files and configuration in an owner-only directory, checks archive/database
integrity, and performs an isolated restore without publishing a host port.
Backup directories contain sensitive encrypted vault data and configuration;
they must not be committed, emailed, or stored in a public location.

For disaster recovery, restore the database, required `/data` files, and the
matching protected environment/configuration backup. Verify login, organization
membership, collection permissions, and retrieval of a controlled test item
before returning the service to use.

## Updates

1. Review the upstream release notes and security advisories.
2. Create and verify a protected backup.
3. Test the target image against an isolated restored copy.
4. Re-run login, organization authorization, synchronization, HTTPS, and
   backup/restore regression tests.
5. Pin the approved image version and document rollback. Do not downgrade a
   changed database without restoring the matching pre-upgrade backup.
