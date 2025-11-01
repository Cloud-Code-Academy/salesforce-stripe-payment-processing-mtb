"""
Event Router

Routes Stripe webhook events to appropriate handlers based on event type.
Implements idempotency tracking to prevent duplicate processing.

Priority Levels:
- HIGH: Critical business events requiring immediate processing (payment failures, cancellations)
- MEDIUM: Standard events processed in real-time via REST API (successful payments, subscriptions)
- LOW: Non-urgent events batched for later Bulk API processing (customer metadata updates)

AWS Lambda Optimizations:
- Uses DynamoDB instead of Redis for idempotency (serverless, cost-effective)
- Uses separate SQS queue for low-priority events (native AWS integration)
"""

from typing import Dict, Any, Optional
from enum import Enum
import json
from datetime import datetime, timezone, timedelta

from app.models.stripe_events import StripeEvent
from app.services.dynamodb_service import dynamodb_service, ConditionalCheckFailedException
from app.services.sqs_service import sqs_service
from app.utils.exceptions import ValidationException
from app.utils.logging_config import get_logger
from app.handlers import (
    customer_handler,
    subscription_handler,
    payment_handler
)

logger = get_logger(__name__)


class EventPriority(Enum):
    """Event processing priority levels"""
    HIGH = "high"      # Immediate processing - critical business events
    MEDIUM = "medium"  # Real-time processing - standard events
    LOW = "low"        # Batched processing - non-urgent events


# High-priority events processed immediately via REST API
HIGH_PRIORITY_EVENTS = {
    "payment_intent.payment_failed",
    "invoice.payment_failed",
    "customer.subscription.deleted",
    "checkout.session.expired",
}

# Low-priority events sent to separate SQS queue for batch processing
LOW_PRIORITY_EVENTS = {
    "customer.updated",
}


# Event type to handler function mapping
EVENT_HANDLERS = {
    # Customer events
    "customer.updated": customer_handler.handle_customer_updated,

    # Subscription lifecycle events
    "customer.subscription.created": subscription_handler.handle_subscription_created,
    "customer.subscription.updated": subscription_handler.handle_subscription_updated,
    "customer.subscription.deleted": subscription_handler.handle_subscription_deleted,
    "checkout.session.completed": subscription_handler.handle_checkout_completed,
    "checkout.session.expired": subscription_handler.handle_checkout_expired,

    # One-time payment events
    "payment_intent.succeeded": payment_handler.handle_payment_succeeded,
    "payment_intent.payment_failed": payment_handler.handle_payment_failed,

    # Recurring payment (invoice) events
    "invoice.payment_succeeded": payment_handler.handle_invoice_payment_succeeded,
    "invoice.payment_failed": payment_handler.handle_invoice_payment_failed,
}


