"""
Integration tests for the SQS Worker Lambda.
"""
import json
import pytest
from unittest.mock import patch, Mock, AsyncMock
from datetime import datetime, timezone
from typing import Dict, Any

from app.models.stripe_events import StripeEvent, EventPriority
from sqs_worker import lambda_handler, process_stripe_event


class TestSQSWorker:
    """Test the SQS Worker Lambda function."""

    @pytest.mark.asyncio
    async def test_process_single_high_priority_event(
        self,
        stripe_event_factory,
        mock_lambda_context,
        mock_salesforce_service,
        dynamodb_service,
        test_settings,
    ):
        """Test processing a single high-priority event from SQS."""
        # Create a payment_intent.succeeded event
        event_data = stripe_event_factory(
            "payment_intent.succeeded",
            customer_id="cus_test123"
        )

        # Create SQS event
        sqs_event = {
            "Records": [
                {
                    "messageId": "msg-001",
                    "receiptHandle": "receipt-001",
                    "body": json.dumps(event_data),
                    "attributes": {
                        "ApproximateReceiveCount": "1",
                        "SentTimestamp": str(int(datetime.now(timezone.utc).timestamp() * 1000)),
                    },
                    "messageAttributes": {
                        "priority": {
                            "stringValue": EventPriority.HIGH.value,
                            "dataType": "String",
                        }
                    },
                }
            ]
        }

        with patch("sqs_worker.settings", test_settings), \
             patch("sqs_worker.salesforce_service", mock_salesforce_service), \
             patch("sqs_worker.dynamodb_service", dynamodb_service):

            # Process event
            result = await lambda_handler(sqs_event, mock_lambda_context)

            # Verify no batch failures
            assert result == {"batchItemFailures": []}

            # Verify Salesforce was called
            mock_salesforce_service.upsert_payment.assert_called_once()

    @pytest.mark.asyncio
    async def test_process_batch_mixed_events(
        self,
        stripe_event_factory,
        mock_lambda_context,
        mock_salesforce_service,
        dynamodb_service,
        test_settings,
    ):
        """Test processing a batch of mixed event types."""
        # Create various events
        events = [
            stripe_event_factory("customer.updated", customer_id="cus_001"),
            stripe_event_factory("customer.subscription.created", subscription_id="sub_001"),
            stripe_event_factory("payment_intent.succeeded", customer_id="cus_002"),
            stripe_event_factory("checkout.session.completed", subscription_id="sub_002"),
            stripe_event_factory("invoice.payment_failed", customer_id="cus_003"),
        ]

        # Create SQS event with multiple records
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

        with patch("sqs_worker.settings", test_settings), \
             patch("sqs_worker.salesforce_service", mock_salesforce_service), \
             patch("sqs_worker.dynamodb_service", dynamodb_service):

            # Process events
            result = await lambda_handler(sqs_event, mock_lambda_context)

            # Verify no batch failures
            assert result == {"batchItemFailures": []}

            # Verify appropriate Salesforce calls were made
            assert mock_salesforce_service.upsert_customer.call_count == 1
            assert mock_salesforce_service.upsert_subscription.call_count == 2
            assert mock_salesforce_service.upsert_payment.call_count == 2

    @pytest.mark.asyncio
    async def test_partial_batch_failure(
        self,
        stripe_event_factory,
        mock_lambda_context,
        mock_salesforce_service,
        dynamodb_service,
        test_settings,
    ):
        """Test handling partial batch failures."""
        # Create events where one will fail
        events = [
            stripe_event_factory("payment_intent.succeeded", customer_id="cus_001"),
            stripe_event_factory("payment_intent.succeeded", customer_id="cus_fail"),  # This will fail
            stripe_event_factory("payment_intent.succeeded", customer_id="cus_003"),
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

        # Configure Salesforce to fail for specific customer
        def salesforce_side_effect(*args, **kwargs):
            payment = args[0] if args else kwargs.get("payment")
            if payment and "cus_fail" in str(payment):
                raise Exception("Salesforce API error")
            return {"id": "a01XX000001234", "success": True}

        mock_salesforce_service.upsert_payment = AsyncMock(side_effect=salesforce_side_effect)

        with patch("sqs_worker.settings", test_settings), \
             patch("sqs_worker.salesforce_service", mock_salesforce_service), \
             patch("sqs_worker.dynamodb_service", dynamodb_service):

            # Process events
            result = await lambda_handler(sqs_event, mock_lambda_context)

            # Verify partial failure response
            assert len(result["batchItemFailures"]) == 1
            assert result["batchItemFailures"][0]["itemIdentifier"] == "msg-001"

    @pytest.mark.asyncio
    async def test_subscription_lifecycle_events(
        self,
        stripe_event_factory,
        mock_lambda_context,
        mock_salesforce_service,
        dynamodb_service,
        test_settings,
    ):
        """Test processing subscription lifecycle events."""
        # Create subscription events
        events = [
            stripe_event_factory(
                "customer.subscription.created",
                subscription_id="sub_new",
                metadata={"salesforce_opportunity_id": "006XX000001234"}
            ),
            stripe_event_factory(
                "customer.subscription.updated",
                subscription_id="sub_updated",
                metadata={"plan_change": "true"}
            ),
            stripe_event_factory(
                "customer.subscription.deleted",
                subscription_id="sub_cancelled"
            ),
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

        with patch("sqs_worker.settings", test_settings), \
             patch("sqs_worker.salesforce_service", mock_salesforce_service), \
             patch("sqs_worker.dynamodb_service", dynamodb_service):

            # Process events
            result = await lambda_handler(sqs_event, mock_lambda_context)

            # Verify success
            assert result == {"batchItemFailures": []}

            # Verify all subscription updates were made
            assert mock_salesforce_service.upsert_subscription.call_count == 3

    @pytest.mark.asyncio
    async def test_checkout_session_events(
        self,
        stripe_event_factory,
        mock_lambda_context,
        mock_salesforce_service,
        dynamodb_service,
        test_settings,
    ):
        """Test processing checkout session events."""
        # Create checkout events
        events = [
            stripe_event_factory(
                "checkout.session.completed",
                subscription_id="sub_success",
                customer_id="cus_success"
            ),
            stripe_event_factory(
                "checkout.session.expired",
                subscription_id="sub_expired",
                customer_id="cus_expired"
            ),
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

        with patch("sqs_worker.settings", test_settings), \
             patch("sqs_worker.salesforce_service", mock_salesforce_service), \
             patch("sqs_worker.dynamodb_service", dynamodb_service):

            # Process events
            result = await lambda_handler(sqs_event, mock_lambda_context)

            # Verify success
            assert result == {"batchItemFailures": []}

            # Verify subscription updates
            assert mock_salesforce_service.upsert_subscription.call_count == 2

            # Check that expired session sets Failed status
            calls = mock_salesforce_service.upsert_subscription.call_args_list
            for call in calls:
                subscription = call[0][0] if call[0] else call[1].get("subscription")
                if hasattr(subscription, "Stripe_Subscription_ID__c"):
                    if subscription.Stripe_Subscription_ID__c == "sub_expired":
                        assert subscription.Sync_Status__c == "Failed"

    @pytest.mark.asyncio
    async def test_invoice_events(
        self,
        stripe_event_factory,
        mock_lambda_context,
        mock_salesforce_service,
        dynamodb_service,
        test_settings,
    ):
        """Test processing invoice events."""
        # Create invoice event
        event_data = {
            "id": "evt_invoice_test",
            "type": "invoice.payment_failed",
            "data": {
                "object": {
                    "id": "in_test123",
                    "customer": "cus_test123",
                    "subscription": "sub_test123",
                    "amount_due": 5000,
                    "currency": "usd",
                    "status": "open",
                    "attempt_count": 2,
                }
            }
        }

        sqs_event = {
            "Records": [
                {
                    "messageId": "msg-001",
                    "receiptHandle": "receipt-001",
                    "body": json.dumps(event_data),
                    "attributes": {
                        "ApproximateReceiveCount": "1",
                    },
                }
            ]
        }

        with patch("sqs_worker.settings", test_settings), \
             patch("sqs_worker.salesforce_service", mock_salesforce_service), \
             patch("sqs_worker.dynamodb_service", dynamodb_service):

            # Process event
            result = await lambda_handler(sqs_event, mock_lambda_context)

            # Verify success
            assert result == {"batchItemFailures": []}

            # Verify payment failure was recorded
            mock_salesforce_service.upsert_payment.assert_called_once()

    @pytest.mark.asyncio
    async def test_max_retry_handling(
        self,
        stripe_event_factory,
        mock_lambda_context,
        mock_salesforce_service,
        dynamodb_service,
        test_settings,
    ):
        """Test handling events that have reached max retries."""
        event_data = stripe_event_factory("payment_intent.succeeded")

        sqs_event = {
            "Records": [
                {
                    "messageId": "msg-001",
                    "receiptHandle": "receipt-001",
                    "body": json.dumps(event_data),
                    "attributes": {
                        "ApproximateReceiveCount": "4",  # Exceeds max retries (3)
                    },
                }
            ]
        }

        with patch("sqs_worker.settings", test_settings), \
             patch("sqs_worker.salesforce_service", mock_salesforce_service), \
             patch("sqs_worker.dynamodb_service", dynamodb_service), \
             patch("sqs_worker.logger") as mock_logger:

            # Make Salesforce fail
            mock_salesforce_service.upsert_payment = AsyncMock(
                side_effect=Exception("API Error")
            )

            # Process event
            result = await lambda_handler(sqs_event, mock_lambda_context)

            # Should not retry after max attempts
            assert result == {"batchItemFailures": []}

            # Verify error was logged
            mock_logger.error.assert_called()

    @pytest.mark.asyncio
    async def test_event_caching(
        self,
        stripe_event_factory,
        mock_lambda_context,
        mock_salesforce_service,
        dynamodb_service,
        test_settings,
    ):
        """Test that successfully processed events are cached."""
        event_data = stripe_event_factory(
            "payment_intent.succeeded",
            event_id="evt_cache_test"
        )

        sqs_event = {
            "Records": [
                {
                    "messageId": "msg-001",
                    "receiptHandle": "receipt-001",
                    "body": json.dumps(event_data),
                    "attributes": {
                        "ApproximateReceiveCount": "1",
                    },
                }
            ]
        }

        with patch("sqs_worker.settings", test_settings), \
             patch("sqs_worker.salesforce_service", mock_salesforce_service), \
             patch("sqs_worker.dynamodb_service", dynamodb_service) as mock_dynamo:

            # Process event
            result = await lambda_handler(sqs_event, mock_lambda_context)

            # Verify success
            assert result == {"batchItemFailures": []}

            # Verify event was cached
            mock_dynamo.put_item.assert_called()
            call_args = mock_dynamo.put_item.call_args
            item = call_args[1]["item"]
            assert item["pk"] == f"event#{event_data['id']}"
            assert item["sk"] == "processed"

    @pytest.mark.asyncio
    async def test_unknown_event_type(
        self,
        mock_lambda_context,
        mock_salesforce_service,
        dynamodb_service,
        test_settings,
    ):
        """Test handling of unknown event types."""
        event_data = {
            "id": "evt_unknown",
            "type": "unknown.event.type",
            "data": {"object": {}}
        }

        sqs_event = {
            "Records": [
                {
                    "messageId": "msg-001",
                    "receiptHandle": "receipt-001",
                    "body": json.dumps(event_data),
                    "attributes": {
                        "ApproximateReceiveCount": "1",
                    },
                }
            ]
        }

        with patch("sqs_worker.settings", test_settings), \
             patch("sqs_worker.salesforce_service", mock_salesforce_service), \
             patch("sqs_worker.dynamodb_service", dynamodb_service), \
             patch("sqs_worker.logger") as mock_logger:

            # Process event
            result = await lambda_handler(sqs_event, mock_lambda_context)

            # Should complete without failure
            assert result == {"batchItemFailures": []}

            # Verify warning was logged
            mock_logger.warning.assert_called_with(
                f"No handler for event type: {event_data['type']}"
            )