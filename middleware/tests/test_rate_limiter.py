"""
Unit tests for SlidingWindowRateLimiter.

Tests rate limiting logic, sliding window algorithm, and DynamoDB integration.
"""
import pytest
from unittest.mock import AsyncMock, patch, MagicMock
import time
from datetime import datetime, timezone

from app.services.rate_limiter import (
    SlidingWindowRateLimiter,
    RateLimitTier,
    get_rate_limiter
)
from app.utils.exceptions import RateLimitException


@pytest.fixture
def mock_dynamodb_service():
    """Mock DynamoDB service for rate limiter tests."""
    mock_service = AsyncMock()
    mock_service.put_item = AsyncMock()
    mock_service.query_items = AsyncMock(return_value={"Items": [], "Count": 0})
    mock_service.ConditionalCheckFailedException = Exception
    return mock_service


@pytest.fixture
def test_tier():
    """Create a test rate limit tier with short window for testing."""
    return RateLimitTier(
        name="test_tier",
        limit=5,
        window_seconds=10,
        table_name="test-rate-limit"
    )


@pytest.fixture
def rate_limiter(mock_dynamodb_service, test_tier):
    """Create rate limiter instance with mocked dependencies."""
    return SlidingWindowRateLimiter(
        dynamodb_service=mock_dynamodb_service,
        resource_id="test_resource",
        tiers=[test_tier]
    )


@pytest.mark.asyncio
class TestRateLimitTier:
    """Test suite for RateLimitTier configuration."""
    
    def test_tier_initialization(self, test_tier):
        """Test that rate limit tier initializes with correct parameters."""
        assert test_tier.name == "test_tier"
        assert test_tier.limit == 5
        assert test_tier.window_seconds == 10
        assert test_tier.table_name == "test-rate-limit"
    
    def test_tier_repr(self, test_tier):
        """Test string representation of rate limit tier."""
        repr_str = repr(test_tier)
        assert "test_tier" in repr_str
        assert "limit=5" in repr_str
        assert "window=10s" in repr_str


