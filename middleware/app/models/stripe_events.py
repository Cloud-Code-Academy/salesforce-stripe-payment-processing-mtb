"""
Stripe Event Models

Pydantic models for Stripe webhook events validation.
"""

from datetime import datetime
from typing import Any, Dict, Literal, Optional

from pydantic import BaseModel, Field


class StripeEventMetadata(BaseModel):
    """Base metadata for Stripe events"""

    pass


class StripeCustomerData(BaseModel):
    """Stripe customer data"""

    id: str = Field(description="Stripe customer ID")
    email: Optional[str] = Field(None, description="Customer email")
    name: Optional[str] = Field(None, description="Customer name")
    phone: Optional[str] = Field(None, description="Customer phone")
    metadata: Dict[str, Any] = Field(default_factory=dict)


class StripeSubscriptionData(BaseModel):
    """Stripe subscription data"""

    id: str = Field(description="Stripe subscription ID")
    customer: str = Field(description="Customer ID")
    status: Literal[
        "active",
        "canceled",
        "incomplete",
        "incomplete_expired",
        "past_due",
        "trialing",
        "unpaid",
    ]
    current_period_start: int = Field(description="Unix timestamp")
    current_period_end: int = Field(description="Unix timestamp")
    items: Dict[str, Any] = Field(default_factory=dict)
    metadata: Dict[str, Any] = Field(default_factory=dict)


class StripePaymentIntentData(BaseModel):
    """Stripe payment intent data"""

    id: str = Field(description="Payment intent ID")
    amount: int = Field(description="Amount in cents")
    currency: str = Field(description="Three-letter ISO currency code")
    customer: Optional[str] = Field(None, description="Customer ID")
    status: Literal[
        "requires_payment_method",
        "requires_confirmation",
        "requires_action",
        "processing",
        "requires_capture",
        "canceled",
        "succeeded",
    ]
    payment_method: Optional[str] = Field(None)
    metadata: Dict[str, Any] = Field(default_factory=dict)


class StripeCheckoutSessionData(BaseModel):
    """Stripe checkout session data"""

    id: str = Field(description="Checkout session ID")
    customer: Optional[str] = Field(None, description="Customer ID")
    subscription: Optional[str] = Field(None, description="Subscription ID")
    payment_intent: Optional[str] = Field(None, description="Payment intent ID")
    payment_status: str
    status: str
    metadata: Dict[str, Any] = Field(default_factory=dict)


class StripeEventData(BaseModel):
    """Stripe event data wrapper"""

    object: Dict[str, Any] = Field(description="The Stripe object")
    previous_attributes: Optional[Dict[str, Any]] = Field(
        None, description="Previous object state for update events"
    )


class StripeEvent(BaseModel):
    """
    Stripe webhook event model.
    Represents the complete webhook payload from Stripe.
    """

    id: str = Field(description="Unique event identifier")
    type: str = Field(description="Event type (e.g., payment_intent.succeeded)")
    created: int = Field(description="Unix timestamp of event creation")
    livemode: bool = Field(description="Whether in live mode")
    data: StripeEventData = Field(description="Event data")
    api_version: Optional[str] = Field(None)
    request: Optional[Dict[str, Any]] = Field(None)

    @property
    def event_object(self) -> Dict[str, Any]:
        """Get the main event object"""
        return self.data.object

    @property
    def event_type_category(self) -> str:
        """Get the event category (e.g., 'customer' from 'customer.updated')"""
        return self.type.split(".")[0] if "." in self.type else self.type

    @property
    def event_action(self) -> str:
        """Get the event action (e.g., 'updated' from 'customer.updated')"""
        parts = self.type.split(".")
        return parts[-1] if len(parts) > 1 else ""


# Event type discriminators for better type safety
class CustomerUpdatedEvent(StripeEvent):
    """customer.updated event"""

    type: Literal["customer.updated"] = "customer.updated"


class CheckoutSessionCompletedEvent(StripeEvent):
    """checkout.session.completed event"""

    type: Literal["checkout.session.completed"] = "checkout.session.completed"


class PaymentIntentSucceededEvent(StripeEvent):
    """payment_intent.succeeded event"""

    type: Literal["payment_intent.succeeded"] = "payment_intent.succeeded"


class PaymentIntentFailedEvent(StripeEvent):
    """payment_intent.payment_failed event"""

    type: Literal["payment_intent.payment_failed"] = "payment_intent.payment_failed"


class SubscriptionUpdatedEvent(StripeEvent):
    """customer.subscription.updated event"""

    type: Literal["customer.subscription.updated"] = "customer.subscription.updated"


class SubscriptionCreatedEvent(StripeEvent):
    """customer.subscription.created event"""

    type: Literal["customer.subscription.created"] = "customer.subscription.created"


class SubscriptionDeletedEvent(StripeEvent):
    """customer.subscription.deleted event"""

    type: Literal["customer.subscription.deleted"] = "customer.subscription.deleted"


# Webhook request model
class WebhookRequest(BaseModel):
    """Model for incoming webhook request"""

    event: StripeEvent
    correlation_id: str = Field(description="Request correlation ID")
    received_at: datetime = Field(default_factory=datetime.utcnow)
