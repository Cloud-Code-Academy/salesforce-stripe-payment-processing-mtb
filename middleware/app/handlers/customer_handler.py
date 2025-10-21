"""
Customer Event Handler

Handles Stripe customer-related webhook events.
"""

from datetime import datetime
from typing import Dict, Any

from app.models.stripe_events import StripeEvent
from app.models.salesforce_records import SalesforceCustomer
from app.services.salesforce_service import salesforce_service
from app.utils.logging_config import get_logger

logger = get_logger(__name__)


class CustomerHandler:
    """Handler for customer events"""

    async def handle_customer_updated(self, event: StripeEvent) -> Dict[str, Any]:
        """
        Handle customer.updated event.
        Updates customer information in Salesforce.

        Args:
            event: Stripe webhook event

        Returns:
            Processing result
        """
        customer_data = event.event_object

        logger.info(
            f"Processing customer.updated event",
            extra={
                "event_id": event.id,
                "customer_id": customer_data.get("id"),
            },
        )

        # Map Stripe customer to Salesforce model
        salesforce_customer = SalesforceCustomer(
            Stripe_Customer_ID__c=customer_data["id"],
            Customer_Email__c=customer_data.get("email"),
            Customer_Name__c=customer_data.get("name"),
            Customer_Phone__c=customer_data.get("phone"),
            Default_Payment_Method__c=customer_data.get(
                "invoice_settings", {}
            ).get("default_payment_method"),
        )

        # Upsert to Salesforce
        result = await salesforce_service.upsert_customer(salesforce_customer)

        logger.info(
            f"Customer updated in Salesforce",
            extra={
                "customer_id": customer_data["id"],
                "result": result,
            },
        )

        return {
            "customer_id": customer_data["id"],
            "salesforce_result": result,
            "timestamp": datetime.utcnow().isoformat(),
        }


# Global customer handler instance
customer_handler = CustomerHandler()
