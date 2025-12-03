"""
Shared fixtures for integration tests.
"""
import os
import json
import asyncio
import pytest
import boto3
from datetime import datetime, timezone
from typing import Dict, Any, Optional, AsyncGenerator
from unittest.mock import Mock, AsyncMock, patch
from moto import mock_sqs, mock_dynamodb, mock_secretsmanager
import aioboto3
from cryptography.hazmat.primitives import hashes, hmac
from cryptography.hazmat.backends import default_backend

from app.models.stripe_events import StripeEvent, EventPriority
from app.services.dynamodb_service import DynamoDBService
from app.services.sqs_service import SQSService
from app.services.salesforce_service import SalesforceService
from app.services.bulk_api_service import BulkAPIService
from app.services.batch_accumulator import BatchAccumulator
from app.config import Settings


# Test configuration
TEST_STRIPE_WEBHOOK_SECRET = "whsec_test_secret_12345"
TEST_STRIPE_API_KEY = "sk_test_12345"
TEST_SALESFORCE_CLIENT_ID = "test_client_id"
TEST_SALESFORCE_CLIENT_SECRET = "test_client_secret"
TEST_SALESFORCE_USERNAME = "test@salesforce.com"
TEST_SALESFORCE_PASSWORD = "test_password"
TEST_SALESFORCE_SECURITY_TOKEN = "test_token"


@pytest.fixture(scope="session")
def event_loop():
    """Create an event loop for async tests."""
    loop = asyncio.get_event_loop_policy().new_event_loop()
    yield loop
    loop.close()


@pytest.fixture
def test_settings():
    """Create test settings."""
    return Settings(
        environment="test",
        stripe_api_key=TEST_STRIPE_API_KEY,
        stripe_webhook_secret=TEST_STRIPE_WEBHOOK_SECRET,
        salesforce_client_id=TEST_SALESFORCE_CLIENT_ID,
        salesforce_client_secret=TEST_SALESFORCE_CLIENT_SECRET,
        salesforce_username=TEST_SALESFORCE_USERNAME,
        salesforce_password=TEST_SALESFORCE_PASSWORD,
        salesforce_security_token=TEST_SALESFORCE_SECURITY_TOKEN,
        salesforce_domain="test.salesforce.com",
        dynamodb_table_name="test-stripe-events",
        sqs_queue_url="https://sqs.us-east-1.amazonaws.com/123456789012/test-queue",
        low_priority_queue_url="https://sqs.us-east-1.amazonaws.com/123456789012/test-low-queue",
        log_level="DEBUG",
    )


@pytest.fixture
@mock_dynamodb
async def dynamodb_service(test_settings):
    """Create DynamoDB service with mocked tables."""
    # Create tables
    dynamodb = boto3.resource("dynamodb", region_name="us-east-1")

    # Main cache table
    dynamodb.create_table(
        TableName=test_settings.dynamodb_table_name,
        KeySchema=[
            {"AttributeName": "pk", "KeyType": "HASH"},
            {"AttributeName": "sk", "KeyType": "RANGE"},
        ],
        AttributeDefinitions=[
            {"AttributeName": "pk", "AttributeType": "S"},
            {"AttributeName": "sk", "AttributeType": "S"},
        ],
        BillingMode="PAY_PER_REQUEST",
    )

    # Batch accumulator table
    dynamodb.create_table(
        TableName="test-batch-accumulator",
        KeySchema=[
            {"AttributeName": "pk", "KeyType": "HASH"},
            {"AttributeName": "sk", "KeyType": "RANGE"},
        ],
        AttributeDefinitions=[
            {"AttributeName": "pk", "AttributeType": "S"},
            {"AttributeName": "sk", "AttributeType": "S"},
        ],
        BillingMode="PAY_PER_REQUEST",
    )

    service = DynamoDBService()
    service.table_name = test_settings.dynamodb_table_name
    return service


@pytest.fixture
@mock_sqs
async def sqs_service(test_settings):
    """Create SQS service with mocked queues."""
    sqs_client = boto3.client("sqs", region_name="us-east-1")

    # Create main queue
    main_queue = sqs_client.create_queue(
        QueueName="test-queue",
        Attributes={
            "VisibilityTimeout": "60",
            "MessageRetentionPeriod": "345600",
        },
    )

    # Create low-priority queue
    low_queue = sqs_client.create_queue(
        QueueName="test-low-queue",
        Attributes={
            "VisibilityTimeout": "300",
            "MessageRetentionPeriod": "345600",
        },
    )

    # Create DLQ
    dlq = sqs_client.create_queue(
        QueueName="test-dlq",
        Attributes={
            "MessageRetentionPeriod": "1209600",  # 14 days
        },
    )

    service = SQSService()
    service.queue_url = main_queue["QueueUrl"]
    service.low_priority_queue_url = low_queue["QueueUrl"]
    service.dlq_url = dlq["QueueUrl"]
    return service


@pytest.fixture
async def mock_salesforce_service():
    """Create mocked Salesforce service."""
    service = AsyncMock(spec=SalesforceService)

    # Mock authentication
    service.authenticate = AsyncMock(return_value={
        "access_token": "test_token",
        "instance_url": "https://test.salesforce.com",
    })

    # Mock REST API operations
    service.upsert_customer = AsyncMock(return_value={
        "id": "003XX000001234",
        "success": True,
    })

    service.upsert_subscription = AsyncMock(return_value={
        "id": "a00XX000001234",
        "success": True,
    })

    service.upsert_payment = AsyncMock(return_value={
        "id": "a01XX000001234",
        "success": True,
    })

    return service


