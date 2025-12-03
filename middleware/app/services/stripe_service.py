"""
Stripe Service

Handles Stripe webhook signature verification and event validation.
"""

import stripe
from fastapi import Request

from app.config import settings
from app.models.stripe_events import StripeEvent
from app.utils.exceptions import StripeException, StripeSignatureException
from app.utils.logging_config import get_logger

logger = get_logger(__name__)

# Configure Stripe
stripe.api_key = settings.stripe_api_key
stripe.api_version = settings.stripe_api_version


class StripeService:
    """Stripe webhook and API service"""

    def __init__(self):
        self.webhook_secret = settings.stripe_webhook_secret

    async def verify_webhook_signature(
        self,
        payload: bytes,
        signature: str,
    ) -> StripeEvent:
        """
        Verify Stripe webhook signature using HMAC-SHA256.

        Args:
            payload: Raw request body as bytes
            signature: Stripe-Signature header value

        Returns:
            Validated StripeEvent

        Raises:
            StripeSignatureException: If signature verification fails
            StripeException: If event construction fails
        """
        try:
            # Verify signature and construct event
            event = stripe.Webhook.construct_event(
                payload,
                signature,
                self.webhook_secret,
            )

            logger.info(
                f"Webhook signature verified successfully",
                extra={
                    "event_id": event.get("id"),
                    "event_type": event.get("type"),
                },
            )

            # Parse into Pydantic model for validation
            stripe_event = StripeEvent(**event)
            return stripe_event

        except stripe.error.SignatureVerificationError as e:
            logger.error(
                f"Stripe signature verification failed: {e}",
                extra={"error": str(e)},
            )
            raise StripeSignatureException(
                "Invalid Stripe webhook signature"
            ) from e

        except ValueError as e:
            logger.error(f"Invalid webhook payload: {e}")
            raise StripeException(
                "Invalid webhook payload",
                details={"error": str(e)},
            ) from e

        except Exception as e:
            logger.error(f"Unexpected error verifying webhook: {e}")
            raise StripeException(
                "Failed to verify webhook",
                details={"error": str(e)},
            ) from e

    async def extract_webhook_data(self, request: Request) -> tuple[bytes, str]:
        """
        Extract webhook payload and signature from request.

        Args:
            request: FastAPI request object

        Returns:
            Tuple of (payload bytes, signature string)

        Raises:
            StripeException: If required data is missing
        """
        try:
            # Get raw request body
            payload = await request.body()

            # Get Stripe signature header
            signature = request.headers.get("Stripe-Signature")

            if not signature:
                raise StripeException(
                    "Missing Stripe-Signature header",
                    details={"header": "Stripe-Signature"},
                )

            if not payload:
                raise StripeException(
                    "Empty request body",
                    details={"body": "empty"},
                )

            return payload, signature

        except Exception as e:
            if isinstance(e, StripeException):
                raise
            logger.error(f"Error extracting webhook data: {e}")
            raise StripeException(
                "Failed to extract webhook data",
                details={"error": str(e)},
            )

    def is_event_type_supported(self, event_type: str) -> bool:
        """
        Check if event type is supported for processing.

        Args:
            event_type: Stripe event type

        Returns:
            True if event type is supported
        """
        supported_events = {
            "checkout.session.completed",
            "payment_intent.succeeded",
            "payment_intent.payment_failed",
            "customer.subscription.updated",
            "customer.subscription.created",
            "customer.subscription.deleted",
            "customer.updated",
            "product.created",
            "product.updated",
            "product.deleted",
            "price.created",
            "price.updated",
            "price.deleted",
        }

        is_supported = event_type in supported_events

        if not is_supported:
            logger.debug(
                f"Event type not supported: {event_type}",
                extra={"event_type": event_type},
            )

        return is_supported

    async def get_customer(self, customer_id: str) -> dict:
        """
        Retrieve customer from Stripe API.

        Args:
            customer_id: Stripe customer ID

        Returns:
            Customer object

        Raises:
            StripeException: If retrieval fails
        """
        try:
            customer = stripe.Customer.retrieve(customer_id)
            logger.info(
                f"Retrieved customer from Stripe",
                extra={"customer_id": customer_id},
            )
            return customer
        except stripe.error.StripeError as e:
            logger.error(f"Failed to retrieve customer {customer_id}: {e}")
            raise StripeException(
                f"Failed to retrieve customer",
                details={"customer_id": customer_id, "error": str(e)},
            ) from e

    async def get_subscription(self, subscription_id: str) -> dict:
        """
        Retrieve subscription from Stripe API.

        Args:
            subscription_id: Stripe subscription ID

        Returns:
            Subscription object

        Raises:
            StripeException: If retrieval fails
        """
        try:
            subscription = stripe.Subscription.retrieve(subscription_id)
            logger.info(
                f"Retrieved subscription from Stripe",
                extra={"subscription_id": subscription_id},
            )
            return subscription
        except stripe.error.StripeError as e:
            logger.error(f"Failed to retrieve subscription {subscription_id}: {e}")
            raise StripeException(
                f"Failed to retrieve subscription",
                details={"subscription_id": subscription_id, "error": str(e)},
            ) from e

    async def get_product(self, product_id: str) -> dict:
        """
        Retrieve product from Stripe API.

        Args:
            product_id: Stripe product ID

        Returns:
            Product object with name and metadata

        Raises:
            StripeException: If retrieval fails
        """
        try:
            product = stripe.Product.retrieve(product_id)
            logger.info(
                f"Retrieved product from Stripe",
                extra={"product_id": product_id, "product_name": product.get("name")},
            )
            return product
        except stripe.error.StripeError as e:
            logger.error(f"Failed to retrieve product {product_id}: {e}")
            raise StripeException(
                f"Failed to retrieve product",
                details={"product_id": product_id, "error": str(e)},
            ) from e


# Global Stripe service instance
stripe_service = StripeService()
