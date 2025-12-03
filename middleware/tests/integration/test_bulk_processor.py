"""
Integration tests for the Bulk Processor Lambda.
"""
import json
import pytest
from unittest.mock import patch, Mock, AsyncMock
from datetime import datetime, timezone, timedelta
from typing import List, Dict, Any

from app.models.stripe_events import StripeEvent, EventPriority
from app.services.batch_accumulator import BatchType
from bulk_processor import lambda_handler, process_customer_updates_bulk


class TestBulkProcessor:
    """Test the Bulk Processor Lambda function."""

    @pytest.mark.asyncio
    async def test_batch_accumulation_below_threshold(
        self,
        stripe_event_factory,
        mock_lambda_context,
        batch_accumulator,
        mock_bulk_api_service,
        test_settings,
    ):
        """Test that events are accumulated when below threshold."""
        # Create a small batch of customer.updated events (below threshold)
        events = [
            stripe_event_factory("customer.updated", customer_id=f"cus_{i:03d}")
            for i in range(5)  # Below the test threshold of 10
        ]

        # Create SQS event
        sqs_event = {
            "Records": [
                {
                    "messageId": f"msg-{i:03d}",
                    "receiptHandle": f"receipt-{i:03d}",
                    "body": json.dumps(event),
                    "attributes": {
                        "ApproximateReceiveCount": "1",
                    },
                }
                for i, event in enumerate(events)
            ]
        }

        with patch("bulk_processor.settings", test_settings), \
             patch("bulk_processor.get_batch_accumulator") as mock_get_accumulator, \
             patch("bulk_processor.get_bulk_api_service") as mock_get_bulk:

            # Configure mocks
            mock_get_accumulator.return_value = batch_accumulator
            mock_get_bulk.return_value = mock_bulk_api_service

            # Process events
            result = await lambda_handler(sqs_event, mock_lambda_context)

            # Verify no batch failures
            assert result == {"batchItemFailures": []}

            # Verify events were accumulated but not processed
            stats = await batch_accumulator.get_batch_stats()
            assert BatchType.CUSTOMER_UPDATE.value in stats["batches"]
            assert stats["batches"][BatchType.CUSTOMER_UPDATE.value]["count"] == 5

            # Verify Bulk API was NOT called (batch not ready)
            mock_bulk_api_service.upsert_records.assert_not_called()

    @pytest.mark.asyncio
    async def test_batch_processing_size_threshold(
        self,
        stripe_event_factory,
        mock_lambda_context,
        batch_accumulator,
        mock_bulk_api_service,
        test_settings,
    ):
        """Test that batch is processed when size threshold is reached."""
        # First, pre-populate the accumulator with 8 events
        for i in range(8):
            event = stripe_event_factory("customer.updated", customer_id=f"cus_pre_{i:03d}")
            await batch_accumulator.add_event(BatchType.CUSTOMER_UPDATE, event)

        # Create 5 more events that will trigger the threshold (13 total > 10 threshold)
        new_events = [
            stripe_event_factory("customer.updated", customer_id=f"cus_new_{i:03d}")
            for i in range(5)
        ]

        sqs_event = {
            "Records": [
                {
                    "messageId": f"msg-{i:03d}",
                    "receiptHandle": f"receipt-{i:03d}",
                    "body": json.dumps(event),
                    "attributes": {
                        "ApproximateReceiveCount": "1",
                    },
                }
                for i, event in enumerate(new_events)
            ]
        }

        with patch("bulk_processor.settings", test_settings), \
             patch("bulk_processor.get_batch_accumulator") as mock_get_accumulator, \
             patch("bulk_processor.get_bulk_api_service") as mock_get_bulk:

            # Configure mocks
            mock_get_accumulator.return_value = batch_accumulator
            mock_get_bulk.return_value = mock_bulk_api_service

            # Process events
            result = await lambda_handler(sqs_event, mock_lambda_context)

            # Verify no batch failures
            assert result == {"batchItemFailures": []}

            # Verify Bulk API was called
            mock_bulk_api_service.upsert_records.assert_called_once()

            # Verify the batch was cleared after processing
            stats = await batch_accumulator.get_batch_stats()
            if BatchType.CUSTOMER_UPDATE.value in stats["batches"]:
                assert stats["batches"][BatchType.CUSTOMER_UPDATE.value]["count"] < 10

    @pytest.mark.asyncio
    async def test_batch_processing_time_threshold(
        self,
        stripe_event_factory,
        mock_lambda_context,
        batch_accumulator,
        mock_bulk_api_service,
        test_settings,
    ):
        """Test that batch is processed when time threshold is reached."""
        # Create an old window that exceeds time threshold
        old_timestamp = datetime.now(timezone.utc) - timedelta(seconds=10)  # > 5 second threshold

        # Manually create an old batch
        batch_item = {
            "pk": BatchType.CUSTOMER_UPDATE.value,
            "sk": old_timestamp.isoformat(),
            "events": [
                stripe_event_factory("customer.updated", customer_id=f"cus_old_{i:03d}")
                for i in range(3)  # Only 3 events, below size threshold
            ],
            "created_at": old_timestamp.isoformat(),
            "window_start": old_timestamp.isoformat(),
            "record_count": 3,
            "ttl": int((datetime.now(timezone.utc) + timedelta(days=1)).timestamp())
        }

        await batch_accumulator.dynamodb.put_item(
            table_name=batch_accumulator.table_name,
            item=batch_item
        )

        # Create one new event that will trigger time threshold check
        new_event = stripe_event_factory("customer.updated", customer_id="cus_trigger")

        sqs_event = {
            "Records": [
                {
                    "messageId": "msg-001",
                    "receiptHandle": "receipt-001",
                    "body": json.dumps(new_event),
                    "attributes": {
                        "ApproximateReceiveCount": "1",
                    },
                }
            ]
        }

        with patch("bulk_processor.settings", test_settings), \
             patch("bulk_processor.get_batch_accumulator") as mock_get_accumulator, \
             patch("bulk_processor.get_bulk_api_service") as mock_get_bulk:

            # Configure mocks
            mock_get_accumulator.return_value = batch_accumulator
            mock_get_bulk.return_value = mock_bulk_api_service

            # Process event
            result = await lambda_handler(sqs_event, mock_lambda_context)

            # Verify no batch failures
            assert result == {"batchItemFailures": []}

            # Verify Bulk API was called due to time threshold
            mock_bulk_api_service.upsert_records.assert_called()

    @pytest.mark.asyncio
    async def test_multiple_batch_types(
        self,
        stripe_event_factory,
        mock_lambda_context,
        batch_accumulator,
        mock_bulk_api_service,
        test_settings,
    ):
        """Test processing multiple batch types in parallel."""
        # Create different types of low-priority events
        events = []

        # Customer updates
        for i in range(12):  # Exceeds threshold
            events.append(stripe_event_factory("customer.updated", customer_id=f"cus_{i:03d}"))

        # Future: Add other batch types when implemented
        # for i in range(12):
        #     events.append(stripe_event_factory("product.updated", product_id=f"prod_{i:03d}"))

        sqs_event = {
            "Records": [
                {
                    "messageId": f"msg-{i:03d}",
                    "receiptHandle": f"receipt-{i:03d}",
                    "body": json.dumps(event),
                    "attributes": {
                        "ApproximateReceiveCount": "1",
                    },
                }
                for i, event in enumerate(events)
            ]
        }

        with patch("bulk_processor.settings", test_settings), \
             patch("bulk_processor.get_batch_accumulator") as mock_get_accumulator, \
             patch("bulk_processor.get_bulk_api_service") as mock_get_bulk:

            # Configure mocks
            mock_get_accumulator.return_value = batch_accumulator
            mock_get_bulk.return_value = mock_bulk_api_service

            # Process events
            result = await lambda_handler(sqs_event, mock_lambda_context)

            # Verify no batch failures
            assert result == {"batchItemFailures": []}

            # Verify Bulk API was called for customer updates
            assert mock_bulk_api_service.upsert_records.call_count >= 1

    @pytest.mark.asyncio
    async def test_bulk_api_failure_handling(
        self,
        stripe_event_factory,
        mock_lambda_context,
        batch_accumulator,
        mock_bulk_api_service,
        test_settings,
    ):
        """Test handling of Bulk API failures."""
        # Create enough events to trigger processing
        events = [
            stripe_event_factory("customer.updated", customer_id=f"cus_{i:03d}")
            for i in range(12)
        ]

        sqs_event = {
            "Records": [
                {
                    "messageId": f"msg-{i:03d}",
                    "receiptHandle": f"receipt-{i:03d}",
                    "body": json.dumps(event),
                    "attributes": {
                        "ApproximateReceiveCount": "1",
                    },
                }
                for i, event in enumerate(events)
            ]
        }

        # Configure Bulk API to fail
        mock_bulk_api_service.upsert_records = AsyncMock(
            side_effect=Exception("Bulk API Error")
        )

        with patch("bulk_processor.settings", test_settings), \
             patch("bulk_processor.get_batch_accumulator") as mock_get_accumulator, \
             patch("bulk_processor.get_bulk_api_service") as mock_get_bulk, \
             patch("bulk_processor.logger") as mock_logger:

            # Configure mocks
            mock_get_accumulator.return_value = batch_accumulator
            mock_get_bulk.return_value = mock_bulk_api_service

            # Process events
            result = await lambda_handler(sqs_event, mock_lambda_context)

            # All messages should be marked as failed for retry
            assert len(result["batchItemFailures"]) == 12

            # Verify error was logged
            mock_logger.error.assert_called()

    @pytest.mark.asyncio
    async def test_partial_bulk_api_failure(
        self,
        stripe_event_factory,
        mock_lambda_context,
        batch_accumulator,
        mock_bulk_api_service,
        test_settings,
    ):
        """Test handling partial failures in Bulk API."""
        # Create events
        events = [
            stripe_event_factory("customer.updated", customer_id=f"cus_{i:03d}")
            for i in range(12)
        ]

        sqs_event = {
            "Records": [
                {
                    "messageId": f"msg-{i:03d}",
                    "receiptHandle": f"receipt-{i:03d}",
                    "body": json.dumps(event),
                    "attributes": {
                        "ApproximateReceiveCount": "1",
                    },
                }
                for i, event in enumerate(events)
            ]
        }

        # Configure Bulk API to return partial failures
        mock_bulk_api_service.upsert_records = AsyncMock(return_value={
            "job_id": "750XX000001234",
            "status": "JobComplete",
            "results": {
                "processed": 10,
                "failed": 2,
                "failures": [
                    {"id": "cus_005", "error": "DUPLICATE_VALUE"},
                    {"id": "cus_008", "error": "INVALID_FIELD"},
                ]
            }
        })

        with patch("bulk_processor.settings", test_settings), \
             patch("bulk_processor.get_batch_accumulator") as mock_get_accumulator, \
             patch("bulk_processor.get_bulk_api_service") as mock_get_bulk, \
             patch("bulk_processor.logger") as mock_logger:

            # Configure mocks
            mock_get_accumulator.return_value = batch_accumulator
            mock_get_bulk.return_value = mock_bulk_api_service

            # Process events
            result = await lambda_handler(sqs_event, mock_lambda_context)

            # Only failed records should be marked for retry
            assert len(result["batchItemFailures"]) == 2

            # Verify warning was logged
            mock_logger.warning.assert_called()

    @pytest.mark.asyncio
    async def test_batch_stats_tracking(
        self,
        stripe_event_factory,
        mock_lambda_context,
        batch_accumulator,
        mock_bulk_api_service,
        test_settings,
    ):
        """Test that batch statistics are properly tracked."""
        # Process events in multiple rounds
        for round_num in range(3):
            events = [
                stripe_event_factory(
                    "customer.updated",
                    customer_id=f"cus_r{round_num}_{i:03d}"
                )
                for i in range(4)  # Below threshold
            ]

            sqs_event = {
                "Records": [
                    {
                        "messageId": f"msg-r{round_num}-{i:03d}",
                        "receiptHandle": f"receipt-r{round_num}-{i:03d}",
                        "body": json.dumps(event),
                        "attributes": {
                            "ApproximateReceiveCount": "1",
                        },
                    }
                    for i, event in enumerate(events)
                ]
            }

            with patch("bulk_processor.settings", test_settings), \
                 patch("bulk_processor.get_batch_accumulator") as mock_get_accumulator, \
                 patch("bulk_processor.get_bulk_api_service") as mock_get_bulk:

                mock_get_accumulator.return_value = batch_accumulator
                mock_get_bulk.return_value = mock_bulk_api_service

                await lambda_handler(sqs_event, mock_lambda_context)

        # Check accumulated stats
        stats = await batch_accumulator.get_batch_stats()
        assert BatchType.CUSTOMER_UPDATE.value in stats["batches"]
        batch_stats = stats["batches"][BatchType.CUSTOMER_UPDATE.value]

        # Should have accumulated 12 events (3 rounds × 4 events)
        assert batch_stats["count"] == 12

        # Verify window age is tracked
        assert "window_age_seconds" in batch_stats
        assert batch_stats["window_age_seconds"] >= 0

    @pytest.mark.asyncio
    async def test_concurrent_batch_processing(
        self,
        stripe_event_factory,
        mock_lambda_context,
        batch_accumulator,
        mock_bulk_api_service,
        test_settings,
    ):
        """Test concurrent processing of multiple batches."""
        import asyncio

        # Simulate concurrent Lambda invocations
        async def process_batch(batch_id: int):
            events = [
                stripe_event_factory(
                    "customer.updated",
                    customer_id=f"cus_b{batch_id}_{i:03d}"
                )
                for i in range(3)
            ]

            sqs_event = {
                "Records": [
                    {
                        "messageId": f"msg-b{batch_id}-{i:03d}",
                        "receiptHandle": f"receipt-b{batch_id}-{i:03d}",
                        "body": json.dumps(event),
                        "attributes": {
                            "ApproximateReceiveCount": "1",
                        },
                    }
                    for i, event in enumerate(events)
                ]
            }

            with patch("bulk_processor.settings", test_settings), \
                 patch("bulk_processor.get_batch_accumulator") as mock_get_accumulator, \
                 patch("bulk_processor.get_bulk_api_service") as mock_get_bulk:

                mock_get_accumulator.return_value = batch_accumulator
                mock_get_bulk.return_value = mock_bulk_api_service

                return await lambda_handler(sqs_event, mock_lambda_context)

        # Process 5 batches concurrently
        results = await asyncio.gather(*[
            process_batch(i) for i in range(5)
        ])

        # All batches should succeed
        for result in results:
            assert result == {"batchItemFailures": []}

        # Check final accumulation
        stats = await batch_accumulator.get_batch_stats()
        if BatchType.CUSTOMER_UPDATE.value in stats["batches"]:
            batch_stats = stats["batches"][BatchType.CUSTOMER_UPDATE.value]
            # Should have 15 events total (5 batches × 3 events)
            # Some may have been processed if threshold was hit
            assert batch_stats["count"] <= 15

    @pytest.mark.asyncio
    async def test_batch_window_rotation(
        self,
        stripe_event_factory,
        mock_lambda_context,
        batch_accumulator,
        mock_bulk_api_service,
        test_settings,
    ):
        """Test that new windows are created after batch submission."""
        # Process enough events to trigger submission
        events_round1 = [
            stripe_event_factory("customer.updated", customer_id=f"cus_r1_{i:03d}")
            for i in range(12)  # Exceeds threshold
        ]

        sqs_event_1 = {
            "Records": [
                {
                    "messageId": f"msg-r1-{i:03d}",
                    "receiptHandle": f"receipt-r1-{i:03d}",
                    "body": json.dumps(event),
                    "attributes": {
                        "ApproximateReceiveCount": "1",
                    },
                }
                for i, event in enumerate(events_round1)
            ]
        }

        with patch("bulk_processor.settings", test_settings), \
             patch("bulk_processor.get_batch_accumulator") as mock_get_accumulator, \
             patch("bulk_processor.get_bulk_api_service") as mock_get_bulk:

            mock_get_accumulator.return_value = batch_accumulator
            mock_get_bulk.return_value = mock_bulk_api_service

            # Process first batch (should trigger submission)
            result1 = await lambda_handler(sqs_event_1, mock_lambda_context)
            assert result1 == {"batchItemFailures": []}

            # Verify Bulk API was called
            assert mock_bulk_api_service.upsert_records.call_count == 1

            # Process more events (should go to new window)
            events_round2 = [
                stripe_event_factory("customer.updated", customer_id=f"cus_r2_{i:03d}")
                for i in range(3)
            ]

            sqs_event_2 = {
                "Records": [
                    {
                        "messageId": f"msg-r2-{i:03d}",
                        "receiptHandle": f"receipt-r2-{i:03d}",
                        "body": json.dumps(event),
                        "attributes": {
                            "ApproximateReceiveCount": "1",
                        },
                    }
                    for i, event in enumerate(events_round2)
                ]
            }

            # Process second batch (should accumulate in new window)
            result2 = await lambda_handler(sqs_event_2, mock_lambda_context)
            assert result2 == {"batchItemFailures": []}

            # Check that we have a new window with 3 events
            stats = await batch_accumulator.get_batch_stats()
            if BatchType.CUSTOMER_UPDATE.value in stats["batches"]:
                assert stats["batches"][BatchType.CUSTOMER_UPDATE.value]["count"] == 3