@pytest.mark.asyncio
class TestSlidingWindowRateLimiter:
    """Test suite for sliding window rate limiter core functionality."""
    
    def test_rate_limiter_initialization(self, mock_dynamodb_service):
        """Test rate limiter initializes with correct default tiers."""
        limiter = SlidingWindowRateLimiter(
            dynamodb_service=mock_dynamodb_service,
            resource_id="salesforce_api"
        )
        
        assert limiter.resource_id == "salesforce_api"
        assert len(limiter.tiers) == 3
        
        tier_names = [tier.name for tier in limiter.tiers]
        assert "per_second" in tier_names
        assert "per_minute" in tier_names
        assert "per_day" in tier_names
    
    async def test_check_rate_limit_allowed(self, rate_limiter, mock_dynamodb_service):
        """
        Test rate limit check allows request when within limits.
        
        Simulates 3 calls in a window with limit of 5.
        """
        mock_dynamodb_service.query_items = AsyncMock(
            return_value={"Items": [{}] * 3, "Count": 3}
        )
        
        result = await rate_limiter.check_rate_limit()
        
        assert result["allowed"] is True
        assert result["current_usage"]["test_tier"] == 3
        assert result["limits"]["test_tier"] == 5
        assert "exceeded_tier" not in result
        assert "retry_after" not in result
    
    async def test_check_rate_limit_exceeded(self, rate_limiter, mock_dynamodb_service):
        """
        Test rate limit check denies request when limit exceeded.
        
        Simulates 5 calls in a window with limit of 5.
        Next call should be denied.
        """
        mock_dynamodb_service.query_items = AsyncMock(
            return_value={
                "Items": [
                    {"timestamp": int(time.time() * 1000) - 5000}
                ] * 5,
                "Count": 5
            }
        )
        
        result = await rate_limiter.check_rate_limit()
        
        assert result["allowed"] is False
        assert result["exceeded_tier"] == "test_tier"
        assert result["current_usage"]["test_tier"] == 5
        assert result["limits"]["test_tier"] == 5
        assert "retry_after" in result
        assert result["retry_after"] > 0
    
    async def test_record_call(self, rate_limiter, mock_dynamodb_service):
        """
        Test recording an API call creates DynamoDB entry with correct fields.
        
        Verifies:
        - Item is written to DynamoDB
        - Timestamp is in milliseconds
        - TTL is set correctly
        - Call count is incremented
        """
        mock_dynamodb_service.query_items = AsyncMock(
            return_value={"Items": [{}] * 1, "Count": 1}
        )
        
        result = await rate_limiter.record_call()
        
        assert result["recorded"] is True
        assert "timestamp" in result
        assert isinstance(result["timestamp"], int)
        assert result["timestamp"] > 0
        assert "current_usage" in result
        
        mock_dynamodb_service.put_item.assert_called_once()
        call_args = mock_dynamodb_service.put_item.call_args
        
        item = call_args.kwargs["item"]
        assert item["resource_id"] == "test_resource"
        assert item["call_count"] == 1
        assert "timestamp" in item
        assert "ttl" in item
    
    async def test_acquire_success(self, rate_limiter, mock_dynamodb_service):
        """
        Test acquire grants permission when rate limit not exceeded.
        
        Flow:
        1. Check rate limit (3/5 calls used)
        2. Record call
        3. Return success
        """
        mock_dynamodb_service.query_items = AsyncMock(
            return_value={"Items": [{}] * 3, "Count": 3}
        )
        
        result = await rate_limiter.acquire()
        
        assert result["acquired"] is True
        assert "timestamp" in result
        assert result["current_usage"]["test_tier"] == 3
        
        mock_dynamodb_service.put_item.assert_called_once()
    
    async def test_acquire_rate_limited(self, rate_limiter, mock_dynamodb_service):
        """
        Test acquire raises RateLimitException when limit exceeded.
        
        Simulates 5/5 calls used, next call should fail.
        """
        mock_dynamodb_service.query_items = AsyncMock(
            return_value={
                "Items": [{"timestamp": int(time.time() * 1000)}] * 5,
                "Count": 5
            }
        )
        
        with pytest.raises(RateLimitException) as exc_info:
            await rate_limiter.acquire()
        
        exception = exc_info.value
        assert exception.tier == "test_tier"
        assert exception.current_usage["test_tier"] == 5
        assert exception.limits["test_tier"] == 5
        assert exception.retry_after > 0
        
        mock_dynamodb_service.put_item.assert_not_called()
    
    async def test_get_current_usage(self, rate_limiter, mock_dynamodb_service):
        """
        Test retrieving current usage statistics across all tiers.
        
        Verifies usage counts are returned correctly.
        """
        mock_dynamodb_service.query_items = AsyncMock(
            return_value={"Items": [{}] * 7, "Count": 7}
        )
        
        usage = await rate_limiter.get_current_usage()
        
        assert "test_tier" in usage
        assert usage["test_tier"] == 7
    
    async def test_count_calls_in_window(self, rate_limiter, mock_dynamodb_service, test_tier):
        """
        Test sliding window call counting with timestamp filtering.
        
        Verifies:
        - Query uses correct time window
        - Only calls within window are counted
        - Expired calls are excluded
        """
        current_time_ms = int(time.time() * 1000)
        window_start_ms = current_time_ms - (test_tier.window_seconds * 1000)
        
        mock_dynamodb_service.query_items = AsyncMock(
            return_value={
                "Items": [
                    {"timestamp": current_time_ms - 2000},
                    {"timestamp": current_time_ms - 5000},
                    {"timestamp": current_time_ms - 8000}
                ],
                "Count": 3
            }
        )
        
        count = await rate_limiter._count_calls_in_window(test_tier)
        
        assert count == 3
        
        call_args = mock_dynamodb_service.query_items.call_args
        assert call_args.kwargs["table_name"] == "test-rate-limit"
        
        expr_values = call_args.kwargs["expression_attribute_values"]
        assert expr_values[":resource_id"] == "test_resource"
        assert expr_values[":window_start"] >= window_start_ms
    
    async def test_calculate_retry_after(self, rate_limiter, mock_dynamodb_service, test_tier):
        """
        Test retry_after calculation based on oldest call in window.
        
        Algorithm:
        - Oldest call timestamp: T
        - Window expires at: T + window_duration
        - Retry after: (expiration - current_time) + 1 second buffer
        """
        current_time_ms = int(time.time() * 1000)
        oldest_call_ms = current_time_ms - 8000  # 8 seconds ago
        
        mock_dynamodb_service.query_items = AsyncMock(
            return_value={
                "Items": [{"timestamp": oldest_call_ms}],
                "Count": 1
            }
        )
        
        retry_after = await rate_limiter._calculate_retry_after(test_tier)
        
        expected_retry = test_tier.window_seconds - 8 + 1
        assert retry_after >= expected_retry - 1
        assert retry_after <= expected_retry + 1
        
        call_args = mock_dynamodb_service.query_items.call_args
        assert call_args.kwargs["scan_index_forward"] is True
        assert call_args.kwargs["limit"] == 1


