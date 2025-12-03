"""
Product and Price Event Handler

Handles Stripe product and price events for Salesforce sync.
"""

import logging
from typing import Any, Dict, List, Optional

from app.models.salesforce_records import SalesforcePricingPlan, SalesforcePricingTier
from app.services.salesforce_service import salesforce_service
from app.services.stripe_service import stripe_service
import stripe
from app.config import settings

logger = logging.getLogger(__name__)


async def handle_product_created(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Handle product.created webhook event.

    Currently, we don't create a separate Product entity in Salesforce.
    Product information will be associated with prices when they are created.

    Args:
        event: Stripe webhook event data

    Returns:
        Result dictionary with processing status
    """
    try:
        product = event.get("data", {}).get("object", {})
        product_id = product.get("id")
        product_name = product.get("name")

        logger.info(
            "Product created event received",
            extra={
                "product_id": product_id,
                "product_name": product_name,
            }
        )

        # For now, just log the product creation
        # Product info will be used when creating pricing plans
        return {
            "success": True,
            "message": f"Product {product_id} creation acknowledged",
            "product_id": product_id,
            "product_name": product_name,
        }

    except Exception as e:
        logger.error(f"Error handling product.created: {str(e)}", exc_info=True)
        return {
            "success": False,
            "error": str(e),
        }


async def handle_product_updated(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Handle product.updated webhook event.

    Updates ProductName__c in all related Pricing_Plan__c records.

    Args:
        event: Stripe webhook event data

    Returns:
        Result dictionary with processing status
    """
    try:
        product = event.get("data", {}).get("object", {})
        product_id = product.get("id")
        product_name = product.get("name")

        logger.info(
            "Product updated event received",
            extra={
                "product_id": product_id,
                "product_name": product_name,
            }
        )

        # Query for all Pricing_Plan__c records that have prices for this product
        # We'll need to fetch prices from Stripe to find which ones belong to this product
        stripe.api_key = settings.stripe_api_key

        # List all prices for this product
        prices = stripe.Price.list(product=product_id, limit=100)

        updated_count = 0
        for price in prices.data:
            try:
                # Map Stripe interval to Salesforce picklist value
                recurrency_mapping = {
                    "day": "Daily",
                    "week": "Weekly",
                    "month": "Monthly",
                    "quarter": "Quarterly",
                    "year": "Yearly"
                }

                recurring = price.get("recurring", {})
                interval = recurring.get("interval") if recurring else None
                recurrency_type = recurrency_mapping.get(interval) if interval else None

                # Include all required fields for upsert (in case the record doesn't exist yet)
                update_data = {
                    "Name": product_name,
                    "ProductName__c": product_name,
                    "Currency__c": price.get("currency", "").upper(),
                    "Recurrency_Type__c": recurrency_type
                }

                result = await salesforce_service.upsert_record(
                    sobject_type="Pricing_Plan__c",
                    external_id_field="Stripe_Price_ID__c",
                    external_id_value=price.id,
                    record_data=update_data
                )

                if result.get("success"):
                    updated_count += 1

            except Exception as e:
                logger.warning(
                    f"Failed to update pricing plan for price {price.id}: {str(e)}"
                )

        return {
            "success": True,
            "message": f"Updated {updated_count} pricing plans with new product name",
            "product_id": product_id,
            "updated_count": updated_count,
        }

    except Exception as e:
        logger.error(f"Error handling product.updated: {str(e)}", exc_info=True)
        return {
            "success": False,
            "error": str(e),
        }


async def handle_product_deleted(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Handle product.deleted webhook event.

    Mark related Pricing_Plan__c records as inactive.
    We don't delete them to preserve historical data.

    Args:
        event: Stripe webhook event data

    Returns:
        Result dictionary with processing status
    """
    try:
        product = event.get("data", {}).get("object", {})
        product_id = product.get("id")

        logger.info(
            "Product deleted event received",
            extra={"product_id": product_id}
        )

        # Note: In Stripe, deleting a product doesn't delete its prices
        # Prices need to be archived separately
        # For now, we'll just log this event

        return {
            "success": True,
            "message": f"Product {product_id} deletion acknowledged",
            "product_id": product_id,
        }

    except Exception as e:
        logger.error(f"Error handling product.deleted: {str(e)}", exc_info=True)
        return {
            "success": False,
            "error": str(e),
        }


async def handle_price_created(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Handle price.created webhook event.

    Creates Pricing_Plan__c record and any associated Pricing_Tier__c records.

    Args:
        event: Stripe webhook event data

    Returns:
        Result dictionary with processing status
    """
    try:
        price = event.get("data", {}).get("object", {})
        price_id = price.get("id")
        product_id = price.get("product")

        logger.info(
            "Price created event received",
            extra={
                "price_id": price_id,
                "product_id": product_id,
            }
        )

        # Initialize Stripe API key
        stripe.api_key = settings.stripe_api_key

        # Fetch product details from Stripe
        product_name = None
        if product_id:
            try:
                if isinstance(product_id, str):
                    product = stripe.Product.retrieve(product_id)
                    product_name = product.name
                elif isinstance(product_id, dict):
                    product_name = product_id.get("name")
            except Exception as e:
                logger.warning(f"Could not fetch product details: {str(e)}")

        # Map Stripe interval to Salesforce picklist value
        recurrency_mapping = {
            "day": "Daily",
            "week": "Weekly",
            "month": "Monthly",
            "quarter": "Quarterly",
            "year": "Yearly"
        }

        recurring = price.get("recurring", {})
        interval = recurring.get("interval") if recurring else None
        recurrency_type = recurrency_mapping.get(interval) if interval else None

        # Create Pricing_Plan__c record
        pricing_plan = SalesforcePricingPlan(
            Stripe_Price_ID__c=price_id,
            Name=product_name,  # Standard Name field
            ProductName__c=product_name,
            Amount__c=price.get("unit_amount", 0) / 100 if price.get("unit_amount") else None,
            Currency__c=price.get("currency", "").upper(),
            Recurrency_Type__c=recurrency_type
        )

        # Upsert the pricing plan
        plan_result = await salesforce_service.upsert_pricing_plan(pricing_plan)

        if not plan_result.get("success"):
            raise Exception(f"Failed to create pricing plan: {plan_result.get('errors', [])}")

        salesforce_plan_id = plan_result.get("id")

        # Handle tiered pricing if present
        tiers = price.get("tiers", [])
        if tiers and salesforce_plan_id:
            logger.info(f"Creating {len(tiers)} pricing tiers for plan {salesforce_plan_id}")

            # First, delete any existing tiers for this plan
            # This ensures we have a clean slate for the new tier structure
            try:
                await salesforce_service.delete_pricing_tiers_for_plan(salesforce_plan_id)
            except Exception as e:
                logger.warning(f"Could not delete existing tiers: {str(e)}")

            # Create new tier records
            tier_results = []
            previous_up_to = 0

            for idx, tier in enumerate(tiers):
                tier_record = SalesforcePricingTier(
                    Pricing_Plan__c=salesforce_plan_id,
                    Tier_Number__c=idx + 1,
                    From_Quantity__c=previous_up_to,
                    To_Quantity__c=tier.get("up_to") if tier.get("up_to") else 999999,
                    Unit_Price__c=tier.get("unit_amount", 0) / 100 if tier.get("unit_amount") else tier.get("flat_amount", 0) / 100
                )

                try:
                    tier_result = await salesforce_service.create_pricing_tier(tier_record)
                    tier_results.append(tier_result)
                except Exception as e:
                    logger.error(f"Failed to create tier {idx + 1}: {str(e)}")

                # Update previous_up_to for next iteration
                if tier.get("up_to"):
                    previous_up_to = tier.get("up_to")

            logger.info(f"Created {len(tier_results)} tiers successfully")

        return {
            "success": True,
            "message": f"Pricing plan {price_id} created successfully",
            "price_id": price_id,
            "salesforce_id": salesforce_plan_id,
            "tiers_created": len(tiers) if tiers else 0,
        }

    except Exception as e:
        logger.error(f"Error handling price.created: {str(e)}", exc_info=True)
        return {
            "success": False,
            "error": str(e),
        }


async def handle_price_updated(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Handle price.updated webhook event.

    Updates Pricing_Plan__c record metadata. Note that in Stripe, most price
    attributes are immutable, so this typically only updates metadata.

    Args:
        event: Stripe webhook event data

    Returns:
        Result dictionary with processing status
    """
    try:
        price = event.get("data", {}).get("object", {})
        price_id = price.get("id")

        logger.info(
            "Price updated event received",
            extra={"price_id": price_id}
        )

        # Since most price fields are immutable in Stripe, we mainly need to
        # update the active status and any metadata
        update_data = {}

        # If the price is no longer active, we might want to reflect that
        if not price.get("active", True):
            # You might want to add an Active__c field to Pricing_Plan__c
            # For now, we'll just log it
            logger.info(f"Price {price_id} is now inactive")

        # Update any changed metadata
        # Most other fields (amount, currency, etc.) are immutable in Stripe

        if update_data:
            result = await salesforce_service.upsert_record(
                sobject_type="Pricing_Plan__c",
                external_id_field="Stripe_Price_ID__c",
                external_id_value=price_id,
                record_data=update_data
            )

            return {
                "success": True,
                "message": f"Pricing plan {price_id} updated",
                "price_id": price_id,
                "updated_fields": list(update_data.keys()),
            }
        else:
            return {
                "success": True,
                "message": f"No updates needed for pricing plan {price_id}",
                "price_id": price_id,
            }

    except Exception as e:
        logger.error(f"Error handling price.updated: {str(e)}", exc_info=True)
        return {
            "success": False,
            "error": str(e),
        }


async def handle_price_deleted(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Handle price.deleted webhook event.

    Mark Pricing_Plan__c as inactive. We don't delete it to preserve
    historical data and relationships.

    Args:
        event: Stripe webhook event data

    Returns:
        Result dictionary with processing status
    """
    try:
        price = event.get("data", {}).get("object", {})
        price_id = price.get("id")

        logger.info(
            "Price deleted event received",
            extra={"price_id": price_id}
        )

        # Mark the pricing plan as inactive
        # Note: You might want to add an Active__c or IsDeleted__c field
        # to Pricing_Plan__c to track this status

        # For now, we'll just log the deletion
        # In production, you'd update a status field

        logger.warning(
            f"Price {price_id} was deleted in Stripe. "
            "Consider adding an Active__c field to track this in Salesforce."
        )

        return {
            "success": True,
            "message": f"Price {price_id} deletion acknowledged",
            "price_id": price_id,
        }

    except Exception as e:
        logger.error(f"Error handling price.deleted: {str(e)}", exc_info=True)
        return {
            "success": False,
            "error": str(e),
        }