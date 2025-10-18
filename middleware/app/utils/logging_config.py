"""
Structured Logging Configuration

Configures JSON-formatted logging with correlation IDs for request tracing.
"""

import logging
import sys
import uuid
from contextvars import ContextVar
from typing import Any, Dict, Optional

from pythonjsonlogger import jsonlogger

# Context variable for correlation ID
correlation_id_var: ContextVar[Optional[str]] = ContextVar(
    "correlation_id", default=None
)


class CorrelationIdFilter(logging.Filter):
    """Add correlation ID to log records"""

    def filter(self, record: logging.LogRecord) -> bool:
        correlation_id = correlation_id_var.get()
        record.correlation_id = correlation_id or "N/A"
        return True


class CustomJsonFormatter(jsonlogger.JsonFormatter):
    """
    Custom JSON formatter for structured logging.
    Includes correlation ID, timestamp, and other metadata.
    """

    def add_fields(
        self,
        log_record: Dict[str, Any],
        record: logging.LogRecord,
        message_dict: Dict[str, Any],
    ) -> None:
        """Add custom fields to log record"""
        super().add_fields(log_record, record, message_dict)

        # Add standard fields
        log_record["timestamp"] = self.formatTime(record, self.datefmt)
        log_record["level"] = record.levelname
        log_record["logger"] = record.name
        log_record["module"] = record.module
        log_record["function"] = record.funcName
        log_record["line"] = record.lineno

        # Add correlation ID
        if hasattr(record, "correlation_id"):
            log_record["correlation_id"] = record.correlation_id

        # Add exception info if present
        if record.exc_info:
            log_record["exception"] = self.formatException(record.exc_info)


def setup_logging(log_level: str = "INFO") -> logging.Logger:
    """
    Configure application logging with JSON formatting.

    Args:
        log_level: Logging level (DEBUG, INFO, WARNING, ERROR, CRITICAL)

    Returns:
        Configured logger instance
    """
    # Create logger
    logger = logging.getLogger("middleware")
    logger.setLevel(log_level)
    logger.propagate = False

    # Remove existing handlers
    logger.handlers.clear()

    # Create console handler with JSON formatter
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setLevel(log_level)

    # Create JSON formatter
    formatter = CustomJsonFormatter(
        "%(timestamp)s %(level)s %(name)s %(message)s",
        datefmt="%Y-%m-%dT%H:%M:%S.%fZ",
    )
    console_handler.setFormatter(formatter)

    # Add correlation ID filter
    console_handler.addFilter(CorrelationIdFilter())

    # Add handler to logger
    logger.addHandler(console_handler)

    return logger


def get_logger(name: str) -> logging.Logger:
    """
    Get a logger instance with the specified name.

    Args:
        name: Logger name (typically module name)

    Returns:
        Logger instance
    """
    return logging.getLogger(f"middleware.{name}")


def set_correlation_id(correlation_id: Optional[str] = None) -> str:
    """
    Set correlation ID for the current context.
    Generates a new UUID if not provided.

    Args:
        correlation_id: Optional correlation ID

    Returns:
        The correlation ID that was set
    """
    if correlation_id is None:
        correlation_id = str(uuid.uuid4())
    correlation_id_var.set(correlation_id)
    return correlation_id


def get_correlation_id() -> Optional[str]:
    """
    Get the current correlation ID.

    Returns:
        Current correlation ID or None
    """
    return correlation_id_var.get()


def clear_correlation_id() -> None:
    """Clear the correlation ID for the current context"""
    correlation_id_var.set(None)


# Initialize default logger
default_logger = setup_logging()