@pytest.mark.asyncio
class TestRateLimitException:
    """Test suite for RateLimitException."""
    
    def test_exception_initialization(self):
        """Test rate limit exception initializes with correct fields."""
        exception = RateLimitException(
            message="Rate limit exceeded",
            tier="per_second",
            current_usage={"per_second": 10, "per_minute": 120},
            limits={"per_second": 10, "per_minute": 250},
            retry_after=2
        )
        
        assert str(exception) == "Rate limit exceeded"
        assert exception.tier == "per_second"
        assert exception.retry_after == 2
    
    def test_exception_to_dict(self):
        """Test converting exception to dictionary for API responses."""
        exception = RateLimitException(
            message="Rate limit exceeded",
            tier="per_second",
            current_usage={"per_second": 10},
            limits={"per_second": 10},
            retry_after=2
        )
        
        error_dict = exception.to_dict()
        
        assert error_dict["error"] == "rate_limit_exceeded"
        assert error_dict["message"] == "Rate limit exceeded"
        assert error_dict["tier"] == "per_second"
        assert error_dict["retry_after"] == 2
        assert "current_usage" in error_dict
        assert "limits" in error_dict


@pytest.mark.asyncio
class TestRateLimiterIntegration:
    """Integration tests for rate limiter with multiple tiers."""
    
    async def test_multiple_tiers_enforcement(self, mock_dynamodb_service):
        """
        Test that rate limiter enforces limits across multiple tiers.
        
        Scenario:
        - per_second: 2/10 calls (OK)
        - per_minute: 245/250 calls (OK)
        - per_day: 14995/15000 calls (OK)
        - All tiers should allow request
        """
        per_second_tier = RateLimitTier("per_second", 10, 1, "rate-limit-per-second")
        per_minute_tier = RateLimitTier("per_minute", 250, 60, "rate-limit-per-minute")
        per_day_tier = RateLimitTier("per_day", 15000, 86400, "rate-limit-per-day")
        
        limiter = SlidingWindowRateLimiter(
            dynamodb_service=mock_dynamodb_service,
            resource_id="salesforce_api",
            tiers=[per_second_tier, per_minute_tier, per_day_tier]
        )
        
        def mock_query_side_effect(*args, **kwargs):
            table_name = kwargs["table_name"]
            if table_name == "rate-limit-per-second":
                return {"Items": [{}] * 2, "Count": 2}
            elif table_name == "rate-limit-per-minute":
                return {"Items": [{}] * 245, "Count": 245}
            elif table_name == "rate-limit-per-day":
                return {"Items": [{}] * 14995, "Count": 14995}
        
        mock_dynamodb_service.query_items = AsyncMock(side_effect=mock_query_side_effect)
        
        result = await limiter.check_rate_limit()
        
        assert result["allowed"] is True
        assert result["current_usage"]["per_second"] == 2
        assert result["current_usage"]["per_minute"] == 245
        assert result["current_usage"]["per_day"] == 14995
    
    async def test_tier_exceeded_stops_at_first_violation(self, mock_dynamodb_service):
        """
        Test that rate limiter stops checking tiers after first violation.
        
        Scenario:
        - per_second: 10/10 calls (EXCEEDED)
        - per_minute: Should not be checked
        - per_day: Should not be checked
        """
        per_second_tier = RateLimitTier("per_second", 10, 1, "rate-limit-per-second")
        per_minute_tier = RateLimitTier("per_minute", 250, 60, "rate-limit-per-minute")
        
        limiter = SlidingWindowRateLimiter(
            dynamodb_service=mock_dynamodb_service,
            resource_id="salesforce_api",
            tiers=[per_second_tier, per_minute_tier]
        )
        
        mock_dynamodb_service.query_items = AsyncMock(
            return_value={
                "Items": [{"timestamp": int(time.time() * 1000)}] * 10,
                "Count": 10
            }
        )
        
        result = await limiter.check_rate_limit()
        
        assert result["allowed"] is False
        assert result["exceeded_tier"] == "per_second"
        
        assert mock_dynamodb_service.query_items.call_count == 1


@pytest.mark.asyncio
class TestRateLimiterSingleton:
    """Test singleton instance management."""
    
    def test_get_rate_limiter_returns_singleton(self):
        """Test that get_rate_limiter returns the same instance."""
        limiter1 = get_rate_limiter()
        limiter2 = get_rate_limiter()
        
        assert limiter1 is limiter2
    
    def test_singleton_has_correct_configuration(self):
        """Test that singleton is configured for Salesforce API."""
        limiter = get_rate_limiter()
        
        assert limiter.resource_id == "salesforce_api"
        assert len(limiter.tiers) == 3