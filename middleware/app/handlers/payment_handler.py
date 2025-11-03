"""
Payment Event Handler

Handles Stripe payment-related webhook events.
"""

from datetime import datetime, timezone
from typing import Dict, Any, Optional

from app.models.stripe_events import StripeEvent
from app.models.salesforce_records import SalesforcePaymentTransaction, SalesforceInvoice
from app.services.salesforce_service import salesforce_service
from app.utils.logging_config import get_logger
from app.utils.exceptions import SalesforceAPIException

logger = get_logger(__name__)


class PaymentHandler:
    """Handler for payment events"""

    async def handle_payment_succeeded(self, event) -> Dict[str, Any]:
        """
        Handle payment_intent.succeeded event.
        Creates a successful payment transaction in Salesforce.

        Args:
            event: Stripe webhook event (dict or StripeEvent object)

        Returns:
            Processing result
        """
        # Handle both dict and StripeEvent object formats
        if isinstance(event, dict):
            event_id = event.get("id")
            payment_intent = event["data"]["object"]
        else:
            event_id = event.id
            payment_intent = event.event_object

        logger.info(
            "Processing payment_intent.succeeded event",
            extra={
                "event_id": event_id,
                "payment_intent_id": payment_intent.get("id"),
                "amount": payment_intent.get("amount"),
            },
        )

        # Look up Salesforce customer ID using Stripe customer ID
        stripe_customer_id = payment_intent.get("customer")
        salesforce_customer_id = None

        if stripe_customer_id:
            try:
                query = (
                    f"SELECT Id FROM Stripe_Customer__c "
                    f"WHERE Stripe_Customer_ID__c = '{stripe_customer_id}' "
                    f"LIMIT 1"
                )
                result = await salesforce_service.query(query)
                if result.get("records"):
                    salesforce_customer_id = result["records"][0]["Id"]
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

        # Map payment intent to Salesforce transaction
        salesforce_transaction = SalesforcePaymentTransaction(
            Stripe_Payment_Intent_ID__c=payment_intent["id"],
            Stripe_Customer__c=salesforce_customer_id,
            Amount__c=payment_intent.get("amount", 0) / 100,  # Convert cents to dollars
            Currency__c=payment_intent.get("currency", "").upper(),
            Status__c="succeeded",
            Payment_Method_Type__c=payment_intent.get("payment_method_types", [])[0]
            if payment_intent.get("payment_method_types")
            else None,
            Transaction_Date__c=datetime.fromtimestamp(payment_intent.get("created"))
            if payment_intent.get("created")
            else datetime.now(timezone.utc),
        )

        # Check if payment is associated with a subscription
        metadata = payment_intent.get("metadata", {})
        if "subscription_id" in metadata:
            salesforce_transaction.Stripe_Subscription__c = metadata["subscription_id"]

        # Check if payment is associated with an invoice
        stripe_invoice_id = payment_intent.get("invoice")
        if stripe_invoice_id:
            salesforce_transaction.Stripe_Invoice_ID__c = stripe_invoice_id
            # Try to find and link the Salesforce invoice record
            invoice_sf_id = await self._get_invoice_salesforce_id(stripe_invoice_id)
            if invoice_sf_id:
                salesforce_transaction.Stripe_Invoice__c = invoice_sf_id

        result = await salesforce_service.upsert_payment_transaction(
            salesforce_transaction
        )

        logger.info(
            "Payment transaction created in Salesforce",
            extra={
                "payment_intent_id": payment_intent["id"],
                "amount": payment_intent.get("amount"),
                "invoice_id": stripe_invoice_id,
            },
        )

        return {
            "payment_intent_id": payment_intent["id"],
            "amount": payment_intent.get("amount", 0) / 100,
            "currency": payment_intent.get("currency"),
            "status": "succeeded",
            "invoice_id": stripe_invoice_id,
            "salesforce_result": result,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }

    async def handle_payment_failed(self, event) -> Dict[str, Any]:
        """
        Handle payment_intent.payment_failed event.
        Creates a failed payment transaction in Salesforce.

        Args:
            event: Stripe webhook event (dict or StripeEvent object)

        Returns:
            Processing result
        """
        # Handle both dict and StripeEvent object formats
        if isinstance(event, dict):
            event_id = event.get("id")
            payment_intent = event["data"]["object"]
        else:
            event_id = event.id
            payment_intent = event.event_object

        logger.warning(
            "Processing payment_intent.payment_failed event",
            extra={
                "event_id": event_id,
                "payment_intent_id": payment_intent.get("id"),
                "amount": payment_intent.get("amount"),
                "error": payment_intent.get("last_payment_error"),
            },
        )

        # Look up Salesforce customer ID using Stripe customer ID
        stripe_customer_id = payment_intent.get("customer")
        salesforce_customer_id = None

        if stripe_customer_id:
            try:
                query = (
                    f"SELECT Id FROM Stripe_Customer__c "
                    f"WHERE Stripe_Customer_ID__c = '{stripe_customer_id}' "
                    f"LIMIT 1"
                )
                result = await salesforce_service.query(query)
                if result.get("records"):
                    salesforce_customer_id = result["records"][0]["Id"]
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

        # Map payment intent to Salesforce transaction
        salesforce_transaction = SalesforcePaymentTransaction(
            Stripe_Payment_Intent_ID__c=payment_intent["id"],
            Stripe_Customer__c=salesforce_customer_id,
            Amount__c=payment_intent.get("amount", 0) / 100,  # Convert cents to dollars
            Currency__c=payment_intent.get("currency", "").upper(),
            Status__c="failed",
            Payment_Method_Type__c=payment_intent.get("payment_method_types", [])[0]
            if payment_intent.get("payment_method_types")
            else None,
            Transaction_Date__c=datetime.fromtimestamp(payment_intent.get("created"))
            if payment_intent.get("created")
            else datetime.now(timezone.utc),
        )

        # Check if payment is associated with a subscription
        metadata = payment_intent.get("metadata", {})
        if "subscription_id" in metadata:
            salesforce_transaction.Stripe_Subscription__c = metadata["subscription_id"]

        # Check if payment is associated with an invoice
        stripe_invoice_id = payment_intent.get("invoice")
        if stripe_invoice_id:
            salesforce_transaction.Stripe_Invoice_ID__c = stripe_invoice_id
            # Try to find and link the Salesforce invoice record
            invoice_sf_id = await self._get_invoice_salesforce_id(stripe_invoice_id)
            if invoice_sf_id:
                salesforce_transaction.Stripe_Invoice__c = invoice_sf_id

        result = await salesforce_service.upsert_payment_transaction(
            salesforce_transaction
        )

        logger.info(
            "Failed payment transaction created in Salesforce",
            extra={
                "payment_intent_id": payment_intent["id"],
                "amount": payment_intent.get("amount"),
                "invoice_id": stripe_invoice_id,
            },
        )

        return {
            "payment_intent_id": payment_intent["id"],
            "amount": payment_intent.get("amount", 0) / 100,
            "currency": payment_intent.get("currency"),
            "status": "failed",
            "invoice_id": stripe_invoice_id,
            "error": payment_intent.get("last_payment_error"),
            "salesforce_result": result,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }

    async def handle_invoice_created(self, event: Dict[str, Any]) -> Dict[str, Any]:
        """
        Handle invoice.created webhook event from Stripe.
        Creates a Stripe_Invoice__c record for tracking all invoices.

        This event fires whenever Stripe creates an invoice (subscription renewal, one-time charge, etc).
        Invoices track billing records regardless of payment status.

        Args:
            event: Stripe webhook event containing invoice data with structure:
                {
                    "id": "evt_xxx",
                    "type": "invoice.created",
                    "data": {
                        "object": {
                            "id": "in_xxx",
                            "customer": "cus_xxx",
                            "subscription": "sub_xxx",
                            "amount_due": 2999,
                            "currency": "usd",
                            "status": "open",
                            "number": "INV-0001",
                            "created": 1234567890,
                            "due_date": 1234567890,
                            "description": "Invoice for subscription"
                        }
                    }
                }

        Returns:
            Processing result with invoice ID and Salesforce record details
        """
        invoice_data = event.get("data", {}).get("object", {})
        invoice_id = invoice_data.get("id")

        logger.info(
            f"Processing invoice.created event",
            extra={
                "event_id": event.get("id"),
                "invoice_id": invoice_id,
                "customer_id": invoice_data.get("customer"),
                "subscription_id": invoice_data.get("subscription"),
            },
        )

        try:
            # Look up Salesforce customer ID using Stripe customer ID
            stripe_customer_id = invoice_data.get("customer")
            salesforce_customer_id = None

            if stripe_customer_id:
                try:
                    query = (
                        f"SELECT Id FROM Stripe_Customer__c "
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

            # Create Salesforce invoice record
            # Calculate discount from total and subtotal
            discount = 0
            total = invoice_data.get("total", 0)
            subtotal = invoice_data.get("subtotal", 0)
            if subtotal > 0:
                discount = (subtotal - total) / 100  # Convert from cents

            # Get tax amount
            tax_amount = invoice_data.get("tax", 0)
            if tax_amount:
                tax_amount = tax_amount / 100  # Convert from cents

            salesforce_invoice = SalesforceInvoice(
                Stripe_Invoice_ID__c=invoice_id,
                Stripe_Customer__c=salesforce_customer_id,
                Stripe_Subscription__c=invoice_data.get("subscription"),
                Amount__c=invoice_data.get("amount_due", 0) / 100 if invoice_data.get("amount_due") else None,
                Status__c=invoice_data.get("status", "open"),
                Due_Date__c=datetime.fromtimestamp(
                    invoice_data["due_date"]
                ) if invoice_data.get("due_date") else None,
                Period_Start__c=datetime.fromtimestamp(
                    invoice_data["period_start"]
                ) if invoice_data.get("period_start") else None,
                Period_End__c=datetime.fromtimestamp(
                    invoice_data["period_end"]
                ) if invoice_data.get("period_end") else None,
                Discount_Applied__c=discount if discount > 0 else None,
                Tax_Amount__c=tax_amount if tax_amount > 0 else None,
            )

            result = await salesforce_service.upsert_invoice(salesforce_invoice)

            logger.info(
                f"Invoice created in Salesforce",
                extra={
                    "invoice_id": invoice_id,
                    "status": invoice_data.get("status"),
                    "amount": invoice_data.get("amount_due", 0) / 100,
                },
            )

            return {
                "invoice_id": invoice_id,
                "status": invoice_data.get("status"),
                "amount": invoice_data.get("amount_due", 0) / 100 if invoice_data.get("amount_due") else 0,
                "currency": invoice_data.get("currency", "").upper(),
                "customer_id": invoice_data.get("customer"),
                "subscription_id": invoice_data.get("subscription"),
                "salesforce_result": result,
                "timestamp": datetime.now(timezone.utc).isoformat(),
            }

        except Exception as e:
            logger.error(
                f"Failed to create invoice in Salesforce: {str(e)}",
                extra={
                    "invoice_id": invoice_id,
                    "error": str(e),
                    "error_type": type(e).__name__,
                },
            )
            raise

    async def handle_invoice_payment_succeeded(self, event: Dict[str, Any]) -> Dict[str, Any]:
        """
        Handle invoice.payment_succeeded webhook event from Stripe.
        Creates a Stripe_Invoice__c record and Payment_Transaction__c record for successful recurring subscription payments.
        Updates subscription period dates and status to 'active'.

        This event fires when Stripe successfully charges a customer for their subscription renewal.

        Args:
            event: Stripe webhook event containing invoice data with structure:
                {
                    "type": "invoice.payment_succeeded",
                    "data": {
                        "object": {
                            "id": "in_xxx",
                            "subscription": "sub_xxx",
                            "customer": "cus_xxx",
                            "payment_intent": "pi_xxx",
                            "amount_paid": 2999,  # in cents
                            "currency": "usd",
                            "period_start": 1698796800,  # Unix timestamp
                            "period_end": 1701388800,
                            "lines": {...}
                        }
                    }
                }

        Returns:
            Dictionary containing:
                - invoice_id: Salesforce ID of created Stripe_Invoice__c
                - transaction_id: Salesforce ID of created Payment_Transaction__c
                - invoice_stripe_id: Stripe invoice ID
                - subscription_id: Stripe subscription ID
                - amount: Payment amount in dollars

        Raises:
            SalesforceAPIException: If Salesforce record creation/update fails

        Example:
            >>> event = {"type": "invoice.payment_succeeded", "data": {...}}
            >>> result = await handle_invoice_payment_succeeded(event)
            >>> print(result)
            {
                "invoice_id": "a02xxx000000001",
                "transaction_id": "a01xxx000000001",
                "invoice_stripe_id": "in_1234567890",
                "subscription_id": "sub_xxx",
                "amount": 29.99
            }
        """
        invoice = event["data"]["object"]
        invoice_id = invoice["id"]

        logger.info(f"Processing invoice.payment_succeeded: {invoice_id}")

        # Extract invoice data
        invoice_data = self._extract_invoice_data(invoice)

        # Get Salesforce IDs for subscription and customer
        subscription_sf_id, stripe_customer_sf_id = await self._get_salesforce_ids(
            invoice_data["subscription_id"],
            invoice_data["customer_id"]
        )

        # Create invoice record in Salesforce
        invoice_sf_id = await self._create_invoice_record(
            invoice_data, subscription_sf_id, stripe_customer_sf_id
        )

        # Create payment transaction linked to invoice
        transaction_id = await self._create_payment_transaction(
            invoice_data, subscription_sf_id, stripe_customer_sf_id, invoice_sf_id
        )

        # Update subscription period if available
        await self._update_subscription_period_if_needed(
            invoice_data, subscription_sf_id
        )

        return {
            "invoice_id": invoice_sf_id,
            "transaction_id": transaction_id,
            "invoice_stripe_id": invoice_data["invoice_id"],
            "subscription_id": invoice_data["subscription_id"],
            "amount": invoice_data["amount_paid"],
            "currency": invoice_data["currency"]
        }

    def _extract_invoice_data(self, invoice: Dict[str, Any]) -> Dict[str, Any]:
        """Extract and format invoice data for processing."""
        # Extract line items
        line_items = []
        if invoice.get("lines", {}).get("data"):
            for line in invoice["lines"]["data"]:
                line_items.append({
                    "id": line.get("id"),
                    "price_id": line.get("price", {}).get("id"),
                    "amount": line.get("amount", 0) / 100.0,
                    "description": line.get("description")
                })

        return {
            "invoice_id": invoice["id"],
            "subscription_id": invoice.get("subscription"),
            "customer_id": invoice.get("customer"),
            "payment_intent_id": invoice.get("payment_intent"),
            "amount_paid": invoice["amount_paid"] / 100.0,  # Convert cents to dollars
            "currency": invoice["currency"].upper(),
            "period_start": invoice.get("period_start"),
            "period_end": invoice.get("period_end"),
            "due_date": invoice.get("due_date"),
            "tax_amount": invoice.get("tax", 0) / 100.0 if invoice.get("tax") else 0,
            "discounts_applied": invoice.get("total_discount_amounts", [{}])[0].get("amount", 0) / 100.0 if invoice.get("total_discount_amounts") else 0,
            "paid": invoice.get("paid", False),
            "pdf_url": invoice.get("invoice_pdf"),
            "line_items": line_items
        }

    async def _get_salesforce_ids(self, subscription_id: str, customer_id: str) -> tuple[Optional[str], Optional[str]]:
        """Get Salesforce IDs for subscription and customer."""
        subscription_sf_id = None
        stripe_customer_sf_id = None

        if subscription_id:
            subscription_sf_id, stripe_customer_sf_id = await self._query_subscription_record(subscription_id)

        # If customer not linked via subscription, try direct lookup
        if not stripe_customer_sf_id and customer_id:
            stripe_customer_sf_id = await self._get_stripe_customer_id(customer_id)

        return subscription_sf_id, stripe_customer_sf_id

    async def _query_subscription_record(self, subscription_id: str) -> tuple[Optional[str], Optional[str]]:
        """Query Salesforce for subscription record and return subscription and customer IDs."""
        try:
            query = (
                f"SELECT Id, Stripe_Customer__c, Stripe_Customer__r.Id "
                f"FROM Stripe_Subscription__c "
                f"WHERE Stripe_Subscription_ID__c = '{subscription_id}' "
                f"LIMIT 1"
            )
            subscription_result = await salesforce_service.query(query)

            if subscription_result.get("records"):
                subscription_record = subscription_result["records"][0]
                subscription_sf_id = subscription_record["Id"]
                stripe_customer_sf_id = subscription_record.get("Stripe_Customer__c")
                logger.info(f"Found subscription: {subscription_sf_id} with customer: {stripe_customer_sf_id}")
                return subscription_sf_id, stripe_customer_sf_id
            else:
                logger.warning(f"Subscription not found in Salesforce: {subscription_id}")
                return None, None

        except SalesforceAPIException as e:
            logger.error(f"Failed to query subscription {subscription_id}: {str(e)}")
            return None, None

    async def _create_invoice_record(
        self,
        invoice_data: Dict[str, Any],
        subscription_sf_id: Optional[str],
        stripe_customer_sf_id: Optional[str]
    ) -> Optional[str]:
        """Create Stripe_Invoice__c record in Salesforce."""
        try:
            # Format line items as JSON string
            line_items_json = None
            if invoice_data.get("line_items"):
                import json
                line_items_json = json.dumps(invoice_data["line_items"])

            invoice_record = SalesforceInvoice(
                Stripe_Invoice_ID__c=invoice_data["invoice_id"],
                Stripe_Subscription__c=subscription_sf_id,
                Stripe_Customer__c=stripe_customer_sf_id,
                Amount__c=invoice_data.get("amount_paid"),
                Line_Items__c=line_items_json,
                Invoice_PDF_URL__c=invoice_data.get("pdf_url"),
                Period_Start__c=datetime.fromtimestamp(
                    invoice_data["period_start"]
                ) if invoice_data.get("period_start") else None,
                Period_End__c=datetime.fromtimestamp(
                    invoice_data["period_end"]
                ) if invoice_data.get("period_end") else None,
                Due_Date__c=datetime.fromtimestamp(
                    invoice_data["due_date"]
                ) if invoice_data.get("due_date") else None,
                Tax_Amount__c=invoice_data.get("tax_amount"),
                Discounts_Applied__c=invoice_data.get("discounts_applied"),
                Status__c="paid" if invoice_data.get("paid") else "open",
                Dunning_Status__c="none"
            )

            result = await salesforce_service.upsert_record(
                sobject="Stripe_Invoice__c",
                external_id_field="Stripe_Invoice_ID__c",
                external_id_value=invoice_data["invoice_id"],
                record_data=invoice_record.model_dump(exclude_none=True)
            )

            invoice_sf_id = result.get("id")
            logger.info(f"Invoice record created/updated: {invoice_sf_id} for Stripe invoice {invoice_data['invoice_id']}")
            return invoice_sf_id

        except Exception as e:
            logger.error(f"Failed to create invoice record for {invoice_data['invoice_id']}: {str(e)}")
            # Don't raise - invoice creation is secondary to payment processing
            return None

    async def _create_payment_transaction(
        self,
        invoice_data: Dict[str, Any],
        subscription_sf_id: Optional[str],
        stripe_customer_sf_id: Optional[str],
        invoice_sf_id: Optional[str] = None
    ) -> str:
        """Create payment transaction record in Salesforce."""
        transaction_data = {
            "Stripe_Payment_Intent_ID__c": invoice_data["payment_intent_id"],
            "Stripe_Invoice_ID__c": invoice_data["invoice_id"],
            "Amount__c": invoice_data["amount_paid"],
            "Currency__c": invoice_data["currency"],
            "Status__c": "succeeded",
            "Payment_Method_Type__c": "card",
            "Transaction_Date__c": datetime.now().isoformat(),
            "Transaction_Type__c": "recurring_payment"
        }

        # Link to subscription and customer if found
        if subscription_sf_id:
            transaction_data["Stripe_Subscription__c"] = subscription_sf_id

        if stripe_customer_sf_id:
            transaction_data["Stripe_Customer__c"] = stripe_customer_sf_id

        # Link to invoice if available
        if invoice_sf_id:
            transaction_data["Stripe_Invoice__c"] = invoice_sf_id

        try:
            result = await salesforce_service.create_record(
                sobject_type="Payment_Transaction__c",
                record_data=transaction_data
            )

            transaction_id = result["id"]
            logger.info(f"Recurring payment transaction created: {transaction_id} for invoice {invoice_data['invoice_id']}")
            return transaction_id

        except SalesforceAPIException as e:
            logger.error(f"Failed to create transaction for invoice {invoice_data['invoice_id']}: {str(e)}")
            raise

    async def _update_subscription_period_if_needed(
        self, 
        invoice_data: Dict[str, Any], 
        subscription_sf_id: Optional[str]
    ) -> None:
        """Update subscription period dates if all required data is available."""
        if (invoice_data["subscription_id"] and subscription_sf_id and 
            invoice_data["period_start"] and invoice_data["period_end"]):
            await self._update_subscription_period(
                subscription_id=invoice_data["subscription_id"],
                subscription_sf_id=subscription_sf_id,
                period_start=invoice_data["period_start"],
                period_end=invoice_data["period_end"]
            )

    async def handle_invoice_payment_failed(self, event: Dict[str, Any]) -> Dict[str, Any]:
        """
        Handle invoice.payment_failed webhook event from Stripe.
        Creates a Stripe_Invoice__c record with dunning status and a failed Payment_Transaction__c record.
        Updates subscription status to 'past_due'.

        This event fires when Stripe fails to charge a customer for their subscription renewal.
        Common reasons: insufficient funds, expired card, declined by bank.

        Args:
            event: Stripe webhook event containing invoice data with structure:
                {
                    "type": "invoice.payment_failed",
                    "data": {
                        "object": {
                            "id": "in_xxx",
                            "subscription": "sub_xxx",
                            "customer": "cus_xxx",
                            "payment_intent": "pi_xxx",
                            "amount_due": 2999,  # in cents
                            "currency": "usd",
                            "last_payment_error": {
                                "code": "card_declined",
                                "message": "Your card was declined"
                            },
                            "attempt_count": 1
                        }
                    }
                }

        Returns:
            Dictionary containing:
                - invoice_id: Salesforce ID of created Stripe_Invoice__c
                - transaction_id: Salesforce ID of created Payment_Transaction__c
                - invoice_stripe_id: Stripe invoice ID
                - subscription_id: Stripe subscription ID
                - failure_reason: Human-readable failure message
                - attempt_count: Number of payment attempts

        Raises:
            SalesforceAPIException: If Salesforce record creation/update fails

        Side Effects:
            - Creates or updates Stripe_Invoice__c with dunning status
            - Updates Stripe_Subscription__c.Status__c to 'past_due'
            - Sets Stripe_Subscription__c.Sync_Status__c to 'Failed'
            - Stores error message in Stripe_Subscription__c.Error_Message__c

        Example:
            >>> event = {"type": "invoice.payment_failed", "data": {...}}
            >>> result = await handle_invoice_payment_failed(event)
            >>> print(result)
            {
                "invoice_id": "a02xxx000000002",
                "transaction_id": "a01xxx000000002",
                "invoice_stripe_id": "in_1234567890",
                "failure_reason": "[card_declined] Your card was declined"
            }
        """
        invoice = event["data"]["object"]
        invoice_id = invoice["id"]

        logger.error(f"Processing invoice.payment_failed: {invoice_id}")

        # Extract and format invoice data
        invoice_data = self._extract_failed_invoice_data(invoice)

        # Get Salesforce IDs for subscription and customer
        subscription_sf_id, stripe_customer_sf_id = await self._get_salesforce_ids(
            invoice_data["subscription_id"],
            invoice_data["customer_id"]
        )

        # Create invoice record with dunning status
        invoice_sf_id = await self._create_failed_invoice_record(
            invoice_data, subscription_sf_id, stripe_customer_sf_id
        )

        # Create failed payment transaction linked to invoice
        transaction_id = await self._create_failed_payment_transaction(
            invoice_data, subscription_sf_id, stripe_customer_sf_id, invoice_sf_id
        )

        # Update subscription status to past_due if needed
        if invoice_data["subscription_id"] and subscription_sf_id:
            await self._update_subscription_status_failed(
                subscription_id=invoice_data["subscription_id"],
                subscription_sf_id=subscription_sf_id,
                failure_message=invoice_data["failure_message"],
                attempt_count=invoice_data["attempt_count"]
            )

        return {
            "invoice_id": invoice_sf_id,
            "transaction_id": transaction_id,
            "invoice_stripe_id": invoice_data["invoice_id"],
            "subscription_id": invoice_data["subscription_id"],
            "failure_reason": invoice_data["failure_message"],
            "attempt_count": invoice_data["attempt_count"]
        }

    def _extract_failed_invoice_data(self, invoice: Dict[str, Any]) -> Dict[str, Any]:
        """Extract and format failed invoice data for processing."""
        invoice_id = invoice["id"]
        subscription_id = invoice.get("subscription")
        customer_id = invoice.get("customer")
        payment_intent_id = invoice.get("payment_intent")
        amount_due = invoice["amount_due"] / 100.0
        currency = invoice["currency"].upper()
        attempt_count = invoice.get("attempt_count", 0)
        period_start = invoice.get("period_start")
        period_end = invoice.get("period_end")

        # Extract line items
        line_items = []
        if invoice.get("lines", {}).get("data"):
            for line in invoice["lines"]["data"]:
                line_items.append({
                    "id": line.get("id"),
                    "price_id": line.get("price", {}).get("id"),
                    "amount": line.get("amount", 0) / 100.0,
                    "description": line.get("description")
                })

        # Extract failure reason from last_payment_error
        failure_message = self._build_failure_message(invoice.get("last_payment_error"))

        logger.error(f"Invoice payment failure: {failure_message} (Attempt {attempt_count})")

        return {
            "invoice_id": invoice_id,
            "subscription_id": subscription_id,
            "customer_id": customer_id,
            "payment_intent_id": payment_intent_id,
            "amount_due": amount_due,
            "currency": currency,
            "attempt_count": attempt_count,
            "failure_message": failure_message,
            "period_start": period_start,
            "period_end": period_end,
            "tax_amount": invoice.get("tax", 0) / 100.0 if invoice.get("tax") else 0,
            "discounts_applied": invoice.get("total_discount_amounts", [{}])[0].get("amount", 0) / 100.0 if invoice.get("total_discount_amounts") else 0,
            "line_items": line_items
        }

    def _build_failure_message(self, last_error: Optional[Dict[str, Any]]) -> str:
        """Build a human-readable failure message from payment error."""
        if not last_error:
            return "Payment failed"
        
        failure_code = last_error.get("code", "unknown")
        error_message = last_error.get("message", "Payment failed")
        failure_message = f"[{failure_code}] {error_message}"

        # Add decline code if available (card-specific)
        if last_error.get("decline_code"):
            failure_message += f" (Decline: {last_error['decline_code']})"

        return failure_message

    async def _create_failed_invoice_record(
        self,
        invoice_data: Dict[str, Any],
        subscription_sf_id: Optional[str],
        stripe_customer_sf_id: Optional[str]
    ) -> Optional[str]:
        """Create Stripe_Invoice__c record for failed invoice in Salesforce."""
        try:
            # Format line items as JSON string
            line_items_json = None
            if invoice_data.get("line_items"):
                import json
                line_items_json = json.dumps(invoice_data["line_items"])

            # Determine dunning status based on attempt count
            dunning_status = "trying" if invoice_data.get("attempt_count", 1) < 5 else "exhausted"

            invoice_record = SalesforceInvoice(
                Stripe_Invoice_ID__c=invoice_data["invoice_id"],
                Stripe_Subscription__c=subscription_sf_id,
                Stripe_Customer__c=stripe_customer_sf_id,
                Amount__c=invoice_data.get("amount_due"),
                Line_Items__c=line_items_json,
                Period_Start__c=datetime.fromtimestamp(
                    invoice_data["period_start"]
                ) if invoice_data.get("period_start") else None,
                Period_End__c=datetime.fromtimestamp(
                    invoice_data["period_end"]
                ) if invoice_data.get("period_end") else None,
                Tax_Amount__c=invoice_data.get("tax_amount"),
                Discounts_Applied__c=invoice_data.get("discounts_applied"),
                Status__c="open",
                Dunning_Status__c=dunning_status
            )

            result = await salesforce_service.upsert_record(
                sobject="Stripe_Invoice__c",
                external_id_field="Stripe_Invoice_ID__c",
                external_id_value=invoice_data["invoice_id"],
                record_data=invoice_record.model_dump(exclude_none=True)
            )

            invoice_sf_id = result.get("id")
            logger.info(f"Failed invoice record created/updated: {invoice_sf_id} with dunning status: {dunning_status}")
            return invoice_sf_id

        except Exception as e:
            logger.error(f"Failed to create failed invoice record for {invoice_data['invoice_id']}: {str(e)}")
            # Don't raise - invoice creation is secondary to payment processing
            return None

    async def _create_failed_payment_transaction(
        self,
        invoice_data: Dict[str, Any],
        subscription_sf_id: Optional[str],
        stripe_customer_sf_id: Optional[str],
        invoice_sf_id: Optional[str] = None
    ) -> str:
        """Create failed payment transaction record in Salesforce."""
        transaction_data = {
            "Stripe_Payment_Intent_ID__c": invoice_data["payment_intent_id"],
            "Stripe_Invoice_ID__c": invoice_data["invoice_id"],
            "Amount__c": invoice_data["amount_due"],
            "Currency__c": invoice_data["currency"],
            "Status__c": "failed",
            "Payment_Method_Type__c": "card",
            "Transaction_Date__c": datetime.now().isoformat(),
            "Transaction_Type__c": "recurring_payment",
            "Failure_Reason__c": invoice_data["failure_message"]
        }

        # Link to subscription and customer if found
        if subscription_sf_id:
            transaction_data["Stripe_Subscription__c"] = subscription_sf_id

        if stripe_customer_sf_id:
            transaction_data["Stripe_Customer__c"] = stripe_customer_sf_id

        # Link to invoice if available
        if invoice_sf_id:
            transaction_data["Stripe_Invoice__c"] = invoice_sf_id

        try:
            result = await salesforce_service.create_record(
                sobject_type="Payment_Transaction__c",
                record_data=transaction_data
            )

            transaction_id = result["id"]
            logger.info(f"Failed recurring payment transaction created: {transaction_id}")
            return transaction_id

        except SalesforceAPIException as e:
            logger.error(f"Failed to create failed transaction for invoice {invoice_data['invoice_id']}: {str(e)}")
            raise

    async def _get_stripe_customer_id(self, stripe_customer_id: str) -> Optional[str]:
        """
        Query Salesforce for Stripe_Customer__c record by Stripe Customer ID.

        Args:
            stripe_customer_id: Stripe customer ID (e.g., 'cus_xxx')

        Returns:
            Salesforce record ID of Stripe_Customer__c or None if not found

        Raises:
            SalesforceAPIException: If SOQL query fails
        """
        try:
            query = (
                f"SELECT Id FROM Stripe_Customer__c "
                f"WHERE Stripe_Customer_ID__c = '{stripe_customer_id}' "
                f"LIMIT 1"
            )
            result = await salesforce_service.query(query)

            if result.get("records"):
                customer_sf_id = result["records"][0]["Id"]
                logger.info(f"Found Stripe Customer: {customer_sf_id} for {stripe_customer_id}")
                return customer_sf_id
            else:
                logger.warning(f"Stripe Customer not found in Salesforce: {stripe_customer_id}")
                return None

        except SalesforceAPIException as e:
            logger.error(f"Failed to query Stripe Customer {stripe_customer_id}: {str(e)}")
            raise

    async def _get_invoice_salesforce_id(self, stripe_invoice_id: str) -> Optional[str]:
        """
        Query Salesforce for Stripe_Invoice__c record by Stripe Invoice ID.

        Args:
            stripe_invoice_id: Stripe invoice ID (e.g., 'in_xxx')

        Returns:
            Salesforce record ID of Stripe_Invoice__c or None if not found

        Side Effects:
            Logs warning if invoice not found (optional, may be created by separate webhook)
        """
        try:
            query = (
                f"SELECT Id FROM Stripe_Invoice__c "
                f"WHERE Stripe_Invoice_ID__c = '{stripe_invoice_id}' "
                f"LIMIT 1"
            )
            result = await salesforce_service.query(query)

            if result.get("records"):
                invoice_sf_id = result["records"][0]["Id"]
                logger.info(f"Found Stripe Invoice: {invoice_sf_id} for {stripe_invoice_id}")
                return invoice_sf_id
            else:
                # This is not necessarily an error - invoice may not yet exist if it's processed by separate webhook
                logger.debug(f"Stripe Invoice not yet found in Salesforce: {stripe_invoice_id}")
                return None

        except Exception as e:
            logger.error(f"Failed to query Stripe Invoice {stripe_invoice_id}: {str(e)}")
            # Don't raise - return None to allow payment transaction to be created without invoice link
            return None

    async def _update_subscription_period(
        self,
        subscription_id: str,
        subscription_sf_id: str,
        period_start: int,
        period_end: int
    ) -> None:
        """
        Update subscription billing period dates and status after successful payment.

        Args:
            subscription_id: Stripe subscription ID (e.g., 'sub_xxx')
            subscription_sf_id: Salesforce record ID of Stripe_Subscription__c
            period_start: Unix timestamp of period start
            period_end: Unix timestamp of period end

        Raises:
            SalesforceAPIException: If Salesforce update fails

        Side Effects:
            Updates Stripe_Subscription__c fields:
                - Current_Period_Start__c
                - Current_Period_End__c
                - Status__c = 'active'
                - Sync_Status__c = 'Completed'
                - Error_Message__c = null
        """
        # Convert Unix timestamps to ISO 8601 datetime strings
        period_start_dt = datetime.fromtimestamp(period_start).isoformat()
        period_end_dt = datetime.fromtimestamp(period_end).isoformat()

        update_data = {
            "Stripe_Subscription_ID__c": subscription_id,
            "Current_Period_Start__c": period_start_dt,
            "Current_Period_End__c": period_end_dt,
            "Status__c": "active",
            "Sync_Status__c": "Completed",
            "Error_Message__c": None  # Clear any previous errors
        }

        try:
            await salesforce_service.update_record(
                sobject="Stripe_Subscription__c",
                record_id=subscription_sf_id,
                data=update_data
            )

            logger.info(
                f"Updated subscription period: {subscription_id} "
                f"({period_start_dt} to {period_end_dt})"
            )

        except SalesforceAPIException as e:
            logger.error(f"Failed to update subscription period for {subscription_id}: {str(e)}")
            raise

    async def _update_subscription_status_failed(
        self,
        subscription_id: str,
        subscription_sf_id: str,
        failure_message: str,
        attempt_count: int
    ) -> None:
        """
        Update subscription status to 'past_due' after payment failure.

        Args:
            subscription_id: Stripe subscription ID (e.g., 'sub_xxx')
            subscription_sf_id: Salesforce record ID of Stripe_Subscription__c
            failure_message: Human-readable failure reason
            attempt_count: Number of failed payment attempts

        Raises:
            SalesforceAPIException: If Salesforce update fails

        Side Effects:
            Updates Stripe_Subscription__c fields:
                - Status__c = 'past_due'
                - Sync_Status__c = 'Failed'
                - Error_Message__c = failure message with attempt count

        Note:
            Stripe will continue retry attempts based on subscription settings.
            After final attempt, subscription may be canceled automatically.
        """
        error_message = f"{failure_message} (Attempt {attempt_count})"

        update_data = {
            "Stripe_Subscription_ID__c": subscription_id,
            "Status__c": "past_due",
            "Sync_Status__c": "Failed",
            "Error_Message__c": error_message
        }

        try:
            await salesforce_service.update_record(
                sobject="Stripe_Subscription__c",
                record_id=subscription_sf_id,
                data=update_data
            )

            logger.info(f"Updated subscription to past_due: {subscription_id}")

        except SalesforceAPIException as e:
            logger.error(f"Failed to update subscription status for {subscription_id}: {str(e)}")
            raise


# Global payment handler instance
payment_handler = PaymentHandler()
