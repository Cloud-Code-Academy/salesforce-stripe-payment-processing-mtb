"""
Tests for Customer Handler

Tests the customer.updated webhook event handler that syncs
Stripe customer data to Contact records.
"""

import pytest
from datetime import datetime
from unittest.mock import AsyncMock, MagicMock, patch

from app.handlers.customer_handler import customer_handler
from app.models.stripe_events import StripeEvent
from app.models.salesforce_records import SalesforceContact


@pytest.fixture
def mock_salesforce_service():
    """Mock Salesforce service"""
    with patch('app.handlers.customer_handler.salesforce_service') as mock:
        mock.upsert_contact = AsyncMock(return_value={"id": "003xx000000001", "success": True})
        yield mock


@pytest.fixture
def customer_updated_event():
    """Sample customer.updated event"""
    return StripeEvent(
        id="evt_test_123",
        type="customer.updated",
        created=int(datetime.utcnow().timestamp()),
        livemode=False,
        event_object={
            "id": "cus_test123",
            "object": "customer",
            "email": "john.doe@example.com",
            "name": "John Doe",
            "phone": "+1234567890",
            "invoice_settings": {
                "default_payment_method": "pm_test456"
            }
        },
        previous_attributes={
            "email": "old@example.com",
            "name": "Old Name"
        }
    )


@pytest.fixture
def customer_updated_event_no_name():
    """Customer updated event with no name"""
    return StripeEvent(
        id="evt_test_124",
        type="customer.updated",
        created=int(datetime.utcnow().timestamp()),
        livemode=False,
        event_object={
            "id": "cus_test124",
            "object": "customer",
            "email": "noname@example.com",
            "name": None,
            "phone": "+1234567890",
            "invoice_settings": {}
        },
        previous_attributes={}
    )


@pytest.fixture
def customer_updated_event_single_name():
    """Customer updated event with single name (no first name)"""
    return StripeEvent(
        id="evt_test_125",
        type="customer.updated",
        created=int(datetime.utcnow().timestamp()),
        livemode=False,
        event_object={
            "id": "cus_test125",
            "object": "customer",
            "email": "smith@example.com",
            "name": "Smith",
            "phone": None,
            "invoice_settings": {}
        },
        previous_attributes={}
    )


@pytest.fixture
def customer_updated_event_complex_name():
    """Customer updated event with complex name"""
    return StripeEvent(
        id="evt_test_126",
        type="customer.updated",
        created=int(datetime.utcnow().timestamp()),
        livemode=False,
        event_object={
            "id": "cus_test126",
            "object": "customer",
            "email": "complex@example.com",
            "name": "José María de la Cruz",
            "phone": "+34 612 345 678",
            "invoice_settings": {
                "default_payment_method": None
            }
        },
        previous_attributes={}
    )


@pytest.mark.asyncio
async def test_handle_customer_updated_success(mock_salesforce_service, customer_updated_event):
    """Test successful handling of customer.updated event"""

    # Call handler
    result = await customer_handler.handle_customer_updated(customer_updated_event)

    # Verify Contact upsert was called
    mock_salesforce_service.upsert_contact.assert_called_once()
    contact_call = mock_salesforce_service.upsert_contact.call_args[0][0]
    assert isinstance(contact_call, SalesforceContact)
    assert contact_call.Stripe_Customer_ID__c == "cus_test123"
    assert contact_call.Email == "john.doe@example.com"
    assert contact_call.FirstName == "John"
    assert contact_call.LastName == "Doe"
    assert contact_call.Phone == "+1234567890"

    # Verify result
    assert result["customer_id"] == "cus_test123"
    assert result["contact_result"]["success"] is True
    assert "timestamp" in result


@pytest.mark.asyncio
async def test_handle_customer_updated_no_name(mock_salesforce_service, customer_updated_event_no_name):
    """Test handling customer.updated event with no name"""

    # Call handler
    result = await customer_handler.handle_customer_updated(customer_updated_event_no_name)

    # Verify Contact upsert was called with "Unknown" as LastName
    mock_salesforce_service.upsert_contact.assert_called_once()
    contact_call = mock_salesforce_service.upsert_contact.call_args[0][0]
    assert contact_call.FirstName is None
    assert contact_call.LastName == "Unknown"
    assert contact_call.Email == "noname@example.com"

    # Verify result
    assert result["customer_id"] == "cus_test124"


