"""
AWS SQS Service

Provides queue operations for asynchronous event processing.
"""

import json
from typing import Any, Dict, List, Optional

import aioboto3
from botocore.exceptions import ClientError

from app.config import settings
from app.utils.exceptions import QueueException
from app.utils.logging_config import get_logger

logger = get_logger(__name__)


class SQSService:
    """AWS SQS queue operations service"""

    def __init__(self):
        self.session = aioboto3.Session(
            aws_access_key_id=settings.aws_access_key_id,
            aws_secret_access_key=settings.aws_secret_access_key,
            region_name=settings.aws_region,
        )
        self.queue_url = settings.sqs_queue_url

    async def send_message(
        self,
        message_body: Dict[str, Any],
        message_attributes: Optional[Dict[str, Any]] = None,
        delay_seconds: int = 0,
    ) -> Dict[str, Any]:
        """
        Send a message to SQS queue.

        Args:
            message_body: Message body as dictionary (will be JSON serialized)
            message_attributes: Optional message attributes
            delay_seconds: Delay before message becomes available (0-900)

        Returns:
            SQS response with MessageId

        Raises:
            QueueException: If send fails
        """
        try:
            async with self.session.client("sqs") as sqs:
                # Serialize message body to JSON
                body = json.dumps(message_body)

                # Prepare message attributes if provided
                attributes = {}
                if message_attributes:
                    for key, value in message_attributes.items():
                        attributes[key] = {
                            "StringValue": str(value),
                            "DataType": "String",
                        }

                response = await sqs.send_message(
                    QueueUrl=self.queue_url,
                    MessageBody=body,
                    MessageAttributes=attributes,
                    DelaySeconds=delay_seconds,
                )

                message_id = response.get("MessageId")
                logger.info(
                    f"Message sent to SQS successfully",
                    extra={
                        "message_id": message_id,
                        "queue_url": self.queue_url,
                    },
                )

                return response

        except ClientError as e:
            error_code = e.response.get("Error", {}).get("Code", "Unknown")
            logger.error(
                f"Failed to send message to SQS: {error_code}",
                extra={"error": str(e), "queue_url": self.queue_url},
            )
            raise QueueException(
                f"Failed to send message to queue: {error_code}",
                details={"error": str(e)},
            )
        except Exception as e:
            logger.error(f"Unexpected error sending message to SQS: {e}")
            raise QueueException(f"Unexpected error: {e}")

    async def receive_messages(
        self,
        max_messages: int = 1,
        wait_time_seconds: Optional[int] = None,
        visibility_timeout: Optional[int] = None,
    ) -> List[Dict[str, Any]]:
        """
        Receive messages from SQS queue.

        Args:
            max_messages: Maximum number of messages to receive (1-10)
            wait_time_seconds: Long polling wait time (0-20)
            visibility_timeout: Visibility timeout for received messages

        Returns:
            List of messages

        Raises:
            QueueException: If receive fails
        """
        try:
            async with self.session.client("sqs") as sqs:
                params = {
                    "QueueUrl": self.queue_url,
                    "MaxNumberOfMessages": min(max_messages, 10),
                    "WaitTimeSeconds": wait_time_seconds
                    or settings.sqs_wait_time_seconds,
                    "MessageAttributeNames": ["All"],
                }

                if visibility_timeout:
                    params["VisibilityTimeout"] = visibility_timeout

                response = await sqs.receive_message(**params)
                messages = response.get("Messages", [])

                logger.info(
                    f"Received {len(messages)} messages from SQS",
                    extra={"count": len(messages), "queue_url": self.queue_url},
                )

                return messages

        except ClientError as e:
            error_code = e.response.get("Error", {}).get("Code", "Unknown")
            logger.error(f"Failed to receive messages from SQS: {error_code}")
            raise QueueException(
                f"Failed to receive messages: {error_code}",
                details={"error": str(e)},
            )
        except Exception as e:
            logger.error(f"Unexpected error receiving messages from SQS: {e}")
            raise QueueException(f"Unexpected error: {e}")

    async def delete_message(self, receipt_handle: str) -> None:
        """
        Delete a message from the queue.

        Args:
            receipt_handle: Receipt handle from received message

        Raises:
            QueueException: If delete fails
        """
        try:
            async with self.session.client("sqs") as sqs:
                await sqs.delete_message(
                    QueueUrl=self.queue_url,
                    ReceiptHandle=receipt_handle,
                )

                logger.debug(
                    "Message deleted from SQS",
                    extra={"queue_url": self.queue_url},
                )

        except ClientError as e:
            error_code = e.response.get("Error", {}).get("Code", "Unknown")
            logger.error(f"Failed to delete message from SQS: {error_code}")
            raise QueueException(
                f"Failed to delete message: {error_code}",
                details={"error": str(e)},
            )
        except Exception as e:
            logger.error(f"Unexpected error deleting message from SQS: {e}")
            raise QueueException(f"Unexpected error: {e}")

    async def get_queue_attributes(self) -> Dict[str, Any]:
        """
        Get queue attributes (e.g., message count).

        Returns:
            Queue attributes dictionary

        Raises:
            QueueException: If operation fails
        """
        try:
            async with self.session.client("sqs") as sqs:
                response = await sqs.get_queue_attributes(
                    QueueUrl=self.queue_url,
                    AttributeNames=["All"],
                )

                attributes = response.get("Attributes", {})
                logger.debug(
                    "Retrieved queue attributes",
                    extra={"queue_url": self.queue_url},
                )

                return attributes

        except ClientError as e:
            error_code = e.response.get("Error", {}).get("Code", "Unknown")
            logger.error(f"Failed to get queue attributes: {error_code}")
            raise QueueException(
                f"Failed to get queue attributes: {error_code}",
                details={"error": str(e)},
            )
        except Exception as e:
            logger.error(f"Unexpected error getting queue attributes: {e}")
            raise QueueException(f"Unexpected error: {e}")


# Global SQS service instance
sqs_service = SQSService()