class EventRouter:
    """
    Routes Stripe webhook events to appropriate handlers with priority-based processing.
    
    Uses DynamoDB for idempotency tracking (serverless, cost-effective).
    Uses SQS for low-priority event queuing (native AWS integration).
    
    Attributes:
        dynamodb: DynamoDB service for idempotency tracking
        sqs: SQS service for low-priority event queuing
    """
    
    def __init__(self, dynamodb_service, sqs_service):
        """
        Initialize event router with AWS services.
        
        Args:
            dynamodb_service: DynamoDB service for idempotency tracking
            sqs_service: SQS service for low-priority event queuing
        """
        self.dynamodb = dynamodb_service
        self.sqs = sqs_service
    
    async def route_event(self, event: Dict[str, Any]) -> Dict[str, Any]:
        """
        Route Stripe webhook event to appropriate handler based on type and priority.
        
        Processing flow:
        1. Validate event structure
        2. Check idempotency using DynamoDB (prevent duplicate processing)
        3. Determine priority level
        4. Route based on priority:
           - HIGH: Process immediately via REST API
           - MEDIUM: Process in real-time via REST API
           - LOW: Send to SQS batch queue for later processing
        
        Args:
            event: Stripe webhook event dictionary containing:
                - id (str): Unique Stripe event ID (e.g., 'evt_xxx')
                - type (str): Event type (e.g., 'invoice.payment_succeeded')
                - data (dict): Event payload with nested 'object' containing entity data
                
        Returns:
            Dictionary containing:
                - status (str): 'success', 'queued', 'duplicate', 'ignored', or 'error'
                - priority (str): 'high', 'medium', or 'low'
                - event_type (str): The event type processed
                - event_id (str): The Stripe event ID
                - result (dict, optional): Handler result if successful
                
        Raises:
            Exception: If handler execution fails (Lambda will retry)
            
        Examples:
            >>> # High-priority event (immediate processing)
            >>> event = {
            ...     "id": "evt_123",
            ...     "type": "invoice.payment_failed",
            ...     "data": {"object": {...}}
            ... }
            >>> result = await router.route_event(event)
            >>> print(result)
            {
                'status': 'success', 
                'priority': 'high',
                'event_type': 'invoice.payment_failed',
                'event_id': 'evt_123'
            }
            
            >>> # Low-priority event (queued for batch processing)
            >>> event = {
            ...     "id": "evt_456",
            ...     "type": "customer.updated",
            ...     "data": {"object": {...}}
            ... }
            >>> result = await router.route_event(event)
            >>> print(result)
            {
                'status': 'queued',
                'priority': 'low',
                'event_type': 'customer.updated',
                'queue_url': 'https://sqs.us-east-1.amazonaws.com/...'
            }
        """
        event_type = event.get("type")
        event_id = event.get("id")
        
        # Validate required fields
        if not event_type:
            logger.error("Event missing 'type' field")
            return {"status": "error", "message": "Missing event type"}
        
        if not event_id:
            logger.error("Event missing 'id' field")
            return {"status": "error", "message": "Missing event ID"}
        
        # Determine priority level
        priority = self._get_event_priority(event_type)
        
        logger.info(
            f"Routing event: {event_type} ({event_id}) - Priority: {priority.value}",
            extra={
                "event_id": event_id,
                "event_type": event_type,
                "priority": priority.value
            }
        )
        
        # Check if event was already processed (idempotency via DynamoDB)
        if await self._is_duplicate_event(event_id):
            logger.info(f"Duplicate event detected, skipping: {event_id}")
            return {
                "status": "duplicate",
                "event_type": event_type,
                "event_id": event_id,
                "priority": priority.value
            }
        
        # Check if handler exists for this event type
        if event_type not in EVENT_HANDLERS:
            logger.warning(f"No handler registered for event type: {event_type}")
            return {
                "status": "ignored",
                "event_type": event_type,
                "event_id": event_id,
                "priority": priority.value,
                "message": f"No handler for {event_type}"
            }
        
        # Route based on priority
        if priority == EventPriority.HIGH:
            return await self._process_high_priority(event, event_type, event_id)
        elif priority == EventPriority.LOW:
            return await self._process_low_priority(event, event_type, event_id)
        else:  # MEDIUM priority
            return await self._process_medium_priority(event, event_type, event_id)
    
    def _get_event_priority(self, event_type: str) -> EventPriority:
        """
        Determine processing priority for an event type.
        
        Args:
            event_type: Stripe event type (e.g., 'invoice.payment_failed')
            
        Returns:
            EventPriority enum value (HIGH, MEDIUM, or LOW)
        """
        if event_type in HIGH_PRIORITY_EVENTS:
            return EventPriority.HIGH
        elif event_type in LOW_PRIORITY_EVENTS:
            return EventPriority.LOW
        else:
            return EventPriority.MEDIUM
    
    async def _process_high_priority(
        self, 
        event: Dict[str, Any], 
        event_type: str, 
        event_id: str
    ) -> Dict[str, Any]:
        """
        Process high-priority events immediately via REST API.
        
        These are critical business events requiring immediate attention:
        - Payment failures (need immediate alerting to finance team)
        - Subscription cancellations (need immediate revenue tracking)
        - Failed checkouts (need immediate follow-up)
        
        Args:
            event: Full Stripe event object
            event_type: Event type string
            event_id: Unique event ID
            
        Returns:
            Processing result with 'high' priority indicator
            
        Raises:
            Exception: If handler fails (Lambda will retry automatically)
        """
        logger.info(
            f"Processing HIGH priority event: {event_type} ({event_id})",
            extra={"event_id": event_id, "priority": "high"}
        )
        
        handler = EVENT_HANDLERS[event_type]
        handler_name = handler.__name__
        
        try:
            result = await handler(event)
            
            logger.info(
                f"HIGH priority event processed successfully: {event_type}",
                extra={
                    "event_id": event_id,
                    "handler": handler_name,
                    "priority": "high"
                }
            )
            
            return {
                "status": "success",
                "priority": EventPriority.HIGH.value,
                "event_type": event_type,
                "event_id": event_id,
                "handler": handler_name,
                "result": result
            }
            
        except Exception as e:
            logger.error(
                f"HIGH priority handler {handler_name} failed for {event_type} ({event_id}): {str(e)}",
                exc_info=True,
                extra={
                    "event_id": event_id,
                    "handler": handler_name,
                    "priority": "high",
                    "error": str(e)
                }
            )
            # Re-raise to trigger Lambda retry
            raise
    
    async def _process_medium_priority(
        self, 
        event: Dict[str, Any], 
        event_type: str, 
        event_id: str
    ) -> Dict[str, Any]:
        """
        Process medium-priority events in real-time via REST API.
        
        Default processing tier for most events including:
        - Successful payments
        - Subscription updates
        - Customer creations
        
        Args:
            event: Full Stripe event object
            event_type: Event type string
            event_id: Unique event ID
            
        Returns:
            Processing result with 'medium' priority indicator
            
        Raises:
            Exception: If handler fails (Lambda will retry automatically)
        """
        logger.info(
            f"Processing MEDIUM priority event: {event_type} ({event_id})",
            extra={"event_id": event_id, "priority": "medium"}
        )
        
        handler = EVENT_HANDLERS[event_type]
        handler_name = handler.__name__
        
        try:
            result = await handler(event)
            
            logger.info(
                f"MEDIUM priority event processed successfully: {event_type}",
                extra={
                    "event_id": event_id,
                    "handler": handler_name,
                    "priority": "medium"
                }
            )
            
            return {
                "status": "success",
                "priority": EventPriority.MEDIUM.value,
                "event_type": event_type,
                "event_id": event_id,
                "handler": handler_name,
                "result": result
            }
            
        except Exception as e:
            logger.error(
                f"MEDIUM priority handler {handler_name} failed for {event_type} ({event_id}): {str(e)}",
                exc_info=True,
                extra={
                    "event_id": event_id,
                    "handler": handler_name,
                    "priority": "medium",
                    "error": str(e)
                }
            )
            raise
    
    async def _process_low_priority(
        self, 
        event: Dict[str, Any], 
        event_type: str, 
        event_id: str
    ) -> Dict[str, Any]:
        """
        Queue low-priority events to separate SQS queue for batch processing.
        
        These are non-urgent metadata updates that can be processed in batches:
        - Customer profile updates (name, email, phone)
        - Address changes
        - Metadata modifications
        
        Events are sent to a dedicated SQS queue monitored by a batch processor Lambda.
        This enables efficient Salesforce Bulk API usage.
        
        Args:
            event: Full Stripe event object
            event_type: Event type string
            event_id: Unique event ID
            
        Returns:
            Result indicating event was queued
            
        Note:
            A separate batch processor Lambda will:
            1. Poll low-priority SQS queue periodically
            2. Accumulate events up to batch size (e.g., 200 records)
            3. Process via Salesforce Bulk API 2.0
            4. Delete processed messages from SQS
        """
        logger.info(
            f"Queuing LOW priority event: {event_type} ({event_id})",
            extra={"event_id": event_id, "priority": "low"}
        )
        
        try:
            # Send event to low-priority SQS queue
            message_id = await self.sqs.send_message(
                message_body=event,
                queue_url=self.sqs.low_priority_queue_url,
                message_attributes={
                    "event_type": event_type,
                    "event_id": event_id,
                    "priority": EventPriority.LOW.value
                }
            )
            
            logger.info(
                f"Event queued successfully: {event_type} → SQS",
                extra={
                    "event_id": event_id,
                    "event_type": event_type,
                    "priority": "low",
                    "sqs_message_id": message_id
                }
            )
            
            return {
                "status": "queued",
                "priority": EventPriority.LOW.value,
                "event_type": event_type,
                "event_id": event_id,
                "sqs_message_id": message_id
            }
            
        except Exception as e:
            logger.error(
                f"Failed to queue event {event_type} ({event_id}): {str(e)}",
                exc_info=True,
                extra={
                    "event_id": event_id,
                    "priority": "low",
                    "error": str(e)
                }
            )
            # Re-raise to trigger Lambda retry
            raise
    
    async def _is_duplicate_event(self, event_id: str) -> bool:
        """
        Check if Stripe event was already processed using DynamoDB.
        
        Uses DynamoDB conditional write to atomically check and mark events as processed.
        Events are stored with a 7-day TTL (DynamoDB automatically deletes expired items).
        
        DynamoDB Table Structure:
            Table: stripe-event-idempotency
            Primary Key: event_id (String)
            Attributes:
                - event_id: Stripe event ID
                - processed_at: ISO timestamp
                - ttl: Unix timestamp (7 days from now)
        
        Args:
            event_id: Stripe event ID (e.g., 'evt_1234567890')
            
        Returns:
            True if event was already processed, False if new event
            
        Note:
            DynamoDB benefits over Redis:
            - Serverless (no infrastructure management)
            - Pay-per-request pricing (~$0.00001 per request)
            - Built-in TTL (automatic cleanup)
            - Native Lambda integration
            - No VPC required
        """
        # Calculate TTL (7 days from now)
        ttl_timestamp = int((datetime.now(timezone.utc) + timedelta(days=7)).timestamp())
        
        try:
            # Attempt to write event_id to DynamoDB (conditional on it not existing)
            await self.dynamodb.put_item_if_not_exists(
                table_name="stripe-event-idempotency",
                item={
                    "event_id": event_id,
                    "processed_at": datetime.now(timezone.utc).isoformat(),
                    "ttl": ttl_timestamp
                }
            )
            
            # If write succeeded, event is new (not a duplicate)
            logger.debug(f"Event marked as processed: {event_id}")
            return False

        except ConditionalCheckFailedException:
            # Write failed because item already exists (duplicate event)
            logger.debug(f"Event already processed: {event_id}")
            return True


