"""
Application Configuration Management

Loads configuration from environment variables and AWS Secrets Manager.
Supports both development (env vars) and production (Secrets Manager) modes.
"""

import json
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
    stripe_api_key: str = Field(description="Stripe secret API key")
    stripe_webhook_secret: str = Field(description="Stripe webhook signing secret")
    stripe_api_version: str = Field(default="2024-10-28")

    # Salesforce OAuth
    salesforce_client_id: str = Field(description="Salesforce Connected App Client ID")
    salesforce_client_secret: str = Field(
        description="Salesforce Connected App Client Secret"
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
    sqs_queue_name: str = Field(default="stripe-webhook-events")
    sqs_visibility_timeout: int = Field(default=300)
    sqs_max_messages: int = Field(default=10)
    sqs_wait_time_seconds: int = Field(default=20)

    # Redis
    redis_host: str = Field(default="localhost")
    redis_port: int = Field(default=6379)
    redis_db: int = Field(default=0)
    redis_password: Optional[str] = Field(default=None)
    redis_ssl: bool = Field(default=False)
    redis_token_ttl: int = Field(
        default=3600, description="Token TTL in seconds (1 hour)"
    )

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
    def salesforce_token_url(self) -> str:
        """Get Salesforce OAuth token endpoint"""
        return f"{self.salesforce_instance_url}/services/oauth2/token"

    @property
    def salesforce_api_base_url(self) -> str:
        """Get Salesforce REST API base URL"""
        # This will be updated with the actual instance URL after OAuth
        return f"{self.salesforce_instance_url}/services/data/{self.salesforce_api_version}"

    @property
    def redis_url(self) -> str:
        """Get Redis connection URL"""
        protocol = "rediss" if self.redis_ssl else "redis"
        auth = f":{self.redis_password}@" if self.redis_password else ""
        return f"{protocol}://{auth}{self.redis_host}:{self.redis_port}/{self.redis_db}"


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


@lru_cache()
def get_settings() -> Settings:
    """
    Get application settings (cached).
    Loads from AWS Secrets Manager in production, environment variables otherwise.
    """
    settings = Settings()

    if settings.use_secrets_manager:
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

    return settings


# Export singleton instance
settings = get_settings()
