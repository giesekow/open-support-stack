from fastapi import HTTPException


def parse_groups(header: str) -> set[str]:
    return {
        item.strip().lstrip("/")
        for item in (header or "").split(",")
        if item.strip()
    }


def authorize_actor(
    email: str,
    username: str,
    groups_header: str,
    allowed_group: str,
) -> dict[str, str]:
    if not email:
        raise HTTPException(status_code=401, detail="Authenticated email header is missing")

    required_group = allowed_group.strip().lstrip("/")
    if not required_group:
        raise HTTPException(status_code=503, detail="Access policy is not configured")
    if required_group not in parse_groups(groups_header):
        raise HTTPException(status_code=403, detail="Insufficient permissions")

    return {"email": email, "name": username or email}
