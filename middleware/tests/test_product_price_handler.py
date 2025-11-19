"""
Unit tests for product_price_handler module.

Tests all product and price-related webhook handlers including:
- product.created
- product.updated
- product.deleted
- price.created
- price.updated
- price.deleted
"""
import pytest
from unittest.mock import AsyncMock, patch, MagicMock
from datetime import datetime
from app.handlers import product_price_handler
from app.models.salesforce_records import SalesforcePricingPlan, SalesforcePricingTier


@pytest.fixture
def mock_salesforce_service():
    """
    Mock Salesforce service with standard responses.

    Returns:
        AsyncMock configured with common Salesforce API responses
    """
    mock_service = AsyncMock()

    # Default responses
    mock_service.upsert_pricing_plan = AsyncMock(return_value={
        "id": "a0Pxx0000000001AAA",
        "success": True,
        "created": False
    })
    mock_service.create_pricing_tier = AsyncMock(return_value={
        "id": "a0Qxx0000000001AAA",
        "success": True
    })
    mock_service.delete_pricing_tiers_for_plan = AsyncMock(return_value={
        "deleted": 2,
        "errors": []
    })
    mock_service.query = AsyncMock(return_value={
        "totalSize": 1,
        "records": [
            {
                "Id": "a0Pxx0000000001AAA",
                "Stripe_Price_ID__c": "price_1ABC123"
            }
        ]
    })

    return mock_service


@pytest.fixture
def mock_stripe_service():
    """
    Mock Stripe service with standard responses.

    Returns:
        AsyncMock configured with common Stripe API responses
    """
    mock_service = AsyncMock()

    # Default product response
    mock_service.get_product = AsyncMock(return_value={
        "id": "prod_TestProduct",
        "name": "Premium Plan",
        "description": "Our premium subscription plan",
        "active": True,
        "metadata": {}
    })

    return mock_service


@pytest.fixture
def sample_product_created_event():
    """
    Sample product.created event from Stripe.

    Returns:
        Dictionary representing a product creation webhook
    """
    return {
        "id": "evt_test_product_created",
        "type": "product.created",
        "data": {
            "object": {
                "id": "prod_TestProduct",
                "name": "Premium Plan",
                "description": "Our premium subscription plan",
                "active": True,
                "default_price": None,
                "metadata": {},
                "created": 1698796800,
                "updated": 1698796800
            }
        }
    }


@pytest.fixture
def sample_product_updated_event():
    """
    Sample product.updated event from Stripe.

    Returns:
        Dictionary representing a product update webhook
    """
    return {
        "id": "evt_test_product_updated",
        "type": "product.updated",
        "data": {
            "object": {
                "id": "prod_TestProduct",
                "name": "Premium Plan Plus",  # Name changed
                "description": "Our enhanced premium subscription plan",
                "active": True,
                "default_price": "price_1ABC123",
                "metadata": {"tier": "premium"},
                "created": 1698796800,
                "updated": 1698883200
            }
        }
    }


@pytest.fixture
def sample_product_deleted_event():
    """
    Sample product.deleted event from Stripe.

    Returns:
        Dictionary representing a product deletion webhook
    """
    return {
        "id": "evt_test_product_deleted",
        "type": "product.deleted",
        "data": {
            "object": {
                "id": "prod_TestProduct",
                "name": "Deprecated Plan",
                "active": False,
                "deleted": True
            }
        }
    }


@pytest.fixture
def sample_price_created_event():
    """
    Sample price.created event from Stripe with tiered pricing.

    Returns:
        Dictionary representing a price creation webhook
    """
    return {
        "id": "evt_test_price_created",
        "type": "price.created",
        "data": {
            "object": {
                "id": "price_1ABC123",
                "product": "prod_TestProduct",
                "active": True,
                "currency": "usd",
                "unit_amount": None,  # Null for tiered pricing
                "billing_scheme": "tiered",
                "recurring": {
                    "interval": "month",
                    "interval_count": 1
                },
                "tiers_mode": "graduated",
                "tiers": [
                    {
                        "up_to": 10,
                        "unit_amount": 1000,  # $10 per unit for first 10
                        "flat_amount": None
                    },
                    {
                        "up_to": 50,
                        "unit_amount": 800,  # $8 per unit for 11-50
                        "flat_amount": None
                    },
                    {
                        "up_to": None,  # Unlimited
                        "unit_amount": 600,  # $6 per unit for 51+
                        "flat_amount": None
                    }
                ],
                "metadata": {},
                "created": 1698796800
            }
        }
    }


