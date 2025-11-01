"""
AWS Lambda Handler for FastAPI Middleware

This module provides the Lambda entry point using Mangum adapter to convert
ASGI FastAPI application to AWS Lambda handler format.

Mangum handles the translation between API Gateway events and FastAPI's ASGI interface.
"""

import os
from mangum import Mangum

from app.main import app
from app.utils.logging_config import get_logger

logger = get_logger(__name__)


# Create Lambda handler
# Mangum wraps the FastAPI app and handles API Gateway integration
# api_gateway_base_path is set to "/" to let Mangum handle stage prefixes automatically
handler = Mangum(app, lifespan="off", api_gateway_base_path="/")


# Alternative: Custom handler with additional logging
def lambda_handler(event, context):
    """
    AWS Lambda handler function with custom logging.

    Args:
        event: API Gateway event containing HTTP request details
        context: Lambda context with runtime information

    Returns:
        API Gateway response format
    """
    # Note: Lambda automatically sets AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY
    # with temporary credentials from the IAM role. This is normal and expected.
    # Only warn if these look like test/invalid credentials
    aws_key = os.getenv("AWS_ACCESS_KEY_ID", "")
    if aws_key and (aws_key == "test" or aws_key.startswith("AKIA")):
        # AKIA prefix indicates long-term IAM user credentials (not temporary role credentials)
        logger.warning(
            "WARNING: Non-temporary AWS credentials detected in Lambda! "
            f"Key prefix: {aws_key[:4]}... "
            "Lambda should use temporary role credentials (starting with ASIA)."
        )

    # Log Lambda invocation details
    logger.info(
        "Lambda invocation started",
        extra={
            "request_id": context.aws_request_id,
            "function_name": context.function_name,
            "memory_limit": context.memory_limit_in_mb,
            "remaining_time": context.get_remaining_time_in_millis(),
            "event_source": event.get("requestContext", {}).get("stage"),
            "http_method": event.get("requestContext", {}).get("http", {}).get("method"),
            "path": event.get("requestContext", {}).get("http", {}).get("path"),
            "raw_path": event.get("rawPath"),
        },
    )

    try:
        # Use Mangum to handle the request
        response = handler(event, context)

        logger.info(
            "Lambda invocation completed",
            extra={
                "request_id": context.aws_request_id,
                "status_code": response.get("statusCode"),
            },
        )

        return response

    except Exception as e:
        logger.error(
            f"Lambda invocation failed: {e}",
            extra={
                "request_id": context.aws_request_id,
                "error": str(e),
                "error_type": type(e).__name__,
            },
        )
        raise


# Export both for flexibility
__all__ = ["handler", "lambda_handler"]
