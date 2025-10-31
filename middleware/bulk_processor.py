"""
Bulk Processor Lambda Handler

Processes low-priority events from SQS in batches using Salesforce Bulk API 2.0.

Architecture:
- Triggered by SQS messages from low-priority queue
- Accumulates events into DynamoDB batch accumulator
- Uses sliding window (size OR time-based) to determine when to submit
- Uses Bulk API 2.0 for efficient processing
- Reduces API call consumption vs. REST API

Event Flow:
1. Lambda triggered by SQS messages (batch of 1-10)
2. Parse Stripe events from message bodies
3. Add events to batch accumulator (DynamoDB)
4. Check if batch is ready (size threshold OR time threshold)
5. If ready: Transform to Salesforce records, submit to Bulk API 2.0
6. Return success/failure for SQS message deletion

Batch Thresholds:
- Size: 200 records (triggers immediate submission)
- Time: 30 seconds (triggers submission if reached, even with fewer records)
"""

import asyncio
import json
from datetime import datetime, timezone
from typing import Dict, Any, List
from collections import defaultdict

from app.services.bulk_api_service import get_bulk_api_service
from app.services.batch_accumulator import get_batch_accumulator, BatchType
from app.models.stripe_events import StripeEvent
from app.models.salesforce_records import SalesforceCustomer
from app.utils.logging_config import get_logger
from app.utils.exceptions import SalesforceAPIException

