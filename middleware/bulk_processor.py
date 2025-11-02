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
from app.models.salesforce_records import SalesforceCustomer, SalesforceContact
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
    request_id = context.aws_request_id if context else "local"

    logger.info(
        f"[BULK_PROCESSOR_START] Lambda invocation received",
        extra={
            "request_id": request_id,
            "record_count": len(event.get("Records", [])),
            "function_name": context.function_name if context else "local",
            "memory_limit": context.memory_limit_in_mb if context else "N/A"
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
        f"[BULK_PROCESSOR_END] Lambda invocation completed",
        extra={
            "request_id": request_id,
            "batch_item_failures": len(batch_item_failures),
            "status": "success" if len(batch_item_failures) == 0 else "partial_failure"
        }
    )

    # Return batch item failures for SQS retry
    return {
        "batchItemFailures": batch_item_failures
    }


async def process_ready_batches(batch_accumulator) -> None:
    """
    Proactively check for and process any batches that are ready.

    This ensures batches are processed as soon as the time/size threshold is exceeded,
    rather than waiting for the next SQS event to arrive.

    Called at the start of every Lambda invocation to drain any accumulated batches.
    """
    try:
        stats = await batch_accumulator.get_batch_stats()

        for batch_type_str, batch_stats in stats.get("batches", {}).items():
            if batch_stats.get("ready"):
                logger.critical(
                    f"[BATCH_READY_PROACTIVE] Found ready batch on invocation start - processing immediately",
                    extra={
                        "batch_type": batch_type_str,
                        "record_count": batch_stats.get("record_count"),
                        "window_age_seconds": batch_stats.get("window_age_seconds", 0)
                    }
                )

                try:
                    # Convert batch_type_str back to BatchType enum
                    batch_type = BatchType[batch_type_str.upper()]

                    # Get the ready batch
                    batch = await batch_accumulator.get_batch(batch_type)

                    if batch and batch.get("events"):
                        logger.info(
                            f"[BATCH_PROACTIVE_PROCESSING] Processing proactively detected ready batch",
                            extra={
                                "batch_type": batch_type_str,
                                "event_count": len(batch["events"])
                            }
                        )

                        # Process the batch
                        await process_customer_updates_bulk(batch["events"])

                        # Clear the batch for next cycle
                        await batch_accumulator.submit_batch(batch_type)

                        logger.info(
                            f"[BATCH_PROACTIVE_COMPLETE] Ready batch processed and cleared",
                            extra={"batch_type": batch_type_str}
                        )
                    else:
                        logger.warning(
                            f"[BATCH_PROACTIVE_ERROR] Ready batch not found or empty on retrieval",
                            extra={"batch_type": batch_type_str}
                        )

                except Exception as e:
                    logger.error(
                        f"[BATCH_PROACTIVE_FAILED] Failed to process ready batch: {str(e)}",
                        exc_info=True,
                        extra={
                            "batch_type": batch_type_str,
                            "error": str(e)
                        }
                    )
                    # Don't raise - continue processing other batches

    except Exception as e:
        logger.error(
            f"[BATCH_PROACTIVE_CHECK_ERROR] Error checking for ready batches: {str(e)}",
            exc_info=True
        )
        # Don't raise - continue with normal SQS processing


async def process_sqs_batch(event: Dict[str, Any], context: Any) -> List[Dict[str, str]]:
    """
    Process batch of SQS messages containing Stripe events.

    Flow:
    1. Check for and process any ready batches from previous invocations (proactive)
    2. Parse Stripe events from SQS messages
    3. Add each event to batch accumulator (DynamoDB)
    4. Check if batch is ready (size threshold OR time threshold)
    5. If ready: process accumulated batch via Bulk API
    6. Return SQS message IDs for failed events

    Args:
        event: SQS batch event
        context: Lambda context

    Returns:
        List of failed message IDs for retry
    """
    records = event.get("Records", [])

    logger.info(
        f"[BATCH_PROCESSING_START] Processing SQS batch",
        extra={
            "record_count": len(records),
            "event_keys": list(event.keys()) if isinstance(event, dict) else "not_a_dict"
        }
    )

    batch_accumulator = get_batch_accumulator()
    logger.debug(f"[BATCH_ACCUMULATOR] Initialized batch accumulator")

    # Proactively process any ready batches from previous invocations
    # This ensures batches don't wait indefinitely for a new SQS event
    await process_ready_batches(batch_accumulator)

    # If no SQS records, we're done after processing ready batches
    if not records:
        logger.info("[BATCH_PROCESSING_INFO] No new SQS records, ready batches processed")
        return []

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

    logger.info(
        f"[STRIPE_EVENTS_PARSED] Parsed Stripe events from SQS",
        extra={
            "parsed_count": len(stripe_events),
            "failed_count": len(records) - len(stripe_events),
            "event_types": list(set(e.type for e in stripe_events))
        }
    )

    if not stripe_events:
        logger.warning("[BATCH_PROCESSING_ERROR] No valid Stripe events parsed from batch")
        return []

    # Add events to batch accumulator and process ready batches
    failed_event_ids = []
    logger.info(
        f"[BATCH_ACCUMULATION_START] Beginning event accumulation",
        extra={"stripe_event_count": len(stripe_events)}
    )

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
                    f"[BATCH_ACCUMULATION_STEP] Event added to batch accumulator",
                    extra={
                        "event_id": stripe_event.id,
                        "customer_id": stripe_event.event_object.get("id", "unknown"),
                        "batch_type": batch_type.value,
                        "batch_ready": accumulation_result["batch_ready"],
                        "record_count": accumulation_result["record_count"],
                        "window_age_seconds": accumulation_result.get("window_age_seconds", 0),
                        "size_threshold": 200,
                        "time_threshold": 30
                    }
                )

                # If batch is ready, process it
                if accumulation_result["batch_ready"]:
                    logger.critical(
                        f"[BATCH_READY_TRIGGERED] Batch threshold reached - submitting to Bulk API!",
                        extra={
                            "batch_type": batch_type.value,
                            "record_count": accumulation_result["record_count"],
                            "reason": "size" if accumulation_result["record_count"] >= 200 else "time_window",
                            "window_age_seconds": accumulation_result.get("window_age_seconds", 0)
                        }
                    )

                    try:
                        # Get accumulated batch
                        batch = await batch_accumulator.get_batch(batch_type)
                        logger.info(
                            f"[BATCH_RETRIEVAL] Retrieved batch from accumulator",
                            extra={
                                "batch_type": batch_type.value,
                                "batch_found": batch is not None,
                                "event_count": len(batch["events"]) if batch else 0
                            }
                        )

                        if batch:
                            logger.info(
                                f"[BATCH_SUBMISSION_START] Beginning customer update bulk processing",
                                extra={
                                    "batch_type": batch_type.value,
                                    "event_count": len(batch["events"]),
                                    "batch_id": batch.get("batch_id")
                                }
                            )

                            # Process the batch
                            await process_customer_updates_bulk(batch["events"])

                            logger.info(
                                f"[BATCH_SUBMISSION_COMPLETE] Bulk API processing completed",
                                extra={"batch_type": batch_type.value}
                            )

                            # Clear the batch for next cycle
                            await batch_accumulator.submit_batch(batch_type)
                            logger.info(
                                f"[BATCH_CLEARED] Batch cleared for next cycle",
                                extra={"batch_type": batch_type.value}
                            )
                        else:
                            logger.warning(
                                f"[BATCH_RETRIEVAL_ERROR] Batch marked ready but not found on retrieval",
                                extra={"batch_type": batch_type.value}
                            )

                    except Exception as e:
                        logger.error(
                            f"[BATCH_PROCESSING_FAILED] Failed to process accumulated batch: {str(e)}",
                            exc_info=True,
                            extra={
                                "batch_type": batch_type.value,
                                "error": str(e)
                            }
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
    logger.critical(
        f"[BULK_API_TRANSFORM_START] Processing {len(events)} customer updates via Bulk API 2.0",
        extra={
            "event_count": len(events),
            "stripe_api_version": "v1"
        }
    )

    # Transform Stripe events to Salesforce records
    customer_records = []
    contact_records = []

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
            customer_records.append(salesforce_customer)

            # Map to Salesforce Contact record
            # Parse name into FirstName and LastName
            customer_name = customer_data.get("name", "")
            first_name = None
            last_name = None

            if customer_name:
                name_parts = customer_name.strip().split(None, 1)  # Split on first whitespace
                if len(name_parts) == 1:
                    last_name = name_parts[0]
                elif len(name_parts) >= 2:
                    first_name = name_parts[0]
                    last_name = name_parts[1]

            salesforce_contact = {
                "Stripe_Customer_ID__c": customer_data.get("id"),
                "Email": customer_data.get("email"),
                "FirstName": first_name,
                "LastName": last_name or "Unknown",  # LastName is required on Contact
                "Phone": customer_data.get("phone")
            }

            # Remove None values but keep LastName as it's required
            salesforce_contact = {k: v for k, v in salesforce_contact.items() if v is not None}
            contact_records.append(salesforce_contact)

            logger.debug(
                f"[RECORD_TRANSFORM] Transformed customer event to Salesforce records",
                extra={
                    "event_id": event.id,
                    "customer_id": customer_data.get("id"),
                    "customer_fields": len(salesforce_customer),
                    "contact_fields": len(salesforce_contact)
                }
            )

        except Exception as e:
            logger.error(
                f"[TRANSFORM_ERROR] Failed to transform event: {str(e)}",
                exc_info=True,
                extra={"event": event_dict}
            )
            continue

    logger.critical(
        f"[BULK_API_TRANSFORM_COMPLETE] Transformation complete - {len(customer_records)} customer and {len(contact_records)} contact records ready",
        extra={
            "input_events": len(events),
            "customer_records": len(customer_records),
            "contact_records": len(contact_records),
            "customer_transform_rate": f"{(len(customer_records)/len(events)*100):.1f}%" if events else "0%",
            "contact_transform_rate": f"{(len(contact_records)/len(events)*100):.1f}%" if events else "0%"
        }
    )

    # Deduplicate customer records by Stripe_Customer_ID__c, keeping only the latest version
    # This prevents "DUPLICATE_VALUE" errors when the same customer appears multiple times in a batch
    customer_by_id = {}
    for record in customer_records:
        customer_id = record.get("Stripe_Customer_ID__c")
        if customer_id:
            customer_by_id[customer_id] = record  # Last occurrence wins (most recent update)

    customer_records = list(customer_by_id.values())

    # Deduplicate contact records by Stripe_Customer_ID__c
    contact_by_id = {}
    for record in contact_records:
        customer_id = record.get("Stripe_Customer_ID__c")
        if customer_id:
            contact_by_id[customer_id] = record  # Last occurrence wins (most recent update)

    contact_records = list(contact_by_id.values())

    if len(customer_records) < len(events):
        dedup_count = len(events) - len(customer_records)
        logger.info(
            f"[BULK_API_DEDUPLICATION] Removed duplicate customer records",
            extra={
                "original_count": len(events),
                "deduplicated_count": len(customer_records),
                "duplicates_removed": dedup_count
            }
        )

    if not customer_records:
        logger.warning("[BULK_API_ERROR] No valid customer records to process - aborting Bulk API submission")
        return

    # Submit to Bulk API
    bulk_service = get_bulk_api_service()
    customer_failed = False
    contact_failed = False

    # Step 1: Submit Stripe_Customer__c records
    try:
        logger.critical(
            f"[BULK_API_JOB_CREATE] Creating Bulk API job for Stripe_Customer__c upsert",
            extra={
                "object_name": "Stripe_Customer__c",
                "operation": "upsert",
                "external_id_field": "Stripe_Customer_ID__c",
                "record_count": len(customer_records),
                "wait_for_completion": True
            }
        )

        result = await bulk_service.upsert_records(
            object_name="Stripe_Customer__c",
            records=customer_records,
            external_id_field="Stripe_Customer_ID__c",
            wait_for_completion=True  # Wait for results
        )

        job_id = result["job_id"]
        status = result["status"]
        results = result.get("results", [])

        # Log summary
        records_processed = status.get("numberRecordsProcessed", 0)
        records_failed = status.get("numberRecordsFailed", 0)

        logger.critical(
            f"[BULK_API_JOB_COMPLETED] Stripe_Customer__c bulk job completed!",
            extra={
                "job_id": job_id,
                "job_state": status.get("state", "unknown"),
                "records_submitted": len(customer_records),
                "records_processed": records_processed,
                "records_failed": records_failed,
                "success_rate": f"{(records_processed / len(customer_records) * 100):.1f}%" if customer_records else "0%",
                "salesforce_instance": status.get("object", "unknown")
            }
        )

        # Log failures
        failed_results = [r for r in results if not r.get("success")]
        if failed_results:
            logger.warning(
                f"[BULK_API_FAILURES] {len(failed_results)} records failed in Stripe_Customer__c bulk job",
                extra={
                    "job_id": job_id,
                    "failed_count": len(failed_results)
                }
            )
            for idx, failed in enumerate(failed_results[:5]):  # Log first 5 failures
                logger.error(
                    f"[BULK_API_FAILURE_DETAIL] Record #{idx+1} failed in bulk job",
                    extra={
                        "job_id": job_id,
                        "record": failed,
                        "error": failed.get("error", "Unknown error")
                    }
                )

        # Mark as failed if any records failed
        if records_failed > 0:
            customer_failed = True
            logger.error(
                f"[BULK_API_CUSTOMER_FAILED] Stripe_Customer__c job had failures",
                extra={
                    "job_id": job_id,
                    "failed_count": records_failed,
                    "total_records": len(customer_records)
                }
            )

    except Exception as e:
        logger.error(
            f"[BULK_API_ERROR] Stripe_Customer__c processing failed: {str(e)}",
            exc_info=True,
            extra={
                "record_count": len(customer_records),
                "error_type": type(e).__name__
            }
        )
        customer_failed = True

    # Step 2: Submit Contact records (even if customer submission had issues)
    if contact_records:
        try:
            logger.critical(
                f"[BULK_API_JOB_CREATE] Creating Bulk API job for Contact upsert",
                extra={
                    "object_name": "Contact",
                    "operation": "upsert",
                    "external_id_field": "Stripe_Customer_ID__c",
                    "record_count": len(contact_records),
                    "wait_for_completion": True
                }
            )

            result = await bulk_service.upsert_records(
                object_name="Contact",
                records=contact_records,
                external_id_field="Stripe_Customer_ID__c",
                wait_for_completion=True  # Wait for results
            )

            job_id = result["job_id"]
            status = result["status"]
            results = result.get("results", [])

            # Log summary
            records_processed = status.get("numberRecordsProcessed", 0)
            records_failed = status.get("numberRecordsFailed", 0)

            logger.critical(
                f"[BULK_API_JOB_COMPLETED] Contact bulk job completed!",
                extra={
                    "job_id": job_id,
                    "job_state": status.get("state", "unknown"),
                    "records_submitted": len(contact_records),
                    "records_processed": records_processed,
                    "records_failed": records_failed,
                    "success_rate": f"{(records_processed / len(contact_records) * 100):.1f}%" if contact_records else "0%",
                    "salesforce_instance": status.get("object", "unknown")
                }
            )

            # Log failures
            failed_results = [r for r in results if not r.get("success")]
            if failed_results:
                logger.warning(
                    f"[BULK_API_FAILURES] {len(failed_results)} records failed in Contact bulk job",
                    extra={
                        "job_id": job_id,
                        "failed_count": len(failed_results)
                    }
                )
                for idx, failed in enumerate(failed_results[:5]):  # Log first 5 failures
                    logger.error(
                        f"[BULK_API_FAILURE_DETAIL] Contact record #{idx+1} failed in bulk job",
                        extra={
                            "job_id": job_id,
                            "record": failed,
                            "error": failed.get("error", "Unknown error")
                        }
                    )

            # Mark as failed if any records failed
            if records_failed > 0:
                contact_failed = True
                logger.error(
                    f"[BULK_API_CONTACT_FAILED] Contact job had failures",
                    extra={
                        "job_id": job_id,
                        "failed_count": records_failed,
                        "total_records": len(contact_records)
                    }
                )

        except Exception as e:
            logger.error(
                f"[BULK_API_ERROR] Contact processing failed: {str(e)}",
                exc_info=True,
                extra={
                    "record_count": len(contact_records),
                    "error_type": type(e).__name__
                }
            )
            contact_failed = True

    # Raise exception if customer submission failed (critical)
    if customer_failed:
        raise SalesforceAPIException(
            f"Bulk API job(s) had failures: Customer records failed"
        )

    # Log warning if contact submission failed but customer succeeded
    if contact_failed:
        logger.warning(
            f"[BULK_API_WARNING] Contact submission had failures but customer submission succeeded"
        )


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
        aws_request_id = "local-test"
        function_name = "bulk-processor-test"
        memory_limit_in_mb = 1024

    result = lambda_handler(test_event, MockContext())
    print(f"Result: {result}")
