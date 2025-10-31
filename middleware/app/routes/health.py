"""
Health Check and Monitoring Endpoints

Provides health status and dependency checks for the application.
Checks all services including Bulk API and batch accumulator components.
"""

from datetime import datetime
from typing import Dict, Any

from fastapi import APIRouter, HTTPException
from fastapi.responses import JSONResponse

from app.config import settings
from app.services.dynamodb_service import dynamodb_service
from app.services.sqs_service import sqs_service
from app.services.batch_accumulator import get_batch_accumulator
from app.services.rate_limiter import get_rate_limiter
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
    Verifies that all dependencies are available including:
    - DynamoDB (cache, rate limiting, batch accumulator)
    - SQS (main queue + low-priority queue)
    - Salesforce (OAuth and API connectivity)
    - Rate Limiter
    - Batch Accumulator
    """
    status = "ready"
    dependencies: Dict[str, Any] = {}
    overall_healthy = True

    # Check DynamoDB Cache
    try:
        # Test DynamoDB connectivity by checking if connected
        if not dynamodb_service.is_connected():
            await dynamodb_service.connect()

        dependencies["dynamodb_cache"] = {
            "status": "healthy",
            "connected": dynamodb_service.is_connected(),
            "table_name": settings.dynamodb_table_name,
        }
    except Exception as e:
        dependencies["dynamodb_cache"] = {
            "status": "unhealthy",
            "connected": False,
            "error": str(e),
        }
        overall_healthy = False

    # Check Batch Accumulator (DynamoDB)
    try:
        batch_accumulator = get_batch_accumulator()
        stats = await batch_accumulator.get_batch_stats()
        dependencies["batch_accumulator"] = {
            "status": "healthy",
            "table_name": batch_accumulator.table_name,
            "active_batches": len(stats.get("batches", {})),
            "stats": stats,
        }
    except Exception as e:
        dependencies["batch_accumulator"] = {
            "status": "unhealthy",
            "error": str(e),
        }
        overall_healthy = False

    # Check Main SQS Queue
    try:
        attributes = await sqs_service.get_queue_attributes()
        dependencies["sqs_main_queue"] = {
            "status": "healthy",
            "queue_url": sqs_service.queue_url,
            "approximate_messages": attributes.get(
                "ApproximateNumberOfMessages", "unknown"
            ),
            "type": "main (HIGH/MEDIUM priority)",
        }
    except Exception as e:
        dependencies["sqs_main_queue"] = {
            "status": "unhealthy",
            "error": str(e),
        }
        overall_healthy = False

    # Check Low-Priority SQS Queue
    try:
        # Create temporary client to check low-priority queue
        import aioboto3
        session = aioboto3.Session(
            aws_access_key_id=settings.aws_access_key_id,
            aws_secret_access_key=settings.aws_secret_access_key,
            region_name=settings.aws_region,
        )
        async with session.client("sqs", endpoint_url=settings.aws_endpoint_url) as sqs_client:
            low_priority_attributes = await sqs_client.get_queue_attributes(
                QueueUrl=sqs_service.low_priority_queue_url,
                AttributeNames=["ApproximateNumberOfMessages"],
            )
            dependencies["sqs_low_priority_queue"] = {
                "status": "healthy",
                "queue_url": sqs_service.low_priority_queue_url,
                "approximate_messages": low_priority_attributes.get("Attributes", {}).get(
                    "ApproximateNumberOfMessages", "unknown"
                ),
                "type": "low-priority (Bulk API)",
            }
    except Exception as e:
        dependencies["sqs_low_priority_queue"] = {
            "status": "unhealthy",
            "error": str(e),
        }
        overall_healthy = False

    # Check Salesforce OAuth
    try:
        # Try to get cached token or authenticate
        await salesforce_oauth.get_access_token()
        instance_url = await salesforce_oauth.get_instance_url()
        dependencies["salesforce_oauth"] = {
            "status": "healthy",
            "authenticated": True,
            "instance_url": instance_url,
        }
    except Exception as e:
        dependencies["salesforce_oauth"] = {
            "status": "unhealthy",
            "authenticated": False,
            "error": str(e),
        }
        overall_healthy = False

    # Check Rate Limiter (DynamoDB connectivity)
    try:
        rate_limiter = get_rate_limiter()
        # Just check if it's initialized (actual check happens via DynamoDB service)
        dependencies["rate_limiter"] = {
            "status": "healthy",
            "service": "initialized",
            "tiers": ["per-second", "per-minute", "per-day"],
        }
    except Exception as e:
        dependencies["rate_limiter"] = {
            "status": "unhealthy",
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
            "summary": {
                "total_checks": len(dependencies),
                "healthy": sum(1 for d in dependencies.values() if d.get("status") == "healthy"),
                "unhealthy": sum(1 for d in dependencies.values() if d.get("status") == "unhealthy"),
            },
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
    Comprehensive metrics endpoint.
    Returns application metrics including:
    - Queue status (main + low-priority)
    - Batch accumulator statistics
    - Rate limiter status
    - Overall system health
    """
    try:
        # Get Main SQS queue metrics
        main_queue_attributes = await sqs_service.get_queue_attributes()

        # Get Low-Priority SQS queue metrics
        import aioboto3
        session = aioboto3.Session(
            aws_access_key_id=settings.aws_access_key_id,
            aws_secret_access_key=settings.aws_secret_access_key,
            region_name=settings.aws_region,
        )
        async with session.client("sqs", endpoint_url=settings.aws_endpoint_url) as sqs_client:
            low_priority_attributes = await sqs_client.get_queue_attributes(
                QueueUrl=sqs_service.low_priority_queue_url,
                AttributeNames=["All"],
            )

        # Get batch accumulator stats
        batch_accumulator = get_batch_accumulator()
        batch_stats = await batch_accumulator.get_batch_stats()

        metrics_data = {
            "timestamp": datetime.utcnow().isoformat(),
            "application": {
                "name": settings.app_name,
                "version": settings.app_version,
                "environment": settings.environment,
            },
            "queues": {
                "main_queue": {
                    "url": sqs_service.queue_url,
                    "type": "HIGH/MEDIUM priority (REST API)",
                    "approximate_messages": int(
                        main_queue_attributes.get("ApproximateNumberOfMessages", 0)
                    ),
                    "approximate_messages_not_visible": int(
                        main_queue_attributes.get("ApproximateNumberOfMessagesNotVisible", 0)
                    ),
                    "approximate_messages_delayed": int(
                        main_queue_attributes.get("ApproximateNumberOfMessagesDelayed", 0)
                    ),
                },
                "low_priority_queue": {
                    "url": sqs_service.low_priority_queue_url,
                    "type": "LOW priority (Bulk API)",
                    "approximate_messages": int(
                        low_priority_attributes.get("Attributes", {}).get("ApproximateNumberOfMessages", 0)
                    ),
                    "approximate_messages_not_visible": int(
                        low_priority_attributes.get("Attributes", {}).get("ApproximateNumberOfMessagesNotVisible", 0)
                    ),
                    "approximate_messages_delayed": int(
                        low_priority_attributes.get("Attributes", {}).get("ApproximateNumberOfMessagesDelayed", 0)
                    ),
                },
            },
            "batch_accumulator": {
                "table_name": batch_accumulator.table_name,
                "size_threshold": batch_accumulator.size_threshold,
                "time_threshold_seconds": batch_accumulator.time_threshold,
                "active_batches": len(batch_stats.get("batches", {})),
                "batches": batch_stats.get("batches", {}),
            },
            "rate_limiter": {
                "status": "enabled",
                "limits": {
                    "per_second": 10,
                    "per_minute": 250,
                    "per_day": 15000,
                },
            },
        }

        return JSONResponse(status_code=200, content=metrics_data)

    except Exception as e:
        logger.error(f"Error retrieving metrics: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Failed to retrieve metrics: {str(e)}")
