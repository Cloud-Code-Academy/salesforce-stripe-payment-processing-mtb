"""
Test utilities and helper functions for integration tests.
"""
import json
import asyncio
import boto3
from datetime import datetime, timezone, timedelta
from typing import Dict, Any, List, Optional, Callable
from unittest.mock import AsyncMock, Mock
import hashlib
import hmac


class TestMetrics:
    """Collect and analyze test metrics."""

    def __init__(self):
        self.events_processed = 0
        self.api_calls = {"salesforce": 0, "stripe": 0, "dynamodb": 0, "sqs": 0}
        self.errors = []
        self.latencies = []
        self.start_time = datetime.now(timezone.utc)

    def record_event(self, event_type: str, priority: str):
        """Record an event processing."""
        self.events_processed += 1

    def record_api_call(self, service: str):
        """Record an API call."""
        if service in self.api_calls:
            self.api_calls[service] += 1

    def record_error(self, error: Exception, context: str):
        """Record an error."""
        self.errors.append({
            "error": str(error),
            "type": type(error).__name__,
            "context": context,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        })

    def record_latency(self, operation: str, duration_ms: float):
        """Record operation latency."""
        self.latencies.append({
            "operation": operation,
            "duration_ms": duration_ms,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        })

    def get_summary(self) -> Dict[str, Any]:
        """Get test metrics summary."""
        duration = (datetime.now(timezone.utc) - self.start_time).total_seconds()
        return {
            "duration_seconds": duration,
            "events_processed": self.events_processed,
            "events_per_second": self.events_processed / duration if duration > 0 else 0,
            "api_calls": self.api_calls,
            "total_api_calls": sum(self.api_calls.values()),
            "error_count": len(self.errors),
            "errors": self.errors,
            "average_latency_ms": sum(l["duration_ms"] for l in self.latencies) / len(self.latencies) if self.latencies else 0,
            "max_latency_ms": max(l["duration_ms"] for l in self.latencies) if self.latencies else 0,
        }


class MockAWSServices:
    """Mock AWS services for testing."""

    def __init__(self):
        self.sqs_messages = []
        self.dynamodb_items = {}
        self.secrets = {}

    async def send_sqs_message(self, queue_url: str, message: Dict[str, Any]) -> Dict[str, Any]:
        """Mock SQS send_message."""
        message_id = f"msg-{len(self.sqs_messages):06d}"
        self.sqs_messages.append({
            "MessageId": message_id,
            "QueueUrl": queue_url,
            "Body": message,
            "Timestamp": datetime.now(timezone.utc).isoformat(),
        })
        return {"MessageId": message_id}

    async def get_sqs_messages(self, queue_url: str, max_messages: int = 10) -> List[Dict[str, Any]]:
        """Mock SQS receive_message."""
        messages = [
            msg for msg in self.sqs_messages
            if msg["QueueUrl"] == queue_url
        ][:max_messages]

        # Remove received messages from queue
        for msg in messages:
            self.sqs_messages.remove(msg)

        return messages

    async def put_dynamodb_item(self, table_name: str, item: Dict[str, Any]) -> None:
        """Mock DynamoDB put_item."""
        key = f"{table_name}#{item.get('pk')}#{item.get('sk')}"
        self.dynamodb_items[key] = item

    async def get_dynamodb_item(
        self,
        table_name: str,
        pk: str,
        sk: str
    ) -> Optional[Dict[str, Any]]:
        """Mock DynamoDB get_item."""
        key = f"{table_name}#{pk}#{sk}"
        return self.dynamodb_items.get(key)

    async def query_dynamodb(
        self,
        table_name: str,
        pk: str
    ) -> List[Dict[str, Any]]:
        """Mock DynamoDB query."""
        items = []
        for key, item in self.dynamodb_items.items():
            if key.startswith(f"{table_name}#{pk}#"):
                items.append(item)
        return items

    def set_secret(self, secret_name: str, secret_value: Dict[str, Any]) -> None:
        """Mock Secrets Manager put_secret_value."""
        self.secrets[secret_name] = json.dumps(secret_value)

    def get_secret(self, secret_name: str) -> Dict[str, Any]:
        """Mock Secrets Manager get_secret_value."""
        return json.loads(self.secrets.get(secret_name, "{}"))


