"""
DynamoDB Service for Token Caching and Temporary Storage

Replaces Redis with DynamoDB for:
- OAuth token caching
- Rate limiting counters
- Temporary event data storage

DynamoDB is serverless, auto-scaling, and often free tier eligible.
"""

import json
import time
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, Optional

import boto3
from botocore.exceptions import ClientError

from app.config import settings
from app.utils.logging_config import get_logger

logger = get_logger(__name__)


class DynamoDBService:
    """
    DynamoDB service for caching and temporary storage.

    Table Structure:
    - Primary Key: pk (partition key)
    - Sort Key: sk (sort key) - optional, used for range queries
    - Attributes:
      - value: The stored value (JSON string or plain string)
      - ttl: TTL timestamp for automatic expiration
      - created_at: ISO timestamp
      - updated_at: ISO timestamp
    """

    def __init__(self):
        """Initialize DynamoDB client and table"""
        self.client = None
        self.table_name = settings.dynamodb_table_name
        self._connected = False

    async def connect(self):
        """Initialize DynamoDB connection"""
        if self._connected:
            return

        try:
            # Create DynamoDB client
            # boto3 is async-compatible via aioboto3, but for simplicity using sync client
            # Lambda provides boto3 by default
            # Only use endpoint_url for local development (LocalStack), not in Lambda
            endpoint_url = settings.aws_endpoint_url if not settings.is_lambda else None
            self.client = boto3.resource(
                "dynamodb",
                region_name=settings.aws_region,
                endpoint_url=endpoint_url,  # For LocalStack (local dev only)
            )

            self.table = self.client.Table(self.table_name)

            # Verify table exists
            self.table.load()

            self._connected = True
            logger.info(f"Connected to DynamoDB table: {self.table_name}")

        except ClientError as e:
            logger.error(f"Failed to connect to DynamoDB: {e}")
            raise
        except Exception as e:
            logger.error(f"Unexpected error connecting to DynamoDB: {e}")
            raise

    async def disconnect(self):
        """Close DynamoDB connection"""
        if self.client:
            # boto3 resource doesn't need explicit close
            self._connected = False
            logger.info("DynamoDB connection closed")

    def is_connected(self) -> bool:
        """Check if connected to DynamoDB"""
        return self._connected

    async def set(
        self,
        key: str,
        value: Any,
        ttl_seconds: Optional[int] = None,
        namespace: str = "default",
    ) -> bool:
        """
        Set a value in DynamoDB with optional TTL.

        Args:
            key: The key to store
            value: The value to store (will be JSON-serialized if dict/list)
            ttl_seconds: Time to live in seconds (None = no expiration)
            namespace: Namespace for the key (used as partition key prefix)

        Returns:
            True if successful, False otherwise
        """
        if not self._connected:
            await self.connect()

        try:
            # Create partition key with namespace and sort key
            pk = f"{namespace}#{key}"
            sk = "value"  # Default sort key for simple key-value pairs

            # Serialize value if needed
            if isinstance(value, (dict, list)):
                stored_value = json.dumps(value)
                value_type = "json"
            else:
                stored_value = str(value)
                value_type = "string"

            # Prepare item (table has both pk and sk in schema)
            now = datetime.now(timezone.utc)
            item = {
                "pk": pk,
                "sk": sk,
                "value": stored_value,
                "value_type": value_type,
                "created_at": now.isoformat(),
                "updated_at": now.isoformat(),
            }

            # Add TTL if specified
            if ttl_seconds:
                ttl_timestamp = int(time.time()) + ttl_seconds
                item["ttl"] = ttl_timestamp

            # Store in DynamoDB
            self.table.put_item(Item=item)

            logger.debug(
                f"Set DynamoDB key: {pk}",
                extra={"ttl_seconds": ttl_seconds, "value_type": value_type},
            )

            return True

        except ClientError as e:
            logger.error(f"Failed to set DynamoDB key {key}: {e}")
            return False
        except Exception as e:
            logger.error(f"Unexpected error setting DynamoDB key {key}: {e}")
            return False

    async def get(self, key: str, namespace: str = "default") -> Optional[Any]:
        """
        Get a value from DynamoDB.

        Args:
            key: The key to retrieve
            namespace: Namespace for the key

        Returns:
            The stored value, or None if not found or expired
        """
        if not self._connected:
            await self.connect()

        try:
            pk = f"{namespace}#{key}"
            sk = "value"  # Default sort key for simple key-value pairs

            # Get item from DynamoDB (table has both pk and sk in schema)
            response = self.table.get_item(Key={"pk": pk, "sk": sk})

            if "Item" not in response:
                logger.debug(f"DynamoDB key not found: {pk}")
                return None

            item = response["Item"]

            # Check if TTL expired (DynamoDB auto-deletes but may have delay)
            if "ttl" in item:
                if int(time.time()) > item["ttl"]:
                    logger.debug(f"DynamoDB key expired: {pk}")
                    # Delete expired item
                    await self.delete(key, namespace)
                    return None

            # Deserialize value
            value = item["value"]
            value_type = item.get("value_type", "string")

            if value_type == "json":
                return json.loads(value)
            else:
                return value

        except ClientError as e:
            logger.error(f"Failed to get DynamoDB key {key}: {e}")
            return None
        except Exception as e:
            logger.error(f"Unexpected error getting DynamoDB key {key}: {e}")
            return None

    async def get_item(self, table_name: str, key: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """
        Get an item from DynamoDB table by primary key.

        Args:
            table_name: Name of the DynamoDB table
            key: Primary key dict (e.g., {"pk": "value"} or {"pk": "value", "sk": "value"})

        Returns:
            Item dict if found, None otherwise
        """
        if not self._connected:
            await self.connect()

        try:
            # Get the table
            table = self.client.Table(table_name)

            # Get the item
            response = table.get_item(Key=key)

            # Return the item if found
            return response.get("Item")

        except ClientError as e:
            if e.response["Error"]["Code"] == "ResourceNotFoundException":
                logger.debug(f"Item not found in {table_name}: {key}")
                return None
            else:
                logger.error(f"Failed to get item from {table_name}: {e}")
                raise
        except Exception as e:
            logger.error(f"Unexpected error getting item from {table_name}: {e}")
            raise

    async def put_item(self, table_name: str, item: Dict[str, Any]) -> bool:
        """
        Put an item into DynamoDB table.

        Args:
            table_name: Name of the DynamoDB table
            item: Item dict to store (must include primary key fields)

        Returns:
            True if successful
        """
        if not self._connected:
            await self.connect()

        try:
            # Get the table
            table = self.client.Table(table_name)

            # Put the item
            table.put_item(Item=item)

            logger.debug(f"Item stored in {table_name}")
            return True

        except ClientError as e:
            logger.error(f"Failed to put item in {table_name}: {e}")
            raise
        except Exception as e:
            logger.error(f"Unexpected error putting item in {table_name}: {e}")
            raise

    async def delete_item(self, table_name: str, key: Dict[str, Any]) -> bool:
        """
        Delete an item from DynamoDB table by primary key.

        Args:
            table_name: Name of the DynamoDB table
            key: Primary key dict (e.g., {"pk": "value"} or {"pk": "value", "sk": "value"})

        Returns:
            True if successful
        """
        if not self._connected:
            await self.connect()

        try:
            # Get the table
            table = self.client.Table(table_name)

            # Delete the item
            table.delete_item(Key=key)

            logger.debug(f"Item deleted from {table_name}: {key}")
            return True

        except ClientError as e:
            logger.error(f"Failed to delete item from {table_name}: {e}")
            raise
        except Exception as e:
            logger.error(f"Unexpected error deleting item from {table_name}: {e}")
            raise

    async def delete(self, key: str, namespace: str = "default") -> bool:
        """
        Delete a value from DynamoDB.

        Args:
            key: The key to delete
            namespace: Namespace for the key

        Returns:
            True if successful, False otherwise
        """
        if not self._connected:
            await self.connect()

        try:
            pk = f"{namespace}#{key}"
            sk = "value"  # Default sort key for simple key-value pairs

            # Table has both pk and sk in schema
            self.table.delete_item(Key={"pk": pk, "sk": sk})

            logger.debug(f"Deleted DynamoDB key: {pk}")
            return True

        except ClientError as e:
            logger.error(f"Failed to delete DynamoDB key {key}: {e}")
            return False
        except Exception as e:
            logger.error(f"Unexpected error deleting DynamoDB key {key}: {e}")
            return False

    async def exists(self, key: str, namespace: str = "default") -> bool:
        """
        Check if a key exists in DynamoDB.

        Args:
            key: The key to check
            namespace: Namespace for the key

        Returns:
            True if exists and not expired, False otherwise
        """
        value = await self.get(key, namespace)
        return value is not None

    async def increment(
        self,
        key: str,
        amount: int = 1,
        ttl_seconds: Optional[int] = None,
        namespace: str = "counter",
    ) -> int:
        """
        Increment a counter in DynamoDB (atomic operation).

        Args:
            key: The counter key
            amount: Amount to increment by
            ttl_seconds: Time to live in seconds
            namespace: Namespace for counters

        Returns:
            New counter value
        """
        if not self._connected:
            await self.connect()

        try:
            pk = f"{namespace}#{key}"
            sk = "value"  # Default sort key for simple key-value pairs
            now = datetime.now(timezone.utc)

            # Prepare update expression
            update_expr = "SET #value = if_not_exists(#value, :zero) + :inc, updated_at = :now"
            expr_attr_names = {"#value": "value"}
            expr_attr_values = {
                ":inc": amount,
                ":zero": 0,
                ":now": now.isoformat(),
            }

            # Add TTL if specified
            if ttl_seconds:
                ttl_timestamp = int(time.time()) + ttl_seconds
                update_expr += ", #ttl = :ttl"
                expr_attr_names["#ttl"] = "ttl"
                expr_attr_values[":ttl"] = ttl_timestamp

            # Atomic increment (table has both pk and sk in schema)
            response = self.table.update_item(
                Key={"pk": pk, "sk": sk},
                UpdateExpression=update_expr,
                ExpressionAttributeNames=expr_attr_names,
                ExpressionAttributeValues=expr_attr_values,
                ReturnValues="UPDATED_NEW",
            )

            new_value = int(response["Attributes"]["value"])

            logger.debug(
                f"Incremented DynamoDB counter: {pk} = {new_value}",
                extra={"amount": amount},
            )

            return new_value

        except ClientError as e:
            logger.error(f"Failed to increment DynamoDB counter {key}: {e}")
            return 0
        except Exception as e:
            logger.error(f"Unexpected error incrementing DynamoDB counter {key}: {e}")
            return 0

    async def get_counter(self, key: str, namespace: str = "counter") -> int:
        """
        Get counter value.

        Args:
            key: The counter key
            namespace: Namespace for counters

        Returns:
            Counter value (0 if not found)
        """
        value = await self.get(key, namespace)
        if value is None:
            return 0
        try:
            return int(value)
        except (ValueError, TypeError):
            return 0

    async def setex(self, key: str, ttl_seconds: int, value: Any, namespace: str = "default") -> bool:
        """
        Set a value with expiration (Redis compatibility method).

        Args:
            key: The key to store
            ttl_seconds: Time to live in seconds
            value: The value to store
            namespace: Namespace for the key

        Returns:
            True if successful
        """
        return await self.set(key, value, ttl_seconds=ttl_seconds, namespace=namespace)

    async def zadd(
        self,
        key: str,
        mapping: Dict[str, float],
        namespace: str = "sorted_set",
    ) -> int:
        """
        Add items to a sorted set (for rate limiting sliding window).

        DynamoDB implementation: Each item gets its own record with score as sort key.

        Args:
            key: The sorted set key
            mapping: Dict of {member: score}
            namespace: Namespace for sorted sets

        Returns:
            Number of items added
        """
        if not self._connected:
            await self.connect()

        count = 0
        for member, score in mapping.items():
            try:
                pk = f"{namespace}#{key}"
                sk = f"{score}#{member}"  # Sort key: score + member

                now = datetime.now(timezone.utc)
                item = {
                    "pk": pk,
                    "sk": sk,
                    "score": score,
                    "member": member,
                    "created_at": now.isoformat(),
                }

                self.table.put_item(Item=item)
                count += 1

            except ClientError as e:
                logger.error(f"Failed to add to sorted set {key}: {e}")

        return count

    async def zcount(
        self,
        key: str,
        min_score: float,
        max_score: float,
        namespace: str = "sorted_set",
    ) -> int:
        """
        Count items in sorted set within score range.

        Args:
            key: The sorted set key
            min_score: Minimum score (inclusive)
            max_score: Maximum score (inclusive)
            namespace: Namespace for sorted sets

        Returns:
            Count of items in range
        """
        if not self._connected:
            await self.connect()

        try:
            pk = f"{namespace}#{key}"

            # Query items in score range
            # Note: This requires GSI if we want efficient range queries
            # For now, scan and filter (works but not optimal for large datasets)
            response = self.table.query(
                KeyConditionExpression="pk = :pk",
                FilterExpression="#score BETWEEN :min AND :max",
                ExpressionAttributeNames={"#score": "score"},
                ExpressionAttributeValues={
                    ":pk": pk,
                    ":min": min_score,
                    ":max": max_score,
                },
                Select="COUNT",
            )

            return response.get("Count", 0)

        except ClientError as e:
            logger.error(f"Failed to count sorted set {key}: {e}")
            return 0
        except Exception as e:
            logger.error(f"Unexpected error counting sorted set {key}: {e}")
            return 0

    async def query_items(
        self,
        table_name: str,
        key_condition_expression: str,
        expression_attribute_names: Optional[Dict[str, str]] = None,
        expression_attribute_values: Optional[Dict[str, Any]] = None,
        scan_index_forward: bool = True,
        limit: Optional[int] = None
    ) -> Dict[str, Any]:
        """
        Query items from DynamoDB table using partition and sort keys.

        Supports efficient range queries on sort keys, which is critical for
        the sliding window rate limiter (queries timestamp ranges).

        Args:
            table_name: DynamoDB table name
            key_condition_expression: Key condition (e.g., "pk = :pk AND sk >= :start")
            expression_attribute_names: Name substitutions for reserved words
            expression_attribute_values: Value bindings for expression
            scan_index_forward: True for ascending, False for descending sort order
            limit: Maximum number of items to return

        Returns:
            Dictionary containing:
                - Items: List of matching items
                - Count: Number of items returned
                - ScannedCount: Number of items evaluated
                - LastEvaluatedKey: Pagination token (if applicable)

        Example:
            >>> result = await dynamodb.query_items(
            ...     table_name="rate-limit-per-second",
            ...     key_condition_expression="resource_id = :id AND #ts >= :start",
            ...     expression_attribute_names={"#ts": "timestamp"},
            ...     expression_attribute_values={
            ...         ":id": "salesforce_api",
            ...         ":start": 1698796800000
            ...     }
            ... )
            >>> print(len(result["Items"]))
            5
        """
        try:
            query_params = {
                "TableName": table_name,
                "KeyConditionExpression": key_condition_expression,
                "ScanIndexForward": scan_index_forward
            }

            if expression_attribute_names:
                query_params["ExpressionAttributeNames"] = expression_attribute_names

            if expression_attribute_values:
                query_params["ExpressionAttributeValues"] = expression_attribute_values

            if limit:
                query_params["Limit"] = limit

            response = await self.client.query(**query_params)

            return {
                "Items": response.get("Items", []),
                "Count": response.get("Count", 0),
                "ScannedCount": response.get("ScannedCount", 0),
                "LastEvaluatedKey": response.get("LastEvaluatedKey")
            }

        except Exception as e:
            logger.error(
                f"DynamoDB query failed for table {table_name}: {str(e)}",
                exc_info=True
            )
            raise


# Singleton instance
dynamodb_service = DynamoDBService()
