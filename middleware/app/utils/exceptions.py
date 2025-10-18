"""
Custom Exception Classes

Defines application-specific exceptions for better error handling and logging.
"""

from typing import Any, Dict, Optional


class MiddlewareException(Exception):
    """Base exception for all middleware errors"""

    def __init__(
        self,
        message: str,
        error_code: str = "MIDDLEWARE_ERROR",
        details: Optional[Dict[str, Any]] = None,
    ):
        self.message = message
        self.error_code = error_code
        self.details = details or {}
        super().__init__(self.message)

    def to_dict(self) -> Dict[str, Any]:
        """Convert exception to dictionary for logging/API responses"""
        return {
            "error_code": self.error_code,
            "message": self.message,
            "details": self.details,
        }


class StripeException(MiddlewareException):
    """Stripe API related errors"""

    def __init__(self, message: str, details: Optional[Dict[str, Any]] = None):
        super().__init__(message, error_code="STRIPE_ERROR", details=details)


class StripeSignatureException(StripeException):
    """Stripe webhook signature verification failed"""

    def __init__(self, message: str = "Invalid Stripe webhook signature"):
        super().__init__(message, details={"verification": "failed"})


class SalesforceException(MiddlewareException):
    """Salesforce API related errors"""

    def __init__(self, message: str, details: Optional[Dict[str, Any]] = None):
        super().__init__(message, error_code="SALESFORCE_ERROR", details=details)


class SalesforceAuthException(SalesforceException):
    """Salesforce OAuth authentication errors"""

    def __init__(self, message: str, details: Optional[Dict[str, Any]] = None):
        super().__init__(
            message,
            details={**(details or {}), "auth_failed": True},
        )


class SalesforceAPIException(SalesforceException):
    """Salesforce REST API call errors"""

    def __init__(
        self,
        message: str,
        status_code: Optional[int] = None,
        details: Optional[Dict[str, Any]] = None,
    ):
        details = details or {}
        if status_code:
            details["status_code"] = status_code
        super().__init__(message, details=details)


class QueueException(MiddlewareException):
    """SQS queue operation errors"""

    def __init__(self, message: str, details: Optional[Dict[str, Any]] = None):
        super().__init__(message, error_code="QUEUE_ERROR", details=details)


class CacheException(MiddlewareException):
    """Redis cache operation errors"""

    def __init__(self, message: str, details: Optional[Dict[str, Any]] = None):
        super().__init__(message, error_code="CACHE_ERROR", details=details)


class ConfigurationException(MiddlewareException):
    """Configuration or environment errors"""

    def __init__(self, message: str, details: Optional[Dict[str, Any]] = None):
        super().__init__(message, error_code="CONFIG_ERROR", details=details)


class RateLimitException(MiddlewareException):
    """Rate limit exceeded errors"""

    def __init__(
        self,
        message: str = "Rate limit exceeded",
        retry_after: Optional[int] = None,
        details: Optional[Dict[str, Any]] = None,
    ):
        details = details or {}
        if retry_after:
            details["retry_after"] = retry_after
        super().__init__(message, error_code="RATE_LIMIT_EXCEEDED", details=details)


class ValidationException(MiddlewareException):
    """Data validation errors"""

    def __init__(self, message: str, details: Optional[Dict[str, Any]] = None):
        super().__init__(message, error_code="VALIDATION_ERROR", details=details)


class RetryableException(MiddlewareException):
    """Exception that can be retried"""

    def __init__(
        self,
        message: str,
        retry_count: int = 0,
        max_retries: int = 5,
        details: Optional[Dict[str, Any]] = None,
    ):
        details = details or {}
        details.update({"retry_count": retry_count, "max_retries": max_retries})
        super().__init__(message, error_code="RETRYABLE_ERROR", details=details)

    @property
    def should_retry(self) -> bool:
        """Check if operation should be retried"""
        return self.details.get("retry_count", 0) < self.details.get("max_retries", 5)