@pytest.mark.asyncio
async def test_handle_customer_updated_single_name(mock_salesforce_service, customer_updated_event_single_name):
    """Test handling customer.updated event with single name"""

    # Call handler
    result = await customer_handler.handle_customer_updated(customer_updated_event_single_name)

    # Verify Contact upsert - single name should go to LastName
    mock_salesforce_service.upsert_contact.assert_called_once()
    contact_call = mock_salesforce_service.upsert_contact.call_args[0][0]
    assert contact_call.FirstName is None
    assert contact_call.LastName == "Smith"
    assert contact_call.Phone is None  # Phone is None in this event

    # Verify result
    assert result["customer_id"] == "cus_test125"


@pytest.mark.asyncio
async def test_handle_customer_updated_complex_name(mock_salesforce_service, customer_updated_event_complex_name):
    """Test handling customer.updated event with complex multi-part name"""

    # Call handler
    result = await customer_handler.handle_customer_updated(customer_updated_event_complex_name)

    # Verify Contact upsert - complex name parsing
    mock_salesforce_service.upsert_contact.assert_called_once()
    contact_call = mock_salesforce_service.upsert_contact.call_args[0][0]
    assert contact_call.FirstName == "José"  # First part
    assert contact_call.LastName == "María de la Cruz"  # Rest of the name
    assert contact_call.Phone == "+34 612 345 678"

    # Verify result
    assert result["customer_id"] == "cus_test126"


@pytest.mark.asyncio
async def test_handle_customer_updated_empty_name(mock_salesforce_service):
    """Test handling customer.updated event with empty string name"""

    event = StripeEvent(
        id="evt_test_127",
        type="customer.updated",
        created=int(datetime.utcnow().timestamp()),
        livemode=False,
        event_object={
            "id": "cus_test127",
            "object": "customer",
            "email": "empty@example.com",
            "name": "",  # Empty string
            "phone": None,
            "invoice_settings": {}
        },
        previous_attributes={}
    )

    # Call handler
    result = await customer_handler.handle_customer_updated(event)

    # Verify Contact upsert - empty name should default to "Unknown"
    mock_salesforce_service.upsert_contact.assert_called_once()
    contact_call = mock_salesforce_service.upsert_contact.call_args[0][0]
    assert contact_call.FirstName is None
    assert contact_call.LastName == "Unknown"


@pytest.mark.asyncio
async def test_handle_customer_updated_salesforce_error():
    """Test error handling when Salesforce upsert fails"""

    with patch('app.handlers.customer_handler.salesforce_service') as mock_service:
        # Make upsert_contact fail
        mock_service.upsert_contact = AsyncMock(side_effect=Exception("Salesforce API error"))

        event = StripeEvent(
            id="evt_test_error",
            type="customer.updated",
            created=int(datetime.utcnow().timestamp()),
            livemode=False,
            event_object={
                "id": "cus_error",
                "object": "customer",
                "email": "error@example.com",
                "name": "Error Test",
                "phone": None,
                "invoice_settings": {}
            },
            previous_attributes={}
        )

        # Should raise the exception
        with pytest.raises(Exception) as exc_info:
            await customer_handler.handle_customer_updated(event)

        assert "Salesforce API error" in str(exc_info.value)


@pytest.mark.asyncio
async def test_handle_customer_updated_contact_upsert(mock_salesforce_service, customer_updated_event):
    """Test that Contact is updated with Stripe customer data"""

    # Call handler
    result = await customer_handler.handle_customer_updated(customer_updated_event)

    # Verify Contact upsert was called
    assert mock_salesforce_service.upsert_contact.call_count == 1
    contact_call = mock_salesforce_service.upsert_contact.call_args[0][0]
    assert isinstance(contact_call, SalesforceContact)
    assert contact_call.Stripe_Customer_ID__c == "cus_test123"


@pytest.mark.asyncio
async def test_handle_customer_updated_minimal_data(mock_salesforce_service):
    """Test handling customer.updated event with minimal data"""

    event = StripeEvent(
        id="evt_minimal",
        type="customer.updated",
        created=int(datetime.utcnow().timestamp()),
        livemode=False,
        event_object={
            "id": "cus_minimal",
            "object": "customer"
            # No other fields provided
        },
        previous_attributes={}
    )

    # Call handler
    result = await customer_handler.handle_customer_updated(event)

    # Verify Contact upsert was called with minimal data
    mock_salesforce_service.upsert_contact.assert_called_once()
    contact_call = mock_salesforce_service.upsert_contact.call_args[0][0]
    assert contact_call.Stripe_Customer_ID__c == "cus_minimal"
    assert contact_call.Email is None
    assert contact_call.FirstName is None
    assert contact_call.LastName == "Unknown"  # Default value
    assert contact_call.Phone is None