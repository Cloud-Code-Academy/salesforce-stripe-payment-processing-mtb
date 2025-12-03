"""
Tests for Salesforce Service Contact Operations

Tests the upsert_contact method that syncs Contact records
using Stripe_Customer_ID__c as the external ID.
"""

import pytest
from unittest.mock import AsyncMock, MagicMock, patch
import httpx

from app.models.salesforce_records import SalesforceContact
from app.services.salesforce_service import salesforce_service
from app.utils.exceptions import SalesforceAPIException


@pytest.fixture
def mock_oauth():
    """Mock Salesforce OAuth"""
    with patch('app.services.salesforce_service.salesforce_oauth') as mock:
        mock.get_instance_url = AsyncMock(return_value="https://test.salesforce.com")
        mock.get_access_token = AsyncMock(return_value="mock_token_123")
        yield mock


@pytest.fixture
def mock_http_client():
    """Mock HTTP client"""
    with patch.object(salesforce_service, 'http_client') as mock:
        yield mock


@pytest.fixture
def sample_contact():
    """Sample SalesforceContact model"""
    return SalesforceContact(
        Stripe_Customer_ID__c="cus_test123",
        Email="john.doe@example.com",
        FirstName="John",
        LastName="Doe",
        Phone="+1234567890"
    )


@pytest.fixture
def minimal_contact():
    """Minimal SalesforceContact with only required fields"""
    return SalesforceContact(
        Stripe_Customer_ID__c="cus_minimal",
        LastName="Required"
    )


@pytest.mark.asyncio
async def test_upsert_contact_success(mock_oauth, mock_http_client, sample_contact):
    """Test successful Contact upsert"""

    # Mock successful response
    mock_response = MagicMock()
    mock_response.status_code = 201
    mock_response.json.return_value = {
        "id": "003xx000000001",
        "success": True,
        "created": True
    }
    mock_http_client.request = AsyncMock(return_value=mock_response)

    # Call upsert_contact
    result = await salesforce_service.upsert_contact(sample_contact)

    # Verify API call
    mock_http_client.request.assert_called_once()
    call_args = mock_http_client.request.call_args

    # Check URL
    assert "Contact/Stripe_Customer_ID__c/cus_test123" in call_args.kwargs["url"]

    # Check method
    assert call_args.kwargs["method"] == "PATCH"

    # Check headers
    assert call_args.kwargs["headers"]["Authorization"] == "Bearer mock_token_123"

    # Check request body
    request_data = call_args.kwargs["json"]
    assert request_data["Stripe_Customer_ID__c"] == "cus_test123"
    assert request_data["Email"] == "john.doe@example.com"
    assert request_data["FirstName"] == "John"
    assert request_data["LastName"] == "Doe"
    assert request_data["Phone"] == "+1234567890"

    # Verify result
    assert result["id"] == "003xx000000001"
    assert result["success"] is True


@pytest.mark.asyncio
async def test_upsert_contact_update_existing(mock_oauth, mock_http_client, sample_contact):
    """Test updating existing Contact"""

    # Mock successful update response (200 instead of 201)
    mock_response = MagicMock()
    mock_response.status_code = 200
    mock_response.json.return_value = {
        "id": "003xx000000001",
        "success": True,
        "created": False
    }
    mock_http_client.request = AsyncMock(return_value=mock_response)

    # Call upsert_contact
    result = await salesforce_service.upsert_contact(sample_contact)

    # Verify result
    assert result["success"] is True
    assert result["created"] is False


@pytest.mark.asyncio
async def test_upsert_contact_no_stripe_id():
    """Test that upsert_contact raises error when Stripe_Customer_ID__c is missing"""

    contact_no_id = SalesforceContact(
        Email="no.id@example.com",
        FirstName="No",
        LastName="ID"
    )

    # Should raise exception
    with pytest.raises(SalesforceAPIException) as exc_info:
        await salesforce_service.upsert_contact(contact_no_id)

    assert "Stripe_Customer_ID__c is required" in str(exc_info.value)


@pytest.mark.asyncio
async def test_upsert_contact_minimal_fields(mock_oauth, mock_http_client, minimal_contact):
    """Test Contact upsert with minimal required fields"""

    # Mock successful response
    mock_response = MagicMock()
    mock_response.status_code = 201
    mock_response.json.return_value = {
        "id": "003xx000000002",
        "success": True
    }
    mock_http_client.request = AsyncMock(return_value=mock_response)

    # Call upsert_contact
    result = await salesforce_service.upsert_contact(minimal_contact)

    # Verify request body only contains non-None fields
    call_args = mock_http_client.request.call_args
    request_data = call_args.kwargs["json"]
    assert request_data["Stripe_Customer_ID__c"] == "cus_minimal"
    assert request_data["LastName"] == "Required"
    assert "Email" not in request_data  # None fields should be excluded
    assert "FirstName" not in request_data
    assert "Phone" not in request_data

    # Verify result
    assert result["success"] is True


