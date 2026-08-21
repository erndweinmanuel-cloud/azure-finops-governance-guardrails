import logging

import azure.functions as func
from azure.identity import DefaultAzureCredential
from azure.mgmt.resource.resources import ResourceManagementClient

app = func.FunctionApp()


def build_attribution_tags(
    created_by: str,
    created_by_type: str,
    created_at: str
) -> dict:
    return {
        "CreatedBy": created_by,
        "CreatedByType": created_by_type,
        "CreatedAt": created_at
    }


def should_apply_attribution(existing_tags: dict) -> bool:
    return not bool(existing_tags.get("CreatedBy"))


def parse_resource_id(resource_id: str) -> dict:
    parts = resource_id.strip("/").split("/")

    return {
        "subscription_id": parts[1],
        "resource_group": parts[3],
        "provider_namespace": parts[5],
        "resource_type": parts[6],
        "resource_name": parts[7]
    }


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

    attribution_tags = build_attribution_tags(
        created_by,
        created_by_type,
        created_at
    )

    resource_parts = parse_resource_id(resource_id)

    credential = DefaultAzureCredential()

    resource_client = ResourceManagementClient(
        credential,
        resource_parts["subscription_id"]
    )

    current_tags = resource_client.tags.get_at_scope(
        resource_id
    )

    existing_tags = current_tags.properties.tags or {}

    logging.info("=== Resource Attribution ===")
    logging.info("ResourceId: %s", resource_id)
    logging.info("Operation: %s", operation)
    logging.info("ExistingTags: %s", existing_tags)

    if should_apply_attribution(existing_tags):

        tag_patch = {
            "operation": "Merge",
            "properties": {
                "tags": attribution_tags
            }
        }

        update = resource_client.tags.begin_update_at_scope(
            resource_id,
            tag_patch
        )

        update.result()

        logging.info("Attribution applied successfully.")
        logging.info("AppliedTags: %s", attribution_tags)

    else:
        logging.info(
            "Attribution skipped. CreatedBy already exists: %s",
            existing_tags.get("CreatedBy")
        )