@pytest.fixture
def sample_price_created_event_simple():
    """
    Sample price.created event from Stripe with simple pricing.

    Returns:
        Dictionary representing a simple price creation webhook
    """
    return {
        "id": "evt_test_price_created_simple",
        "type": "price.created",
        "data": {
            "object": {
                "id": "price_2DEF456",
                "product": "prod_TestProduct",
                "active": True,
                "currency": "usd",
                "unit_amount": 2999,  # $29.99
                "billing_scheme": "per_unit",
                "recurring": {
                    "interval": "month",
                    "interval_count": 1
                },
                "tiers_mode": None,
                "tiers": None,
                "metadata": {},
                "created": 1698796800
            }
        }
    }


@pytest.fixture
def sample_price_updated_event():
    """
    Sample price.updated event from Stripe.

    Returns:
        Dictionary representing a price update webhook
    """
    return {
        "id": "evt_test_price_updated",
        "type": "price.updated",
        "data": {
            "object": {
                "id": "price_1ABC123",
                "product": "prod_TestProduct",
                "active": False,  # Price deactivated
                "currency": "usd",
                "unit_amount": 2999,
                "metadata": {"archived": "true"},
                "updated": 1698883200
            }
        }
    }


@pytest.fixture
def sample_price_deleted_event():
    """
    Sample price.deleted event from Stripe.

    Returns:
        Dictionary representing a price deletion webhook
    """
    return {
        "id": "evt_test_price_deleted",
        "type": "price.deleted",
        "data": {
            "object": {
                "id": "price_1ABC123",
                "product": "prod_TestProduct",
                "deleted": True
            }
        }
    }


@pytest.mark.asyncio
async def test_handle_product_created(
    sample_product_created_event
):
    """Test product.created event handler."""
    # Act
    result = await product_price_handler.handle_product_created(sample_product_created_event)

    # Assert
    assert result["success"] == True
    assert result["product_id"] == "prod_TestProduct"
    assert result["product_name"] == "Premium Plan"


@pytest.mark.asyncio
async def test_handle_product_updated(
    sample_product_updated_event,
    mock_salesforce_service
):
    """Test product.updated event handler updates all related pricing plans."""
    # Arrange
    with patch("app.handlers.product_price_handler.salesforce_service", mock_salesforce_service):
        with patch("app.handlers.product_price_handler.stripe") as mock_stripe:
            # Mock Stripe price list
            mock_stripe.Price.list = MagicMock(return_value={
                "data": [
                    {"id": "price_1ABC123"},
                    {"id": "price_2DEF456"}
                ]
            })

            # Act
            result = await product_price_handler.handle_product_updated(sample_product_updated_event)

    # Assert
    assert result["success"] == True
    assert result["updated_count"] == 2
    assert mock_salesforce_service.upsert_record.call_count == 2


@pytest.mark.asyncio
async def test_handle_product_deleted(
    sample_product_deleted_event
):
    """Test product.deleted event handler."""
    # Act
    result = await product_price_handler.handle_product_deleted(sample_product_deleted_event)

    # Assert
    assert result["success"] == True
    assert result["product_id"] == "prod_TestProduct"
    assert "deletion" in result["message"]


