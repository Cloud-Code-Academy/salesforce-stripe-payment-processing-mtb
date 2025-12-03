"""
Test Stripe Webhook Endpoint

Tests webhook signature verification, event processing, and error handling.
"""

import json
import pytest
from unittest.mock import patch, AsyncMock

from app.services.stripe_service import stripe_service


@pytest.mark.asyncio
async def test_webhook_with_valid_signature(
    async_client,
    mock_stripe_customer_event,
    mock_valid_stripe_signature,
    mock_sqs_service,
):
    """Test webhook endpoint with valid Stripe signature"""

    with patch("app.routes.webhook.sqs_service", mock_sqs_service):
        # Prepare request
        payload = json.dumps(mock_stripe_customer_event, separators=(",", ":"))
        signature = mock_valid_stripe_signature(mock_stripe_customer_event)

        # Make request
        response = await async_client.post(
            "/webhook/stripe",
            content=payload,
            headers={
                "Stripe-Signature": signature,
                "Content-Type": "application/json",
            },
        )

        # Assertions
        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True
        assert data["event_id"] == mock_stripe_customer_event["id"]
        assert data["event_type"] == "customer.updated"
        assert "correlation_id" in data

        # Verify SQS message was sent
        mock_sqs_service.send_message.assert_called_once()


@pytest.mark.asyncio
async def test_webhook_with_invalid_signature(
    async_client, mock_stripe_customer_event
):
    """Test webhook endpoint rejects invalid signature"""

    payload = json.dumps(mock_stripe_customer_event)

    response = await async_client.post(
        "/webhook/stripe",
        content=payload,
        headers={
            "Stripe-Signature": "t=123456,v1=invalid_signature",
            "Content-Type": "application/json",
        },
    )

    assert response.status_code == 400
    assert "Invalid signature" in response.text


@pytest.mark.asyncio
async def test_webhook_missing_signature(async_client, mock_stripe_customer_event):
    """Test webhook endpoint requires Stripe-Signature header"""

    payload = json.dumps(mock_stripe_customer_event)

    response = await async_client.post(
        "/webhook/stripe",
        content=payload,
        headers={"Content-Type": "application/json"},
    )

    assert response.status_code == 400


@pytest.mark.asyncio
async def test_webhook_empty_payload(async_client, mock_valid_stripe_signature):
    """Test webhook endpoint handles empty payload"""

    response = await async_client.post(
        "/webhook/stripe",
        content="",
        headers={
            "Stripe-Signature": "t=123456,v1=test",
            "Content-Type": "application/json",
        },
    )

    assert response.status_code == 400


@pytest.mark.asyncio
async def test_webhook_checkout_completed(
    async_client,
    mock_stripe_checkout_completed_event,
    mock_valid_stripe_signature,
    mock_sqs_service,
):
    """Test webhook handles checkout.session.completed event"""

    with patch("app.routes.webhook.sqs_service", mock_sqs_service):
        payload = json.dumps(
            mock_stripe_checkout_completed_event, separators=(",", ":")
        )
        signature = mock_valid_stripe_signature(mock_stripe_checkout_completed_event)

        response = await async_client.post(
            "/webhook/stripe",
            content=payload,
            headers={
                "Stripe-Signature": signature,
                "Content-Type": "application/json",
            },
        )

        assert response.status_code == 200
        data = response.json()
        assert data["event_type"] == "checkout.session.completed"


@pytest.mark.asyncio
async def test_webhook_payment_succeeded(
    async_client,
    mock_stripe_payment_succeeded_event,
    mock_valid_stripe_signature,
    mock_sqs_service,
):
    """Test webhook handles payment_intent.succeeded event"""

    with patch("app.routes.webhook.sqs_service", mock_sqs_service):
        payload = json.dumps(
            mock_stripe_payment_succeeded_event, separators=(",", ":")
        )
        signature = mock_valid_stripe_signature(mock_stripe_payment_succeeded_event)

        response = await async_client.post(
            "/webhook/stripe",
            content=payload,
            headers={
                "Stripe-Signature": signature,
                "Content-Type": "application/json",
            },
        )

        assert response.status_code == 200
        data = response.json()
        assert data["event_type"] == "payment_intent.succeeded"
