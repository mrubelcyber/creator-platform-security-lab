def creator_to_dict(row):
    return {
        "id": row["id"],
        "name": row["name"],
        "platform": row["platform"],
        "followers": row["followers"],
    }

def validate_creator(payload):
    if not isinstance(payload, dict):
        return "JSON body is required"

    name = str(payload.get("name", "")).strip()
    platform = str(payload.get("platform", "")).strip()

    try:
        followers = int(payload.get("followers", 0))
    except (TypeError, ValueError):
        return "followers must be an integer"

    if not name or not platform:
        return "name and platform are required"
    if followers < 0:
        return "followers cannot be negative"

    return None
