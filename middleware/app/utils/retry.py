"""
Retry Utilities

Implements exponential backoff retry logic for resilient API calls.
"""

import asyncio
from functools import wraps
from typing import Any, Callable, Optional, Tuple, Type

from app.config import settings
from app.utils.exceptions import RetryableException
from app.utils.logging_config import get_logger

logger = get_logger(__name__)


def calculate_backoff(
    attempt: int,
    base: int = 2,
    max_backoff: int = 32,
) -> float:
    """
    Calculate exponential backoff delay.

    Args:
        attempt: Current retry attempt (0-indexed)
        base: Base for exponential calculation
        max_backoff: Maximum backoff time in seconds

    Returns:
        Backoff delay in seconds
    """
    backoff = min(base**attempt, max_backoff)
    return float(backoff)


def retry_async(
    max_attempts: Optional[int] = None,
    backoff_base: Optional[int] = None,
    backoff_max: Optional[int] = None,
    retryable_exceptions: Tuple[Type[Exception], ...] = (Exception,),
    on_retry: Optional[Callable[[Exception, int], None]] = None,
) -> Callable:
    """
    Decorator for async functions with exponential backoff retry logic.

    Args:
        max_attempts: Maximum number of retry attempts (default from config)
        backoff_base: Base for exponential backoff (default from config)
        backoff_max: Maximum backoff time in seconds (default from config)
        retryable_exceptions: Tuple of exception types that should trigger retry
        on_retry: Optional callback function called on each retry

    Example:
        @retry_async(max_attempts=3, retryable_exceptions=(httpx.HTTPError,))
        async def fetch_data():
            response = await client.get("https://api.example.com/data")
            return response.json()
    """
    _max_attempts = max_attempts or settings.max_retry_attempts
    _backoff_base = backoff_base or settings.retry_backoff_base
    _backoff_max = backoff_max or settings.retry_backoff_max

    def decorator(func: Callable) -> Callable:
        @wraps(func)
        async def wrapper(*args: Any, **kwargs: Any) -> Any:
            last_exception: Optional[Exception] = None

            for attempt in range(_max_attempts):
                try:
                    result = await func(*args, **kwargs)
                    if attempt > 0:
                        logger.info(
                            f"Function {func.__name__} succeeded after {attempt} retries"
                        )
                    return result

                except retryable_exceptions as e:
                    last_exception = e

                    if attempt < _max_attempts - 1:
                        backoff_time = calculate_backoff(
                            attempt, _backoff_base, _backoff_max
                        )

                        logger.warning(
                            f"Attempt {attempt + 1}/{_max_attempts} failed for {func.__name__}: {str(e)}. "
                            f"Retrying in {backoff_time}s...",
                            extra={
                                "function": func.__name__,
                                "attempt": attempt + 1,
                                "max_attempts": _max_attempts,
                                "backoff_time": backoff_time,
                                "error": str(e),
                            },
                        )

                        # Call on_retry callback if provided
                        if on_retry:
                            on_retry(e, attempt)

                        await asyncio.sleep(backoff_time)
                    else:
                        logger.error(
                            f"All {_max_attempts} attempts failed for {func.__name__}",
                            extra={
                                "function": func.__name__,
                                "max_attempts": _max_attempts,
                                "error": str(e),
                            },
                        )

            # If we've exhausted all retries, raise the last exception
            if last_exception:
                if isinstance(last_exception, RetryableException):
                    last_exception.details["retry_count"] = _max_attempts
                raise last_exception

            # This should never happen, but just in case
            raise RuntimeError(f"Unexpected error in retry logic for {func.__name__}")

        return wrapper

    return decorator


def retry_sync(
    max_attempts: Optional[int] = None,
    backoff_base: Optional[int] = None,
    backoff_max: Optional[int] = None,
    retryable_exceptions: Tuple[Type[Exception], ...] = (Exception,),
    on_retry: Optional[Callable[[Exception, int], None]] = None,
) -> Callable:
    """
    Decorator for synchronous functions with exponential backoff retry logic.

    Args:
        max_attempts: Maximum number of retry attempts (default from config)
        backoff_base: Base for exponential backoff (default from config)
        backoff_max: Maximum backoff time in seconds (default from config)
        retryable_exceptions: Tuple of exception types that should trigger retry
        on_retry: Optional callback function called on each retry

    Example:
        @retry_sync(max_attempts=3, retryable_exceptions=(requests.RequestException,))
        def fetch_data():
            response = requests.get("https://api.example.com/data")
            return response.json()
    """
    _max_attempts = max_attempts or settings.max_retry_attempts
    _backoff_base = backoff_base or settings.retry_backoff_base
    _backoff_max = backoff_max or settings.retry_backoff_max

    def decorator(func: Callable) -> Callable:
        @wraps(func)
        def wrapper(*args: Any, **kwargs: Any) -> Any:
            import time

            last_exception: Optional[Exception] = None

            for attempt in range(_max_attempts):
                try:
                    result = func(*args, **kwargs)
                    if attempt > 0:
                        logger.info(
                            f"Function {func.__name__} succeeded after {attempt} retries"
                        )
                    return result

                except retryable_exceptions as e:
                    last_exception = e

                    if attempt < _max_attempts - 1:
                        backoff_time = calculate_backoff(
                            attempt, _backoff_base, _backoff_max
                        )

                        logger.warning(
                            f"Attempt {attempt + 1}/{_max_attempts} failed for {func.__name__}: {str(e)}. "
                            f"Retrying in {backoff_time}s...",
                            extra={
                                "function": func.__name__,
                                "attempt": attempt + 1,
                                "max_attempts": _max_attempts,
                                "backoff_time": backoff_time,
                                "error": str(e),
                            },
                        )

                        # Call on_retry callback if provided
                        if on_retry:
                            on_retry(e, attempt)

                        time.sleep(backoff_time)
                    else:
                        logger.error(
                            f"All {_max_attempts} attempts failed for {func.__name__}",
                            extra={
                                "function": func.__name__,
                                "max_attempts": _max_attempts,
                                "error": str(e),
                            },
                        )

            # If we've exhausted all retries, raise the last exception
            if last_exception:
                if isinstance(last_exception, RetryableException):
                    last_exception.details["retry_count"] = _max_attempts
                raise last_exception

            # This should never happen, but just in case
            raise RuntimeError(f"Unexpected error in retry logic for {func.__name__}")

        return wrapper

    return decorator