class EventSimulator:
    """Simulate Stripe webhook events."""

    def __init__(self, webhook_secret: str = "whsec_test"):
        self.webhook_secret = webhook_secret
        self.event_counter = 0

    def generate_signature(self, payload: str) -> str:
        """Generate valid Stripe webhook signature."""
        timestamp = int(datetime.now(timezone.utc).timestamp())
        signed_payload = f"{timestamp}.{payload}"
        signature = hmac.new(
            self.webhook_secret.encode("utf-8"),
            signed_payload.encode("utf-8"),
            hashlib.sha256
        ).hexdigest()
        return f"t={timestamp},v1={signature}"

    def create_webhook_request(
        self,
        event_type: str,
        event_data: Dict[str, Any],
        invalid_signature: bool = False
    ) -> Dict[str, Any]:
        """Create a webhook request."""
        self.event_counter += 1

        event = {
            "id": f"evt_test_{self.event_counter:06d}",
            "object": "event",
            "api_version": "2023-10-16",
            "created": int(datetime.now(timezone.utc).timestamp()),
            "type": event_type,
            "livemode": False,
            "data": event_data,
        }

        payload = json.dumps(event)
        signature = "invalid" if invalid_signature else self.generate_signature(payload)

        return {
            "httpMethod": "POST",
            "path": "/webhook/stripe",
            "headers": {
                "stripe-signature": signature,
                "content-type": "application/json",
            },
            "body": payload,
        }

    def create_batch_events(
        self,
        event_type: str,
        count: int,
        **kwargs
    ) -> List[Dict[str, Any]]:
        """Create multiple webhook events."""
        events = []
        for i in range(count):
            event_data = {
                "object": {
                    "id": f"{kwargs.get('id_prefix', 'obj')}_{i:03d}",
                    **kwargs.get("extra_fields", {})
                }
            }
            events.append(self.create_webhook_request(event_type, event_data))
        return events


class PerformanceProfiler:
    """Profile performance characteristics."""

    def __init__(self):
        self.measurements = []

    async def measure(self, name: str, func: Callable, *args, **kwargs):
        """Measure function execution time."""
        start = datetime.now(timezone.utc)
        try:
            result = await func(*args, **kwargs) if asyncio.iscoroutinefunction(func) else func(*args, **kwargs)
            duration = (datetime.now(timezone.utc) - start).total_seconds() * 1000
            self.measurements.append({
                "name": name,
                "duration_ms": duration,
                "success": True,
            })
            return result
        except Exception as e:
            duration = (datetime.now(timezone.utc) - start).total_seconds() * 1000
            self.measurements.append({
                "name": name,
                "duration_ms": duration,
                "success": False,
                "error": str(e),
            })
            raise

    def get_report(self) -> Dict[str, Any]:
        """Get performance report."""
        if not self.measurements:
            return {"measurements": 0}

        successful = [m for m in self.measurements if m["success"]]
        failed = [m for m in self.measurements if not m["success"]]

        return {
            "total_measurements": len(self.measurements),
            "successful": len(successful),
            "failed": len(failed),
            "average_duration_ms": sum(m["duration_ms"] for m in successful) / len(successful) if successful else 0,
            "max_duration_ms": max(m["duration_ms"] for m in successful) if successful else 0,
            "min_duration_ms": min(m["duration_ms"] for m in successful) if successful else 0,
            "p95_duration_ms": self._percentile(successful, 95),
            "p99_duration_ms": self._percentile(successful, 99),
        }

    def _percentile(self, measurements: List[Dict], percentile: int) -> float:
        """Calculate percentile."""
        if not measurements:
            return 0
        sorted_durations = sorted(m["duration_ms"] for m in measurements)
        index = int(len(sorted_durations) * (percentile / 100))
        return sorted_durations[min(index, len(sorted_durations) - 1)]


