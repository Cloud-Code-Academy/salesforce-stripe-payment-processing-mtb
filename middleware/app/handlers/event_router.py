"""
Event Router

Routes Stripe webhook events to appropriate handlers based on event type.
Implements idempotency tracking to prevent duplicate processing.
"""

from typing import Dict, Any

from app.models.stripe_events import StripeEvent
from app.services.redis_service import redis_service
from app.utils.exceptions import ValidationException
from app.utils.logging_config import get_logger

logger = get_logger(__name__)


class EventRouter:
    """Routes events to appropriate handlers"""

    def __init__(self):
        # Import handlers here to avoid circular imports
        from app.handlers.customer_handler import customer_handler
        from app.handlers.subscription_handler import subscription_handler
        from app.handlers.payment_handler import payment_handler

        # Register event handlers
        self.handlers: Dict[str, Any] = {
            "customer.updated": customer_handler.handle_customer_updated,
            "checkout.session.completed": subscription_handler.handle_checkout_completed,
            "customer.subscription.created": subscription_handler.handle_subscription_created,
            "customer.subscription.updated": subscription_handler.handle_subscription_updated,
            "customer.subscription.deleted": subscription_handler.handle_subscription_deleted,
            "payment_intent.succeeded": payment_handler.handle_payment_succeeded,
            "payment_intent.payment_failed": payment_handler.handle_payment_failed,
        }

    async def is_event_processed(self, event_id: str) -> bool:
        """
        Check if event has already been processed (idempotency check).

        Args:
            event_id: Stripe event ID

        Returns:
            True if event was already processed
        """
        key = f"stripe:event:processed:{event_id}"
        return await redis_service.exists(key)

    async def mark_event_processed(self, event_id: str, ttl: int = 86400) -> None:
        """
        Mark event as processed.

        Args:
            event_id: Stripe event ID
            ttl: Time to live in seconds (default 24 hours)
        """
        key = f"stripe:event:processed:{event_id}"
        await redis_service.set(key, "1", ttl=ttl)
        logger.debug(f"Marked event {event_id} as processed")

    async def route_event(self, event: StripeEvent) -> Dict[str, Any]:
        """
        Route event to appropriate handler.

        Args:
            event: Validated Stripe event

        Returns:
            Handler response

        Raises:
            ValidationException: If event type is not supported
        """
        event_type = event.type
        event_id = event.id

        logger.info(
            f"Routing event",
            extra={
                "event_id": event_id,
                "event_type": event_type,
            },
        )

        # Check idempotency
        if await self.is_event_processed(event_id):
            logger.warning(
                f"Event {event_id} already processed (idempotency check)",
                extra={"event_id": event_id},
            )
            return {
                "status": "duplicate",
                "event_id": event_id,
                "message": "Event already processed",
            }

        # Get handler for event type
        handler = self.handlers.get(event_type)

        if not handler:
            logger.warning(
                f"No handler registered for event type: {event_type}",
                extra={"event_type": event_type, "event_id": event_id},
            )
            # Mark as processed even if not supported to avoid reprocessing
            await self.mark_event_processed(event_id)
            return {
                "status": "unsupported",
                "event_id": event_id,
                "event_type": event_type,
                "message": f"Event type {event_type} not supported",
            }

        # Execute handler
        try:
            logger.info(
                f"Processing event {event_id} with handler",
                extra={
                    "event_id": event_id,
                    "event_type": event_type,
                    "handler": handler.__name__,
                },
            )

            result = await handler(event)

            # Mark as processed after successful handling
            await self.mark_event_processed(event_id)

            logger.info(
                f"Successfully processed event {event_id}",
                extra={
                    "event_id": event_id,
                    "event_type": event_type,
                },
            )

            return {
                "status": "success",
                "event_id": event_id,
                "event_type": event_type,
                "result": result,
            }

        except Exception as e:
            logger.error(
                f"Error processing event {event_id}: {e}",
                extra={
                    "event_id": event_id,
                    "event_type": event_type,
                    "error": str(e),
                },
            )
            # Don't mark as processed on failure to allow retry
            raise


# Global event router instance
event_router = EventRouter()
