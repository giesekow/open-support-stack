# Keycloak validation evidence requirements

Every command-based evidence record must be independently auditable and contain:

1. Evidence ID, UTC execution time, environment, and result.
2. The exact executed entry command, with host/key paths sanitized where needed.
3. Complete command forms for each material check. Do not use `...` in place of arguments.
4. Relevant stdout/stderr, HTTP status, response fields, and exit status or an explicit assertion result.
5. Explicit placeholders such as `<REDACTED_TOKEN>`, `<REDACTED_SECRET>`, and `<USER_ID>` for sensitive or identifying values.
6. Cleanup commands and output proving temporary users, clients, groups, containers, networks, and files were removed.
7. The path and SHA-256 of a reusable evidence script when a script performs the commands.
8. A limitation statement when an original historical command transcript was not retained. Never reconstruct or present an unverified command as historically executed; rerun the control where safe and link the supplemental transcript.

Interactive evidence must identify the steps performed, expected and actual behavior, UTC confirmation time, tester/reviewer reference, and a server-side corroborating command where available. Screenshots must exclude secrets, OTP seeds, recovery codes, tokens, and unnecessary personal data.

A narrative summary may accompany a transcript but cannot replace it.
