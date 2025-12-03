"""
Pytest Configuration and Fixtures

Provides common fixtures and test utilities for middleware tests.
"""

import json
import hmac
import hashlib
import time
from typing import Dict, Any
from unittest.mock import AsyncMock, MagicMock

import pytest
from fastapi.testclient import TestClient
from httpx import AsyncClient

from app.main import app
from app.config import settings


@pytest.fixture
def test_client():
    """FastAPI test client"""
    return TestClient(app)


@pytest.fixture
async def async_client():
    """Async HTTP client for testing"""
    async with AsyncClient(app=app, base_url="http://test") as client:
        yield client


@pytest.fixture
def stripe_webhook_secret():
    """Stripe webhook secret for testing"""
    return "whsec_test_secret"


@pytest.fixture
def mock_stripe_customer_event() -> Dict[str, Any]:
    """Mock Stripe customer.updated event"""
    return {
        "id": "evt_test_customer_updated",
        "object": "event",
        "api_version": "2024-10-28",
        "created": int(time.time()),
        "type": "customer.updated",
        "livemode": False,
        "data": {
            "object": {
                "id": "cus_test123",
                "object": "customer",
                "email": "test@example.com",
                "name": "Test Customer",
                "phone": "+1234567890",
                "metadata": {},
            }
        },
    }


@pytest.fixture
def mock_stripe_subscription_event() -> Dict[str, Any]:
    """Mock Stripe customer.subscription.updated event"""
    return {
        "id": "evt_test_subscription_updated",
        "object": "event",
        "api_version": "2024-10-28",
        "created": int(time.time()),
        "type": "customer.subscription.updated",
        "livemode": False,
        "data": {
            "object": {
                "id": "sub_test123",
                "object": "subscription",
                "customer": "cus_test123",
                "status": "active",
                "current_period_start": int(time.time()),
                "current_period_end": int(time.time()) + 2592000,
                "items": {
                    "data": [
                        {
                            "price": {
                                "id": "price_test123",
                                "unit_amount": 2999,
                                "currency": "usd",
                            }
                        }
                    ]
                },
                "metadata": {},
            }
        },
    }


@pytest.fixture
def mock_stripe_payment_succeeded_event() -> Dict[str, Any]:
    """Mock Stripe payment_intent.succeeded event"""
    return {
        "id": "evt_test_payment_succeeded",
        "object": "event",
        "api_version": "2024-10-28",
        "created": int(time.time()),
        "type": "payment_intent.succeeded",
        "livemode": False,
        "data": {
            "object": {
                "id": "pi_test123",
                "object": "payment_intent",
                "amount": 2999,
                "currency": "usd",
                "customer": "cus_test123",
                "status": "succeeded",
                "payment_method_types": ["card"],
                "metadata": {},
            }
        },
    }


@pytest.fixture
def mock_stripe_checkout_completed_event() -> Dict[str, Any]:
    """Mock Stripe checkout.session.completed event"""
    return {
        "id": "evt_test_checkout_completed",
        "object": "event",
        "api_version": "2024-10-28",
        "created": int(time.time()),
        "type": "checkout.session.completed",
        "livemode": False,
        "data": {
            "object": {
                "id": "cs_test123",
                "object": "checkout.session",
                "customer": "cus_test123",
                "subscription": "sub_test123",
                "payment_intent": "pi_test123",
                "payment_status": "paid",
                "status": "complete",
                "metadata": {},
            }
        },
    }


def generate_stripe_signature(payload: str, secret: str) -> str:
    """
    Generate valid Stripe webhook signature for testing.

    Args:
        payload: JSON payload as string
        secret: Webhook secret

    Returns:
        Stripe-Signature header value
    """
    timestamp = str(int(time.time()))
    signed_payload = f"{timestamp}.{payload}"

    signature = hmac.new(
        secret.encode("utf-8"),
        signed_payload.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()

    return f"t={timestamp},v1={signature}"


@pytest.fixture
def mock_valid_stripe_signature(stripe_webhook_secret):
    """Factory to generate valid Stripe signatures"""

    def _signature(payload: Dict[str, Any]) -> str:
        payload_str = json.dumps(payload, separators=(",", ":"))
        return generate_stripe_signature(payload_str, stripe_webhook_secret)

    return _signature


@pytest.fixture
def mock_dynamodb_service():
    """Mock DynamoDB service"""
    mock = AsyncMock()
    mock.get.return_value = None
    mock.set.return_value = True
    mock.exists.return_value = False
    mock.delete.return_value = True
    return mock


@pytest.fixture
def mock_sqs_service():
    """Mock SQS service"""
    mock = AsyncMock()
    mock.send_message.return_value = {"MessageId": "test-message-id"}
    return mock


@pytest.fixture
def mock_salesforce_service():
    """Mock Salesforce service"""
    mock = AsyncMock()
    mock.upsert_customer.return_value = {"id": "a00XX000000XXXX", "success": True}
    mock.upsert_subscription.return_value = {"id": "a01XX000000XXXX", "success": True}
    mock.upsert_payment_transaction.return_value = {
        "id": "a02XX000000XXXX",
        "success": True,
    }
    return mock


@pytest.fixture
def mock_salesforce_oauth():
    """Mock Salesforce OAuth client"""
    mock = AsyncMock()
    mock.get_access_token.return_value = "test_access_token"
    mock.get_instance_url.return_value = "https://test.salesforce.com"
    return mock
