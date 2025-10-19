"""
FastAPI Middleware Application

Main application entry point for Salesforce-Stripe integration middleware.
Provides webhook handling, event processing, and Salesforce synchronization.
"""

from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.config import settings
from app.routes import health, webhook
from app.services.redis_service import redis_service
from app.utils.exceptions import MiddlewareException
from app.utils.logging_config import (
    get_logger,
    set_correlation_id,
    setup_logging,
)

# Setup logging
setup_logging(log_level=settings.log_level)
logger = get_logger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Application lifespan context manager.
    Handles startup and shutdown events.
    """
    # Startup
    logger.info(
        f"Starting {settings.app_name} v{settings.app_version}",
        extra={"environment": settings.environment},
    )

    # Initialize Redis connection
    try:
        await redis_service.connect()
        logger.info("Redis connection established")
    except Exception as e:
        logger.error(f"Failed to connect to Redis: {e}")
        # Continue anyway - app can run without Redis but with degraded performance

    logger.info("Application startup complete")

    yield

    # Shutdown
    logger.info("Shutting down application...")

    # Close Redis connection
    try:
        await redis_service.disconnect()
        logger.info("Redis connection closed")
    except Exception as e:
        logger.warning(f"Error closing Redis connection: {e}")

    logger.info("Application shutdown complete")


# Create FastAPI application
app = FastAPI(
    title=settings.app_name,
    version=settings.app_version,
    description="Middleware for Salesforce-Stripe payment processing integration",
    docs_url="/docs" if settings.is_development else None,
    redoc_url="/redoc" if settings.is_development else None,
    lifespan=lifespan,
)


# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=settings.cors_allow_credentials,
    allow_methods=settings.cors_allow_methods,
    allow_headers=settings.cors_allow_headers,
)


# Correlation ID middleware
@app.middleware("http")
async def correlation_id_middleware(request: Request, call_next):
    """Add correlation ID to all requests for tracing"""
    # Get or generate correlation ID
    correlation_id = request.headers.get("X-Correlation-ID")
    if not correlation_id:
        correlation_id = set_correlation_id()
    else:
        set_correlation_id(correlation_id)

    # Process request
    response = await call_next(request)

    # Add correlation ID to response headers
    response.headers["X-Correlation-ID"] = correlation_id

    return response


# Exception handlers
@app.exception_handler(MiddlewareException)
async def middleware_exception_handler(request: Request, exc: MiddlewareException):
    """Handle custom middleware exceptions"""
    logger.error(
        f"Middleware exception: {exc.message}",
        extra={"error": exc.to_dict()},
    )

    return JSONResponse(
        status_code=500,
        content={
            "error": exc.error_code,
            "message": exc.message,
            "details": exc.details,
        },
    )


@app.exception_handler(Exception)
async def general_exception_handler(request: Request, exc: Exception):
    """Handle unexpected exceptions"""
    logger.error(
        f"Unexpected exception: {exc}",
        extra={"error": str(exc), "type": type(exc).__name__},
    )

    return JSONResponse(
        status_code=500,
        content={
            "error": "INTERNAL_ERROR",
            "message": "An unexpected error occurred",
        },
    )


# Include routers
app.include_router(webhook.router)
app.include_router(health.router)


# Root endpoint
@app.get("/")
async def root():
    """Root endpoint with API information"""
    return {
        "name": settings.app_name,
        "version": settings.app_version,
        "environment": settings.environment,
        "docs_url": "/docs" if settings.is_development else None,
    }


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "app.main:app",
        host=settings.host,
        port=settings.port,
        reload=settings.is_development,
        log_level=settings.log_level.lower(),
    )
