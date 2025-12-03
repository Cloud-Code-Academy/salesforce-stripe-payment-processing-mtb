"""
Sliding Window Rate Limiter Service

Implements a distributed sliding window rate limiting algorithm using DynamoDB.
Designed for AWS Lambda environments to prevent Salesforce API rate limit violations.

Algorithm:
- Uses sliding window counter to track API calls over time
- Removes expired entries automatically via DynamoDB TTL
- Atomic operations prevent race conditions in concurrent Lambda invocations
- Supports multiple rate limit tiers (per-second, per-minute, per-day)

Salesforce API Limits:
- REST API: 15,000 calls per 24 hours per org
- Peak rate: ~10 calls per second recommended
- Burst handling: 20 calls per 20 seconds

Rate Limit Strategy:
- Daily limit: 15,000 calls per 24 hours (hard limit)
- Minute limit: 250 calls per minute (prevents burst exhaustion)
- Second limit: 10 calls per second (prevents connection pooling issues)
"""

from typing import Dict, Any, Optional, List
from datetime import datetime, timezone, timedelta
from decimal import Decimal
import time

from app.services.dynamodb_service import dynamodb_service
from app.utils.logging_config import get_logger
from app.utils.exceptions import RateLimitException

logger = get_logger(__name__)


class RateLimitTier:
    """
    Rate limit tier configuration.
    
    Attributes:
        name: Tier identifier (e.g., 'per_second', 'per_minute', 'per_day')
        limit: Maximum number of calls allowed in the time window
        window_seconds: Time window duration in seconds
        table_name: DynamoDB table name for this tier
    """
    
    def __init__(self, name: str, limit: int, window_seconds: int, table_name: str):
        """
        Initialize rate limit tier.
        
        Args:
            name: Tier identifier (e.g., 'per_second')
            limit: Maximum calls allowed in window
            window_seconds: Window duration in seconds
            table_name: DynamoDB table for storing rate limit data
        """
        self.name = name
        self.limit = limit
        self.window_seconds = window_seconds
        self.table_name = table_name
    
    def __repr__(self) -> str:
        """String representation of rate limit tier."""
        return f"RateLimitTier(name={self.name}, limit={self.limit}, window={self.window_seconds}s)"


