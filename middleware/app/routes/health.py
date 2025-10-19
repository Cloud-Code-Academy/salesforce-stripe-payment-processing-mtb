"""
Health Check and Monitoring Endpoints

Provides health status and dependency checks for the application.
"""

from datetime import datetime
from typing import Dict, Any

from fastapi import APIRouter, HTTPException
from fastapi.responses import JSONResponse

from app.config import settings
from app.services.redis_service import redis_service
from app.services.sqs_service import sqs_service
from app.auth.salesforce_oauth import salesforce_oauth
from app.utils.logging_config import get_logger

logger = get_logger(__name__)

router = APIRouter(tags=["health"])


@router.get("/health")
async def health_check():
    """
    Basic health check endpoint.
    Returns 200 if application is running.
    """
    return JSONResponse(
        status_code=200,
        content={
            "status": "healthy",
            "timestamp": datetime.utcnow().isoformat(),
            "version": settings.app_version,
        },
    )


@router.get("/health/ready")
async def readiness_check():
    """
    Readiness check endpoint.
    Verifies that all dependencies are available.
    """
    status = "ready"
    dependencies: Dict[str, Any] = {}
    overall_healthy = True

    # Check Redis
    try:
        await redis_service.redis_client.ping()
        dependencies["redis"] = {"status": "healthy", "connected": True}
    except Exception as e:
        dependencies["redis"] = {
            "status": "unhealthy",
            "connected": False,
            "error": str(e),
        }
        overall_healthy = False

    # Check SQS
    try:
        attributes = await sqs_service.get_queue_attributes()
        dependencies["sqs"] = {
            "status": "healthy",
            "queue_url": sqs_service.queue_url,
            "approximate_messages": attributes.get(
                "ApproximateNumberOfMessages", "unknown"
            ),
        }
    except Exception as e:
        dependencies["sqs"] = {
            "status": "unhealthy",
            "error": str(e),
        }
        overall_healthy = False

    # Check Salesforce OAuth
    try:
        # Try to get cached token or authenticate
        await salesforce_oauth.get_access_token()
        instance_url = await salesforce_oauth.get_instance_url()
        dependencies["salesforce"] = {
            "status": "healthy",
            "authenticated": True,
            "instance_url": instance_url,
        }
    except Exception as e:
        dependencies["salesforce"] = {
            "status": "unhealthy",
            "authenticated": False,
            "error": str(e),
        }
        overall_healthy = False

    if not overall_healthy:
        status = "not_ready"

    status_code = 200 if overall_healthy else 503

    return JSONResponse(
        status_code=status_code,
        content={
            "status": status,
            "timestamp": datetime.utcnow().isoformat(),
            "dependencies": dependencies,
        },
    )


@router.get("/health/live")
async def liveness_check():
    """
    Liveness check endpoint.
    Returns 200 if application is alive.
    """
    return JSONResponse(
        status_code=200,
        content={
            "status": "alive",
            "timestamp": datetime.utcnow().isoformat(),
        },
    )


@router.get("/metrics")
async def metrics():
    """
    Basic metrics endpoint.
    Returns application metrics and queue status.
    """
    try:
        # Get SQS queue metrics
        attributes = await sqs_service.get_queue_attributes()

        metrics_data = {
            "timestamp": datetime.utcnow().isoformat(),
            "application": {
                "name": settings.app_name,
                "version": settings.app_version,
                "environment": settings.environment,
            },
            "queue": {
                "url": sqs_service.queue_url,
                "approximate_messages": int(
                    attributes.get("ApproximateNumberOfMessages", 0)
                ),
                "approximate_messages_not_visible": int(
                    attributes.get("ApproximateNumberOfMessagesNotVisible", 0)
                ),
                "approximate_messages_delayed": int(
                    attributes.get("ApproximateNumberOfMessagesDelayed", 0)
                ),
            },
        }

        return JSONResponse(status_code=200, content=metrics_data)

    except Exception as e:
        logger.error(f"Error retrieving metrics: {e}")
        raise HTTPException(status_code=500, detail="Failed to retrieve metrics")