logger = get_logger(__name__)


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    AWS Lambda handler for bulk processing of low-priority Stripe events.

    Args:
        event: SQS event containing Stripe webhook events
        context: Lambda context object

    Returns:
        Response with batch item failures (for partial batch failures)
    """
    request_id = context.request_id if context else "local"

    logger.info(
        f"Bulk processor invoked",
        extra={
            "request_id": request_id,
            "record_count": len(event.get("Records", []))
        }
    )

    # Run async processing
    try:
        loop = asyncio.get_event_loop()
    except RuntimeError:
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)

    batch_item_failures = loop.run_until_complete(
        process_sqs_batch(event, context)
    )

    logger.info(
        f"Bulk processor completed",
        extra={
            "request_id": request_id,
            "failures": len(batch_item_failures)
        }
    )

    # Return batch item failures for SQS retry
    return {
        "batchItemFailures": batch_item_failures
    }


async def process_sqs_batch(event: Dict[str, Any], context: Any) -> List[Dict[str, str]]:
    """
    Process batch of SQS messages containing Stripe events.

    Flow:
    1. Parse Stripe events from SQS messages
    2. Add each event to batch accumulator (DynamoDB)
    3. Check if batch is ready (size threshold OR time threshold)
    4. If ready: process accumulated batch via Bulk API
    5. Return SQS message IDs for failed events

    Args:
        event: SQS batch event
        context: Lambda context

    Returns:
        List of failed message IDs for retry
    """
    records = event.get("Records", [])

    if not records:
        logger.warning("No records in SQS batch")
        return []

    batch_accumulator = get_batch_accumulator()

    # Parse Stripe events from SQS messages
    stripe_events = []
    message_id_map = {}  # Map event_id -> sqs_message_id for failure tracking

    for record in records:
        try:
            sqs_message_id = record["messageId"]
            body = json.loads(record["body"])

            # Parse Stripe event
            stripe_event = StripeEvent(**body)
            stripe_events.append(stripe_event)
            message_id_map[stripe_event.id] = sqs_message_id

            logger.debug(
                f"Parsed Stripe event from SQS",
                extra={
                    "event_id": stripe_event.id,
                    "event_type": stripe_event.type,
                    "sqs_message_id": sqs_message_id
                }
            )

        except Exception as e:
            logger.error(
                f"Failed to parse SQS message: {str(e)}",
                exc_info=True,
                extra={"sqs_message_id": record.get("messageId")}
            )
            # Don't add to failures - let it retry
            continue

    if not stripe_events:
        logger.warning("No valid Stripe events parsed from batch")
        return []

    # Add events to batch accumulator and process ready batches
    failed_event_ids = []

    for stripe_event in stripe_events:
        try:
            # Determine batch type based on event type
            if stripe_event.type == "customer.updated":
                batch_type = BatchType.CUSTOMER_UPDATE

                # Add event to accumulator
                accumulation_result = await batch_accumulator.add_event(
                    batch_type=batch_type,
                    event=stripe_event.dict()
                )

                logger.info(
                    f"Event added to batch accumulator",
                    extra={
                        "event_id": stripe_event.id,
                        "batch_type": batch_type.value,
                        "batch_ready": accumulation_result["batch_ready"],
                        "record_count": accumulation_result["record_count"],
                        "window_age_seconds": accumulation_result.get("window_age_seconds", 0)
                    }
                )

                # If batch is ready, process it
                if accumulation_result["batch_ready"]:
                    logger.info(
                        f"Batch ready for submission - triggering Bulk API",
                        extra={
                            "batch_type": batch_type.value,
                            "record_count": accumulation_result["record_count"]
                        }
                    )

                    try:
                        # Get accumulated batch
                        batch = await batch_accumulator.get_batch(batch_type)
                        if batch:
                            # Process the batch
                            await process_customer_updates_bulk(batch["events"])

                            # Clear the batch for next cycle
                            await batch_accumulator.submit_batch(batch_type)

                    except Exception as e:
                        logger.error(
                            f"Failed to process accumulated batch: {str(e)}",
                            exc_info=True,
                            extra={"batch_type": batch_type.value}
                        )
                        # Mark current event as failed
                        failed_event_ids.append(stripe_event.id)

            else:
                logger.warning(
                    f"Unsupported bulk event type: {stripe_event.type}",
                    extra={"event_type": stripe_event.type}
                )

        except Exception as e:
            logger.error(
                f"Failed to add event to accumulator: {str(e)}",
                exc_info=True,
                extra={"event_id": stripe_event.id}
            )
            failed_event_ids.append(stripe_event.id)

    # Log batch accumulator stats
    stats = await batch_accumulator.get_batch_stats()
    logger.info(
        f"Batch accumulator stats",
        extra={"stats": stats}
    )

    # Convert failed event IDs to SQS message IDs
    batch_item_failures = [
        {"itemIdentifier": message_id_map[event_id]}
        for event_id in failed_event_ids
        if event_id in message_id_map
    ]

    return batch_item_failures


async def process_customer_updates_bulk(events: List[Dict[str, Any]]) -> None:
    """
    Process customer.updated events in bulk using Bulk API 2.0.

    Args:
        events: List of customer.updated Stripe events (as dictionaries)

    Raises:
        SalesforceAPIException: If bulk processing fails
    """
    logger.info(
        f"Processing customer updates via Bulk API",
        extra={"event_count": len(events)}
    )

    # Transform Stripe events to Salesforce records
    salesforce_records = []

    for event_dict in events:
        try:
            # Parse event if it's a raw dictionary
            if isinstance(event_dict, dict):
                event = StripeEvent(**event_dict)
            else:
                event = event_dict

            customer_data = event.event_object

            # Map to Salesforce Customer record
            salesforce_customer = {
                "Stripe_Customer_ID__c": customer_data.get("id"),
                "Customer_Email__c": customer_data.get("email"),
                "Customer_Name__c": customer_data.get("name"),
                "Customer_Phone__c": customer_data.get("phone"),
                "Default_Payment_Method__c": customer_data.get("invoice_settings", {}).get("default_payment_method")
            }

            # Remove None values
            salesforce_customer = {k: v for k, v in salesforce_customer.items() if v is not None}

            salesforce_records.append(salesforce_customer)

            logger.debug(
                f"Transformed customer event to Salesforce record",
                extra={
                    "event_id": event.id,
                    "customer_id": customer_data.get("id")
                }
            )

        except Exception as e:
            logger.error(
                f"Failed to transform event: {str(e)}",
                exc_info=True
            )
            continue

    if not salesforce_records:
        logger.warning("No valid records to process")
        return

    # Submit to Bulk API
    bulk_service = get_bulk_api_service()

    try:
        result = await bulk_service.upsert_records(
            object_name="Stripe_Customer__c",
            records=salesforce_records,
            external_id_field="Stripe_Customer_ID__c",
            wait_for_completion=True  # Wait for results
        )

        job_id = result["job_id"]
        status = result["status"]
        results = result.get("results", [])

        # Log summary
        records_processed = status.get("numberRecordsProcessed", 0)
        records_failed = status.get("numberRecordsFailed", 0)

        logger.info(
            f"Bulk API job completed",
            extra={
                "job_id": job_id,
                "records_processed": records_processed,
                "records_failed": records_failed,
                "success_rate": f"{(records_processed / len(salesforce_records) * 100):.1f}%"
            }
        )

        # Log failures
        failed_results = [r for r in results if not r.get("success")]
        for failed in failed_results:
            logger.error(
                f"Record failed in bulk job",
                extra={
                    "job_id": job_id,
                    "record": failed,
                    "error": failed.get("error")
                }
            )

        # Raise exception if any records failed (will trigger SQS retry)
        if records_failed > 0:
            raise SalesforceAPIException(
                f"Bulk API job had {records_failed} failed records out of {len(salesforce_records)}"
            )

    except Exception as e:
        logger.error(
            f"Bulk API processing failed: {str(e)}",
            exc_info=True,
            extra={"record_count": len(salesforce_records)}
        )
        raise


# For local testing
if __name__ == "__main__":
    # Mock event for testing
    test_event = {
        "Records": [
            {
                "messageId": "test-message-1",
                "body": json.dumps({
                    "id": "evt_test_123",
                    "type": "customer.updated",
                    "created": 1234567890,
                    "livemode": False,
                    "data": {
                        "object": {
                            "id": "cus_test_123",
                            "email": "test@example.com",
                            "name": "Test Customer",
                            "phone": "+1234567890"
                        }
                    }
                })
            }
        ]
    }

    class MockContext:
        request_id = "local-test"
        function_name = "bulk-processor-test"

    result = lambda_handler(test_event, MockContext())
    print(f"Result: {result}")
