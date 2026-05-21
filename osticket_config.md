# osTicket OAuth2 + Keycloak Configuration

This document captures the working OAuth2 mapping/settings for osTicket with Keycloak in this stack.

## Base Details

- osTicket URL: `https://tickets.example.com`
- Keycloak realm issuer: `https://sso.example.com/realms/support`
- Client ID: `osticket`
- Client Secret: from `.env` -> `OSTICKET_OIDC_CLIENT_SECRET`

## OAuth2 Endpoints

Use these values in the osTicket OAuth2 provider/plugin settings:

- Authorization URL: `https://sso.example.com/realms/support/protocol/openid-connect/auth`
- Token URL: `https://sso.example.com/realms/support/protocol/openid-connect/token`
- User Info URL: `https://sso.example.com/realms/support/protocol/openid-connect/userinfo`
- Scope: `openid profile email`

## Claim Mapping

Recommended mapping for this environment:

- User Identifier: `email`
- Username Claim: `preferred_username`
- Email Claim: `email`
- Name Claim: `name`
- First Name Field: `given_name`
- Last Name Field: `family_name`

## Why `email` as User Identifier

- Aligns with current account handling across BookStack/Guacamole/Vaultwarden.
- Easier operationally when reviewing users manually.
- Works well for this support stack where email is the canonical login identity.

## osTicket Admin Flow (Quick Checklist)

1. Go to `Admin Panel -> Manage -> Plugins`.
2. Enable `OAuth2 Client`.
3. Open plugin settings and add/configure Keycloak provider using the values above.
4. Go to authentication settings for Agents/Users and enable the OAuth2 backend where desired.
5. Test logins from:
   - Agent portal: `/scp/login.php`
   - User portal: `/login.php`

## TLS Note (Self-Signed Cert)

If OAuth fails due to certificate trust, ensure the osTicket container trusts your stack CA/cert.
Without trust, discovery/token/userinfo calls may fail TLS verification.
