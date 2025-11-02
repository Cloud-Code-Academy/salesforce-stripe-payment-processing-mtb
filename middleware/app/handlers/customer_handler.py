"""
Customer Event Handler

Handles Stripe customer-related webhook events.
"""

from datetime import datetime
from typing import Dict, Any

from app.models.stripe_events import StripeEvent
from app.models.salesforce_records import SalesforceCustomer, SalesforceContact
from app.services.salesforce_service import salesforce_service
from app.utils.logging_config import get_logger

logger = get_logger(__name__)


class CustomerHandler:
    """Handler for customer events"""

    async def handle_customer_updated(self, event: StripeEvent) -> Dict[str, Any]:
        """
        Handle customer.updated event.
        Updates customer information in Salesforce Customer and Contact records.

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

        # Map Stripe customer to Salesforce Customer model
        salesforce_customer = SalesforceCustomer(
            Stripe_Customer_ID__c=customer_data["id"],
            Customer_Email__c=customer_data.get("email"),
            Customer_Name__c=customer_data.get("name"),
            Customer_Phone__c=customer_data.get("phone"),
            Default_Payment_Method__c=customer_data.get(
                "invoice_settings", {}
            ).get("default_payment_method"),
        )

        # Upsert Stripe Customer to Salesforce
        customer_result = await salesforce_service.upsert_customer(salesforce_customer)

        logger.info(
            f"Stripe Customer updated in Salesforce",
            extra={
                "customer_id": customer_data["id"],
                "result": customer_result,
            },
        )

        # Also update the Contact record
        # Parse name into FirstName and LastName
        customer_name = customer_data.get("name", "")
        first_name = None
        last_name = None

        if customer_name:
            name_parts = customer_name.strip().split(None, 1)  # Split on first whitespace
            if len(name_parts) == 1:
                last_name = name_parts[0]
            elif len(name_parts) >= 2:
                first_name = name_parts[0]
                last_name = name_parts[1]

        salesforce_contact = SalesforceContact(
            Stripe_Customer_ID__c=customer_data["id"],
            Email=customer_data.get("email"),
            FirstName=first_name,
            LastName=last_name or "Unknown",  # LastName is required on Contact
            Phone=customer_data.get("phone"),
        )

        # Upsert Contact to Salesforce
        contact_result = await salesforce_service.upsert_contact(salesforce_contact)

        logger.info(
            f"Contact updated in Salesforce",
            extra={
                "customer_id": customer_data["id"],
                "result": contact_result,
            },
        )

        return {
            "customer_id": customer_data["id"],
            "stripe_customer_result": customer_result,
            "contact_result": contact_result,
            "timestamp": datetime.utcnow().isoformat(),
        }


# Global customer handler instance
customer_handler = CustomerHandler()