def get_supported_event_types() -> list[str]:
    """
    Get list of all supported Stripe event types.
    
    Useful for configuring Stripe webhook endpoints and documentation.
    
    Returns:
        List of event type strings
        
    Example:
        >>> event_types = get_supported_event_types()
        >>> print(event_types)
        ['customer.updated', 'payment_intent.succeeded', ...]
    """
    return list(EVENT_HANDLERS.keys())


def get_event_priority_mapping() -> Dict[str, str]:
    """
    Get mapping of event types to their priority levels.
    
    Useful for monitoring and documentation purposes.
    
    Returns:
        Dictionary mapping event type to priority level string
        
    Example:
        >>> priority_map = get_event_priority_mapping()
        >>> print(priority_map['invoice.payment_failed'])
        'high'
    """
    priority_mapping = {}
    
    for event_type in get_supported_event_types():
        if event_type in HIGH_PRIORITY_EVENTS:
            priority_mapping[event_type] = EventPriority.HIGH.value
        elif event_type in LOW_PRIORITY_EVENTS:
            priority_mapping[event_type] = EventPriority.LOW.value
        else:
            priority_mapping[event_type] = EventPriority.MEDIUM.value
    
    return priority_mapping


# Singleton instance
_router_instance: Optional[EventRouter] = None


def get_event_router() -> EventRouter:
    """
    Get or create EventRouter singleton instance.
    
    Returns:
        EventRouter instance with configured AWS services
    """
    global _router_instance
    if _router_instance is None:
        _router_instance = EventRouter(dynamodb_service, sqs_service)
    return _router_instance
