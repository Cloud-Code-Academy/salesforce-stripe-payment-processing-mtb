"""
Integration tests for the Webhook Receiver Lambda.
"""
import json
import pytest
from unittest.mock import patch, Mock, AsyncMock
from datetime import datetime, timezone

from app.models.stripe_events import EventPriority
from webhook_receiver import lambda_handler


class TestWebhookReceiver:
    """Test the webhook receiver Lambda function."""

    @pytest.mark.asyncio
    async def test_valid_webhook_high_priority_event(
        self,
        stripe_event_factory,
        generate_stripe_signature,
        mock_lambda_context,
        sqs_service,
        dynamodb_service,
        test_settings,
    ):
        """Test processing a valid high-priority webhook event."""
        # Create a high-priority event (payment_intent.succeeded)
        event_data = stripe_event_factory("payment_intent.succeeded")
        payload = json.dumps(event_data)
        signature = generate_stripe_signature(payload)

        # Create Lambda event
        lambda_event = {
            "httpMethod": "POST",
            "path": "/webhook/stripe",
            "headers": {
                "stripe-signature": signature,
                "content-type": "application/json",
            },
            "body": payload,
        }

        # Mock services
        with patch("webhook_receiver.settings", test_settings), \
             patch("webhook_receiver.sqs_service", sqs_service), \
             patch("webhook_receiver.dynamodb_service", dynamodb_service), \
             patch("webhook_receiver.get_rate_limiter") as mock_rate_limiter:

            # Configure rate limiter
            rate_limiter = AsyncMock()
            rate_limiter.check_rate_limit = AsyncMock(return_value={"allowed": True})
            mock_rate_limiter.return_value = rate_limiter

            # Process webhook
            response = await lambda_handler(lambda_event, mock_lambda_context)

            # Verify response
            assert response["statusCode"] == 200
            body = json.loads(response["body"])
            assert body["status"] == "success"
            assert body["event_id"] == event_data["id"]
            assert body["priority"] == EventPriority.HIGH.value
            assert body["queued"] is True

    @pytest.mark.asyncio
    async def test_valid_webhook_low_priority_event(
        self,
        stripe_event_factory,
        generate_stripe_signature,
        mock_lambda_context,
        sqs_service,
        dynamodb_service,
        test_settings,
    ):
        """Test processing a valid low-priority webhook event."""
        # Create a low-priority event (customer.updated)
        event_data = stripe_event_factory("customer.updated")
        payload = json.dumps(event_data)
        signature = generate_stripe_signature(payload)

        # Create Lambda event
        lambda_event = {
            "httpMethod": "POST",
            "path": "/webhook/stripe",
            "headers": {
                "stripe-signature": signature,
                "content-type": "application/json",
            },
            "body": payload,
        }

        # Mock services
        with patch("webhook_receiver.settings", test_settings), \
             patch("webhook_receiver.sqs_service", sqs_service), \
             patch("webhook_receiver.dynamodb_service", dynamodb_service), \
             patch("webhook_receiver.get_rate_limiter") as mock_rate_limiter:

            # Configure rate limiter
            rate_limiter = AsyncMock()
            rate_limiter.check_rate_limit = AsyncMock(return_value={"allowed": True})
            mock_rate_limiter.return_value = rate_limiter

            # Process webhook
            response = await lambda_handler(lambda_event, mock_lambda_context)

            # Verify response
            assert response["statusCode"] == 200
            body = json.loads(response["body"])
            assert body["status"] == "success"
            assert body["event_id"] == event_data["id"]
            assert body["priority"] == EventPriority.LOW.value
            assert body["queued"] is True

    @pytest.mark.asyncio
    async def test_invalid_signature(
        self,
        stripe_event_factory,
        mock_lambda_context,
        test_settings,
    ):
        """Test webhook with invalid signature."""
        event_data = stripe_event_factory("payment_intent.succeeded")
        payload = json.dumps(event_data)

        # Create Lambda event with invalid signature
        lambda_event = {
            "httpMethod": "POST",
            "path": "/webhook/stripe",
            "headers": {
                "stripe-signature": "invalid_signature",
                "content-type": "application/json",
            },
            "body": payload,
        }

        with patch("webhook_receiver.settings", test_settings):
            # Process webhook
            response = await lambda_handler(lambda_event, mock_lambda_context)

            # Verify response
            assert response["statusCode"] == 401
            body = json.loads(response["body"])
            assert body["error"] == "Invalid signature"

    @pytest.mark.asyncio
    async def test_duplicate_event_detection(
        self,
        stripe_event_factory,
        generate_stripe_signature,
        mock_lambda_context,
        sqs_service,
        dynamodb_service,
        test_settings,
    ):
        """Test duplicate event detection."""
        event_data = stripe_event_factory(
            "payment_intent.succeeded",
            event_id="evt_duplicate_test"
        )
        payload = json.dumps(event_data)
        signature = generate_stripe_signature(payload)

        lambda_event = {
            "httpMethod": "POST",
            "path": "/webhook/stripe",
            "headers": {
                "stripe-signature": signature,
                "content-type": "application/json",
            },
            "body": payload,
        }

        with patch("webhook_receiver.settings", test_settings), \
             patch("webhook_receiver.sqs_service", sqs_service), \
             patch("webhook_receiver.dynamodb_service", dynamodb_service) as mock_dynamo, \
             patch("webhook_receiver.get_rate_limiter") as mock_rate_limiter:

            # Configure rate limiter
            rate_limiter = AsyncMock()
            rate_limiter.check_rate_limit = AsyncMock(return_value={"allowed": True})
            mock_rate_limiter.return_value = rate_limiter

            # Configure DynamoDB to indicate duplicate
            mock_dynamo.get_item = AsyncMock(return_value={
                "pk": f"event#{event_data['id']}",
                "sk": "processed",
                "timestamp": datetime.now(timezone.utc).isoformat(),
            })

            # Process webhook
            response = await lambda_handler(lambda_event, mock_lambda_context)

            # Verify response
            assert response["statusCode"] == 200
            body = json.loads(response["body"])
            assert body["status"] == "duplicate"
            assert body["message"] == "Event already processed"

    @pytest.mark.asyncio
    async def test_rate_limiting(
        self,
        stripe_event_factory,
        generate_stripe_signature,
        mock_lambda_context,
        test_settings,
    ):
        """Test rate limiting."""
        event_data = stripe_event_factory("payment_intent.succeeded")
        payload = json.dumps(event_data)
        signature = generate_stripe_signature(payload)

        lambda_event = {
            "httpMethod": "POST",
            "path": "/webhook/stripe",
            "headers": {
                "stripe-signature": signature,
                "content-type": "application/json",
            },
            "body": payload,
        }

        with patch("webhook_receiver.settings", test_settings), \
             patch("webhook_receiver.get_rate_limiter") as mock_rate_limiter:

            # Configure rate limiter to deny request
            rate_limiter = AsyncMock()
            rate_limiter.check_rate_limit = AsyncMock(return_value={
                "allowed": False,
                "retry_after": 60,
                "reason": "Daily limit exceeded",
            })
            mock_rate_limiter.return_value = rate_limiter

            # Process webhook
            response = await lambda_handler(lambda_event, mock_lambda_context)

            # Verify response
            assert response["statusCode"] == 429
            assert response["headers"]["Retry-After"] == "60"
            body = json.loads(response["body"])
            assert body["error"] == "Rate limit exceeded"

    @pytest.mark.asyncio
    async def test_priority_routing_to_correct_queue(
        self,
        stripe_event_factory,
        generate_stripe_signature,
        mock_lambda_context,
        sqs_service,
        dynamodb_service,
        test_settings,
    ):
        """Test that events are routed to correct queues based on priority."""
        test_cases = [
            ("payment_intent.succeeded", EventPriority.HIGH, test_settings.sqs_queue_url),
            ("customer.subscription.created", EventPriority.HIGH, test_settings.sqs_queue_url),
            ("invoice.payment_failed", EventPriority.MEDIUM, test_settings.sqs_queue_url),
            ("customer.updated", EventPriority.LOW, test_settings.low_priority_queue_url),
        ]

        for event_type, expected_priority, expected_queue in test_cases:
            event_data = stripe_event_factory(event_type)
            payload = json.dumps(event_data)
            signature = generate_stripe_signature(payload)

            lambda_event = {
                "httpMethod": "POST",
                "path": "/webhook/stripe",
                "headers": {
                    "stripe-signature": signature,
                    "content-type": "application/json",
                },
                "body": payload,
            }

            with patch("webhook_receiver.settings", test_settings), \
                 patch("webhook_receiver.sqs_service") as mock_sqs, \
                 patch("webhook_receiver.dynamodb_service", dynamodb_service), \
                 patch("webhook_receiver.get_rate_limiter") as mock_rate_limiter:

                # Configure mocks
                rate_limiter = AsyncMock()
                rate_limiter.check_rate_limit = AsyncMock(return_value={"allowed": True})
                mock_rate_limiter.return_value = rate_limiter

                mock_sqs.send_message = AsyncMock(return_value={"MessageId": "test-msg-id"})
                mock_sqs.queue_url = test_settings.sqs_queue_url
                mock_sqs.low_priority_queue_url = test_settings.low_priority_queue_url

                # Process webhook
                response = await lambda_handler(lambda_event, mock_lambda_context)

                # Verify correct queue was used
                assert response["statusCode"] == 200
                mock_sqs.send_message.assert_called_once()
                call_args = mock_sqs.send_message.call_args
                assert call_args[1]["queue_url"] == expected_queue

    @pytest.mark.asyncio
    async def test_malformed_json_body(
        self,
        generate_stripe_signature,
        mock_lambda_context,
        test_settings,
    ):
        """Test handling of malformed JSON in request body."""
        payload = "invalid json {"
        signature = generate_stripe_signature(payload)

        lambda_event = {
            "httpMethod": "POST",
            "path": "/webhook/stripe",
            "headers": {
                "stripe-signature": signature,
                "content-type": "application/json",
            },
            "body": payload,
        }

        with patch("webhook_receiver.settings", test_settings):
            # Process webhook
            response = await lambda_handler(lambda_event, mock_lambda_context)

            # Verify response
            assert response["statusCode"] == 400
            body = json.loads(response["body"])
            assert "Invalid JSON" in body["error"]

    @pytest.mark.asyncio
    async def test_missing_signature_header(
        self,
        stripe_event_factory,
        mock_lambda_context,
        test_settings,
    ):
        """Test handling of missing signature header."""
        event_data = stripe_event_factory("payment_intent.succeeded")
        payload = json.dumps(event_data)

        lambda_event = {
            "httpMethod": "POST",
            "path": "/webhook/stripe",
            "headers": {
                "content-type": "application/json",
            },
            "body": payload,
        }

        with patch("webhook_receiver.settings", test_settings):
            # Process webhook
            response = await lambda_handler(lambda_event, mock_lambda_context)

            # Verify response
            assert response["statusCode"] == 401
            body = json.loads(response["body"])
            assert body["error"] == "No signature provided"

    @pytest.mark.asyncio
    async def test_health_check_endpoint(
        self,
        mock_lambda_context,
        test_settings,
    ):
        """Test health check endpoint."""
        lambda_event = {
            "httpMethod": "GET",
            "path": "/health",
            "headers": {},
            "body": None,
        }

        with patch("webhook_receiver.settings", test_settings):
            # Process request
            response = await lambda_handler(lambda_event, mock_lambda_context)

            # Verify response
            assert response["statusCode"] == 200
            body = json.loads(response["body"])
            assert body["status"] == "healthy"

    @pytest.mark.asyncio
    async def test_readiness_check_endpoint(
        self,
        mock_lambda_context,
        dynamodb_service,
        sqs_service,
        test_settings,
    ):
        """Test readiness check endpoint."""
        lambda_event = {
            "httpMethod": "GET",
            "path": "/health/ready",
            "headers": {},
            "body": None,
        }

        with patch("webhook_receiver.settings", test_settings), \
             patch("webhook_receiver.dynamodb_service", dynamodb_service), \
             patch("webhook_receiver.sqs_service", sqs_service), \
             patch("webhook_receiver.salesforce_service") as mock_sf, \
             patch("webhook_receiver.get_batch_accumulator") as mock_batch, \
             patch("webhook_receiver.get_rate_limiter") as mock_rate:

            # Configure mocks
            mock_sf.is_authenticated = AsyncMock(return_value=True)

            batch_accumulator = AsyncMock()
            batch_accumulator.get_batch_stats = AsyncMock(return_value={"batches": {}})
            batch_accumulator.table_name = "test-batch-accumulator"
            mock_batch.return_value = batch_accumulator

            rate_limiter = AsyncMock()
            rate_limiter.get_current_usage = AsyncMock(return_value={
                "second": 0,
                "minute": 0,
                "day": 0,
            })
            mock_rate.return_value = rate_limiter

            # Process request
            response = await lambda_handler(lambda_event, mock_lambda_context)

            # Verify response
            assert response["statusCode"] == 200
            body = json.loads(response["body"])
            assert body["status"] == "ready"
            assert "dependencies" in body
            assert body["summary"]["total_checks"] == 6