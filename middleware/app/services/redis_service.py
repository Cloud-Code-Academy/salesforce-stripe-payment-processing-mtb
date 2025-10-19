"""
Redis Service

Provides caching operations for OAuth tokens and temporary data storage.
"""

import json
from typing import Any, Optional

import redis.asyncio as aioredis
from redis.asyncio import Redis

from app.config import settings
from app.utils.exceptions import CacheException
from app.utils.logging_config import get_logger

logger = get_logger(__name__)


class RedisService:
    """Redis cache operations service"""

    def __init__(self):
        self.redis_client: Optional[Redis] = None
        self._pool = None

    async def connect(self) -> None:
        """Establish connection to Redis"""
        try:
            self._pool = aioredis.ConnectionPool.from_url(
                settings.redis_url,
                encoding="utf-8",
                decode_responses=True,
                max_connections=10,
            )
            self.redis_client = aioredis.Redis(connection_pool=self._pool)
            await self.redis_client.ping()
            logger.info("Successfully connected to Redis")
        except Exception as e:
            logger.error(f"Failed to connect to Redis: {e}")
            raise CacheException(f"Redis connection failed: {e}")

    async def disconnect(self) -> None:
        """Close Redis connection"""
        if self.redis_client:
            await self.redis_client.close()
            if self._pool:
                await self._pool.disconnect()
            logger.info("Disconnected from Redis")

    async def get(self, key: str) -> Optional[str]:
        """
        Get value from cache.

        Args:
            key: Cache key

        Returns:
            Cached value or None if not found
        """
        try:
            if not self.redis_client:
                raise CacheException("Redis client not connected")

            value = await self.redis_client.get(key)
            if value:
                logger.debug(f"Cache hit for key: {key}")
            else:
                logger.debug(f"Cache miss for key: {key}")
            return value
        except Exception as e:
            logger.error(f"Error getting key {key} from Redis: {e}")
            raise CacheException(f"Failed to get key from cache: {e}")

    async def set(
        self,
        key: str,
        value: str,
        ttl: Optional[int] = None,
    ) -> bool:
        """
        Set value in cache with optional TTL.

        Args:
            key: Cache key
            value: Value to cache
            ttl: Time-to-live in seconds (default from config)

        Returns:
            True if successful
        """
        try:
            if not self.redis_client:
                raise CacheException("Redis client not connected")

            _ttl = ttl or settings.redis_token_ttl
            await self.redis_client.setex(key, _ttl, value)
            logger.debug(f"Set cache key: {key} with TTL: {_ttl}s")
            return True
        except Exception as e:
            logger.error(f"Error setting key {key} in Redis: {e}")
            raise CacheException(f"Failed to set key in cache: {e}")

    async def delete(self, key: str) -> bool:
        """
        Delete key from cache.

        Args:
            key: Cache key to delete

        Returns:
            True if key was deleted, False if key didn't exist
        """
        try:
            if not self.redis_client:
                raise CacheException("Redis client not connected")

            result = await self.redis_client.delete(key)
            logger.debug(f"Deleted cache key: {key}")
            return bool(result)
        except Exception as e:
            logger.error(f"Error deleting key {key} from Redis: {e}")
            raise CacheException(f"Failed to delete key from cache: {e}")

    async def exists(self, key: str) -> bool:
        """
        Check if key exists in cache.

        Args:
            key: Cache key

        Returns:
            True if key exists
        """
        try:
            if not self.redis_client:
                raise CacheException("Redis client not connected")

            result = await self.redis_client.exists(key)
            return bool(result)
        except Exception as e:
            logger.error(f"Error checking existence of key {key}: {e}")
            raise CacheException(f"Failed to check key existence: {e}")

    async def get_json(self, key: str) -> Optional[Any]:
        """
        Get JSON value from cache and deserialize.

        Args:
            key: Cache key

        Returns:
            Deserialized JSON value or None
        """
        try:
            value = await self.get(key)
            if value:
                return json.loads(value)
            return None
        except json.JSONDecodeError as e:
            logger.error(f"Error decoding JSON for key {key}: {e}")
            raise CacheException(f"Failed to decode JSON from cache: {e}")

    async def set_json(
        self,
        key: str,
        value: Any,
        ttl: Optional[int] = None,
    ) -> bool:
        """
        Serialize value to JSON and set in cache.

        Args:
            key: Cache key
            value: Value to serialize and cache
            ttl: Time-to-live in seconds

        Returns:
            True if successful
        """
        try:
            json_value = json.dumps(value)
            return await self.set(key, json_value, ttl)
        except (TypeError, ValueError) as e:
            logger.error(f"Error encoding JSON for key {key}: {e}")
            raise CacheException(f"Failed to encode JSON for cache: {e}")

    async def increment(self, key: str, amount: int = 1) -> int:
        """
        Increment a counter in cache.

        Args:
            key: Cache key
            amount: Amount to increment by

        Returns:
            New value after increment
        """
        try:
            if not self.redis_client:
                raise CacheException("Redis client not connected")

            new_value = await self.redis_client.incrby(key, amount)
            return new_value
        except Exception as e:
            logger.error(f"Error incrementing key {key}: {e}")
            raise CacheException(f"Failed to increment key: {e}")

    async def get_ttl(self, key: str) -> int:
        """
        Get remaining TTL for a key.

        Args:
            key: Cache key

        Returns:
            Remaining TTL in seconds, -1 if no TTL, -2 if key doesn't exist
        """
        try:
            if not self.redis_client:
                raise CacheException("Redis client not connected")

            ttl = await self.redis_client.ttl(key)
            return ttl
        except Exception as e:
            logger.error(f"Error getting TTL for key {key}: {e}")
            raise CacheException(f"Failed to get TTL: {e}")


# Global Redis service instance
redis_service = RedisService()
