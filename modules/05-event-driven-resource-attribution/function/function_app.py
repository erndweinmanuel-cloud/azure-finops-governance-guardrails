import logging
import azure.functions as func

app = func.FunctionApp()


@app.function_name(name="ResourceAttribution")
@app.event_grid_trigger(arg_name="event")
def resource_attribution(event: func.EventGridEvent):

    data = event.get_json()
    claims = data.get("claims", {})

    resource_id = data.get("resourceUri") or event.subject
    operation = data.get("operationName")
    identity_type = claims.get("idtyp", "unknown")

    created_by = (
        claims.get(
            "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress"
        )
        or claims.get("name")
        or "unknown"
    )

    if identity_type == "user":
        created_by_type = "User"
    else:
        created_by_type = identity_type

    created_at = str(event.event_time)

    logging.info("=== Resource Attribution ===")
    logging.info("ResourceId: %s", resource_id)
    logging.info("Operation: %s", operation)
    logging.info("CreatedBy: %s", created_by)
    logging.info("CreatedByType: %s", created_by_type)
    logging.info("CreatedAt: %s", created_at)
