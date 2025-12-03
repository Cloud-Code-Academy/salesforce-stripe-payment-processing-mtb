"""
Stripe Webhook Endpoint

Handles incoming Stripe webhook events with signature verification,
SQS queuing, and immediate 200 OK response.
"""

from fastapi import APIRouter, Request, HTTPException
from fastapi.responses import JSONResponse
from app.services.stripe_service import stripe_service
from app.services.sqs_service import sqs_service
from app.utils.exceptions import StripeSignatureException, StripeException
from app.utils.logging_config import get_logger, set_correlation_id

logger = get_logger(__name__)

router = APIRouter(prefix="/webhook", tags=["webhook"])


@router.post("/stripe")
async def stripe_webhook(request: Request):
    """
    Stripe webhook endpoint.

    Verifies webhook signature, pushes event to SQS queue,
    and returns 200 OK immediately to stay within Stripe's timeout.

    Events are processed asynchronously by the SQS worker Lambda.
    """
    correlation_id = set_correlation_id()

    try:
        # Extract webhook data
        payload, signature = await stripe_service.extract_webhook_data(request)

        # Verify signature and parse event
        stripe_event = await stripe_service.verify_webhook_signature(
            payload, signature
        )

        logger.info(
            f"Received Stripe webhook event",
            extra={
                "event_id": stripe_event.id,
                "event_type": stripe_event.type,
                "correlation_id": correlation_id,
            },
        )

        # Push event to SQS for async processing
        await sqs_service.send_message(
            message_body={
                "event_id": stripe_event.id,
                "event_type": stripe_event.type,
                "event_data": stripe_event.model_dump(mode="json"),
                "correlation_id": correlation_id,
            },
            message_attributes={
                "event_type": stripe_event.type,
                "event_id": stripe_event.id,
            },
        )

        logger.info(
            f"Event pushed to SQS successfully",
            extra={
                "event_id": stripe_event.id,
                "event_type": stripe_event.type,
            },
        )

        # Return 200 OK immediately
        return JSONResponse(
            status_code=200,
            content={
                "success": True,
                "event_id": stripe_event.id,
                "event_type": stripe_event.type,
                "correlation_id": correlation_id,
            },
        )

    except StripeSignatureException as e:
        logger.error(
            f"Webhook signature verification failed",
            extra={
                "error": str(e),
                "correlation_id": correlation_id,
            },
        )
        raise HTTPException(status_code=400, detail="Invalid signature")

    except StripeException as e:
        logger.error(
            f"Stripe webhook error: {e.message}",
            extra={
                "error": e.to_dict(),
                "correlation_id": correlation_id,
            },
        )
        raise HTTPException(status_code=400, detail=e.message)

    except Exception as e:
        logger.error(
            f"Unexpected error processing webhook: {e}",
            extra={
                "error": str(e),
                "correlation_id": correlation_id,
            },
        )
        raise HTTPException(status_code=500, detail="Internal server error")
