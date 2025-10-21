"""
Payment Event Handler

Handles Stripe payment-related webhook events.
"""

from datetime import datetime
from typing import Dict, Any

from app.models.stripe_events import StripeEvent
from app.models.salesforce_records import SalesforcePaymentTransaction
from app.services.salesforce_service import salesforce_service
from app.utils.logging_config import get_logger

logger = get_logger(__name__)


class PaymentHandler:
    """Handler for payment events"""

    async def handle_payment_succeeded(self, event: StripeEvent) -> Dict[str, Any]:
        """
        Handle payment_intent.succeeded event.
        Creates a successful payment transaction in Salesforce.

        Args:
            event: Stripe webhook event

        Returns:
            Processing result
        """
        payment_intent = event.event_object

        logger.info(
            f"Processing payment_intent.succeeded event",
            extra={
                "event_id": event.id,
                "payment_intent_id": payment_intent.get("id"),
                "amount": payment_intent.get("amount"),
            },
        )

        # Map payment intent to Salesforce transaction
        salesforce_transaction = SalesforcePaymentTransaction(
            Stripe_Payment_Intent_ID__c=payment_intent["id"],
            Stripe_Customer__c=payment_intent.get("customer"),
            Amount__c=payment_intent.get("amount", 0) / 100,  # Convert cents to dollars
            Currency__c=payment_intent.get("currency", "").upper(),
            Status__c="succeeded",
            Payment_Method_Type__c=payment_intent.get("payment_method_types", [])[0]
            if payment_intent.get("payment_method_types")
            else None,
            Transaction_Date__c=datetime.fromtimestamp(payment_intent.get("created"))
            if payment_intent.get("created")
            else datetime.utcnow(),
        )

        # Check if payment is associated with a subscription
        metadata = payment_intent.get("metadata", {})
        if "subscription_id" in metadata:
            salesforce_transaction.Stripe_Subscription__c = metadata["subscription_id"]

        result = await salesforce_service.upsert_payment_transaction(
            salesforce_transaction
        )

        logger.info(
            f"Payment transaction created in Salesforce",
            extra={
                "payment_intent_id": payment_intent["id"],
                "amount": payment_intent.get("amount"),
            },
        )

        return {
            "payment_intent_id": payment_intent["id"],
            "amount": payment_intent.get("amount", 0) / 100,
            "currency": payment_intent.get("currency"),
            "status": "succeeded",
            "salesforce_result": result,
            "timestamp": datetime.utcnow().isoformat(),
        }

    async def handle_payment_failed(self, event: StripeEvent) -> Dict[str, Any]:
        """
        Handle payment_intent.payment_failed event.
        Creates a failed payment transaction in Salesforce.

        Args:
            event: Stripe webhook event

        Returns:
            Processing result
        """
        payment_intent = event.event_object

        logger.warning(
            f"Processing payment_intent.payment_failed event",
            extra={
                "event_id": event.id,
                "payment_intent_id": payment_intent.get("id"),
                "amount": payment_intent.get("amount"),
                "error": payment_intent.get("last_payment_error"),
            },
        )

        # Map payment intent to Salesforce transaction
        salesforce_transaction = SalesforcePaymentTransaction(
            Stripe_Payment_Intent_ID__c=payment_intent["id"],
            Stripe_Customer__c=payment_intent.get("customer"),
            Amount__c=payment_intent.get("amount", 0) / 100,  # Convert cents to dollars
            Currency__c=payment_intent.get("currency", "").upper(),
            Status__c="failed",
            Payment_Method_Type__c=payment_intent.get("payment_method_types", [])[0]
            if payment_intent.get("payment_method_types")
            else None,
            Transaction_Date__c=datetime.fromtimestamp(payment_intent.get("created"))
            if payment_intent.get("created")
            else datetime.utcnow(),
        )

        # Check if payment is associated with a subscription
        metadata = payment_intent.get("metadata", {})
        if "subscription_id" in metadata:
            salesforce_transaction.Stripe_Subscription__c = metadata["subscription_id"]

        result = await salesforce_service.upsert_payment_transaction(
            salesforce_transaction
        )

        logger.info(
            f"Failed payment transaction created in Salesforce",
            extra={
                "payment_intent_id": payment_intent["id"],
                "amount": payment_intent.get("amount"),
            },
        )

        return {
            "payment_intent_id": payment_intent["id"],
            "amount": payment_intent.get("amount", 0) / 100,
            "currency": payment_intent.get("currency"),
            "status": "failed",
            "error": payment_intent.get("last_payment_error"),
            "salesforce_result": result,
            "timestamp": datetime.utcnow().isoformat(),
        }


# Global payment handler instance
payment_handler = PaymentHandler()