@pytest.mark.asyncio
async def test_handle_price_created_with_tiers(
    sample_price_created_event,
    mock_salesforce_service,
    mock_stripe_service
):
    """Test price.created event handler with tiered pricing."""
    # Arrange
    with patch("app.handlers.product_price_handler.salesforce_service", mock_salesforce_service):
        with patch("app.handlers.product_price_handler.stripe_service", mock_stripe_service):
            # Act
            result = await product_price_handler.handle_price_created(sample_price_created_event)

    # Assert
    assert result["success"] == True
    assert result["salesforce_id"] == "a0Pxx0000000001AAA"
    assert result["tiers_created"] == 3

    # Verify pricing plan was created with correct data
    mock_salesforce_service.upsert_pricing_plan.assert_called_once()
    plan_data = mock_salesforce_service.upsert_pricing_plan.call_args[0][0]
    assert plan_data.Stripe_Price_ID__c == "price_1ABC123"
    assert plan_data.Name == "Premium Plan"
    assert plan_data.ProductName__c == "Premium Plan"
    assert plan_data.Currency__c == "usd"
    assert plan_data.Recurrency_Type__c == "Monthly"

    # Verify tiers were created
    assert mock_salesforce_service.create_pricing_tier.call_count == 3

    # Verify old tiers were deleted first
    mock_salesforce_service.delete_pricing_tiers_for_plan.assert_called_once_with("a0Pxx0000000001AAA")


@pytest.mark.asyncio
async def test_handle_price_created_simple_pricing(
    sample_price_created_event_simple,
    mock_salesforce_service,
    mock_stripe_service
):
    """Test price.created event handler with simple per-unit pricing."""
    # Arrange
    with patch("app.handlers.product_price_handler.salesforce_service", mock_salesforce_service):
        with patch("app.handlers.product_price_handler.stripe_service", mock_stripe_service):
            # Act
            result = await product_price_handler.handle_price_created(sample_price_created_event_simple)

    # Assert
    assert result["success"] == True
    assert result["salesforce_id"] == "a0Pxx0000000001AAA"
    assert result["tiers_created"] == 0

    # Verify pricing plan was created with amount
    plan_data = mock_salesforce_service.upsert_pricing_plan.call_args[0][0]
    assert plan_data.Amount__c == 29.99  # Converted from cents

    # Verify no tiers were created for simple pricing
    mock_salesforce_service.create_pricing_tier.assert_not_called()


@pytest.mark.asyncio
async def test_handle_price_created_with_yearly_interval(
    mock_salesforce_service,
    mock_stripe_service
):
    """Test price.created event handler with yearly billing interval."""
    # Arrange
    event = {
        "id": "evt_test_price_yearly",
        "type": "price.created",
        "data": {
            "object": {
                "id": "price_yearly",
                "product": "prod_TestProduct",
                "active": True,
                "currency": "usd",
                "unit_amount": 29900,  # $299 yearly
                "billing_scheme": "per_unit",
                "recurring": {
                    "interval": "year",
                    "interval_count": 1
                }
            }
        }
    }

    with patch("app.handlers.product_price_handler.salesforce_service", mock_salesforce_service):
        with patch("app.handlers.product_price_handler.stripe_service", mock_stripe_service):
            # Act
            result = await product_price_handler.handle_price_created(event)

    # Assert
    plan_data = mock_salesforce_service.upsert_pricing_plan.call_args[0][0]
    assert plan_data.Recurrency_Type__c == "Yearly"
    assert plan_data.Amount__c == 299.00


@pytest.mark.asyncio
async def test_handle_price_updated(
    sample_price_updated_event,
    mock_salesforce_service
):
    """Test price.updated event handler."""
    # Arrange
    with patch("app.handlers.product_price_handler.salesforce_service", mock_salesforce_service):
        # Act
        result = await product_price_handler.handle_price_updated(sample_price_updated_event)

    # Assert
    assert result["success"] == True
    assert result["price_id"] == "price_1ABC123"
    assert "No updates" in result["message"]


@pytest.mark.asyncio
async def test_handle_price_deleted(
    sample_price_deleted_event
):
    """Test price.deleted event handler."""
    # Act
    result = await product_price_handler.handle_price_deleted(sample_price_deleted_event)

    # Assert
    assert result["success"] == True
    assert result["price_id"] == "price_1ABC123"
    assert "deletion" in result["message"]


