"""
Test Event Router

Tests event routing logic and idempotency.
"""

import pytest
from unittest.mock import patch, AsyncMock

from app.handlers.event_router import get_event_router
from app.models.stripe_events import StripeEvent


@pytest.mark.asyncio
async def test_route_customer_updated_event(
    mock_stripe_customer_event, mock_redis_service, mock_salesforce_service
):
    """Test routing customer.updated event"""

    event = StripeEvent(**mock_stripe_customer_event)
    event_router = get_event_router()

    with patch("app.handlers.event_router.redis_service", mock_redis_service), patch(
        "app.handlers.customer_handler.salesforce_service", mock_salesforce_service
    ):
        mock_redis_service.exists.return_value = False  # Not processed yet

        result = await event_router.route_event(event)

        assert result["status"] == "success"
        assert result["event_id"] == event.id
        assert result["event_type"] == "customer.updated"

        # Verify Salesforce was called
        mock_salesforce_service.upsert_customer.assert_called_once()


@pytest.mark.asyncio
async def test_route_subscription_updated_event(
    mock_stripe_subscription_event, mock_redis_service, mock_salesforce_service
):
    """Test routing customer.subscription.updated event"""

    event = StripeEvent(**mock_stripe_subscription_event)
    event_router = get_event_router()

    with patch("app.handlers.event_router.redis_service", mock_redis_service), patch(
        "app.handlers.subscription_handler.salesforce_service", mock_salesforce_service
    ):
        mock_redis_service.exists.return_value = False

        result = await event_router.route_event(event)

        assert result["status"] == "success"
        assert result["event_type"] == "customer.subscription.updated"

        # Verify Salesforce was called
        mock_salesforce_service.upsert_subscription.assert_called_once()


@pytest.mark.asyncio
async def test_route_payment_succeeded_event(
    mock_stripe_payment_succeeded_event, mock_redis_service, mock_salesforce_service
):
    """Test routing payment_intent.succeeded event"""

    event = StripeEvent(**mock_stripe_payment_succeeded_event)
    event_router = get_event_router()

    with patch("app.handlers.event_router.redis_service", mock_redis_service), patch(
        "app.handlers.payment_handler.salesforce_service", mock_salesforce_service
    ):
        mock_redis_service.exists.return_value = False

        result = await event_router.route_event(event)

        assert result["status"] == "success"
        assert result["event_type"] == "payment_intent.succeeded"

        # Verify Salesforce was called
        mock_salesforce_service.upsert_payment_transaction.assert_called_once()


@pytest.mark.asyncio
async def test_idempotency_check(mock_stripe_customer_event, mock_redis_service):
    """Test that duplicate events are not processed"""

    event = StripeEvent(**mock_stripe_customer_event)
    event_router = get_event_router()

    with patch("app.handlers.event_router.redis_service", mock_redis_service):
        # Simulate event already processed
        mock_redis_service.exists.return_value = True

        result = await event_router.route_event(event)

        assert result["status"] == "duplicate"
        assert result["event_id"] == event.id
        assert "already processed" in result["message"].lower()


@pytest.mark.asyncio
async def test_unsupported_event_type(mock_redis_service):
    """Test handling of unsupported event types"""

    unsupported_event = {
        "id": "evt_test_unsupported",
        "type": "unsupported.event.type",
        "created": 1234567890,
        "livemode": False,
        "data": {"object": {}},
    }

    event = StripeEvent(**unsupported_event)
    event_router = get_event_router()

    with patch("app.handlers.event_router.redis_service", mock_redis_service):
        mock_redis_service.exists.return_value = False

        result = await event_router.route_event(event)

        assert result["status"] == "unsupported"
        assert result["event_type"] == "unsupported.event.type"