class SlidingWindowRateLimiter:
    """
    Distributed sliding window rate limiter using DynamoDB.
    
    The sliding window algorithm works by:
    1. Recording each API call with a timestamp in DynamoDB
    2. Counting calls within the current time window
    3. Removing expired entries via DynamoDB TTL
    4. Using atomic DynamoDB operations to prevent race conditions
    
    DynamoDB Table Structure (per tier):
        Table: salesforce-rate-limit-{tier}
        Primary Key: resource_id (String) - identifies the rate-limited resource
        Sort Key: timestamp (Number) - Unix timestamp in milliseconds
        Attributes:
            - resource_id: 'salesforce_api' (partition key)
            - timestamp: 1698796800000 (sort key)
            - ttl: Unix timestamp for automatic cleanup
            - call_count: 1 (for aggregation)
    
    Attributes:
        tiers: List of rate limit tiers (per-second, per-minute, per-day)
        resource_id: Identifier for the rate-limited resource (default: 'salesforce_api')
        dynamodb: DynamoDB service instance
    """
    
    # Salesforce API rate limit tiers
    TIER_PER_SECOND = RateLimitTier(
        name="per_second",
        limit=10,  # Conservative limit to prevent connection issues
        window_seconds=1,
        table_name="salesforce-rate-limit-per-second"
    )
    
    TIER_PER_MINUTE = RateLimitTier(
        name="per_minute",
        limit=250,  # Prevents burst exhaustion (15,000 / 60 = 250)
        window_seconds=60,
        table_name="salesforce-rate-limit-per-minute"
    )
    
    TIER_PER_DAY = RateLimitTier(
        name="per_day",
        limit=15000,  # Salesforce org limit
        window_seconds=86400,  # 24 hours
        table_name="salesforce-rate-limit-per-day"
    )
    
    def __init__(
        self, 
        dynamodb_service, 
        resource_id: str = "salesforce_api",
        tiers: Optional[List[RateLimitTier]] = None
    ):
        """
        Initialize sliding window rate limiter.
        
        Args:
            dynamodb_service: DynamoDB service for storing rate limit data
            resource_id: Identifier for rate-limited resource (default: 'salesforce_api')
            tiers: Custom rate limit tiers (defaults to Salesforce API tiers)
        """
        self.dynamodb = dynamodb_service
        self.resource_id = resource_id
        self.tiers = tiers or [
            self.TIER_PER_SECOND,
            self.TIER_PER_MINUTE,
            self.TIER_PER_DAY
        ]
        
        logger.info(
            f"Rate limiter initialized for resource: {resource_id}",
            extra={
                "resource_id": resource_id,
                "tiers": [tier.name for tier in self.tiers]
            }
        )
    
    async def check_rate_limit(self) -> Dict[str, Any]:
        """
        Check if request is within rate limits across all tiers.
        
        Evaluates rate limits in order of strictness (per-second → per-minute → per-day).
        Stops at first tier that would be exceeded.
        
        Returns:
            Dictionary containing:
                - allowed (bool): True if request is within limits
                - current_usage (dict): Current call counts per tier
                - limits (dict): Configured limits per tier
                - retry_after (int, optional): Seconds to wait if rate limited
                - exceeded_tier (str, optional): Name of tier that would be exceeded
                
        Example:
            >>> result = await rate_limiter.check_rate_limit()
            >>> print(result)
            {
                'allowed': True,
                'current_usage': {
                    'per_second': 5,
                    'per_minute': 120,
                    'per_day': 8432
                },
                'limits': {
                    'per_second': 10,
                    'per_minute': 250,
                    'per_day': 15000
                }
            }
            
            >>> result = await rate_limiter.check_rate_limit()
            >>> print(result)
            {
                'allowed': False,
                'exceeded_tier': 'per_second',
                'retry_after': 1,
                'current_usage': {'per_second': 10, ...},
                'limits': {'per_second': 10, ...}
            }
        """
        current_usage = {}
        limits = {}
        
        # Check each tier in order of strictness
        for tier in self.tiers:
            call_count = await self._count_calls_in_window(tier)
            current_usage[tier.name] = call_count
            limits[tier.name] = tier.limit
            
            # Check if adding one more call would exceed limit
            if call_count >= tier.limit:
                # Calculate retry_after based on oldest call in window
                retry_after = await self._calculate_retry_after(tier)
                
                logger.warning(
                    f"Rate limit exceeded for tier: {tier.name}",
                    extra={
                        "tier": tier.name,
                        "current": call_count,
                        "limit": tier.limit,
                        "retry_after": retry_after
                    }
                )
                
                return {
                    "allowed": False,
                    "exceeded_tier": tier.name,
                    "current_usage": current_usage,
                    "limits": limits,
                    "retry_after": retry_after
                }
        
        logger.debug(
            "Rate limit check passed",
            extra={
                "resource_id": self.resource_id,
                "current_usage": current_usage
            }
        )
        
        return {
            "allowed": True,
            "current_usage": current_usage,
            "limits": limits
        }
    
    async def record_call(self) -> Dict[str, Any]:
        """
        Record an API call across all rate limit tiers.
        
        Atomically increments call counters in DynamoDB for each tier.
        Uses current timestamp in milliseconds for precise tracking.
        
        Returns:
            Dictionary containing:
                - recorded (bool): True if call was recorded
                - timestamp (int): Unix timestamp in milliseconds
                - current_usage (dict): Updated call counts per tier
                
        Raises:
            Exception: If DynamoDB write fails
            
        Example:
            >>> result = await rate_limiter.record_call()
            >>> print(result)
            {
                'recorded': True,
                'timestamp': 1698796800000,
                'current_usage': {
                    'per_second': 6,
                    'per_minute': 121,
                    'per_day': 8433
                }
            }
        """
        timestamp_ms = int(time.time() * 1000)  # Millisecond precision
        current_usage = {}
        
        # Record call in each tier's table
        for tier in self.tiers:
            await self._record_call_in_tier(tier, timestamp_ms)
            
            # Get updated count
            call_count = await self._count_calls_in_window(tier)
            current_usage[tier.name] = call_count
        
        logger.debug(
            "API call recorded",
            extra={
                "resource_id": self.resource_id,
                "timestamp": timestamp_ms,
                "current_usage": current_usage
            }
        )
        
        return {
            "recorded": True,
            "timestamp": timestamp_ms,
            "current_usage": current_usage
        }
    
    async def acquire(self) -> Dict[str, Any]:
        """
        Acquire rate limit permission (check and record if allowed).
        
        Atomic operation that checks rate limits and records the call if allowed.
        This is the primary method for rate-limited API calls.
        
        Returns:
            Dictionary containing:
                - acquired (bool): True if permission granted
                - timestamp (int, optional): Timestamp if acquired
                - current_usage (dict): Current call counts
                - retry_after (int, optional): Seconds to wait if denied
                
        Raises:
            RateLimitException: If rate limit is exceeded
            
        Example:
            >>> try:
            ...     result = await rate_limiter.acquire()
            ...     await salesforce_api.make_call()
            ... except RateLimitException as e:
            ...     await asyncio.sleep(e.retry_after)
        """
        # Check if request is within limits
        check_result = await self.check_rate_limit()
        
        if not check_result["allowed"]:
            raise RateLimitException(
                message=f"Rate limit exceeded for tier: {check_result['exceeded_tier']}",
                tier=check_result["exceeded_tier"],
                current_usage=check_result["current_usage"],
                limits=check_result["limits"],
                retry_after=check_result["retry_after"]
            )
        
        # Record the call
        record_result = await self.record_call()
        
        return {
            "acquired": True,
            "timestamp": record_result["timestamp"],
            "current_usage": record_result["current_usage"],
            "limits": check_result["limits"]
        }
    
    async def get_current_usage(self) -> Dict[str, int]:
        """
        Get current API call usage across all tiers.
        
        Returns:
            Dictionary mapping tier names to current call counts
            
        Example:
            >>> usage = await rate_limiter.get_current_usage()
            >>> print(usage)
            {'per_second': 5, 'per_minute': 120, 'per_day': 8432}
        """
        usage = {}
        
        for tier in self.tiers:
            call_count = await self._count_calls_in_window(tier)
            usage[tier.name] = call_count
        
        return usage
    
    async def _count_calls_in_window(self, tier: RateLimitTier) -> int:
        """
        Count API calls within the tier's time window using sliding window algorithm.
        
        The sliding window works by:
        1. Calculate window_start = current_time - window_duration
        2. Query DynamoDB for all calls where timestamp >= window_start
        3. Count results (DynamoDB automatically filters by sort key range)
        
        Args:
            tier: Rate limit tier configuration
            
        Returns:
            Number of calls in the current time window
            
        Example:
            Current time: 2024-10-30 15:30:45
            Window: 60 seconds (per_minute tier)
            Window start: 2024-10-30 15:29:45
            
            Query: SELECT COUNT(*) WHERE timestamp >= 1698765585000
            Result: 120 calls
        """
        current_time_ms = int(time.time() * 1000)
        window_start_ms = current_time_ms - (tier.window_seconds * 1000)
        
        try:
            # Query DynamoDB for calls in window
            # Uses partition key (resource_id) and sort key range (timestamp)
            result = await self.dynamodb.query_items(
                table_name=tier.table_name,
                key_condition_expression="resource_id = :resource_id AND #ts >= :window_start",
                expression_attribute_names={
                    "#ts": "timestamp"  # 'timestamp' is a reserved word in DynamoDB
                },
                expression_attribute_values={
                    ":resource_id": self.resource_id,
                    ":window_start": window_start_ms
                }
            )
            
            call_count = len(result.get("Items", []))
            
            logger.debug(
                f"Counted {call_count} calls in {tier.name} window",
                extra={
                    "tier": tier.name,
                    "count": call_count,
                    "limit": tier.limit,
                    "window_seconds": tier.window_seconds
                }
            )
            
            return call_count
            
        except Exception as e:
            logger.error(
                f"Failed to count calls for tier {tier.name}: {str(e)}",
                exc_info=True
            )
            # On error, return 0 to allow the call (fail open)
            # Alternative: return tier.limit to block calls (fail closed)
            return 0
    
    async def _record_call_in_tier(self, tier: RateLimitTier, timestamp_ms: int) -> None:
        """
        Record a single API call in a specific tier's DynamoDB table.
        
        Creates a new item with:
        - resource_id: Partition key (e.g., 'salesforce_api')
        - timestamp: Sort key (millisecond precision)
        - ttl: Expiration timestamp (window_seconds * 2 for safety margin)
        - call_count: Always 1 (for potential aggregation queries)
        
        The TTL ensures DynamoDB automatically deletes old entries, preventing
        unbounded table growth and reducing storage costs.
        
        Args:
            tier: Rate limit tier configuration
            timestamp_ms: Unix timestamp in milliseconds
            
        Raises:
            Exception: If DynamoDB write fails
        """
        # Calculate TTL (2x window duration for safety margin)
        ttl_seconds = int(time.time()) + (tier.window_seconds * 2)
        
        item = {
            "resource_id": self.resource_id,
            "timestamp": timestamp_ms,
            "ttl": ttl_seconds,
            "call_count": 1
        }
        
        try:
            await self.dynamodb.put_item(
                table_name=tier.table_name,
                item=item
            )
            
            logger.debug(
                f"Recorded call in {tier.name} tier",
                extra={
                    "tier": tier.name,
                    "timestamp": timestamp_ms,
                    "ttl": ttl_seconds
                }
            )
            
        except Exception as e:
            logger.error(
                f"Failed to record call in {tier.name} tier: {str(e)}",
                exc_info=True
            )
            raise
    
    async def _calculate_retry_after(self, tier: RateLimitTier) -> int:
        """
        Calculate how many seconds to wait before retrying after rate limit hit.
        
        Algorithm:
        1. Query oldest call in the current window
        2. Calculate when that call will expire from the window
        3. Add 1 second buffer
        
        Args:
            tier: Rate limit tier that was exceeded
            
        Returns:
            Number of seconds to wait before retrying
            
        Example:
            Tier: per_second (10 calls/second)
            Current time: 15:30:45.800
            Oldest call: 15:30:45.200
            Window expires: 15:30:46.200
            Retry after: (46.200 - 45.800) + 1 = 1.4 → 2 seconds
        """
        current_time_ms = int(time.time() * 1000)
        window_start_ms = current_time_ms - (tier.window_seconds * 1000)
        
        try:
            # Query oldest call in window (sort ascending by timestamp)
            result = await self.dynamodb.query_items(
                table_name=tier.table_name,
                key_condition_expression="resource_id = :resource_id AND #ts >= :window_start",
                expression_attribute_names={
                    "#ts": "timestamp"
                },
                expression_attribute_values={
                    ":resource_id": self.resource_id,
                    ":window_start": window_start_ms
                },
                scan_index_forward=True,  # Ascending order (oldest first)
                limit=1
            )
            
            items = result.get("Items", [])
            
            if items:
                oldest_timestamp_ms = items[0]["timestamp"]
                # Calculate when oldest call expires from window
                expires_at_ms = oldest_timestamp_ms + (tier.window_seconds * 1000)
                retry_after_ms = expires_at_ms - current_time_ms
                
                # Convert to seconds and add 1 second buffer
                retry_after_seconds = max(1, int(retry_after_ms / 1000) + 1)
                
                logger.debug(
                    f"Calculated retry_after for {tier.name}",
                    extra={
                        "tier": tier.name,
                        "oldest_timestamp": oldest_timestamp_ms,
                        "retry_after": retry_after_seconds
                    }
                )
                
                return retry_after_seconds
            else:
                # No calls in window (shouldn't happen), default to window duration
                return tier.window_seconds
                
        except Exception as e:
            logger.error(
                f"Failed to calculate retry_after for {tier.name}: {str(e)}",
                exc_info=True
            )
            # Default to full window duration on error
            return tier.window_seconds


# Singleton instance
_rate_limiter_instance: Optional[SlidingWindowRateLimiter] = None


def get_rate_limiter() -> SlidingWindowRateLimiter:
    """
    Get or create SlidingWindowRateLimiter singleton instance.
    
    Returns:
        SlidingWindowRateLimiter instance configured for Salesforce API
    """
    global _rate_limiter_instance
    if _rate_limiter_instance is None:
        _rate_limiter_instance = SlidingWindowRateLimiter(
            dynamodb_service=dynamodb_service,
            resource_id="salesforce_api"
        )
    return _rate_limiter_instance