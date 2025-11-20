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
            event: Stripe webhook event (dict or StripeEvent)

        Returns:
            Processing result
        """
        # Handle both dict and StripeEvent object formats
        if isinstance(event, dict):
            event_id = event.get("id")
            session_data = event["data"]["object"]
        else:
            event_id = event.id
            session_data = event.event_object

        logger.info(
            f"Processing checkout.session.completed event",
            extra={
                "event_id": event_id,
                "session_id": session_data.get("id"),
                "subscription_id": session_data.get("subscription"),
            },
        )

        subscription_id = session_data.get("subscription")
        session_id = session_data.get("id")
        stripe_customer_id = session_data.get("customer")

        if not subscription_id:
            logger.warning("No subscription ID in checkout session")
            return {
                "status": "skipped",
                "reason": "No subscription in checkout session",
            }

        # First, try to find existing Salesforce record by checkout session ID
        # This prevents creating duplicate records when subscription was initiated from Salesforce
        salesforce_record_id = None
        if session_id:
            try:
                query = (
                    f"SELECT Id FROM Stripe_Subscription__c "
                    f"WHERE Stripe_Checkout_Session_ID__c = '{session_id}' "
                    f"LIMIT 1"
                )
                result = await salesforce_service.query(query)
                if result.get("records"):
                    salesforce_record_id = result["records"][0]["Id"]
                    logger.info(
                        f"Found existing Salesforce subscription record by session ID: {salesforce_record_id}",
                        extra={"session_id": session_id}
                    )
            except Exception as e:
                logger.warning(
                    f"Failed to query for existing subscription by session ID: {str(e)}",
                    extra={"session_id": session_id, "error": str(e)}
                )

        # Look up Salesforce Contact ID (Stripe_Customer__c now points to Contact.Id)
        salesforce_customer_id = None
        if stripe_customer_id:
            try:
                query = (
                    f"SELECT Id FROM Contact "
                    f"WHERE Stripe_Customer_ID__c = '{stripe_customer_id}' "
                    f"LIMIT 1"
                )
                result = await salesforce_service.query(query)
                if result.get("records"):
                    salesforce_customer_id = result["records"][0]["Id"]
                    logger.info(
                        f"Found Salesforce customer for Stripe customer {stripe_customer_id}: {salesforce_customer_id}",
                        extra={"stripe_customer_id": stripe_customer_id}
                    )
            except Exception as e:
                logger.warning(
                    f"Failed to query Stripe customer: {str(e)}",
                    extra={"stripe_customer_id": stripe_customer_id, "error": str(e)}
                )

        # Update subscription with Stripe subscription ID and completed status
        # Note: Contact__c is a Master-Detail field and cannot be updated, only set on insert
        # Check payment status to determine if we should set status to active
        payment_status = session_data.get("payment_status")
        logger.info(
            f"Checkout session payment status: {payment_status}",
            extra={"session_id": session_id, "payment_status": payment_status}
        )

        if salesforce_record_id:
            # Exclude Contact__c (Master-Detail) from updates - cannot be changed after insert
            # INCLUDE Stripe_Subscription_ID__c to ensure it gets populated on Salesforce-initiated subscriptions
            update_data = {
                "Stripe_Subscription_ID__c": subscription_id,  # Populate the external ID field
                "Stripe_Checkout_Session_ID__c": session_id,
                "Sync_Status__c": "Completed"
            }
            # Set status based on payment status
            if payment_status == "paid":
                update_data["Status__c"] = "active"
            elif payment_status == "unpaid":
                update_data["Status__c"] = "unpaid"

            logger.info(
                f"Updating Salesforce subscription with Stripe subscription ID",
                extra={
                    "salesforce_subscription_id": salesforce_record_id,
                    "stripe_subscription_id": subscription_id,
                    "session_id": session_id
                }
            )

            result = await salesforce_service.update_record(
                sobject_type="Stripe_Subscription__c",
                record_id=salesforce_record_id,
                record_data=update_data
            )
        else:
            # Include Contact__c only when creating new records
            # Determine status based on payment status
            subscription_status = None
            if payment_status == "paid" or payment_status == "no_payment_required":
                subscription_status = "active"
            elif payment_status == "unpaid":
                subscription_status = "unpaid"

            salesforce_subscription = SalesforceSubscription(
                Stripe_Subscription_ID__c=subscription_id,
                Stripe_Checkout_Session_ID__c=session_id,
                Contact__c=salesforce_customer_id,
                Status__c=subscription_status,
                Sync_Status__c="Completed",
            )
            result = await salesforce_service.upsert_subscription(salesforce_subscription)

        logger.info(
            f"Checkout session completed - subscription updated",
            extra={
                "subscription_id": subscription_id,
                "session_id": session_id,
                "salesforce_record_id": salesforce_record_id,
            },
        )

        return {
            "subscription_id": subscription_id,
            "session_id": session_id,
            "salesforce_result": result,
            "timestamp": datetime.utcnow().isoformat(),
        }

    async def handle_checkout_expired(self, event: StripeEvent) -> Dict[str, Any]:
        """
        Handle checkout.session.expired event.
        Updates subscription status to Failed/Expired in Salesforce.

        Args:
            event: Stripe webhook event (dict or StripeEvent)

        Returns:
            Processing result
        """
        # Handle both dict and StripeEvent object formats
        if isinstance(event, dict):
            event_id = event.get("id")
            session_data = event["data"]["object"]
        else:
            event_id = event.id
            session_data = event.event_object

        logger.warning(
            f"Processing checkout.session.expired event",
            extra={
                "event_id": event_id,
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
            event: Stripe webhook event (dict or StripeEvent)

        Returns:
            Processing result
        """
        # Handle both dict and StripeEvent object formats
        if isinstance(event, dict):
            event_id = event.get("id")
            subscription_data = event["data"]["object"]
        else:
            event_id = event.id
            subscription_data = event.event_object

        logger.info(
            f"Processing customer.subscription.created event",
            extra={
                "event_id": event_id,
                "subscription_id": subscription_data.get("id"),
            },
        )

        # Extract subscription details
        items = subscription_data.get("items", {}).get("data", [])
        price_data = items[0] if items else {}
        price = price_data.get("price", {})

        # Look up Salesforce customer ID using Stripe customer ID
        stripe_customer_id = subscription_data.get("customer")
        stripe_subscription_id = subscription_data["id"]
        salesforce_customer_id = None

        if stripe_customer_id:
            try:
                query = (
                    f"SELECT Id FROM Contact "
                    f"WHERE Stripe_Customer_ID__c = '{stripe_customer_id}' "
                    f"LIMIT 1"
                )
                result = await salesforce_service.query(query)
                if result.get("records"):
                    salesforce_customer_id = result["records"][0]["Id"]
                    logger.info(
                        f"Found Salesforce customer for Stripe customer {stripe_customer_id}: {salesforce_customer_id}",
                        extra={"stripe_customer_id": stripe_customer_id}
                    )
                else:
                    logger.warning(
                        f"Stripe customer not found in Salesforce: {stripe_customer_id}",
                        extra={"stripe_customer_id": stripe_customer_id}
                    )
            except Exception as e:
                logger.error(
                    f"Failed to query Stripe customer: {str(e)}",
                    extra={"stripe_customer_id": stripe_customer_id, "error": str(e)}
                )

        # Check if subscription already exists (prevents duplicates from Salesforce-initiated checkouts)
        existing_subscription_id = None
        try:
            # First, check if we already have this Stripe subscription ID
            query = (
                f"SELECT Id, Stripe_Subscription_ID__c, Stripe_Checkout_Session_ID__c "
                f"FROM Stripe_Subscription__c "
                f"WHERE Stripe_Subscription_ID__c = '{stripe_subscription_id}' "
                f"LIMIT 1"
            )
            result = await salesforce_service.query(query)
            if result.get("records"):
                existing_subscription_id = result["records"][0]["Id"]
                logger.info(
                    f"Found existing subscription by Stripe ID - will update instead of create",
                    extra={
                        "stripe_subscription_id": stripe_subscription_id,
                        "salesforce_subscription_id": existing_subscription_id
                    }
                )
            else:
                # Check for pending Salesforce-initiated subscription (has Contact but no Stripe subscription ID yet)
                if salesforce_customer_id:
                    query = (
                        f"SELECT Id, Stripe_Checkout_Session_ID__c "
                        f"FROM Stripe_Subscription__c "
                        f"WHERE Contact__c = '{salesforce_customer_id}' "
                        f"AND Stripe_Subscription_ID__c = null "
                        f"AND Stripe_Checkout_Session_ID__c != null "
                        f"ORDER BY CreatedDate DESC "
                        f"LIMIT 1"
                    )
                    result = await salesforce_service.query(query)
                    if result.get("records"):
                        existing_subscription_id = result["records"][0]["Id"]
                        logger.info(
                            f"Found Salesforce-initiated subscription awaiting Stripe sync - will update instead of create",
                            extra={
                                "stripe_subscription_id": stripe_subscription_id,
                                "salesforce_subscription_id": existing_subscription_id,
                                "checkout_session_id": result["records"][0].get("Stripe_Checkout_Session_ID__c")
                            }
                        )
        except Exception as e:
            logger.warning(
                f"Failed to check for existing subscription: {str(e)}",
                extra={"stripe_subscription_id": stripe_subscription_id, "error": str(e)}
            )

        # If we found an existing record, update it instead of upserting
        if existing_subscription_id:
            update_data = {
                "Stripe_Subscription_ID__c": stripe_subscription_id,
                "Status__c": subscription_data.get("status"),
                "Current_Period_Start__c": datetime.fromtimestamp(
                    subscription_data["current_period_start"]
                ).isoformat() if subscription_data.get("current_period_start") else None,
                "Current_Period_End__c": datetime.fromtimestamp(
                    subscription_data["current_period_end"]
                ).isoformat() if subscription_data.get("current_period_end") else None,
                "Amount__c": price.get("unit_amount", 0) / 100 if price.get("unit_amount") else None,
                "Currency__c": price.get("currency", "").upper(),
                "Stripe_Price_ID__c": price.get("id"),
            }
            # Remove None values
            update_data = {k: v for k, v in update_data.items() if v is not None}

            logger.info(
                f"Updating existing subscription with Stripe data",
                extra={
                    "stripe_subscription_id": stripe_subscription_id,
                    "salesforce_subscription_id": existing_subscription_id,
                    "update_data": update_data
                }
            )

            result = await salesforce_service.update_record(
                sobject_type="Stripe_Subscription__c",
                record_id=existing_subscription_id,
                record_data=update_data
            )

            logger.info(
                f"Subscription updated in Salesforce (prevented duplicate)",
                extra={
                    "stripe_subscription_id": stripe_subscription_id,
                    "salesforce_subscription_id": existing_subscription_id
                },
            )
        else:
            # No existing record found - create new one via upsert
            salesforce_subscription = SalesforceSubscription(
                Stripe_Subscription_ID__c=stripe_subscription_id,
                Contact__c=salesforce_customer_id,
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

            logger.info(
                f"Creating new subscription in Salesforce",
                extra={
                    "stripe_subscription_id": stripe_subscription_id,
                    "contact_id": salesforce_customer_id
                }
            )

            result = await salesforce_service.upsert_subscription(salesforce_subscription)

            logger.info(
                f"Subscription created in Salesforce",
                extra={
                    "stripe_subscription_id": stripe_subscription_id,
                    "salesforce_result": result
                },
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
            event: Stripe webhook event (dict or StripeEvent)

        Returns:
            Processing result
        """
        # Handle both dict and StripeEvent object formats
        if isinstance(event, dict):
            event_id = event.get("id")
            subscription_data = event["data"]["object"]
        else:
            event_id = event.id
            subscription_data = event.event_object

        logger.info(
            f"Processing customer.subscription.updated event",
            extra={
                "event_id": event_id,
                "subscription_id": subscription_data.get("id"),
                "status": subscription_data.get("status"),
            },
        )

        # Extract subscription details
        items = subscription_data.get("items", {}).get("data", [])
        price_data = items[0] if items else {}
        price = price_data.get("price", {})

        # Look up Salesforce customer ID using Stripe customer ID
        stripe_customer_id = subscription_data.get("customer")
        salesforce_customer_id = None

        if stripe_customer_id:
            try:
                query = (
                    f"SELECT Id FROM Contact "
                    f"WHERE Stripe_Customer_ID__c = '{stripe_customer_id}' "
                    f"LIMIT 1"
                )
                result = await salesforce_service.query(query)
                if result.get("records"):
                    salesforce_customer_id = result["records"][0]["Id"]
                    logger.info(
                        f"Found Salesforce customer for Stripe customer {stripe_customer_id}: {salesforce_customer_id}",
                        extra={"stripe_customer_id": stripe_customer_id}
                    )
            except Exception as e:
                logger.warning(
                    f"Failed to query Stripe customer: {str(e)}",
                    extra={"stripe_customer_id": stripe_customer_id, "error": str(e)}
                )

        salesforce_subscription = SalesforceSubscription(
            Stripe_Subscription_ID__c=subscription_data["id"],
            Contact__c=salesforce_customer_id,
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
            event: Stripe webhook event (dict or StripeEvent)

        Returns:
            Processing result
        """
        # Handle both dict and StripeEvent object formats
        if isinstance(event, dict):
            event_id = event.get("id")
            subscription_data = event["data"]["object"]
        else:
            event_id = event.id
            subscription_data = event.event_object

        logger.info(
            f"Processing customer.subscription.deleted event",
            extra={
                "event_id": event_id,
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
