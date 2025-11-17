"""
Payment Event Handler

Handles Stripe payment-related webhook events.
"""

from datetime import datetime, timezone
from typing import Dict, Any, Optional

from app.models.stripe_events import StripeEvent
from app.models.salesforce_records import SalesforcePaymentTransaction, SalesforceInvoice
from app.services.salesforce_service import salesforce_service
from app.services.dynamodb_service import dynamodb_service
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
                    f"SELECT Id FROM Contact "
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
        # Note: Stripe_Invoice__c is a required Master-Detail field on Payment_Transaction__c
        # so we can only create transactions that have an associated invoice
        stripe_invoice_id = payment_intent.get("invoice")
        if not stripe_invoice_id:
            logger.info(
                "Payment intent has no invoice - skipping transaction creation. "
                "Transaction will be created by invoice.payment_succeeded event instead.",
                extra={"payment_intent_id": payment_intent["id"]}
            )
            return {
                "status": "skipped",
                "reason": "no_invoice",
                "payment_intent_id": payment_intent["id"]
            }

        salesforce_transaction.Stripe_Invoice_ID__c = stripe_invoice_id
        # Try to find and link the Salesforce invoice record
        invoice_sf_id = await self._get_invoice_salesforce_id(stripe_invoice_id)
        if not invoice_sf_id:
            logger.warning(
                "Invoice not found in Salesforce - skipping transaction creation. "
                "Transaction will be created by invoice.payment_succeeded event instead.",
                extra={
                    "payment_intent_id": payment_intent["id"],
                    "stripe_invoice_id": stripe_invoice_id
                }
            )
            return {
                "status": "skipped",
                "reason": "invoice_not_found",
                "payment_intent_id": payment_intent["id"],
                "stripe_invoice_id": stripe_invoice_id
            }

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

        # Map payment intent to Salesforce transaction
        salesforce_transaction = SalesforcePaymentTransaction(
            Stripe_Payment_Intent_ID__c=payment_intent["id"],
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
            # Look up Salesforce IDs for subscription and customer
            stripe_subscription_id = invoice_data.get("subscription")
            stripe_customer_id = invoice_data.get("customer")

            subscription_sf_id, salesforce_customer_id = await self._get_salesforce_ids(
                stripe_subscription_id,
                stripe_customer_id
            )

            # Build standardized invoice record data using helper method
            # At creation time, dunning_status is "none" (no payment attempts yet)
            invoice_record_data = self._build_invoice_record_data(
                invoice_data=invoice_data,
                subscription_sf_id=subscription_sf_id,
                customer_sf_id=salesforce_customer_id,
                dunning_status="none"
            )

            # Upsert invoice using the standardized record data
            result = await salesforce_service.upsert_record(
                sobject_type="Stripe_Invoice__c",
                external_id_field="Stripe_Invoice_ID__c",
                external_id_value=invoice_id,
                record_data={k: v for k, v in invoice_record_data.items()
                           if k != "Stripe_Invoice_ID__c"}
            )

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

        # Create invoice and payment transaction in a single Composite API call
        result = await self._create_invoice_and_transaction_composite(
            invoice_data, subscription_sf_id, stripe_customer_sf_id
        )
        invoice_sf_id = result["invoice_id"]
        transaction_id = result["transaction_id"]

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

        # Extract subscription ID with fallbacks for different Stripe API versions
        # Stripe API 2025+ moved subscription to nested parent objects
        subscription_id = invoice.get("subscription")  # Try top-level first (old API)
        subscription_source = "top_level"

        if not subscription_id:
            # Try parent.subscription_details.subscription (new API format)
            parent = invoice.get("parent", {})
            if parent.get("type") == "subscription_details":
                subscription_details = parent.get("subscription_details", {})
                subscription_id = subscription_details.get("subscription")
                if subscription_id:
                    subscription_source = "parent.subscription_details"

        if not subscription_id:
            # Try first line item's subscription (most reliable for subscription invoices)
            lines_data = invoice.get("lines", {}).get("data", [])
            if lines_data:
                first_line = lines_data[0]
                line_parent = first_line.get("parent", {})
                if line_parent.get("type") == "subscription_item_details":
                    sub_item_details = line_parent.get("subscription_item_details", {})
                    subscription_id = sub_item_details.get("subscription")
                    if subscription_id:
                        subscription_source = "line_items[0].parent.subscription_item_details"

        # Log which source was used
        if subscription_id:
            logger.info(
                f"Extracted subscription ID from invoice",
                extra={
                    "invoice_id": invoice.get("id"),
                    "subscription_id": subscription_id,
                    "source": subscription_source
                }
            )
        else:
            logger.warning(
                f"No subscription ID found in invoice",
                extra={
                    "invoice_id": invoice.get("id"),
                    "checked_sources": ["top_level", "parent.subscription_details", "line_items"]
                }
            )

        # Extract payment method type if available
        payment_method_type = None
        payment_intent = invoice.get("payment_intent")
        if payment_intent and isinstance(payment_intent, dict):
            # payment_intent is expanded object
            payment_method_types = payment_intent.get("payment_method_types", [])
            payment_method_type = payment_method_types[0] if payment_method_types else None

        # Extract period dates with fallbacks for different Stripe API versions
        # Similar to subscription_id, period dates may be in different locations
        period_start = invoice.get("period_start")  # Try top-level first (old API)
        period_end = invoice.get("period_end")
        period_source = "top_level"

        # If period dates are not at top level, check parent.subscription_details (Stripe API 2025+)
        if not period_start or not period_end:
            parent = invoice.get("parent", {})
            if parent.get("type") == "subscription_details":
                subscription_details = parent.get("subscription_details", {})
                if not period_start:
                    period_start = subscription_details.get("period_start")
                if not period_end:
                    period_end = subscription_details.get("period_end")
                if period_start or period_end:
                    period_source = "parent.subscription_details"

        # Log which source was used for period dates
        if period_start and period_end:
            logger.info(
                f"Extracted period dates from invoice",
                extra={
                    "invoice_id": invoice.get("id"),
                    "period_start": period_start,
                    "period_end": period_end,
                    "source": period_source,
                    "dates_equal": period_start == period_end
                }
            )
        else:
            logger.warning(
                f"Missing period dates in invoice",
                extra={
                    "invoice_id": invoice.get("id"),
                    "period_start": period_start,
                    "period_end": period_end,
                    "checked_sources": ["top_level", "parent.subscription_details"]
                }
            )

        return {
            "invoice_id": invoice["id"],
            "subscription_id": subscription_id,
            "customer_id": invoice.get("customer"),
            "payment_intent_id": invoice.get("payment_intent") if isinstance(invoice.get("payment_intent"), str) else invoice.get("payment_intent", {}).get("id"),
            "amount_paid": invoice["amount_paid"] / 100.0,  # Convert cents to dollars
            "amount_due": invoice.get("amount_due", 0) / 100.0 if invoice.get("amount_due") else 0,  # Convert cents to dollars
            "currency": invoice["currency"].upper(),
            "period_start": period_start,
            "period_end": period_end,
            "due_date": invoice.get("due_date"),
            "tax_amount": invoice.get("tax", 0) / 100.0 if invoice.get("tax") else 0,
            "discounts_applied": invoice.get("total_discount_amounts", [{}])[0].get("amount", 0) / 100.0 if invoice.get("total_discount_amounts") else 0,
            "paid": invoice.get("paid", False),
            "pdf_url": invoice.get("invoice_pdf"),
            "payment_method_type": payment_method_type,
            "line_items": line_items
        }

    def _build_invoice_record_data(
        self,
        invoice_data: Dict[str, Any],
        subscription_sf_id: Optional[str],
        customer_sf_id: Optional[str],
        dunning_status: str = "none"
    ) -> Dict[str, Any]:
        """
        Build standardized invoice record data for Salesforce.

        This is the single source of truth for invoice field mapping, ensuring
        consistency across all invoice creation paths (created, payment_succeeded, payment_failed).

        Args:
            invoice_data: Extracted invoice data from Stripe
            subscription_sf_id: Salesforce Subscription ID (not Stripe subscription ID)
            customer_sf_id: Salesforce Contact ID
            dunning_status: Dunning status for failed payments ("none", "trying", "exhausted")

        Returns:
            Dictionary with standardized Salesforce invoice fields
        """
        import json

        # Format line items as JSON string
        line_items_json = None
        if invoice_data.get("line_items"):
            line_items_json = json.dumps(invoice_data["line_items"])

        # Build record data with standardized field names
        invoice_record_data = {
            "Stripe_Invoice_ID__c": invoice_data.get("invoice_id"),
            "Stripe_Subscription__c": subscription_sf_id,
            "Contact__c": customer_sf_id,
            # Use amount_due for the invoice amount (what's owed)
            "Amount__c": invoice_data.get("amount_due") or invoice_data.get("amount_paid"),
            "Line_Items__c": line_items_json,
            "Invoice_PDF_URL__c": invoice_data.get("pdf_url"),
            # Status: "paid" if paid, otherwise "open"
            "Status__c": "paid" if invoice_data.get("paid") else "open",
            # Always set dunning status
            "Dunning_Status__c": dunning_status
        }

        # Add optional date fields
        if invoice_data.get("period_start"):
            invoice_record_data["Period_Start__c"] = datetime.fromtimestamp(
                invoice_data["period_start"]
            ).isoformat()
        if invoice_data.get("period_end"):
            invoice_record_data["Period_End__c"] = datetime.fromtimestamp(
                invoice_data["period_end"]
            ).isoformat()
        if invoice_data.get("due_date"):
            invoice_record_data["Due_Date__c"] = datetime.fromtimestamp(
                invoice_data["due_date"]
            ).isoformat()

        # Handle tax amount - convert from cents to dollars if needed
        tax_amount = invoice_data.get("tax_amount")
        if tax_amount and tax_amount > 0:
            invoice_record_data["Tax_Amount__c"] = tax_amount

        # Handle discounts - use standardized field name with 's'
        discount = invoice_data.get("discounts_applied")
        if discount and discount > 0:
            invoice_record_data["Discounts_Applied__c"] = discount

        # Remove None values to avoid overwriting existing fields
        invoice_record_data = {k: v for k, v in invoice_record_data.items() if v is not None}

        return invoice_record_data

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
        """
        Query Salesforce for subscription record and return subscription and Contact IDs.
        Uses DynamoDB cache to minimize Salesforce API calls.
        """
        # Try cache first
        try:
            cached_sf_id = await dynamodb_service.get(
                key=subscription_id,
                namespace="stripe_subscriptions"
            )

            if cached_sf_id:
                # Cache hit! Still need to query for Contact__c
                # Use Salesforce ID for a more efficient query
                logger.info(
                    f"Cache hit for subscription {subscription_id}",
                    extra={"cached_sf_id": cached_sf_id}
                )

                try:
                    query = f"SELECT Contact__c FROM Stripe_Subscription__c WHERE Id = '{cached_sf_id}' LIMIT 1"
                    result = await salesforce_service.query(query)

                    if result.get("records"):
                        contact_id = result["records"][0].get("Contact__c")
                        logger.info(f"Found subscription from cache: {cached_sf_id} with contact: {contact_id}")
                        return cached_sf_id, contact_id
                    else:
                        # Cache was stale, fall through to full query
                        logger.warning(f"Cached subscription ID not found in Salesforce, will re-query")
                except Exception as e:
                    logger.warning(f"Failed to query with cached ID: {str(e)}, falling back to full query")
        except Exception as e:
            logger.debug(f"Cache lookup failed: {str(e)}, falling back to Salesforce query")

        # Cache miss or error - query Salesforce
        try:
            query = (
                f"SELECT Id, Contact__c "
                f"FROM Stripe_Subscription__c "
                f"WHERE Stripe_Subscription_ID__c = '{subscription_id}' "
                f"LIMIT 1"
            )
            subscription_result = await salesforce_service.query(query)

            if subscription_result.get("records"):
                subscription_record = subscription_result["records"][0]
                subscription_sf_id = subscription_record["Id"]
                stripe_customer_sf_id = subscription_record.get("Contact__c")

                logger.info(f"Found subscription from Salesforce: {subscription_sf_id} with contact: {stripe_customer_sf_id}")

                # Cache the result for future lookups
                try:
                    await dynamodb_service.set(
                        key=subscription_id,
                        value=subscription_sf_id,
                        ttl_seconds=30 * 24 * 3600,  # 30 days
                        namespace="stripe_subscriptions"
                    )
                    logger.debug(f"Cached subscription ID mapping for {subscription_id}")
                except Exception as cache_error:
                    logger.warning(f"Failed to cache subscription ID: {str(cache_error)}")

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
                Contact__c=stripe_customer_sf_id,
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

        # Link to subscription if found
        if subscription_sf_id:
            transaction_data["Stripe_Subscription__c"] = subscription_sf_id

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

    async def _ensure_invoice_exists(
        self,
        invoice_data: Dict[str, Any],
        subscription_sf_id: Optional[str],
        stripe_customer_sf_id: Optional[str]
    ) -> str:
        """
        Ensure an invoice exists in Salesforce, creating or updating as needed.

        Args:
            invoice_data: Extracted invoice data from Stripe
            subscription_sf_id: Salesforce subscription ID
            stripe_customer_sf_id: Salesforce customer ID

        Returns:
            Salesforce Invoice ID

        Raises:
            SalesforceAPIException: If invoice creation/update fails
        """
        # Get dunning status from invoice_data if present (for failed payments)
        dunning_status = invoice_data.get("dunning_status", "none")

        # Build standardized invoice record data using helper method
        invoice_record_data = self._build_invoice_record_data(
            invoice_data=invoice_data,
            subscription_sf_id=subscription_sf_id,
            customer_sf_id=stripe_customer_sf_id,
            dunning_status=dunning_status
        )

        # Check if invoice already exists
        existing_invoice_id = await self._get_invoice_salesforce_id(invoice_data["invoice_id"])

        if existing_invoice_id:
            logger.info(
                "Invoice already exists in Salesforce, updating it",
                extra={
                    "stripe_invoice_id": invoice_data["invoice_id"],
                    "sf_invoice_id": existing_invoice_id
                }
            )

            # Update the existing invoice (exclude external ID and Contact fields from update)
            update_data = {k: v for k, v in invoice_record_data.items()
                          if k not in ["Stripe_Invoice_ID__c", "Contact__c"]}

            await salesforce_service.update_record(
                sobject_type="Stripe_Invoice__c",
                record_id=existing_invoice_id,
                record_data=update_data
            )

            return existing_invoice_id
        else:
            # Create new invoice using upsert with external ID
            logger.info(
                "Creating new invoice in Salesforce",
                extra={"stripe_invoice_id": invoice_data["invoice_id"]}
            )

            result = await salesforce_service.upsert_record(
                sobject_type="Stripe_Invoice__c",
                external_id_field="Stripe_Invoice_ID__c",
                external_id_value=invoice_data["invoice_id"],
                record_data={k: v for k, v in invoice_record_data.items()
                           if k != "Stripe_Invoice_ID__c"}
            )

            invoice_id = result.get("id")
            logger.info(
                "Successfully created invoice",
                extra={
                    "stripe_invoice_id": invoice_data["invoice_id"],
                    "sf_invoice_id": invoice_id
                }
            )

            return invoice_id

    async def _create_linked_transaction(
        self,
        invoice_data: Dict[str, Any],
        invoice_sf_id: str,
        subscription_sf_id: Optional[str],
        transaction_status: str = "succeeded"
    ) -> str:
        """
        Create a payment transaction that is REQUIRED to be linked to an invoice.

        IMPORTANT: This method will NOT update the Master-Detail parent field
        (Stripe_Invoice__c) on existing transactions, as Salesforce forbids this.
        If a transaction already exists for this payment intent, returns its ID.

        Args:
            invoice_data: Extracted invoice data from Stripe
            invoice_sf_id: REQUIRED Salesforce Invoice ID to link transaction to
            subscription_sf_id: Optional Salesforce subscription ID
            transaction_status: Transaction status (succeeded/failed)

        Returns:
            Salesforce Transaction ID

        Raises:
            ValueError: If invoice_sf_id is not provided
            SalesforceAPIException: If transaction creation fails
        """
        # Validate required invoice link
        if not invoice_sf_id:
            raise ValueError(
                f"Cannot create payment transaction without invoice ID. "
                f"Stripe Invoice: {invoice_data.get('invoice_id')}"
            )

        payment_intent_id = invoice_data.get("payment_intent_id")
        stripe_invoice_id = invoice_data.get("invoice_id")

        # Determine which external ID field to use for upsert
        # This prevents Master-Detail constraint violations when payment_intent_id is NULL
        if payment_intent_id:
            # Use payment intent as external ID (preferred)
            external_id_field = "Stripe_Payment_Intent_ID__c"
            external_id_value = payment_intent_id

            # Check if transaction already exists
            existing_transaction_id = await self._get_transaction_salesforce_id(payment_intent_id)
            if existing_transaction_id:
                logger.info(
                    "Payment transaction already exists, returning existing ID",
                    extra={
                        "stripe_invoice_id": stripe_invoice_id,
                        "sf_invoice_id": invoice_sf_id,
                        "payment_intent_id": payment_intent_id,
                        "existing_transaction_id": existing_transaction_id
                    }
                )
                return existing_transaction_id
        else:
            # Fallback to invoice ID when payment_intent_id is NULL
            # This ensures one transaction per invoice and prevents matching unrelated transactions
            external_id_field = "Stripe_Invoice_ID__c"
            external_id_value = stripe_invoice_id

            logger.info(
                "No payment_intent_id, using invoice ID as external ID for transaction upsert",
                extra={
                    "stripe_invoice_id": stripe_invoice_id,
                    "sf_invoice_id": invoice_sf_id
                }
            )

        # Prepare transaction record data
        transaction_record_data = {
            "Stripe_Payment_Intent_ID__c": payment_intent_id,
            "Stripe_Invoice_ID__c": stripe_invoice_id,
            "Stripe_Invoice__c": invoice_sf_id,  # REQUIRED link to invoice
            "Amount__c": invoice_data.get("amount_paid", 0),
            "Currency__c": invoice_data.get("currency", "usd"),
            "Status__c": transaction_status,
            "Payment_Method_Type__c": invoice_data.get("payment_method_type", "card"),
            "Transaction_Date__c": datetime.now().isoformat(),
            "Transaction_Type__c": "recurring_payment"
        }

        # Add optional subscription link
        if subscription_sf_id:
            transaction_record_data["Stripe_Subscription__c"] = subscription_sf_id

        # Remove None values
        transaction_record_data = {k: v for k, v in transaction_record_data.items() if v is not None}

        logger.info(
            "Creating payment transaction linked to invoice",
            extra={
                "stripe_invoice_id": stripe_invoice_id,
                "sf_invoice_id": invoice_sf_id,
                "payment_intent_id": payment_intent_id,
                "external_id_field": external_id_field,
                "external_id_value": external_id_value
            }
        )

        # Create transaction using upsert with dynamically selected external ID
        # When payment_intent_id is NULL, uses Stripe_Invoice_ID__c to ensure idempotency
        # and prevent Master-Detail constraint violations
        result = await salesforce_service.upsert_record(
            sobject_type="Payment_Transaction__c",
            external_id_field=external_id_field,
            external_id_value=external_id_value,
            record_data={k: v for k, v in transaction_record_data.items()
                        if k != external_id_field}  # Exclude the external ID field being used
        )

        transaction_id = result.get("id")
        logger.info(
            "Successfully created payment transaction",
            extra={
                "sf_transaction_id": transaction_id,
                "sf_invoice_id": invoice_sf_id,
                "stripe_payment_intent_id": payment_intent_id
            }
        )

        return transaction_id

    async def _create_invoice_and_transaction_composite(
        self,
        invoice_data: Dict[str, Any],
        subscription_sf_id: Optional[str],
        stripe_customer_sf_id: Optional[str]
    ) -> Dict[str, Any]:
        """
        Create or update invoice and create linked payment transaction.
        This ensures the transaction is ALWAYS linked to an invoice.

        Args:
            invoice_data: Extracted invoice data from Stripe
            subscription_sf_id: Salesforce subscription ID
            stripe_customer_sf_id: Salesforce customer ID

        Returns:
            Dictionary with:
                - invoice_id: Salesforce ID of created/updated Stripe_Invoice__c
                - transaction_id: Salesforce ID of created Payment_Transaction__c
                - error: Optional error message if transaction creation fails

        Raises:
            SalesforceAPIException: If invoice creation fails (transaction won't be created)
        """
        # Step 1: Ensure invoice exists (create or update)
        # This will always succeed or raise an exception
        invoice_sf_id = None
        try:
            invoice_sf_id = await self._ensure_invoice_exists(
                invoice_data=invoice_data,
                subscription_sf_id=subscription_sf_id,
                stripe_customer_sf_id=stripe_customer_sf_id
            )

            logger.info(
                "Invoice ready for transaction creation",
                extra={
                    "stripe_invoice_id": invoice_data["invoice_id"],
                    "sf_invoice_id": invoice_sf_id
                }
            )
        except Exception as e:
            # Invoice creation/update failed - do NOT create transaction
            logger.error(
                f"Failed to ensure invoice exists, aborting transaction creation",
                extra={
                    "stripe_invoice_id": invoice_data["invoice_id"],
                    "error": str(e)
                }
            )
            raise  # Re-raise to prevent orphan transactions

        # Step 2: Create transaction WITH REQUIRED invoice link
        transaction_id = None
        transaction_error = None
        try:
            transaction_id = await self._create_linked_transaction(
                invoice_data=invoice_data,
                invoice_sf_id=invoice_sf_id,  # REQUIRED parameter
                subscription_sf_id=subscription_sf_id,
                transaction_status="succeeded"
            )

            logger.info(
                "Successfully created invoice and linked transaction",
                extra={
                    "invoice_id": invoice_sf_id,
                    "transaction_id": transaction_id,
                    "stripe_invoice_id": invoice_data["invoice_id"]
                }
            )
        except Exception as e:
            # Transaction creation failed, but invoice exists
            # This is a valid state per data model (invoice with 0 transactions)
            transaction_error = str(e)
            logger.error(
                f"Transaction creation failed but invoice exists",
                extra={
                    "invoice_id": invoice_sf_id,
                    "stripe_invoice_id": invoice_data["invoice_id"],
                    "payment_intent_id": invoice_data.get("payment_intent_id"),
                    "error": transaction_error
                }
            )
            # Don't raise - return partial success

        # Return results
        result = {
            "invoice_id": invoice_sf_id,
            "transaction_id": transaction_id,
            "composite_response": None  # Kept for backwards compatibility
        }

        if transaction_error:
            result["error"] = transaction_error

        return result

    async def _create_failed_invoice_and_transaction_composite(
        self,
        invoice_data: Dict[str, Any],
        subscription_sf_id: Optional[str],
        stripe_customer_sf_id: Optional[str]
    ) -> Dict[str, Any]:
        """
        Create or update invoice for a failed payment and create linked failed transaction.
        This ensures the failed transaction is ALWAYS linked to an invoice.

        Args:
            invoice_data: Extracted failed invoice data from Stripe
            subscription_sf_id: Salesforce subscription ID
            stripe_customer_sf_id: Salesforce customer ID

        Returns:
            Dictionary with:
                - invoice_id: Salesforce ID of created/updated Stripe_Invoice__c
                - transaction_id: Salesforce ID of created Payment_Transaction__c
                - error: Optional error message if transaction creation fails

        Raises:
            SalesforceAPIException: If invoice creation fails (transaction won't be created)
        """
        # Determine dunning status based on attempt count
        dunning_status = "trying" if invoice_data.get("attempt_count", 1) < 5 else "exhausted"

        # Update invoice_data with failed payment specifics
        invoice_data_modified = invoice_data.copy()
        invoice_data_modified["paid"] = False  # Mark invoice as unpaid
        invoice_data_modified["dunning_status"] = dunning_status

        # Use amount_due for failed payments (not amount_paid)
        if "amount_due" in invoice_data_modified and "amount_paid" not in invoice_data_modified:
            invoice_data_modified["amount_paid"] = invoice_data_modified["amount_due"]

        # Step 1: Ensure invoice exists (create or update)
        invoice_sf_id = None
        try:
            invoice_sf_id = await self._ensure_invoice_exists(
                invoice_data=invoice_data_modified,
                subscription_sf_id=subscription_sf_id,
                stripe_customer_sf_id=stripe_customer_sf_id
            )

            logger.info(
                "Failed invoice ready for failed transaction creation",
                extra={
                    "stripe_invoice_id": invoice_data["invoice_id"],
                    "sf_invoice_id": invoice_sf_id,
                    "dunning_status": dunning_status
                }
            )
        except Exception as e:
            # Invoice creation/update failed - do NOT create transaction
            logger.error(
                f"Failed to ensure invoice exists for failed payment, aborting transaction creation",
                extra={
                    "stripe_invoice_id": invoice_data["invoice_id"],
                    "error": str(e)
                }
            )
            raise  # Re-raise to prevent orphan transactions

        # Step 2: Create failed transaction WITH REQUIRED invoice link
        transaction_id = None
        transaction_error = None

        # Add failure reason to invoice_data if present
        if invoice_data.get("failure_message"):
            invoice_data_modified["failure_reason"] = invoice_data["failure_message"]

        try:
            # Override the _create_linked_transaction for failed status
            # We need to handle the failure_reason field
            transaction_record_data = {
                "Stripe_Payment_Intent_ID__c": invoice_data.get("payment_intent_id"),
                "Stripe_Invoice_ID__c": invoice_data.get("invoice_id"),
                "Stripe_Invoice__c": invoice_sf_id,  # REQUIRED link to invoice
                "Amount__c": invoice_data.get("amount_due", 0),
                "Currency__c": invoice_data.get("currency", "usd"),
                "Status__c": "failed",
                "Payment_Method_Type__c": invoice_data.get("payment_method_type", "card"),
                "Transaction_Date__c": datetime.now().isoformat(),
                "Transaction_Type__c": "recurring_payment",
                "Failure_Reason__c": invoice_data.get("failure_message")
            }

            # Add optional subscription link
            if subscription_sf_id:
                transaction_record_data["Stripe_Subscription__c"] = subscription_sf_id

            # Remove None values
            transaction_record_data = {k: v for k, v in transaction_record_data.items() if v is not None}

            # Create the failed transaction
            result = await salesforce_service.upsert_record(
                sobject_type="Payment_Transaction__c",
                external_id_field="Stripe_Payment_Intent_ID__c",
                external_id_value=invoice_data.get("payment_intent_id"),
                record_data={k: v for k, v in transaction_record_data.items()
                            if k != "Stripe_Payment_Intent_ID__c"}
            )

            transaction_id = result.get("id")

            logger.info(
                "Successfully created failed invoice and linked failed transaction",
                extra={
                    "invoice_id": invoice_sf_id,
                    "transaction_id": transaction_id,
                    "stripe_invoice_id": invoice_data["invoice_id"],
                    "dunning_status": dunning_status
                }
            )
        except Exception as e:
            # Transaction creation failed, but invoice exists
            # This is a valid state per data model (invoice with 0 transactions)
            transaction_error = str(e)
            logger.error(
                f"Failed transaction creation failed but invoice exists",
                extra={
                    "invoice_id": invoice_sf_id,
                    "stripe_invoice_id": invoice_data["invoice_id"],
                    "payment_intent_id": invoice_data.get("payment_intent_id"),
                    "error": transaction_error,
                    "dunning_status": dunning_status
                }
            )
            # Don't raise - return partial success

        # Return results
        result = {
            "invoice_id": invoice_sf_id,
            "transaction_id": transaction_id,
            "composite_response": None  # Kept for backwards compatibility
        }

        if transaction_error:
            result["error"] = transaction_error

        return result

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

        # Create invoice and failed payment transaction in a single Composite API call
        result = await self._create_failed_invoice_and_transaction_composite(
            invoice_data, subscription_sf_id, stripe_customer_sf_id
        )
        invoice_sf_id = result["invoice_id"]
        transaction_id = result["transaction_id"]

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

        # Extract subscription ID with fallbacks for different Stripe API versions
        subscription_id = invoice.get("subscription")  # Try top-level first
        if not subscription_id:
            # Check parent.subscription_details for Stripe API 2025+
            parent = invoice.get("parent", {})
            if parent.get("type") == "subscription_details":
                subscription_details = parent.get("subscription_details", {})
                subscription_id = subscription_details.get("subscription")

        customer_id = invoice.get("customer")
        payment_intent_id = invoice.get("payment_intent")
        amount_due = invoice["amount_due"] / 100.0
        currency = invoice["currency"].upper()
        attempt_count = invoice.get("attempt_count", 0)

        # Extract period dates with fallbacks for different Stripe API versions
        period_start = invoice.get("period_start")  # Try top-level first
        period_end = invoice.get("period_end")
        period_source = "top_level"

        # If period dates are not at top level, check parent.subscription_details (Stripe API 2025+)
        if not period_start or not period_end:
            parent = invoice.get("parent", {})
            if parent.get("type") == "subscription_details":
                subscription_details = parent.get("subscription_details", {})
                if not period_start:
                    period_start = subscription_details.get("period_start")
                if not period_end:
                    period_end = subscription_details.get("period_end")
                if period_start or period_end:
                    period_source = "parent.subscription_details"

        # Log period date extraction for failed invoices
        if period_start and period_end:
            logger.info(
                f"Extracted period dates from failed invoice",
                extra={
                    "invoice_id": invoice_id,
                    "period_start": period_start,
                    "period_end": period_end,
                    "source": period_source,
                    "dates_equal": period_start == period_end
                }
            )

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
                Contact__c=stripe_customer_sf_id,
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

        # Link to subscription if found
        if subscription_sf_id:
            transaction_data["Stripe_Subscription__c"] = subscription_sf_id

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
        Query Salesforce for Contact record via Stripe_Customer__c lookup field by Stripe Customer ID.

        Args:
            stripe_customer_id: Stripe customer ID (e.g., 'cus_xxx')

        Returns:
            Salesforce Contact record ID or None if not found

        Raises:
            SalesforceAPIException: If SOQL query fails
        """
        try:
            query = (
                f"SELECT Id FROM Contact "
                f"WHERE Stripe_Customer_ID__c = '{stripe_customer_id}' "
                f"LIMIT 1"
            )
            result = await salesforce_service.query(query)

            if result.get("records"):
                customer_sf_id = result["records"][0]["Id"]
                logger.info(f"Found Contact: {customer_sf_id} for Stripe customer {stripe_customer_id}")
                return customer_sf_id
            else:
                logger.warning(f"Contact not found in Salesforce for Stripe customer: {stripe_customer_id}")
                return None

        except SalesforceAPIException as e:
            logger.error(f"Failed to query Contact for Stripe customer {stripe_customer_id}: {str(e)}")
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

    async def _get_transaction_salesforce_id(self, stripe_payment_intent_id: str) -> Optional[str]:
        """
        Query Salesforce for Payment_Transaction__c record by Stripe Payment Intent ID.

        Args:
            stripe_payment_intent_id: Stripe payment intent ID (e.g., 'pi_xxx')

        Returns:
            Salesforce record ID of Payment_Transaction__c or None if not found

        Side Effects:
            Returns None if transaction not found or if query fails
        """
        try:
            query = (
                f"SELECT Id FROM Payment_Transaction__c "
                f"WHERE Stripe_Payment_Intent_ID__c = '{stripe_payment_intent_id}' "
                f"LIMIT 1"
            )
            result = await salesforce_service.query(query)

            if result.get("records"):
                transaction_sf_id = result["records"][0]["Id"]
                logger.info(f"Found Payment Transaction: {transaction_sf_id} for {stripe_payment_intent_id}")
                return transaction_sf_id
            else:
                logger.debug(f"Payment Transaction not found in Salesforce: {stripe_payment_intent_id}")
                return None

        except Exception as e:
            logger.error(f"Failed to query Payment Transaction {stripe_payment_intent_id}: {str(e)}")
            # Don't raise - return None to allow transaction to be created
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
                sobject_type="Stripe_Subscription__c",
                record_id=subscription_sf_id,
                record_data=update_data
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
                sobject_type="Stripe_Subscription__c",
                record_id=subscription_sf_id,
                record_data=update_data
            )

            logger.info(f"Updated subscription to past_due: {subscription_id}")

        except SalesforceAPIException as e:
            logger.error(f"Failed to update subscription status for {subscription_id}: {str(e)}")
            raise


# Global payment handler instance
payment_handler = PaymentHandler()
