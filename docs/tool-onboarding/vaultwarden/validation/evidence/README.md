# Vaultwarden validation evidence requirements
Command evidence must include the UTC timestamp, environment, exact sanitized
entry command, relevant command output/status, result, cleanup proof, reusable
script path, and script SHA-256. Passwords, vault contents, tokens, recovery
material, SMTP credentials, account identifiers, email addresses, encryption
keys, and personal/customer data must never be retained.

Interactive evidence must identify the test step, expected and actual result,
UTC confirmation time, tester/reviewer reference, and a redacted screenshot or
observation where useful. Screenshots must not show credential values, vault
notes, recovery material, email addresses, or unrelated item names.

A summary cannot replace a transcript. If a test is only partially executed,
the completed and pending portions must be stated separately; a partial test
must not be marked passed.
