"""
Batch Accumulator Service

Implements time-based and size-based batch accumulation for efficient bulk processing.

Strategy:
- Accumulate events in DynamoDB
- Submit when reaching size threshold (e.g., 200 records) OR time threshold (e.g., 30 seconds)
- Uses sliding window approach to track accumulation time

This ensures:
1. **Efficiency:** Batch large operations together
2. **Latency:** Events never wait longer than 30 seconds
3. **Cost:** Fewer Bulk API jobs for the same volume
"""

import json
from datetime import datetime, timezone, timedelta
from typing import Dict, Any, List, Optional
from enum import Enum

from app.services.dynamodb_service import dynamodb_service
from app.config import get_settings
from app.utils.logging_config import get_logger
from app.utils.exceptions import CacheException

logger = get_logger(__name__)
settings = get_settings()


class BatchType(Enum):
    """Types of batches for different object types"""
    CUSTOMER_UPDATE = "customer_update"


class BatchAccumulator:
    """
    Accumulates events in DynamoDB for batch processing.

    Sliding Window Strategy:
    - Each batch type has a "window start time" in DynamoDB
    - Events accumulate in a list within that window
    - When size OR time threshold exceeded, batch is ready for processing
    - New window created after submission

    DynamoDB Schema:
    ```
    Table: batch-accumulator
    PK: batch_type (e.g., "customer_update")
    SK: window_id (e.g., "2024-11-15T10:30:00Z")

    Attributes:
    - events: List[Dict] - Accumulated events
    - created_at: ISO timestamp
    - window_start: ISO timestamp
    - record_count: Number
    - ttl: Unix timestamp (auto-delete after 24 hours)
    ```
    """

    def __init__(self):
        """Initialize batch accumulator"""
        self.dynamodb = dynamodb_service
        # Use environment variable for table name, fallback to legacy name for backward compatibility
        self.table_name = settings.batch_accumulator_table_name if hasattr(settings, 'batch_accumulator_table_name') else "stripe-event-batches"
        self.size_threshold = 200  # Submit when reaching 200 records
        self.time_threshold = 30  # Submit if window open > 30 seconds

    async def add_event(
        self,
        batch_type: BatchType,
        event: Dict[str, Any]
    ) -> Dict[str, Any]:
        """
        Add event to batch accumulator.

        Returns whether batch is ready for submission.

        Args:
            batch_type: Type of batch (e.g., CUSTOMER_UPDATE)
            event: Event to add to batch

        Returns:
            {
                "added": True,
                "batch_ready": False,
                "batch_id": "2024-11-15T10:30:00Z"
            }
            OR
            {
                "added": True,
                "batch_ready": True,
                "batch_id": "2024-11-15T10:30:00Z",
                "record_count": 200
            }
        """
        batch_type_str = batch_type.value
        current_window = await self._get_or_create_window(batch_type_str)
        window_id = current_window["window_id"]

        logger.debug(
            f"Adding event to batch: {batch_type_str}",
            extra={
                "batch_type": batch_type_str,
                "window_id": window_id
            }
        )

        try:
            # Add event to batch
            batch_item = {
                "pk": batch_type_str,
                "sk": window_id,
                "events": current_window.get("events", []) + [event],
                "created_at": current_window["created_at"],
                "window_start": current_window["window_start"],
                "record_count": current_window.get("record_count", 0) + 1,
                "ttl": int((datetime.now(timezone.utc) + timedelta(days=1)).timestamp())
            }

            # Save updated batch
            await self.dynamodb.put_item(
                table_name=self.table_name,
                item=batch_item
            )

            record_count = batch_item["record_count"]
            window_age = await self._get_window_age_seconds(current_window["window_start"])

            # Check if batch is ready for submission
            batch_ready = (
                record_count >= self.size_threshold or
                window_age >= self.time_threshold
            )

            logger.info(
                f"Event added to batch",
                extra={
                    "batch_type": batch_type_str,
                    "window_id": window_id,
                    "record_count": record_count,
                    "window_age_seconds": window_age,
                    "batch_ready": batch_ready
                }
            )

            return {
                "added": True,
                "batch_ready": batch_ready,
                "batch_id": window_id,
                "record_count": record_count,
                "window_age_seconds": window_age
            }

        except Exception as e:
            logger.error(
                f"Failed to add event to batch: {str(e)}",
                exc_info=True,
                extra={"batch_type": batch_type_str}
            )
            raise CacheException(f"Failed to add event to batch: {str(e)}")

    async def get_batch(
        self,
        batch_type: BatchType
    ) -> Optional[Dict[str, Any]]:
        """
        Get accumulated batch if ready for submission.

        Returns None if not ready yet.

        Args:
            batch_type: Type of batch to retrieve

        Returns:
            {
                "batch_id": "2024-11-15T10:30:00Z",
                "batch_type": "customer_update",
                "events": [...],
                "record_count": 200
            }
            OR None if not ready
        """
        batch_type_str = batch_type.value

        try:
            batch_item = await self.dynamodb.get_item(
                table_name=self.table_name,
                key={"pk": batch_type_str}
            )

            if not batch_item:
                logger.debug(
                    f"No batch found for type: {batch_type_str}",
                    extra={"batch_type": batch_type_str}
                )
                return None

            record_count = batch_item.get("record_count", 0)
            window_age = await self._get_window_age_seconds(batch_item["window_start"])

            # Check if batch is ready
            is_ready = (
                record_count >= self.size_threshold or
                window_age >= self.time_threshold
            )

            if not is_ready:
                logger.debug(
                    f"Batch not ready yet",
                    extra={
                        "batch_type": batch_type_str,
                        "record_count": record_count,
                        "size_threshold": self.size_threshold,
                        "window_age_seconds": window_age,
                        "time_threshold": self.time_threshold
                    }
                )
                return None

            logger.info(
                f"Batch ready for submission",
                extra={
                    "batch_type": batch_type_str,
                    "batch_id": batch_item["sk"],
                    "record_count": record_count,
                    "window_age_seconds": window_age
                }
            )

            return {
                "batch_id": batch_item["sk"],
                "batch_type": batch_type_str,
                "events": batch_item.get("events", []),
                "record_count": record_count,
                "window_age_seconds": window_age
            }

        except Exception as e:
            logger.error(
                f"Failed to get batch: {str(e)}",
                exc_info=True,
                extra={"batch_type": batch_type_str}
            )
            return None

    async def submit_batch(self, batch_type: BatchType) -> bool:
        """
        Mark batch as submitted and create new window for next batch.

        Args:
            batch_type: Type of batch submitted

        Returns:
            True if successfully submitted, False otherwise
        """
        batch_type_str = batch_type.value

        try:
            # Delete old batch (implicitly starts new window on next add_event)
            await self.dynamodb.delete_item(
                table_name=self.table_name,
                key={"pk": batch_type_str}
            )

            logger.info(
                f"Batch submitted and cleared",
                extra={"batch_type": batch_type_str}
            )

            return True

        except Exception as e:
            logger.error(
                f"Failed to clear batch: {str(e)}",
                exc_info=True,
                extra={"batch_type": batch_type_str}
            )
            return False

    async def _get_or_create_window(self, batch_type_str: str) -> Dict[str, Any]:
        """
        Get current window or create new one if doesn't exist.

        Returns window information with created_at and window_start timestamps.
        """
        try:
            existing_batch = await self.dynamodb.get_item(
                table_name=self.table_name,
                key={"pk": batch_type_str}
            )

            if existing_batch:
                return existing_batch

            # Create new window
            now = datetime.now(timezone.utc).isoformat()
            window_id = now

            return {
                "pk": batch_type_str,
                "sk": window_id,
                "created_at": now,
                "window_start": now,
                "events": [],
                "record_count": 0
            }

        except Exception as e:
            logger.error(
                f"Failed to get/create window: {str(e)}",
                exc_info=True
            )
            raise

    async def _get_window_age_seconds(self, window_start_iso: str) -> float:
        """
        Calculate how long the batch window has been open.

        Args:
            window_start_iso: ISO timestamp when window started

        Returns:
            Age in seconds
        """
        try:
            window_start = datetime.fromisoformat(window_start_iso.replace("Z", "+00:00"))
            now = datetime.now(timezone.utc)
            age = (now - window_start).total_seconds()
            return age
        except Exception as e:
            logger.error(f"Failed to calculate window age: {str(e)}")
            return 0

    async def get_batch_stats(self) -> Dict[str, Any]:
        """
        Get statistics about accumulated batches.

        Returns:
            {
                "batches": {
                    "customer_update": {
                        "window_id": "...",
                        "record_count": 150,
                        "window_age_seconds": 15,
                        "ready": False
                    }
                }
            }
        """
        stats = {"batches": {}}

        for batch_type in BatchType:
            batch = await self.get_batch(batch_type)
            if batch:
                stats["batches"][batch_type.value] = {
                    "window_id": batch["batch_id"],
                    "record_count": batch["record_count"],
                    "window_age_seconds": batch.get("window_age_seconds", 0),
                    "ready": (
                        batch["record_count"] >= self.size_threshold or
                        batch.get("window_age_seconds", 0) >= self.time_threshold
                    )
                }

        return stats


# Singleton instance
_batch_accumulator_instance: Optional[BatchAccumulator] = None


def get_batch_accumulator() -> BatchAccumulator:
    """Get or create BatchAccumulator singleton instance"""
    global _batch_accumulator_instance
    if _batch_accumulator_instance is None:
        _batch_accumulator_instance = BatchAccumulator()
    return _batch_accumulator_instance
