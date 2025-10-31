"""
Application Configuration Management

Loads configuration from environment variables and AWS Secrets Manager.
Supports both development (env vars) and production (Secrets Manager) modes.
Auto-detects AWS Lambda runtime environment.
"""

import json
import os
from functools import lru_cache
from typing import Any, Dict, List, Optional

import boto3
from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Application settings with validation"""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    # Environment
    environment: str = Field(default="development", description="Environment name")

    # Application
    app_name: str = Field(default="Salesforce-Stripe Middleware")
    app_version: str = Field(default="1.0.0")
    log_level: str = Field(default="INFO")

    # FastAPI
    host: str = Field(default="0.0.0.0")
    port: int = Field(default=8000)
    workers: int = Field(default=4)

    # Stripe
    stripe_api_key: Optional[str] = Field(default=None, description="Stripe secret API key")
    stripe_webhook_secret: Optional[str] = Field(default=None, description="Stripe webhook signing secret")
    stripe_api_version: str = Field(default="2024-10-28")

    # Salesforce OAuth
    salesforce_client_id: Optional[str] = Field(default=None, description="Salesforce Connected App Client ID")
    salesforce_client_secret: Optional[str] = Field(
        default=None, description="Salesforce Connected App Client Secret"
    )
    salesforce_username: Optional[str] = Field(
        default=None, description="Salesforce integration user username"
    )
    salesforce_password: Optional[str] = Field(
        default=None, description="Salesforce integration user password"
    )
    salesforce_security_token: Optional[str] = Field(
        default=None, description="Salesforce security token"
    )
    salesforce_instance_url: str = Field(
        default="https://login.salesforce.com", description="Salesforce instance URL"
    )
    salesforce_api_version: str = Field(default="v63.0")

    # AWS
    aws_region: str = Field(default="us-east-1")
    aws_access_key_id: Optional[str] = Field(default=None)
    aws_secret_access_key: Optional[str] = Field(default=None)
    aws_endpoint_url: Optional[str] = Field(default=None)

    # SQS
    sqs_queue_url: str = Field(description="SQS queue URL for webhook events")
    low_priority_queue_url: str = Field(description="SQS queue URL for low-priority events (Bulk API)")
    sqs_queue_name: str = Field(default="stripe-webhook-events")
    sqs_visibility_timeout: int = Field(default=300)
    sqs_max_messages: int = Field(default=10)
    sqs_wait_time_seconds: int = Field(default=20)

    # DynamoDB (replaces Redis for token caching)
    dynamodb_table_name: str = Field(default="salesforce-stripe-cache")
    dynamodb_token_ttl: int = Field(
        default=3600, description="Token TTL in seconds (1 hour)"
    )

    # Legacy Redis support (for local development if needed)
    redis_host: Optional[str] = Field(default=None)
    redis_port: Optional[int] = Field(default=None)
    use_redis: bool = Field(default=False, description="Use Redis instead of DynamoDB")

    # AWS Secrets Manager
    use_secrets_manager: bool = Field(default=False)
    secrets_manager_secret_name: str = Field(
        default="salesforce-stripe-middleware/prod"
    )

    # Retry Configuration
    max_retry_attempts: int = Field(default=5)
    retry_backoff_base: int = Field(default=2)
    retry_backoff_max: int = Field(default=32)

    # Rate Limiting
    rate_limit_window: int = Field(default=60, description="Rate limit window in seconds")
    rate_limit_max_calls: int = Field(default=100, description="Max API calls per window")

    # Monitoring
    enable_metrics: bool = Field(default=True)
    metrics_port: int = Field(default=9090)

    # CORS
    cors_origins: List[str] = Field(default=["http://localhost:3000"])
    cors_allow_credentials: bool = Field(default=True)
    cors_allow_methods: List[str] = Field(default=["GET", "POST"])
    cors_allow_headers: List[str] = Field(default=["*"])

    @field_validator("log_level")
    @classmethod
    def validate_log_level(cls, v: str) -> str:
        """Validate log level"""
        valid_levels = ["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"]
        v_upper = v.upper()
        if v_upper not in valid_levels:
            raise ValueError(f"Log level must be one of {valid_levels}")
        return v_upper

    @field_validator("environment")
    @classmethod
    def validate_environment(cls, v: str) -> str:
        """Validate environment"""
        valid_envs = ["development", "staging", "production"]
        v_lower = v.lower()
        if v_lower not in valid_envs:
            raise ValueError(f"Environment must be one of {valid_envs}")
        return v_lower

    @property
    def is_production(self) -> bool:
        """Check if running in production"""
        return self.environment == "production"

    @property
    def is_development(self) -> bool:
        """Check if running in development"""
        return self.environment == "development"

    @property
    def is_lambda(self) -> bool:
        """Check if running in AWS Lambda environment"""
        return bool(os.getenv("AWS_LAMBDA_FUNCTION_NAME"))

    @property
    def lambda_function_name(self) -> Optional[str]:
        """Get Lambda function name if running in Lambda"""
        return os.getenv("AWS_LAMBDA_FUNCTION_NAME")

    @property
    def lambda_request_id(self) -> Optional[str]:
        """Get Lambda request ID if available"""
        return os.getenv("AWS_REQUEST_ID")

    @property
    def salesforce_token_url(self) -> str:
        """Get Salesforce OAuth token endpoint"""
        return f"{self.salesforce_instance_url}/services/oauth2/token"

    @property
    def salesforce_api_base_url(self) -> str:
        """Get Salesforce REST API base URL"""
        # This will be updated with the actual instance URL after OAuth
        return f"{self.salesforce_instance_url}/services/data/{self.salesforce_api_version}"

    @property
    def redis_url(self) -> Optional[str]:
        """Get Redis connection URL (legacy support)"""
        if not self.use_redis or not self.redis_host:
            return None
        protocol = "rediss" if self.redis_ssl else "redis"
        auth = f":{self.redis_password}@" if self.redis_password else ""
        return f"{protocol}://{auth}{self.redis_host}:{self.redis_port}/0"

    def validate_required_secrets(self) -> None:
        """
        Validate that required secrets are present.
        Raises ValueError if any required secrets are missing.
        """
        missing = []

        if not self.stripe_api_key:
            missing.append("stripe_api_key")
        if not self.stripe_webhook_secret:
            missing.append("stripe_webhook_secret")
        if not self.salesforce_client_id:
            missing.append("salesforce_client_id")
        if not self.salesforce_client_secret:
            missing.append("salesforce_client_secret")

        if missing:
            raise ValueError(
                f"Missing required configuration: {', '.join(missing)}. "
                f"In Lambda, ensure ARN environment variables are set. "
                f"Locally, ensure .env file or environment variables are configured."
            )


class SecretsManager:
    """AWS Secrets Manager client for retrieving production secrets"""

    def __init__(self, region: str, secret_name: str):
        self.client = boto3.client("secretsmanager", region_name=region)
        self.secret_name = secret_name

    def get_secrets(self) -> Dict[str, Any]:
        """Retrieve secrets from AWS Secrets Manager"""
        try:
            response = self.client.get_secret_value(SecretId=self.secret_name)
            secret_string = response.get("SecretString")
            if secret_string:
                return json.loads(secret_string)
            return {}
        except Exception as e:
            raise RuntimeError(f"Failed to retrieve secrets from Secrets Manager: {e}")


def _fetch_secret_by_arn(arn: str, region: str) -> str:
    """
    Fetch a secret value from AWS Secrets Manager using ARN.

    Args:
        arn: The ARN of the secret
        region: AWS region

    Returns:
        The secret value as a string
    """
    try:
        client = boto3.client("secretsmanager", region_name=region)
        response = client.get_secret_value(SecretId=arn)
        return response.get("SecretString", "")
    except Exception as e:
        raise RuntimeError(f"Failed to retrieve secret from ARN {arn}: {e}")


@lru_cache()
def get_settings() -> Settings:
    """
    Get application settings (cached).
    Loads from AWS Secrets Manager in production, environment variables otherwise.

    In Lambda environment, automatically fetches secrets from Secrets Manager
    using ARN environment variables (STRIPE_API_KEY_ARN, etc.)
    """
    # Check if running in Lambda with ARN-based secrets
    is_lambda = bool(os.getenv("AWS_LAMBDA_FUNCTION_NAME"))
    stripe_api_key_arn = os.getenv("STRIPE_API_KEY_ARN")
    stripe_webhook_secret_arn = os.getenv("STRIPE_WEBHOOK_SECRET_ARN")
    salesforce_client_secret_arn = os.getenv("SALESFORCE_CLIENT_SECRET_ARN")

    # If in Lambda with ARNs, fetch secrets and inject as env vars before Settings init
    if is_lambda and (stripe_api_key_arn or stripe_webhook_secret_arn or salesforce_client_secret_arn):
        region = os.getenv("AWS_REGION", "us-east-1")

        try:
            # Fetch Stripe API key
            if stripe_api_key_arn and not os.getenv("STRIPE_API_KEY"):
                os.environ["STRIPE_API_KEY"] = _fetch_secret_by_arn(stripe_api_key_arn, region)

            # Fetch Stripe webhook secret
            if stripe_webhook_secret_arn and not os.getenv("STRIPE_WEBHOOK_SECRET"):
                os.environ["STRIPE_WEBHOOK_SECRET"] = _fetch_secret_by_arn(stripe_webhook_secret_arn, region)

            # Fetch Salesforce credentials (stored as JSON)
            if salesforce_client_secret_arn:
                sf_secret_str = _fetch_secret_by_arn(salesforce_client_secret_arn, region)
                sf_secrets = json.loads(sf_secret_str)

                if not os.getenv("SALESFORCE_CLIENT_ID"):
                    os.environ["SALESFORCE_CLIENT_ID"] = sf_secrets.get("client_id", "")
                if not os.getenv("SALESFORCE_CLIENT_SECRET"):
                    os.environ["SALESFORCE_CLIENT_SECRET"] = sf_secrets.get("client_secret", "")
                if not os.getenv("SALESFORCE_INSTANCE_URL"):
                    # Only override if not already set by template.yaml
                    instance_url = sf_secrets.get("instance_url")
                    if instance_url:
                        os.environ["SALESFORCE_INSTANCE_URL"] = instance_url

        except Exception as e:
            # Log error but continue - Settings validation will catch missing required values
            print(f"Error loading secrets from Secrets Manager: {e}")

    # Initialize settings (will now use the injected env vars in Lambda)
    settings = Settings()

    # Legacy: Support for use_secrets_manager flag with single secret containing all values
    if settings.use_secrets_manager and not is_lambda:
        try:
            secrets_manager = SecretsManager(
                region=settings.aws_region,
                secret_name=settings.secrets_manager_secret_name,
            )
            secrets = secrets_manager.get_secrets()

            # Override settings with secrets from Secrets Manager
            for key, value in secrets.items():
                if hasattr(settings, key.lower()):
                    setattr(settings, key.lower(), value)

        except Exception as e:
            # Log error but don't fail - fall back to environment variables
            print(f"Warning: Failed to load secrets from Secrets Manager: {e}")

    # Validate that all required secrets are present
    settings.validate_required_secrets()

    return settings


# Export singleton instance
settings = get_settings()
