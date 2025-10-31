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
        "paused",
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
    object: Optional[str] = Field(None, description="Object type")
    amount: int = Field(description="Amount in smallest currency unit")
    amount_capturable: Optional[int] = Field(
        None, description="Amount that can be captured"
    )
    amount_received: Optional[int] = Field(
        None, description="Amount that was collected"
    )
    application: Optional[str] = Field(None, description="Connect application ID")
    application_fee_amount: Optional[int] = Field(None, description="Application fee")
    canceled_at: Optional[int] = Field(
        None, description="Unix timestamp when canceled"
    )
    cancellation_reason: Optional[
        Literal[
            "abandoned",
            "automatic",
            "duplicate",
            "expired",
            "failed_invoice",
            "fraudulent",
            "requested_by_customer",
            "void_invoice",
        ]
    ] = Field(None, description="Reason for cancellation")
    capture_method: Optional[Literal["automatic", "automatic_async", "manual"]] = (
        Field(None, description="When funds will be captured")
    )
    client_secret: Optional[str] = Field(None, description="Client secret")
    confirmation_method: Optional[Literal["automatic", "manual"]] = Field(
        None, description="Confirmation method"
    )
    created: Optional[int] = Field(None, description="Unix timestamp when created")
    currency: str = Field(description="Three-letter ISO currency code")
    customer: Optional[str] = Field(None, description="Customer ID")
    description: Optional[str] = Field(None, description="Description")
    invoice: Optional[str] = Field(None, description="Invoice ID")
    livemode: Optional[bool] = Field(None, description="Live mode flag")
    payment_method: Optional[str] = Field(None, description="Payment method ID")
    receipt_email: Optional[str] = Field(None, description="Receipt email")
    setup_future_usage: Optional[Literal["off_session", "on_session"]] = Field(
        None, description="Setup for future usage"
    )
    status: Literal[
        "requires_payment_method",
        "requires_confirmation",
        "requires_action",
        "processing",
        "requires_capture",
        "canceled",
        "succeeded",
    ]
    metadata: Dict[str, Any] = Field(default_factory=dict)


class StripeCheckoutSessionData(BaseModel):
    """Stripe checkout session data"""

    id: str = Field(description="Checkout session ID")
    customer: Optional[str] = Field(None, description="Customer ID")
    subscription: Optional[str] = Field(None, description="Subscription ID")
    payment_intent: Optional[str] = Field(None, description="Payment intent ID")
    payment_status: str
    status: Literal["open", "complete", "expired"]
    metadata: Dict[str, Any] = Field(default_factory=dict)


class StripeInvoiceData(BaseModel):
    """Stripe invoice data"""

    id: str = Field(description="Invoice ID")
    object: Optional[str] = Field(None, description="Object type")
    customer: str = Field(description="Customer ID")
    subscription: Optional[str] = Field(None, description="Subscription ID")
    amount_due: int = Field(description="Final amount due")
    amount_paid: int = Field(description="Amount paid")
    amount_remaining: int = Field(description="Amount remaining")
    attempt_count: int = Field(description="Number of payment attempts")
    attempted: bool = Field(description="Whether payment was attempted")
    billing_reason: Optional[
        Literal[
            "automatic_pending_invoice_item_invoice",
            "manual",
            "quote_accept",
            "subscription",
            "subscription_create",
            "subscription_cycle",
            "subscription_threshold",
            "subscription_update",
            "upcoming",
        ]
    ] = Field(None, description="Reason invoice was created")
    collection_method: Literal["charge_automatically", "send_invoice"] = Field(
        description="Payment collection method"
    )
    created: int = Field(description="Unix timestamp when created")
    currency: str = Field(description="Three-letter ISO currency code")
    customer_email: Optional[str] = Field(None, description="Customer email")
    customer_name: Optional[str] = Field(None, description="Customer name")
    description: Optional[str] = Field(None, description="Invoice description")
    due_date: Optional[int] = Field(None, description="Unix timestamp when due")
    hosted_invoice_url: Optional[str] = Field(
        None, description="URL for hosted invoice page"
    )
    invoice_pdf: Optional[str] = Field(None, description="PDF download link")
    livemode: Optional[bool] = Field(None, description="Live mode flag")
    number: Optional[str] = Field(None, description="Invoice number")
    paid: Optional[bool] = Field(None, description="Whether invoice is paid")
    payment_intent: Optional[str] = Field(None, description="Payment intent ID")
    period_end: Optional[int] = Field(None, description="Period end timestamp")
    period_start: Optional[int] = Field(None, description="Period start timestamp")
    status: Optional[
        Literal["draft", "open", "paid", "uncollectible", "void"]
    ] = Field(None, description="Invoice status")
    subtotal: Optional[int] = Field(None, description="Subtotal amount")
    total: int = Field(description="Total after discounts and taxes")
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


class InvoicePaymentSucceededEvent(StripeEvent):
    """invoice.payment_succeeded event"""

    type: Literal["invoice.payment_succeeded"] = "invoice.payment_succeeded"


class InvoicePaymentFailedEvent(StripeEvent):
    """invoice.payment_failed event"""

    type: Literal["invoice.payment_failed"] = "invoice.payment_failed"


class CheckoutSessionExpiredEvent(StripeEvent):
    """checkout.session.expired event"""

    type: Literal["checkout.session.expired"] = "checkout.session.expired"


# Webhook request model
class WebhookRequest(BaseModel):
    """Model for incoming webhook request"""

    event: StripeEvent
    correlation_id: str = Field(description="Request correlation ID")
    received_at: datetime = Field(default_factory=datetime.utcnow)