class DataValidator:
    """Validate data consistency."""

    @staticmethod
    def validate_salesforce_customer(customer: Dict[str, Any]) -> List[str]:
        """Validate Salesforce customer data."""
        errors = []
        required_fields = ["Email", "Stripe_Customer_ID__c"]

        for field in required_fields:
            if field not in customer or not customer[field]:
                errors.append(f"Missing required field: {field}")

        if "Email" in customer and "@" not in str(customer.get("Email", "")):
            errors.append("Invalid email format")

        return errors

    @staticmethod
    def validate_salesforce_subscription(subscription: Dict[str, Any]) -> List[str]:
        """Validate Salesforce subscription data."""
        errors = []
        required_fields = ["Stripe_Subscription_ID__c", "Status__c"]

        for field in required_fields:
            if field not in subscription or not subscription[field]:
                errors.append(f"Missing required field: {field}")

        valid_statuses = ["Active", "Canceled", "Past_Due", "Trialing", "Unpaid", "Failed"]
        if subscription.get("Status__c") not in valid_statuses:
            errors.append(f"Invalid status: {subscription.get('Status__c')}")

        return errors

    @staticmethod
    def validate_stripe_event(event: Dict[str, Any]) -> List[str]:
        """Validate Stripe event structure."""
        errors = []
        required_fields = ["id", "type", "data"]

        for field in required_fields:
            if field not in event:
                errors.append(f"Missing required field: {field}")

        if "data" in event and "object" not in event["data"]:
            errors.append("Missing data.object field")

        return errors


class TestDataBuilder:
    """Build test data sets."""

    @staticmethod
    def create_customer_lifecycle() -> List[Dict[str, Any]]:
        """Create events for complete customer lifecycle."""
        customer_id = "cus_lifecycle_test"
        subscription_id = "sub_lifecycle_test"

        return [
            {
                "type": "customer.created",
                "data": {
                    "object": {
                        "id": customer_id,
                        "email": "test@example.com",
                        "name": "Test Customer",
                    }
                }
            },
            {
                "type": "customer.subscription.created",
                "data": {
                    "object": {
                        "id": subscription_id,
                        "customer": customer_id,
                        "status": "trialing",
                        "items": {
                            "data": [
                                {
                                    "price": {
                                        "id": "price_test",
                                        "recurring": {
                                            "interval": "month",
                                        }
                                    }
                                }
                            ]
                        }
                    }
                }
            },
            {
                "type": "customer.subscription.updated",
                "data": {
                    "object": {
                        "id": subscription_id,
                        "customer": customer_id,
                        "status": "active",
                    },
                    "previous_attributes": {
                        "status": "trialing",
                    }
                }
            },
            {
                "type": "payment_intent.succeeded",
                "data": {
                    "object": {
                        "id": "pi_test",
                        "customer": customer_id,
                        "amount": 5000,
                        "currency": "usd",
                    }
                }
            },
            {
                "type": "customer.subscription.deleted",
                "data": {
                    "object": {
                        "id": subscription_id,
                        "customer": customer_id,
                        "status": "canceled",
                    }
                }
            },
        ]

    @staticmethod
    def create_bulk_update_batch(size: int = 100) -> List[Dict[str, Any]]:
        """Create batch of customer updates for bulk processing."""
        events = []
        for i in range(size):
            events.append({
                "type": "customer.updated",
                "data": {
                    "object": {
                        "id": f"cus_bulk_{i:04d}",
                        "email": f"bulk_{i:04d}@example.com",
                        "metadata": {
                            "batch_test": "true",
                            "index": str(i),
                        }
                    }
                }
            })
        return events


def assert_eventually(
    condition: Callable[[], bool],
    timeout: int = 10,
    interval: float = 0.5,
    message: str = "Condition not met"
):
    """Assert that a condition becomes true within timeout."""
    start = datetime.now(timezone.utc)
    while (datetime.now(timezone.utc) - start).total_seconds() < timeout:
        if condition():
            return
        asyncio.sleep(interval)
    raise AssertionError(f"{message} (timeout: {timeout}s)")