"""
Test data factories for integration tests.
"""
import random
import string
from datetime import datetime, timezone, timedelta
from typing import Dict, Any, Optional, List
from decimal import Decimal

from app.models.stripe_events import EventPriority


class StripeEventFactory:
    """Factory for creating Stripe event test data."""

    @staticmethod
    def _random_id(prefix: str) -> str:
        """Generate random ID."""
        suffix = ''.join(random.choices(string.ascii_lowercase + string.digits, k=14))
        return f"{prefix}_{suffix}"

    @classmethod
    def customer_created(
        cls,
        customer_id: Optional[str] = None,
        email: Optional[str] = None,
        name: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        """Create customer.created event."""
        customer_id = customer_id or cls._random_id("cus")
        email = email or f"{cls._random_id('user')}@example.com"

        return {
            "id": cls._random_id("evt"),
            "type": "customer.created",
            "created": int(datetime.now(timezone.utc).timestamp()),
            "data": {
                "object": {
                    "id": customer_id,
                    "object": "customer",
                    "created": int(datetime.now(timezone.utc).timestamp()),
                    "email": email,
                    "name": name or f"Test Customer {customer_id}",
                    "description": None,
                    "metadata": metadata or {},
                    "balance": 0,
                    "currency": "usd",
                    "delinquent": False,
                }
            }
        }

    @classmethod
    def customer_updated(
        cls,
        customer_id: Optional[str] = None,
        email: Optional[str] = None,
        previous_email: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        """Create customer.updated event."""
        customer_id = customer_id or cls._random_id("cus")
        email = email or f"{cls._random_id('updated')}@example.com"

        event = cls.customer_created(customer_id, email, metadata=metadata)
        event["type"] = "customer.updated"

        if previous_email:
            event["data"]["previous_attributes"] = {
                "email": previous_email
            }

        return event

    @classmethod
    def subscription_created(
        cls,
        subscription_id: Optional[str] = None,
        customer_id: Optional[str] = None,
        status: str = "active",
        plan_id: Optional[str] = None,
        amount: int = 5000,
        interval: str = "month",
        metadata: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        """Create customer.subscription.created event."""
        subscription_id = subscription_id or cls._random_id("sub")
        customer_id = customer_id or cls._random_id("cus")
        plan_id = plan_id or cls._random_id("price")

        current_period_start = int(datetime.now(timezone.utc).timestamp())
        current_period_end = int((datetime.now(timezone.utc) + timedelta(days=30)).timestamp())

        return {
            "id": cls._random_id("evt"),
            "type": "customer.subscription.created",
            "created": int(datetime.now(timezone.utc).timestamp()),
            "data": {
                "object": {
                    "id": subscription_id,
                    "object": "subscription",
                    "customer": customer_id,
                    "status": status,
                    "current_period_start": current_period_start,
                    "current_period_end": current_period_end,
                    "created": int(datetime.now(timezone.utc).timestamp()),
                    "start_date": current_period_start,
                    "metadata": metadata or {},
                    "items": {
                        "object": "list",
                        "data": [
                            {
                                "id": cls._random_id("si"),
                                "object": "subscription_item",
                                "price": {
                                    "id": plan_id,
                                    "object": "price",
                                    "unit_amount": amount,
                                    "currency": "usd",
                                    "recurring": {
                                        "interval": interval,
                                        "interval_count": 1,
                                    }
                                }
                            }
                        ]
                    }
                }
            }
        }

    @classmethod
    def subscription_updated(
        cls,
        subscription_id: Optional[str] = None,
        customer_id: Optional[str] = None,
        status: str = "active",
        previous_status: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        """Create customer.subscription.updated event."""
        event = cls.subscription_created(subscription_id, customer_id, status, metadata=metadata)
        event["type"] = "customer.subscription.updated"

        if previous_status:
            event["data"]["previous_attributes"] = {
                "status": previous_status
            }

        return event

    @classmethod
    def subscription_deleted(
        cls,
        subscription_id: Optional[str] = None,
        customer_id: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        """Create customer.subscription.deleted event."""
        event = cls.subscription_created(subscription_id, customer_id, "canceled", metadata=metadata)
        event["type"] = "customer.subscription.deleted"
        return event

    @classmethod
    def payment_intent_succeeded(
        cls,
        payment_intent_id: Optional[str] = None,
        customer_id: Optional[str] = None,
        amount: int = 5000,
        currency: str = "usd",
        payment_method_type: str = "card",
        metadata: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        """Create payment_intent.succeeded event."""
        payment_intent_id = payment_intent_id or cls._random_id("pi")
        customer_id = customer_id or cls._random_id("cus")

        return {
            "id": cls._random_id("evt"),
            "type": "payment_intent.succeeded",
            "created": int(datetime.now(timezone.utc).timestamp()),
            "data": {
                "object": {
                    "id": payment_intent_id,
                    "object": "payment_intent",
                    "amount": amount,
                    "amount_received": amount,
                    "currency": currency,
                    "customer": customer_id,
                    "status": "succeeded",
                    "created": int(datetime.now(timezone.utc).timestamp()),
                    "metadata": metadata or {},
                    "payment_method": cls._random_id("pm"),
                    "payment_method_types": [payment_method_type],
                    "charges": {
                        "object": "list",
                        "data": [
                            {
                                "id": cls._random_id("ch"),
                                "object": "charge",
                                "amount": amount,
                                "currency": currency,
                                "customer": customer_id,
                                "paid": True,
                                "payment_method": cls._random_id("pm"),
                            }
                        ]
                    }
                }
            }
        }

    @classmethod
    def invoice_payment_failed(
        cls,
        invoice_id: Optional[str] = None,
        customer_id: Optional[str] = None,
        subscription_id: Optional[str] = None,
        amount_due: int = 5000,
        attempt_count: int = 1,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        """Create invoice.payment_failed event."""
        invoice_id = invoice_id or cls._random_id("in")
        customer_id = customer_id or cls._random_id("cus")
        subscription_id = subscription_id or cls._random_id("sub")

        return {
            "id": cls._random_id("evt"),
            "type": "invoice.payment_failed",
            "created": int(datetime.now(timezone.utc).timestamp()),
            "data": {
                "object": {
                    "id": invoice_id,
                    "object": "invoice",
                    "customer": customer_id,
                    "subscription": subscription_id,
                    "amount_due": amount_due,
                    "amount_paid": 0,
                    "amount_remaining": amount_due,
                    "currency": "usd",
                    "status": "open",
                    "attempt_count": attempt_count,
                    "attempted": True,
                    "created": int(datetime.now(timezone.utc).timestamp()),
                    "metadata": metadata or {},
                    "next_payment_attempt": int((datetime.now(timezone.utc) + timedelta(days=3)).timestamp()),
                }
            }
        }

    @classmethod
    def checkout_session_completed(
        cls,
        session_id: Optional[str] = None,
        customer_id: Optional[str] = None,
        subscription_id: Optional[str] = None,
        amount_total: int = 5000,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        """Create checkout.session.completed event."""
        session_id = session_id or cls._random_id("cs")
        customer_id = customer_id or cls._random_id("cus")
        subscription_id = subscription_id or cls._random_id("sub")

        return {
            "id": cls._random_id("evt"),
            "type": "checkout.session.completed",
            "created": int(datetime.now(timezone.utc).timestamp()),
            "data": {
                "object": {
                    "id": session_id,
                    "object": "checkout.session",
                    "customer": customer_id,
                    "subscription": subscription_id,
                    "payment_status": "paid",
                    "status": "complete",
                    "mode": "subscription",
                    "amount_total": amount_total,
                    "currency": "usd",
                    "created": int(datetime.now(timezone.utc).timestamp()),
                    "metadata": metadata or {},
                    "success_url": "https://example.com/success",
                    "cancel_url": "https://example.com/cancel",
                }
            }
        }

    @classmethod
    def checkout_session_expired(
        cls,
        session_id: Optional[str] = None,
        customer_id: Optional[str] = None,
        subscription_id: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        """Create checkout.session.expired event."""
        event = cls.checkout_session_completed(session_id, customer_id, subscription_id, metadata=metadata)
        event["type"] = "checkout.session.expired"
        event["data"]["object"]["payment_status"] = "unpaid"
        event["data"]["object"]["status"] = "expired"
        return event


class SalesforceDataFactory:
    """Factory for creating Salesforce test data."""

    @staticmethod
    def _random_salesforce_id(prefix: str = "003") -> str:
        """Generate random Salesforce ID."""
        suffix = ''.join(random.choices(string.ascii_uppercase + string.digits, k=12))
        return f"{prefix}XX{suffix}"

    @classmethod
    def contact(
        cls,
        contact_id: Optional[str] = None,
        email: Optional[str] = None,
        stripe_customer_id: Optional[str] = None,
        first_name: Optional[str] = None,
        last_name: Optional[str] = None,
    ) -> Dict[str, Any]:
        """Create Salesforce Contact data."""
        contact_id = contact_id or cls._random_salesforce_id("003")
        email = email or f"contact_{random.randint(1000, 9999)}@example.com"

        return {
            "Id": contact_id,
            "Email": email,
            "FirstName": first_name or "Test",
            "LastName": last_name or f"Contact {contact_id[-4:]}",
            "Stripe_Customer_ID__c": stripe_customer_id or f"cus_{random.randint(10000, 99999)}",
            "Sync_Status__c": "Active",
            "Last_Sync__c": datetime.now(timezone.utc).isoformat(),
        }

    @classmethod
    def subscription(
        cls,
        subscription_id: Optional[str] = None,
        contact_id: Optional[str] = None,
        stripe_subscription_id: Optional[str] = None,
        status: str = "Active",
        amount: Decimal = Decimal("50.00"),
    ) -> Dict[str, Any]:
        """Create Salesforce Subscription data."""
        subscription_id = subscription_id or cls._random_salesforce_id("a00")
        contact_id = contact_id or cls._random_salesforce_id("003")

        return {
            "Id": subscription_id,
            "Contact__c": contact_id,
            "Stripe_Subscription_ID__c": stripe_subscription_id or f"sub_{random.randint(10000, 99999)}",
            "Status__c": status,
            "Amount__c": float(amount),
            "Currency__c": "USD",
            "Billing_Period__c": "Monthly",
            "Start_Date__c": datetime.now(timezone.utc).date().isoformat(),
            "Sync_Status__c": "Completed",
            "Last_Sync__c": datetime.now(timezone.utc).isoformat(),
        }

    @classmethod
    def payment(
        cls,
        payment_id: Optional[str] = None,
        contact_id: Optional[str] = None,
        subscription_id: Optional[str] = None,
        stripe_payment_intent_id: Optional[str] = None,
        amount: Decimal = Decimal("50.00"),
        status: str = "Completed",
    ) -> Dict[str, Any]:
        """Create Salesforce Payment data."""
        payment_id = payment_id or cls._random_salesforce_id("a01")
        contact_id = contact_id or cls._random_salesforce_id("003")

        return {
            "Id": payment_id,
            "Contact__c": contact_id,
            "Subscription__c": subscription_id,
            "Stripe_Payment_Intent_ID__c": stripe_payment_intent_id or f"pi_{random.randint(10000, 99999)}",
            "Amount__c": float(amount),
            "Currency__c": "USD",
            "Status__c": status,
            "Payment_Date__c": datetime.now(timezone.utc).isoformat(),
            "Sync_Status__c": "Completed",
        }


class BulkDataFactory:
    """Factory for creating bulk test data."""

    @staticmethod
    def create_customer_batch(size: int = 100) -> List[Dict[str, Any]]:
        """Create batch of customer update events."""
        factory = StripeEventFactory()
        events = []

        for i in range(size):
            events.append(factory.customer_updated(
                customer_id=f"cus_batch_{i:04d}",
                email=f"batch_{i:04d}@example.com",
                metadata={
                    "batch_id": f"batch_{size}",
                    "index": str(i),
                    "segment": random.choice(["enterprise", "pro", "starter"]),
                }
            ))

        return events

    @staticmethod
    def create_mixed_priority_batch(
        high: int = 10,
        medium: int = 10,
        low: int = 10
    ) -> List[Dict[str, Any]]:
        """Create batch with mixed priority events."""
        factory = StripeEventFactory()
        events = []

        # High priority events
        for i in range(high):
            events.append(factory.payment_intent_succeeded(
                customer_id=f"cus_high_{i:03d}",
                amount=random.randint(1000, 10000),
            ))

        # Medium priority events
        for i in range(medium):
            events.append(factory.invoice_payment_failed(
                customer_id=f"cus_medium_{i:03d}",
                amount_due=random.randint(1000, 10000),
            ))

        # Low priority events
        for i in range(low):
            events.append(factory.customer_updated(
                customer_id=f"cus_low_{i:03d}",
            ))

        random.shuffle(events)
        return events

    @staticmethod
    def create_stress_test_batch(total: int = 1000) -> List[Dict[str, Any]]:
        """Create large batch for stress testing."""
        factory = StripeEventFactory()
        events = []

        event_types = [
            ("payment_intent.succeeded", 0.3),
            ("customer.subscription.created", 0.2),
            ("customer.subscription.updated", 0.1),
            ("customer.updated", 0.25),
            ("invoice.payment_failed", 0.1),
            ("checkout.session.completed", 0.05),
        ]

        for i in range(total):
            # Select event type based on probability
            rand = random.random()
            cumulative = 0

            for event_type, probability in event_types:
                cumulative += probability
                if rand <= cumulative:
                    if event_type == "payment_intent.succeeded":
                        event = factory.payment_intent_succeeded(customer_id=f"cus_stress_{i:05d}")
                    elif event_type == "customer.subscription.created":
                        event = factory.subscription_created(customer_id=f"cus_stress_{i:05d}")
                    elif event_type == "customer.subscription.updated":
                        event = factory.subscription_updated(customer_id=f"cus_stress_{i:05d}")
                    elif event_type == "customer.updated":
                        event = factory.customer_updated(customer_id=f"cus_stress_{i:05d}")
                    elif event_type == "invoice.payment_failed":
                        event = factory.invoice_payment_failed(customer_id=f"cus_stress_{i:05d}")
                    else:
                        event = factory.checkout_session_completed(customer_id=f"cus_stress_{i:05d}")

                    events.append(event)
                    break

        return events


class ScenarioFactory:
    """Factory for creating complete test scenarios."""

    @staticmethod
    def subscription_lifecycle() -> Dict[str, Any]:
        """Create complete subscription lifecycle scenario."""
        customer_id = "cus_lifecycle_test"
        subscription_id = "sub_lifecycle_test"
        factory = StripeEventFactory()

        return {
            "customer_id": customer_id,
            "subscription_id": subscription_id,
            "events": [
                factory.customer_created(customer_id=customer_id),
                factory.checkout_session_completed(
                    customer_id=customer_id,
                    subscription_id=subscription_id
                ),
                factory.subscription_created(
                    customer_id=customer_id,
                    subscription_id=subscription_id,
                    status="trialing"
                ),
                factory.payment_intent_succeeded(
                    customer_id=customer_id,
                    amount=5000
                ),
                factory.subscription_updated(
                    customer_id=customer_id,
                    subscription_id=subscription_id,
                    status="active",
                    previous_status="trialing"
                ),
                factory.invoice_payment_failed(
                    customer_id=customer_id,
                    subscription_id=subscription_id
                ),
                factory.subscription_updated(
                    customer_id=customer_id,
                    subscription_id=subscription_id,
                    status="past_due",
                    previous_status="active"
                ),
                factory.payment_intent_succeeded(
                    customer_id=customer_id,
                    amount=5000
                ),
                factory.subscription_updated(
                    customer_id=customer_id,
                    subscription_id=subscription_id,
                    status="active",
                    previous_status="past_due"
                ),
                factory.subscription_deleted(
                    customer_id=customer_id,
                    subscription_id=subscription_id
                ),
            ]
        }

    @staticmethod
    def failed_payment_recovery() -> Dict[str, Any]:
        """Create failed payment recovery scenario."""
        customer_id = "cus_recovery_test"
        subscription_id = "sub_recovery_test"
        factory = StripeEventFactory()

        return {
            "customer_id": customer_id,
            "subscription_id": subscription_id,
            "events": [
                factory.invoice_payment_failed(
                    customer_id=customer_id,
                    subscription_id=subscription_id,
                    attempt_count=1
                ),
                factory.invoice_payment_failed(
                    customer_id=customer_id,
                    subscription_id=subscription_id,
                    attempt_count=2
                ),
                factory.invoice_payment_failed(
                    customer_id=customer_id,
                    subscription_id=subscription_id,
                    attempt_count=3
                ),
                factory.payment_intent_succeeded(
                    customer_id=customer_id,
                    amount=5000,
                    metadata={"retry_attempt": "3"}
                ),
                factory.subscription_updated(
                    customer_id=customer_id,
                    subscription_id=subscription_id,
                    status="active",
                    previous_status="past_due"
                ),
            ]
        }