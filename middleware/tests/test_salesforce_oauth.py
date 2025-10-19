"""
Test Salesforce OAuth

Tests OAuth token acquisition, caching, and refresh.
"""

import pytest
from unittest.mock import patch, AsyncMock
from datetime import datetime, timedelta

from app.auth.salesforce_oauth import salesforce_oauth
from app.utils.exceptions import SalesforceAuthException


@pytest.mark.asyncio
async def test_get_access_token_success(mock_redis_service):
    """Test successful token acquisition"""

    mock_response = AsyncMock()
    mock_response.status_code = 200
    mock_response.json.return_value = {
        "access_token": "test_token_123",
        "instance_url": "https://test.salesforce.com",
        "token_type": "Bearer",
    }

    with patch("app.auth.salesforce_oauth.redis_service", mock_redis_service), patch(
        "app.auth.salesforce_oauth.httpx.AsyncClient.post", return_value=mock_response
    ):
        mock_redis_service.get.return_value = None  # No cached token

        token = await salesforce_oauth.get_access_token()

        assert token == "test_token_123"
        # Verify token was cached
        mock_redis_service.set.assert_called()


@pytest.mark.asyncio
async def test_get_cached_token(mock_redis_service):
    """Test using cached token"""

    future_time = datetime.utcnow() + timedelta(hours=1)

    with patch("app.auth.salesforce_oauth.redis_service", mock_redis_service):
        mock_redis_service.get.side_effect = [
            "cached_token_123",
            future_time.isoformat(),
        ]

        token = await salesforce_oauth.get_access_token()

        assert token == "cached_token_123"


@pytest.mark.asyncio
async def test_token_refresh_on_expiry(mock_redis_service):
    """Test token refresh when cached token is expired"""

    past_time = datetime.utcnow() - timedelta(minutes=1)

    mock_response = AsyncMock()
    mock_response.status_code = 200
    mock_response.json.return_value = {
        "access_token": "new_token_456",
        "instance_url": "https://test.salesforce.com",
    }

    with patch("app.auth.salesforce_oauth.redis_service", mock_redis_service), patch(
        "app.auth.salesforce_oauth.httpx.AsyncClient.post", return_value=mock_response
    ):
        # Return expired token
        mock_redis_service.get.side_effect = [
            "old_token",
            past_time.isoformat(),
        ]

        token = await salesforce_oauth.get_access_token()

        assert token == "new_token_456"


@pytest.mark.asyncio
async def test_authentication_failure(mock_redis_service):
    """Test handling of authentication failure"""

    mock_response = AsyncMock()
    mock_response.status_code = 400
    mock_response.json.return_value = {
        "error": "invalid_grant",
        "error_description": "authentication failure",
    }

    with patch("app.auth.salesforce_oauth.redis_service", mock_redis_service), patch(
        "app.auth.salesforce_oauth.httpx.AsyncClient.post", return_value=mock_response
    ):
        mock_redis_service.get.return_value = None

        with pytest.raises(SalesforceAuthException):
            await salesforce_oauth.get_access_token()


@pytest.mark.asyncio
async def test_force_token_refresh(mock_redis_service):
    """Test forcing token refresh even with valid cached token"""

    mock_response = AsyncMock()
    mock_response.status_code = 200
    mock_response.json.return_value = {
        "access_token": "refreshed_token_789",
        "instance_url": "https://test.salesforce.com",
    }

    with patch("app.auth.salesforce_oauth.redis_service", mock_redis_service), patch(
        "app.auth.salesforce_oauth.httpx.AsyncClient.post", return_value=mock_response
    ):
        token = await salesforce_oauth.get_access_token(force_refresh=True)

        assert token == "refreshed_token_789"
        # Should not check cache when force_refresh=True
