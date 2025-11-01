"""
End-to-end integration tests for the complete middleware flow.
"""
import json
import pytest
from unittest.mock import patch, Mock, AsyncMock, MagicMock
from datetime import datetime, timezone
from typing import List, Dict, Any

from app.models.stripe_events import EventPriority
from webhook_receiver import lambda_handler as webhook_handler
from sqs_worker import lambda_handler as sqs_worker_handler
from bulk_processor import lambda_handler as bulk_processor_handler


class TestEndToEndFlow:
    """Test complete event flow through all three Lambdas."""

    @pytest.mark.asyncio
    async def test_high_priority_event_flow(
        self,
        stripe_event_factory,
        generate_stripe_signature,
        mock_lambda_context,
        sqs_service,
        dynamodb_service,
        mock_salesforce_service,
        test_settings,
    ):
        """Test complete flow for a high-priority event."""
        # Step 1: Create a payment_intent.succeeded event
        event_data = stripe_event_factory(
            "payment_intent.succeeded",
            customer_id="cus_e2e_test",
            metadata={"order_id": "ord_12345"}
        )
        payload = json.dumps(event_data)
        signature = generate_stripe_signature(payload)

        # Step 2: Webhook receives the event
        webhook_event = {
            "httpMethod": "POST",
            "path": "/webhook/stripe",
            "headers": {
                "stripe-signature": signature,
                "content-type": "application/json",
            },
            "body": payload,
        }

        with patch("webhook_receiver.settings", test_settings), \
             patch("webhook_receiver.sqs_service") as mock_sqs_webhook, \
             patch("webhook_receiver.dynamodb_service", dynamodb_service), \
             patch("webhook_receiver.get_rate_limiter") as mock_rate_limiter:

            # Configure rate limiter
            rate_limiter = AsyncMock()
            rate_limiter.check_rate_limit = AsyncMock(return_value={"allowed": True})
            mock_rate_limiter.return_value = rate_limiter

            # Mock SQS to capture the message
            sent_message = None

            async def capture_message(**kwargs):
                nonlocal sent_message
                sent_message = kwargs["message_body"]
                return {"MessageId": "msg-001"}

            mock_sqs_webhook.send_message = AsyncMock(side_effect=capture_message)
            mock_sqs_webhook.queue_url = test_settings.sqs_queue_url

            # Process webhook
            webhook_response = await webhook_handler(webhook_event, mock_lambda_context)

            # Verify webhook response
            assert webhook_response["statusCode"] == 200
            body = json.loads(webhook_response["body"])
            assert body["priority"] == EventPriority.HIGH.value
            assert sent_message is not None

        # Step 3: SQS Worker processes the event
        sqs_event = {
            "Records": [
                {
                    "messageId": "msg-001",
                    "receiptHandle": "receipt-001",
                    "body": json.dumps(sent_message),
                    "attributes": {
                        "ApproximateReceiveCount": "1",
                    },
                }
            ]
        }

        with patch("sqs_worker.settings", test_settings), \
             patch("sqs_worker.salesforce_service", mock_salesforce_service), \
             patch("sqs_worker.dynamodb_service", dynamodb_service):

            # Process in SQS Worker
            worker_result = await sqs_worker_handler(sqs_event, mock_lambda_context)

            # Verify worker processed successfully
            assert worker_result == {"batchItemFailures": []}

            # Verify Salesforce was updated
            mock_salesforce_service.upsert_payment.assert_called_once()

    @pytest.mark.asyncio
    async def test_low_priority_bulk_flow(
        self,
        stripe_event_factory,
        generate_stripe_signature,
        mock_lambda_context,
        sqs_service,
        dynamodb_service,
        batch_accumulator,
        mock_bulk_api_service,
        test_settings,
    ):
        """Test complete flow for low-priority events using Bulk API."""
        accumulated_events = []

        # Step 1: Send multiple customer.updated events through webhook
        for i in range(12):  # Enough to trigger bulk processing
            event_data = stripe_event_factory(
                "customer.updated",
                customer_id=f"cus_bulk_{i:03d}",
                metadata={"segment": "enterprise"}
            )
            payload = json.dumps(event_data)
            signature = generate_stripe_signature(payload)

            webhook_event = {
                "httpMethod": "POST",
                "path": "/webhook/stripe",
                "headers": {
                    "stripe-signature": signature,
                    "content-type": "application/json",
                },
                "body": payload,
            }

            with patch("webhook_receiver.settings", test_settings), \
                 patch("webhook_receiver.sqs_service") as mock_sqs_webhook, \
                 patch("webhook_receiver.dynamodb_service", dynamodb_service), \
                 patch("webhook_receiver.get_rate_limiter") as mock_rate_limiter:

                # Configure rate limiter
                rate_limiter = AsyncMock()
                rate_limiter.check_rate_limit = AsyncMock(return_value={"allowed": True})
                mock_rate_limiter.return_value = rate_limiter

                # Capture messages sent to low-priority queue
                async def capture_low_priority(**kwargs):
                    if kwargs.get("queue_url") == test_settings.low_priority_queue_url:
                        accumulated_events.append(kwargs["message_body"])
                    return {"MessageId": f"msg-low-{i:03d}"}

                mock_sqs_webhook.send_message = AsyncMock(side_effect=capture_low_priority)
                mock_sqs_webhook.queue_url = test_settings.sqs_queue_url
                mock_sqs_webhook.low_priority_queue_url = test_settings.low_priority_queue_url

                # Process webhook
                webhook_response = await webhook_handler(webhook_event, mock_lambda_context)
                assert webhook_response["statusCode"] == 200

        # Step 2: Bulk Processor accumulates and processes events
        bulk_sqs_event = {
            "Records": [
                {
                    "messageId": f"msg-bulk-{i:03d}",
                    "receiptHandle": f"receipt-bulk-{i:03d}",
                    "body": json.dumps(event),
                    "attributes": {
                        "ApproximateReceiveCount": "1",
                    },
                }
                for i, event in enumerate(accumulated_events)
            ]
        }

        with patch("bulk_processor.settings", test_settings), \
             patch("bulk_processor.get_batch_accumulator") as mock_get_accumulator, \
             patch("bulk_processor.get_bulk_api_service") as mock_get_bulk:

            mock_get_accumulator.return_value = batch_accumulator
            mock_get_bulk.return_value = mock_bulk_api_service

            # Process in Bulk Processor
            bulk_result = await bulk_processor_handler(bulk_sqs_event, mock_lambda_context)

            # Verify bulk processing succeeded
            assert bulk_result == {"batchItemFailures": []}

            # Verify Bulk API was called
            mock_bulk_api_service.upsert_records.assert_called()

            # Verify correct number of records were sent
            call_args = mock_bulk_api_service.upsert_records.call_args
            records = call_args[1]["records"]
            assert len(records) >= 12

    @pytest.mark.asyncio
    async def test_mixed_priority_concurrent_flow(
        self,
        stripe_event_factory,
        generate_stripe_signature,
        mock_lambda_context,
        sqs_service,
        dynamodb_service,
        mock_salesforce_service,
        batch_accumulator,
        mock_bulk_api_service,
        test_settings,
    ):
        """Test concurrent processing of mixed priority events."""
        import asyncio

        high_priority_messages = []
        low_priority_messages = []

        # Create mixed events
        events = [
            # High priority
            ("payment_intent.succeeded", "cus_hp_001", EventPriority.HIGH),
            ("customer.subscription.created", "cus_hp_002", EventPriority.HIGH),
            # Low priority
            ("customer.updated", "cus_lp_001", EventPriority.LOW),
            ("customer.updated", "cus_lp_002", EventPriority.LOW),
            # Medium priority
            ("invoice.payment_failed", "cus_mp_001", EventPriority.MEDIUM),
        ]

        # Process all events through webhook
        async def send_webhook(event_type, customer_id, expected_priority):
            event_data = stripe_event_factory(event_type, customer_id=customer_id)
            payload = json.dumps(event_data)
            signature = generate_stripe_signature(payload)

            webhook_event = {
                "httpMethod": "POST",
                "path": "/webhook/stripe",
                "headers": {
                    "stripe-signature": signature,
                    "content-type": "application/json",
                },
                "body": payload,
            }

            with patch("webhook_receiver.settings", test_settings), \
                 patch("webhook_receiver.sqs_service") as mock_sqs_webhook, \
                 patch("webhook_receiver.dynamodb_service", dynamodb_service), \
                 patch("webhook_receiver.get_rate_limiter") as mock_rate_limiter:

                rate_limiter = AsyncMock()
                rate_limiter.check_rate_limit = AsyncMock(return_value={"allowed": True})
                mock_rate_limiter.return_value = rate_limiter

                async def route_message(**kwargs):
                    if kwargs.get("queue_url") == test_settings.low_priority_queue_url:
                        low_priority_messages.append(kwargs["message_body"])
                    else:
                        high_priority_messages.append(kwargs["message_body"])
                    return {"MessageId": f"msg-{customer_id}"}

                mock_sqs_webhook.send_message = AsyncMock(side_effect=route_message)
                mock_sqs_webhook.queue_url = test_settings.sqs_queue_url
                mock_sqs_webhook.low_priority_queue_url = test_settings.low_priority_queue_url

                response = await webhook_handler(webhook_event, mock_lambda_context)
                assert response["statusCode"] == 200

        # Send all webhooks concurrently
        await asyncio.gather(*[
            send_webhook(event_type, customer_id, priority)
            for event_type, customer_id, priority in events
        ])

        # Verify routing
        assert len(high_priority_messages) == 3  # 2 HIGH + 1 MEDIUM
        assert len(low_priority_messages) == 2   # 2 LOW

        # Process HIGH/MEDIUM priority events
        high_sqs_event = {
            "Records": [
                {
                    "messageId": f"msg-high-{i:03d}",
                    "receiptHandle": f"receipt-high-{i:03d}",
                    "body": json.dumps(msg),
                }
                for i, msg in enumerate(high_priority_messages)
            ]
        }

        with patch("sqs_worker.settings", test_settings), \
             patch("sqs_worker.salesforce_service", mock_salesforce_service), \
             patch("sqs_worker.dynamodb_service", dynamodb_service):

            result = await sqs_worker_handler(high_sqs_event, mock_lambda_context)
            assert result == {"batchItemFailures": []}

        # Process LOW priority events
        low_sqs_event = {
            "Records": [
                {
                    "messageId": f"msg-low-{i:03d}",
                    "receiptHandle": f"receipt-low-{i:03d}",
                    "body": json.dumps(msg),
                }
                for i, msg in enumerate(low_priority_messages)
            ]
        }

        with patch("bulk_processor.settings", test_settings), \
             patch("bulk_processor.get_batch_accumulator") as mock_get_accumulator, \
             patch("bulk_processor.get_bulk_api_service") as mock_get_bulk:

            mock_get_accumulator.return_value = batch_accumulator
            mock_get_bulk.return_value = mock_bulk_api_service

            result = await bulk_processor_handler(low_sqs_event, mock_lambda_context)
            assert result == {"batchItemFailures": []}

    @pytest.mark.asyncio
    async def test_failure_recovery_flow(
        self,
        stripe_event_factory,
        generate_stripe_signature,
        mock_lambda_context,
        sqs_service,
        dynamodb_service,
        mock_salesforce_service,
        test_settings,
    ):
        """Test failure recovery through the system."""
        # Create an event
        event_data = stripe_event_factory(
            "payment_intent.succeeded",
            event_id="evt_retry_test",
            customer_id="cus_fail_test"
        )
        payload = json.dumps(event_data)
        signature = generate_stripe_signature(payload)

        # Step 1: Successfully receive webhook
        webhook_event = {
            "httpMethod": "POST",
            "path": "/webhook/stripe",
            "headers": {
                "stripe-signature": signature,
                "content-type": "application/json",
            },
            "body": payload,
        }

        sent_message = None

        with patch("webhook_receiver.settings", test_settings), \
             patch("webhook_receiver.sqs_service") as mock_sqs_webhook, \
             patch("webhook_receiver.dynamodb_service", dynamodb_service), \
             patch("webhook_receiver.get_rate_limiter") as mock_rate_limiter:

            rate_limiter = AsyncMock()
            rate_limiter.check_rate_limit = AsyncMock(return_value={"allowed": True})
            mock_rate_limiter.return_value = rate_limiter

            async def capture_message(**kwargs):
                nonlocal sent_message
                sent_message = kwargs["message_body"]
                return {"MessageId": "msg-fail-001"}

            mock_sqs_webhook.send_message = AsyncMock(side_effect=capture_message)
            mock_sqs_webhook.queue_url = test_settings.sqs_queue_url

            response = await webhook_handler(webhook_event, mock_lambda_context)
            assert response["statusCode"] == 200

        # Step 2: First SQS Worker attempt fails
        sqs_event = {
            "Records": [
                {
                    "messageId": "msg-fail-001",
                    "receiptHandle": "receipt-fail-001",
                    "body": json.dumps(sent_message),
                    "attributes": {
                        "ApproximateReceiveCount": "1",
                    },
                }
            ]
        }

        # Configure Salesforce to fail
        mock_salesforce_service.upsert_payment = AsyncMock(
            side_effect=Exception("Salesforce API Error")
        )

        with patch("sqs_worker.settings", test_settings), \
             patch("sqs_worker.salesforce_service", mock_salesforce_service), \
             patch("sqs_worker.dynamodb_service", dynamodb_service):

            result = await sqs_worker_handler(sqs_event, mock_lambda_context)

            # Should report failure for retry
            assert len(result["batchItemFailures"]) == 1
            assert result["batchItemFailures"][0]["itemIdentifier"] == "msg-fail-001"

        # Step 3: Second attempt succeeds
        sqs_event["Records"][0]["attributes"]["ApproximateReceiveCount"] = "2"

        # Configure Salesforce to succeed
        mock_salesforce_service.upsert_payment = AsyncMock(
            return_value={"id": "a01XX000001234", "success": True}
        )

        with patch("sqs_worker.settings", test_settings), \
             patch("sqs_worker.salesforce_service", mock_salesforce_service), \
             patch("sqs_worker.dynamodb_service", dynamodb_service):

            result = await sqs_worker_handler(sqs_event, mock_lambda_context)

            # Should succeed this time
            assert result == {"batchItemFailures": []}
            mock_salesforce_service.upsert_payment.assert_called_once()

    @pytest.mark.asyncio
    async def test_duplicate_prevention_across_lambdas(
        self,
        stripe_event_factory,
        generate_stripe_signature,
        mock_lambda_context,
        dynamodb_service,
        test_settings,
    ):
        """Test that duplicate events are prevented across Lambda boundaries."""
        event_data = stripe_event_factory(
            "payment_intent.succeeded",
            event_id="evt_duplicate_e2e",
            customer_id="cus_dup_test"
        )
        payload = json.dumps(event_data)
        signature = generate_stripe_signature(payload)

        webhook_event = {
            "httpMethod": "POST",
            "path": "/webhook/stripe",
            "headers": {
                "stripe-signature": signature,
                "content-type": "application/json",
            },
            "body": payload,
        }

        # Step 1: First webhook processes successfully
        with patch("webhook_receiver.settings", test_settings), \
             patch("webhook_receiver.sqs_service") as mock_sqs, \
             patch("webhook_receiver.dynamodb_service") as mock_dynamo, \
             patch("webhook_receiver.get_rate_limiter") as mock_rate_limiter:

            rate_limiter = AsyncMock()
            rate_limiter.check_rate_limit = AsyncMock(return_value={"allowed": True})
            mock_rate_limiter.return_value = rate_limiter

            mock_sqs.send_message = AsyncMock(return_value={"MessageId": "msg-001"})
            mock_dynamo.get_item = AsyncMock(return_value=None)
            mock_dynamo.put_item = AsyncMock()

            response1 = await webhook_handler(webhook_event, mock_lambda_context)
            assert response1["statusCode"] == 200
            assert json.loads(response1["body"])["status"] == "success"

        # Step 2: Duplicate webhook is detected
        with patch("webhook_receiver.settings", test_settings), \
             patch("webhook_receiver.dynamodb_service") as mock_dynamo, \
             patch("webhook_receiver.get_rate_limiter") as mock_rate_limiter:

            rate_limiter = AsyncMock()
            rate_limiter.check_rate_limit = AsyncMock(return_value={"allowed": True})
            mock_rate_limiter.return_value = rate_limiter

            # Simulate that event was already processed
            mock_dynamo.get_item = AsyncMock(return_value={
                "pk": f"event#{event_data['id']}",
                "sk": "processed",
                "timestamp": datetime.now(timezone.utc).isoformat(),
            })

            response2 = await webhook_handler(webhook_event, mock_lambda_context)
            assert response2["statusCode"] == 200
            assert json.loads(response2["body"])["status"] == "duplicate"