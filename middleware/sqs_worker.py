"""
AWS Lambda SQS Worker

This Lambda function processes Stripe webhook events from SQS queue.
It's triggered automatically when messages appear in the SQS queue.

Event Flow:
1. Stripe sends webhook → API Gateway → Lambda (lambda_handler.py) → SQS
2. SQS triggers this worker Lambda
3. Worker processes event → Routes to handler → Updates Salesforce
"""

import asyncio
import json
import os
from typing import Any, Dict, List

from app.config import settings
from app.handlers.event_router import EventRouter
from app.services.dynamodb_service import dynamodb_service
from app.utils.logging_config import get_logger, setup_logging

# Setup logging for Lambda
setup_logging(log_level=os.getenv("LOG_LEVEL", "INFO"))
logger = get_logger(__name__)


async def process_event(event_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Process a single Stripe event.

    Args:
        event_data: Stripe event payload from SQS message

    Returns:
        Processing result with status and details
    """
    event_id = event_data.get("id", "unknown")
    event_type = event_data.get("type", "unknown")

    logger.info(
        f"Processing Stripe event",
        extra={"event_id": event_id, "event_type": event_type},
    )

    try:
        # Initialize DynamoDB connection if not already connected
        if not dynamodb_service.is_connected():
            await dynamodb_service.connect()

        # Route event to appropriate handler
        router = EventRouter()
        result = await router.route_event(event_data)

        logger.info(
            f"Event processed successfully",
            extra={
                "event_id": event_id,
                "event_type": event_type,
                "result": result,
            },
        )

        return {
            "status": "success",
            "event_id": event_id,
            "event_type": event_type,
            "result": result,
        }

    except Exception as e:
        logger.error(
            f"Failed to process event: {e}",
            extra={
                "event_id": event_id,
                "event_type": event_type,
                "error": str(e),
                "error_type": type(e).__name__,
            },
        )

        # Re-raise to trigger DLQ after retries
        raise


async def process_sqs_records(records: List[Dict[str, Any]]) -> Dict[str, Any]:
    """
    Process multiple SQS records (batch processing).

    Args:
        records: List of SQS records from Lambda event

    Returns:
        Batch processing results
    """
    results = {
        "successful": [],
        "failed": [],
        "total": len(records),
    }

    for record in records:
        try:
            # Parse SQS message body (contains Stripe event)
            message_body = json.loads(record["body"])

            # Process the event
            result = await process_event(message_body)
            results["successful"].append(
                {"message_id": record["messageId"], "result": result}
            )

        except Exception as e:
            logger.error(
                f"Failed to process SQS record: {e}",
                extra={
                    "message_id": record.get("messageId"),
                    "error": str(e),
                },
            )
            results["failed"].append(
                {
                    "message_id": record["messageId"],
                    "error": str(e),
                    "error_type": type(e).__name__,
                }
            )

    logger.info(
        f"Batch processing complete",
        extra={
            "total": results["total"],
            "successful": len(results["successful"]),
            "failed": len(results["failed"]),
        },
    )

    return results


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    AWS Lambda handler for SQS-triggered event processing.

    This function is triggered automatically when messages are added to the SQS queue.
    Lambda polls the queue and invokes this handler with batches of messages.

    Args:
        event: Lambda event containing SQS records
        context: Lambda context with runtime information

    Returns:
        Processing results and any failed message IDs (for partial batch failures)

    Note:
        Failed messages will be returned to SQS and retried.
        After max retries, they go to the Dead Letter Queue (DLQ).
    """
    logger.info(
        "SQS Worker Lambda invoked",
        extra={
            "request_id": context.aws_request_id,
            "function_name": context.function_name,
            "record_count": len(event.get("Records", [])),
        },
    )

    try:
        # Get SQS records from event
        records = event.get("Records", [])

        if not records:
            logger.warning("No SQS records found in event")
            return {"statusCode": 200, "body": json.dumps({"message": "No records"})}

        # Process records asynchronously
        results = asyncio.run(process_sqs_records(records))

        # Prepare response
        response = {
            "statusCode": 200,
            "body": json.dumps(results),
        }

        # If there are failures, return batch item failures for retry
        # This tells SQS which messages to retry (partial batch failure)
        if results["failed"]:
            failed_message_ids = [f["message_id"] for f in results["failed"]]
            response["batchItemFailures"] = [
                {"itemIdentifier": msg_id} for msg_id in failed_message_ids
            ]

            logger.warning(
                f"Partial batch failure",
                extra={
                    "failed_count": len(failed_message_ids),
                    "failed_message_ids": failed_message_ids,
                },
            )

        return response

    except Exception as e:
        logger.error(
            f"SQS Worker Lambda failed: {e}",
            extra={
                "request_id": context.request_id,
                "error": str(e),
                "error_type": type(e).__name__,
            },
        )

        # Return all messages as failed for retry
        return {
            "statusCode": 500,
            "body": json.dumps({"error": str(e)}),
            "batchItemFailures": [
                {"itemIdentifier": record["messageId"]}
                for record in event.get("Records", [])
            ],
        }


# For local testing
if __name__ == "__main__":
    # Test event structure
    test_event = {
        "Records": [
            {
                "messageId": "test-123",
                "body": json.dumps(
                    {
                        "id": "evt_test_123",
                        "type": "payment_intent.succeeded",
                        "data": {
                            "object": {
                                "id": "pi_test_123",
                                "amount": 1000,
                                "currency": "usd",
                                "status": "succeeded",
                            }
                        },
                    }
                ),
            }
        ]
    }

    class TestContext:
        request_id = "test-request-id"
        function_name = "test-function"
        memory_limit_in_mb = 128

    result = lambda_handler(test_event, TestContext())
    print(json.dumps(result, indent=2))