@pytest.mark.asyncio
async def test_handle_price_created_with_stripe_api_error(
    sample_price_created_event,
    mock_salesforce_service
):
    """Test price.created handler when Stripe API fails."""
    # Arrange
    mock_stripe_service = AsyncMock()
    mock_stripe_service.get_product = AsyncMock(side_effect=Exception("Stripe API error"))

    with patch("app.handlers.product_price_handler.salesforce_service", mock_salesforce_service):
        with patch("app.handlers.product_price_handler.stripe_service", mock_stripe_service):
            # Act & Assert
            with pytest.raises(Exception, match="Stripe API error"):
                await product_price_handler.handle_price_created(sample_price_created_event)


@pytest.mark.asyncio
async def test_handle_price_created_with_salesforce_api_error(
    sample_price_created_event,
    mock_stripe_service
):
    """Test price.created handler when Salesforce API fails."""
    # Arrange
    mock_sf_service = AsyncMock()
    mock_sf_service.upsert_pricing_plan = AsyncMock(side_effect=Exception("Salesforce API error"))

    with patch("app.handlers.product_price_handler.salesforce_service", mock_sf_service):
        with patch("app.handlers.product_price_handler.stripe_service", mock_stripe_service):
            # Act & Assert
            with pytest.raises(Exception, match="Salesforce API error"):
                await product_price_handler.handle_price_created(sample_price_created_event)


@pytest.mark.asyncio
async def test_recurrency_mapping():
    """Test that all Stripe intervals map correctly to Salesforce picklist values."""
    # Arrange
    test_cases = [
        ("day", "Daily"),
        ("week", "Weekly"),
        ("month", "Monthly"),
        ("quarter", "Quarterly"),
        ("year", "Yearly"),
    ]

    mock_sf = AsyncMock()
    mock_sf.upsert_pricing_plan = AsyncMock(return_value={"id": "a0Pxx0000000001AAA", "success": True})

    mock_stripe = AsyncMock()
    mock_stripe.get_product = AsyncMock(return_value={"name": "Test Product"})

    # Test each interval mapping
    for stripe_interval, expected_sf_value in test_cases:
        event = {
            "type": "price.created",
            "data": {
                "object": {
                    "id": f"price_{stripe_interval}",
                    "product": "prod_Test",
                    "currency": "usd",
                    "unit_amount": 1000,
                    "billing_scheme": "per_unit",
                    "recurring": {
                        "interval": stripe_interval,
                        "interval_count": 1
                    }
                }
            }
        }

        with patch("app.handlers.product_price_handler.salesforce_service", mock_sf):
            with patch("app.handlers.product_price_handler.stripe_service", mock_stripe):
                # Act
                await product_price_handler.handle_price_created(event)

                # Assert
                plan_data = mock_sf.upsert_pricing_plan.call_args[0][0]
                assert plan_data.Recurrency_Type__c == expected_sf_value, \
                    f"Failed mapping {stripe_interval} -> {expected_sf_value}"


@pytest.mark.asyncio
async def test_handle_price_with_volume_tiers(
    mock_salesforce_service,
    mock_stripe_service
):
    """Test handling of volume-based pricing tiers (different from graduated)."""
    # Arrange
    event = {
        "type": "price.created",
        "data": {
            "object": {
                "id": "price_volume",
                "product": "prod_TestProduct",
                "currency": "usd",
                "billing_scheme": "tiered",
                "tiers_mode": "volume",  # Volume pricing instead of graduated
                "recurring": {"interval": "month", "interval_count": 1},
                "tiers": [
                    {"up_to": 10, "unit_amount": 1000},
                    {"up_to": 50, "unit_amount": 800},
                    {"up_to": None, "unit_amount": 600}
                ]
            }
        }
    }

    with patch("app.handlers.product_price_handler.salesforce_service", mock_salesforce_service):
        with patch("app.handlers.product_price_handler.stripe_service", mock_stripe_service):
            # Act
            result = await product_price_handler.handle_price_created(event)

    # Assert
    assert result["success"] == True
    assert result["tiers_created"] == 3

    # Verify tier creation calls
    tier_calls = mock_salesforce_service.create_pricing_tier.call_args_list
    assert len(tier_calls) == 3

    # Check first tier
    first_tier = tier_calls[0][0][0]
    assert first_tier.Tier_Number__c == 1
    assert first_tier.From_Quantity__c == 0
    assert first_tier.To_Quantity__c == 10
    assert first_tier.Unit_Price__c == 10.00