"""
Subscription Event Handler

Handles Stripe subscription-related webhook events.
"""

from datetime import datetime
from typing import Dict, Any

from app.models.stripe_events import StripeEvent
from app.models.salesforce_records import SalesforceSubscription
from app.services.salesforce_service import salesforce_service
from app.utils.logging_config import get_logger

logger = get_logger(__name__)


class SubscriptionHandler:
    """Handler for subscription events"""

    async def handle_checkout_completed(self, event: StripeEvent) -> Dict[str, Any]:
        """
        Handle checkout.session.completed event.
        Updates subscription status to Completed in Salesforce.

        Args:
            event: Stripe webhook event

        Returns:
            Processing result
        """
        session_data = event.event_object

        logger.info(
            f"Processing checkout.session.completed event",
            extra={
                "event_id": event.id,
                "session_id": session_data.get("id"),
                "subscription_id": session_data.get("subscription"),
            },
        )

        subscription_id = session_data.get("subscription")
        if not subscription_id:
            logger.warning("No subscription ID in checkout session")
            return {
                "status": "skipped",
                "reason": "No subscription in checkout session",
            }

        # Update subscription sync status in Salesforce
        salesforce_subscription = SalesforceSubscription(
            Stripe_Subscription_ID__c=subscription_id,
            Stripe_Checkout_Session_ID__c=session_data.get("id"),
            Stripe_Customer__c=session_data.get("customer"),
            Sync_Status__c="Completed",
        )

        result = await salesforce_service.upsert_subscription(salesforce_subscription)

        logger.info(
            f"Checkout session completed - subscription updated",
            extra={
                "subscription_id": subscription_id,
                "session_id": session_data.get("id"),
            },
        )

        return {
            "subscription_id": subscription_id,
            "session_id": session_data.get("id"),
            "salesforce_result": result,
            "timestamp": datetime.utcnow().isoformat(),
        }

    async def handle_checkout_expired(self, event: StripeEvent) -> Dict[str, Any]:
        """
        Handle checkout.session.expired event.
        Updates subscription status to Failed/Expired in Salesforce.

        Args:
            event: Stripe webhook event

        Returns:
            Processing result
        """
        session_data = event.event_object

        logger.warning(
            f"Processing checkout.session.expired event",
            extra={
                "event_id": event.id,
                "session_id": session_data.get("id"),
                "subscription_id": session_data.get("subscription"),
            },
        )

        subscription_id = session_data.get("subscription")

        # Update subscription sync status to Failed in Salesforce
        salesforce_subscription = SalesforceSubscription(
            Stripe_Checkout_Session_ID__c=session_data.get("id"),
            Sync_Status__c="Failed",
            Error_Message__c=f"Checkout session expired without completion. Session ID: {session_data.get('id')}",
        )

        # If we have a subscription ID, link it
        if subscription_id:
            salesforce_subscription.Stripe_Subscription_ID__c = subscription_id

        result = await salesforce_service.upsert_subscription(salesforce_subscription)

        logger.warning(
            f"Checkout session expired - subscription marked as failed",
            extra={
                "subscription_id": subscription_id,
                "session_id": session_data.get("id"),
            },
        )

        return {
            "subscription_id": subscription_id,
            "session_id": session_data.get("id"),
            "status": "expired",
            "salesforce_result": result,
            "timestamp": datetime.utcnow().isoformat(),
        }

    async def handle_subscription_created(self, event: StripeEvent) -> Dict[str, Any]:
        """
        Handle customer.subscription.created event.

        Args:
            event: Stripe webhook event

        Returns:
            Processing result
        """
        subscription_data = event.event_object

        logger.info(
            f"Processing customer.subscription.created event",
            extra={
                "event_id": event.id,
                "subscription_id": subscription_data.get("id"),
            },
        )

        # Extract subscription details
        items = subscription_data.get("items", {}).get("data", [])
        price_data = items[0] if items else {}
        price = price_data.get("price", {})

        salesforce_subscription = SalesforceSubscription(
            Stripe_Subscription_ID__c=subscription_data["id"],
            Stripe_Customer__c=subscription_data.get("customer"),
            Status__c=subscription_data.get("status"),
            Current_Period_Start__c=datetime.fromtimestamp(
                subscription_data["current_period_start"]
            )
            if subscription_data.get("current_period_start")
            else None,
            Current_Period_End__c=datetime.fromtimestamp(
                subscription_data["current_period_end"]
            )
            if subscription_data.get("current_period_end")
            else None,
            Amount__c=price.get("unit_amount", 0) / 100 if price.get("unit_amount") else None,
            Currency__c=price.get("currency", "").upper(),
            Stripe_Price_ID__c=price.get("id"),
        )

        result = await salesforce_service.upsert_subscription(salesforce_subscription)

        logger.info(
            f"Subscription created in Salesforce",
            extra={"subscription_id": subscription_data["id"]},
        )

        return {
            "subscription_id": subscription_data["id"],
            "salesforce_result": result,
            "timestamp": datetime.utcnow().isoformat(),
        }

    async def handle_subscription_updated(self, event: StripeEvent) -> Dict[str, Any]:
        """
        Handle customer.subscription.updated event.

        Args:
            event: Stripe webhook event

        Returns:
            Processing result
        """
        subscription_data = event.event_object

        logger.info(
            f"Processing customer.subscription.updated event",
            extra={
                "event_id": event.id,
                "subscription_id": subscription_data.get("id"),
                "status": subscription_data.get("status"),
            },
        )

        # Extract subscription details
        items = subscription_data.get("items", {}).get("data", [])
        price_data = items[0] if items else {}
        price = price_data.get("price", {})

        salesforce_subscription = SalesforceSubscription(
            Stripe_Subscription_ID__c=subscription_data["id"],
            Stripe_Customer__c=subscription_data.get("customer"),
            Status__c=subscription_data.get("status"),
            Current_Period_Start__c=datetime.fromtimestamp(
                subscription_data["current_period_start"]
            )
            if subscription_data.get("current_period_start")
            else None,
            Current_Period_End__c=datetime.fromtimestamp(
                subscription_data["current_period_end"]
            )
            if subscription_data.get("current_period_end")
            else None,
            Amount__c=price.get("unit_amount", 0) / 100 if price.get("unit_amount") else None,
            Currency__c=price.get("currency", "").upper(),
            Stripe_Price_ID__c=price.get("id"),
        )

        result = await salesforce_service.upsert_subscription(salesforce_subscription)

        logger.info(
            f"Subscription updated in Salesforce",
            extra={
                "subscription_id": subscription_data["id"],
                "status": subscription_data.get("status"),
            },
        )

        return {
            "subscription_id": subscription_data["id"],
            "status": subscription_data.get("status"),
            "salesforce_result": result,
            "timestamp": datetime.utcnow().isoformat(),
        }

    async def handle_subscription_deleted(self, event: StripeEvent) -> Dict[str, Any]:
        """
        Handle customer.subscription.deleted event.

        Args:
            event: Stripe webhook event

        Returns:
            Processing result
        """
        subscription_data = event.event_object

        logger.info(
            f"Processing customer.subscription.deleted event",
            extra={
                "event_id": event.id,
                "subscription_id": subscription_data.get("id"),
            },
        )

        # Update subscription status to canceled
        salesforce_subscription = SalesforceSubscription(
            Stripe_Subscription_ID__c=subscription_data["id"],
            Status__c="canceled",
        )

        result = await salesforce_service.upsert_subscription(salesforce_subscription)

        logger.info(
            f"Subscription deleted/canceled in Salesforce",
            extra={"subscription_id": subscription_data["id"]},
        )

        return {
            "subscription_id": subscription_data["id"],
            "status": "canceled",
            "salesforce_result": result,
            "timestamp": datetime.utcnow().isoformat(),
        }


# Global subscription handler instance
subscription_handler = SubscriptionHandler()