@pytest.fixture
async def mock_bulk_api_service():
    """Create mocked Bulk API service."""
    service = AsyncMock(spec=BulkAPIService)

    # Mock job operations
    service.create_job = AsyncMock(return_value={
        "id": "750XX000001234",
        "state": "Open",
        "object": "Contact",
    })

    service.upload_job_data = AsyncMock(return_value={"success": True})

    service.close_job = AsyncMock(return_value={
        "id": "750XX000001234",
        "state": "InProgress",
    })

    service.get_job_info = AsyncMock(return_value={
        "id": "750XX000001234",
        "state": "JobComplete",
        "numberRecordsProcessed": 200,
        "numberRecordsFailed": 0,
    })

    service.upsert_records = AsyncMock(return_value={
        "job_id": "750XX000001234",
        "status": "JobComplete",
        "results": {
            "processed": 200,
            "failed": 0,
        },
    })

    return service


@pytest.fixture
async def batch_accumulator(dynamodb_service):
    """Create batch accumulator with test configuration."""
    accumulator = BatchAccumulator()
    accumulator.table_name = "test-batch-accumulator"
    accumulator.size_threshold = 10  # Lower threshold for testing
    accumulator.time_threshold = 5   # 5 seconds for testing
    accumulator.dynamodb = dynamodb_service
    return accumulator


@pytest.fixture
def stripe_event_factory():
    """Factory for creating Stripe events."""
    def create_event(
        event_type: str,
        event_id: Optional[str] = None,
        customer_id: Optional[str] = None,
        subscription_id: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        event_id = event_id or f"evt_test_{datetime.now(timezone.utc).timestamp()}"

        event_data = {
            "id": event_id,
            "object": "event",
            "api_version": "2023-10-16",
            "created": int(datetime.now(timezone.utc).timestamp()),
            "type": event_type,
            "livemode": False,
            "pending_webhooks": 1,
            "request": {"id": None, "idempotency_key": None},
        }

        # Add event-specific data
        if event_type == "customer.updated":
            event_data["data"] = {
                "object": {
                    "id": customer_id or "cus_test123",
                    "object": "customer",
                    "email": "test@example.com",
                    "name": "Test Customer",
                    "metadata": metadata or {},
                }
            }
        elif event_type == "customer.subscription.created":
            event_data["data"] = {
                "object": {
                    "id": subscription_id or "sub_test123",
                    "object": "subscription",
                    "customer": customer_id or "cus_test123",
                    "status": "active",
                    "current_period_start": int(datetime.now(timezone.utc).timestamp()),
                    "current_period_end": int(datetime.now(timezone.utc).timestamp()) + 2592000,
                    "metadata": metadata or {},
                }
            }
        elif event_type == "payment_intent.succeeded":
            event_data["data"] = {
                "object": {
                    "id": "pi_test123",
                    "object": "payment_intent",
                    "amount": 5000,
                    "currency": "usd",
                    "customer": customer_id or "cus_test123",
                    "status": "succeeded",
                    "metadata": metadata or {},
                }
            }
        elif event_type == "checkout.session.completed":
            event_data["data"] = {
                "object": {
                    "id": "cs_test123",
                    "object": "checkout.session",
                    "customer": customer_id or "cus_test123",
                    "subscription": subscription_id or "sub_test123",
                    "payment_status": "paid",
                    "metadata": metadata or {},
                }
            }
        elif event_type == "checkout.session.expired":
            event_data["data"] = {
                "object": {
                    "id": "cs_test456",
                    "object": "checkout.session",
                    "customer": customer_id or "cus_test123",
                    "subscription": subscription_id or "sub_test123",
                    "payment_status": "unpaid",
                    "metadata": metadata or {},
                }
            }

        return event_data

    return create_event


@pytest.fixture
def generate_stripe_signature():
    """Generate valid Stripe webhook signature."""
    def _generate(payload: str, secret: str = TEST_STRIPE_WEBHOOK_SECRET) -> str:
        timestamp = int(datetime.now(timezone.utc).timestamp())
        signed_payload = f"{timestamp}.{payload}"

        # Compute HMAC
        h = hmac.HMAC(
            secret.encode("utf-8"),
            hashes.SHA256(),
            backend=default_backend()
        )
        h.update(signed_payload.encode("utf-8"))
        signature = h.finalize().hex()

        return f"t={timestamp},v1={signature}"

    return _generate


@pytest.fixture
@mock_secretsmanager
async def secrets_manager():
    """Create mocked AWS Secrets Manager."""
    client = boto3.client("secretsmanager", region_name="us-east-1")

    # Create test secrets
    client.create_secret(
        Name="stripe-api-key",
        SecretString=json.dumps({"api_key": TEST_STRIPE_API_KEY}),
    )

    client.create_secret(
        Name="stripe-webhook-secret",
        SecretString=json.dumps({"webhook_secret": TEST_STRIPE_WEBHOOK_SECRET}),
    )

    client.create_secret(
        Name="salesforce-credentials",
        SecretString=json.dumps({
            "client_id": TEST_SALESFORCE_CLIENT_ID,
            "client_secret": TEST_SALESFORCE_CLIENT_SECRET,
            "username": TEST_SALESFORCE_USERNAME,
            "password": TEST_SALESFORCE_PASSWORD,
            "security_token": TEST_SALESFORCE_SECURITY_TOKEN,
        }),
    )

    return client


@pytest.fixture
def mock_lambda_context():
    """Create mock Lambda context."""
    context = Mock()
    context.function_name = "test-function"
    context.function_version = "$LATEST"
    context.invoked_function_arn = "arn:aws:lambda:us-east-1:123456789012:function:test-function"
    context.memory_limit_in_mb = "128"
    context.aws_request_id = "test-request-id"
    context.log_group_name = "/aws/lambda/test-function"
    context.log_stream_name = "2024/01/01/[$LATEST]test-stream"
    context.get_remaining_time_in_millis = Mock(return_value=30000)
    return context