@pytest.mark.asyncio
async def test_upsert_contact_special_characters(mock_oauth, mock_http_client):
    """Test Contact upsert with special characters"""

    contact_special = SalesforceContact(
        Stripe_Customer_ID__c="cus_special",
        Email="josé.maría@example.com",
        FirstName="José María",
        LastName="O'Brien-Smith",
        Phone="+1 (555) 123-4567"
    )

    # Mock successful response
    mock_response = MagicMock()
    mock_response.status_code = 201
    mock_response.json.return_value = {"id": "003xx000000003", "success": True}
    mock_http_client.request = AsyncMock(return_value=mock_response)

    # Call upsert_contact
    result = await salesforce_service.upsert_contact(contact_special)

    # Verify special characters are preserved
    call_args = mock_http_client.request.call_args
    request_data = call_args.kwargs["json"]
    assert request_data["FirstName"] == "José María"
    assert request_data["LastName"] == "O'Brien-Smith"
    assert request_data["Email"] == "josé.maría@example.com"


@pytest.mark.asyncio
async def test_upsert_contact_api_error(mock_oauth, mock_http_client, sample_contact):
    """Test handling of Salesforce API error"""

    # Mock error response
    mock_response = MagicMock()
    mock_response.status_code = 400
    mock_response.json.return_value = {
        "error": "INVALID_FIELD",
        "message": "Invalid field: BadField__c"
    }
    mock_http_client.request = AsyncMock(return_value=mock_response)

    # Should raise exception
    with pytest.raises(SalesforceAPIException) as exc_info:
        await salesforce_service.upsert_contact(sample_contact)

    assert exc_info.value.status_code == 400
    assert "INVALID_FIELD" in str(exc_info.value)


@pytest.mark.asyncio
async def test_upsert_contact_auth_refresh(mock_oauth, mock_http_client, sample_contact):
    """Test automatic token refresh on 401 error"""

    # Mock 401 response followed by success
    mock_response_401 = MagicMock()
    mock_response_401.status_code = 401

    mock_response_success = MagicMock()
    mock_response_success.status_code = 201
    mock_response_success.json.return_value = {"id": "003xx000000001", "success": True}

    mock_http_client.request = AsyncMock(
        side_effect=[mock_response_401, mock_response_success]
    )

    # Call upsert_contact
    result = await salesforce_service.upsert_contact(sample_contact)

    # Verify token refresh was called
    assert mock_oauth.get_access_token.call_count >= 2  # Initial + refresh

    # Verify request was retried
    assert mock_http_client.request.call_count == 2

    # Verify result
    assert result["success"] is True


@pytest.mark.asyncio
async def test_upsert_contact_network_error(mock_oauth, mock_http_client, sample_contact):
    """Test handling of network errors"""

    # Mock network error
    mock_http_client.request = AsyncMock(
        side_effect=httpx.RequestError("Connection timeout")
    )

    # Should raise exception
    with pytest.raises(SalesforceAPIException) as exc_info:
        await salesforce_service.upsert_contact(sample_contact)

    assert "Network error" in str(exc_info.value)


@pytest.mark.asyncio
async def test_upsert_contact_empty_stripe_id(mock_oauth, mock_http_client):
    """Test that empty string Stripe_Customer_ID__c is rejected"""

    contact_empty_id = SalesforceContact(
        Stripe_Customer_ID__c="",  # Empty string
        LastName="Empty"
    )

    # Should raise exception before making API call
    with pytest.raises(SalesforceAPIException) as exc_info:
        await salesforce_service.upsert_contact(contact_empty_id)

    assert "Stripe_Customer_ID__c is required" in str(exc_info.value)
    mock_http_client.request.assert_not_called()


@pytest.mark.asyncio
async def test_upsert_contact_204_response(mock_oauth, mock_http_client, sample_contact):
    """Test handling of 204 No Content response"""

    # Mock 204 response (no body)
    mock_response = MagicMock()
    mock_response.status_code = 204
    mock_http_client.request = AsyncMock(return_value=mock_response)

    # Call upsert_contact
    result = await salesforce_service.upsert_contact(sample_contact)

    # Should return None for 204 responses
    assert result is None


@pytest.mark.asyncio
async def test_upsert_contact_concurrent_calls(mock_oauth, mock_http_client):
    """Test concurrent Contact upserts"""

    import asyncio

    # Create multiple contacts
    contacts = [
        SalesforceContact(
            Stripe_Customer_ID__c=f"cus_concurrent_{i}",
            Email=f"user{i}@example.com",
            FirstName=f"User{i}",
            LastName=f"Test{i}"
        )
        for i in range(5)
    ]

    # Mock successful responses
    mock_response = MagicMock()
    mock_response.status_code = 201
    mock_response.json.return_value = {"success": True}
    mock_http_client.request = AsyncMock(return_value=mock_response)

    # Run concurrent upserts
    tasks = [salesforce_service.upsert_contact(contact) for contact in contacts]
    results = await asyncio.gather(*tasks)

    # Verify all succeeded
    assert len(results) == 5
    assert all(r["success"] for r in results)
    assert mock_http_client.request.call_count == 5