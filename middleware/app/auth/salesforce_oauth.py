"""
Salesforce OAuth 2.0 Authentication

Implements OAuth 2.0 client credentials flow with token caching in DynamoDB.
Supports automatic token refresh on expiration.
"""

from datetime import datetime, timedelta
from typing import Dict, Optional

import httpx

from app.config import settings
from app.services.dynamodb_service import dynamodb_service
from app.utils.exceptions import SalesforceAuthException
from app.utils.logging_config import get_logger
from app.utils.retry import retry_async

logger = get_logger(__name__)

# DynamoDB cache keys and namespace
OAUTH_NAMESPACE = "oauth"
OAUTH_TOKEN_KEY = "access_token"
OAUTH_INSTANCE_URL_KEY = "instance_url"
OAUTH_TOKEN_EXPIRY_KEY = "token_expiry"


class SalesforceOAuth:
    """Salesforce OAuth 2.0 client with token management"""

    def __init__(self):
        self.client_id = settings.salesforce_client_id
        self.client_secret = settings.salesforce_client_secret
        self.username = settings.salesforce_username
        self.password = settings.salesforce_password
        # self.security_token = settings.salesforce_security_token
        self.instance_url = settings.salesforce_instance_url
        self.token_url = settings.salesforce_token_url

        # HTTP client for OAuth requests
        self.http_client = httpx.AsyncClient(timeout=30.0)

    async def get_access_token(self, force_refresh: bool = False) -> str:
        """
        Get valid access token, using cache when available.

        Args:
            force_refresh: Force token refresh even if cached token exists

        Returns:
            Valid access token

        Raises:
            SalesforceAuthException: If authentication fails
        """
        # Check cache first unless force refresh is requested
        if not force_refresh:
            cached_token = await self._get_cached_token()
            if cached_token:
                logger.debug("Using cached Salesforce access token")
                return cached_token

        # Acquire new token
        logger.info("Acquiring new Salesforce access token")
        token_data = await self._authenticate()

        # Cache the new token
        await self._cache_token(token_data)

        return token_data["access_token"]

    async def get_instance_url(self) -> str:
        """
        Get Salesforce instance URL.

        Returns:
            Instance URL from cache or OAuth response

        Raises:
            SalesforceAuthException: If instance URL not available
        """
        # Try to get from cache first
        instance_url = await dynamodb_service.get(OAUTH_INSTANCE_URL_KEY, namespace=OAUTH_NAMESPACE)
        if instance_url:
            return instance_url

        # If not cached, authenticate to get it
        await self.get_access_token()
        instance_url = await dynamodb_service.get(OAUTH_INSTANCE_URL_KEY, namespace=OAUTH_NAMESPACE)

        if not instance_url:
            raise SalesforceAuthException("Failed to retrieve instance URL")

        return instance_url

    @retry_async(
        max_attempts=3,
        retryable_exceptions=(httpx.RequestError, httpx.HTTPStatusError),
    )
    async def _authenticate(self) -> Dict[str, str]:
        """
        Authenticate with Salesforce using OAuth 2.0 password flow.

        Returns:
            OAuth response with access_token and instance_url

        Raises:
            SalesforceAuthException: If authentication fails
        """
        try:
            # Check which authentication method to use based on available credentials
            if self.username and self.password:
                # Use password flow (username-password flow)
                # Note: Salesforce requires password + security token concatenated
                data = {
                    "grant_type": "password",
                    "client_id": self.client_id,
                    "client_secret": self.client_secret,
                    "username": self.username,
                    "password": self.password  # This should be password + security_token
                }
            else:
                # Fall back to client credentials (requires special setup in Salesforce)
                data = {
                    "grant_type": "client_credentials",
                    "client_id": self.client_id,
                    "client_secret": self.client_secret
                }

            logger.info(
                "Authenticating with Salesforce",
                extra={
                    "token_url": self.token_url,
                    "client_id": self.client_id[:10] + "..." if self.client_id else None,
                    "grant_type": data.get("grant_type"),
                },
            )

            # Make OAuth request
            response = await self.http_client.post(
                self.token_url,
                data=data,
                headers={"Content-Type": "application/x-www-form-urlencoded"},
            )

            response.raise_for_status()
            token_data = response.json()

            # Validate response
            if "access_token" not in token_data:
                raise SalesforceAuthException(
                    "Invalid OAuth response: missing access_token",
                    details={"response": token_data},
                )

            logger.info(
                "Successfully authenticated with Salesforce",
                extra={"instance_url": token_data.get("instance_url")},
            )

            return token_data

        except httpx.HTTPStatusError as e:
            error_data = {}
            try:
                error_data = e.response.json()
            except Exception:
                error_data = {"message": e.response.text}

            logger.error(
                f"Salesforce authentication failed with HTTP {e.response.status_code}",
                extra={
                    "status_code": e.response.status_code,
                    "error": error_data,
                },
            )

            raise SalesforceAuthException(
                f"Authentication failed: {error_data.get('error_description', str(e))}",
                details={
                    "status_code": e.response.status_code,
                    "error": error_data,
                },
            ) from e

        except httpx.RequestError as e:
            logger.error(f"Network error during authentication: {e}")
            raise SalesforceAuthException(
                f"Network error during authentication: {e}",
                details={"error": str(e)},
            ) from e

        except Exception as e:
            logger.error(f"Unexpected error during authentication: {e}")
            raise SalesforceAuthException(
                f"Unexpected authentication error: {e}",
                details={"error": str(e)},
            ) from e

    async def _get_cached_token(self) -> Optional[str]:
        """
        Get cached access token if valid.

        Returns:
            Cached access token or None if not available/expired
        """
        try:
            # Get token and expiry from cache
            token = await dynamodb_service.get(OAUTH_TOKEN_KEY, namespace=OAUTH_NAMESPACE)
            expiry_str = await dynamodb_service.get(OAUTH_TOKEN_EXPIRY_KEY, namespace=OAUTH_NAMESPACE)

            if not token or not expiry_str:
                return None

            # Check if token is expired
            expiry = datetime.fromisoformat(expiry_str)
            now = datetime.utcnow()

            # Add 5 minute buffer to avoid using token that's about to expire
            if now + timedelta(minutes=5) >= expiry:
                logger.debug("Cached token is expired or about to expire")
                return None

            return token

        except Exception as e:
            logger.warning(f"Error retrieving cached token: {e}")
            return None

    async def _cache_token(self, token_data: Dict[str, str]) -> None:
        """
        Cache access token and metadata in DynamoDB.

        Args:
            token_data: OAuth response data
        """
        try:
            access_token = token_data["access_token"]
            instance_url = token_data.get("instance_url", settings.salesforce_instance_url)

            # Calculate token expiry (Salesforce tokens typically valid for 2 hours)
            # We'll cache for 1.5 hours to be safe
            ttl = 5400  # 90 minutes

            # Store token
            await dynamodb_service.set(OAUTH_TOKEN_KEY, access_token, ttl_seconds=ttl, namespace=OAUTH_NAMESPACE)

            # Store instance URL
            await dynamodb_service.set(OAUTH_INSTANCE_URL_KEY, instance_url, ttl_seconds=ttl, namespace=OAUTH_NAMESPACE)

            # Store expiry timestamp
            expiry = datetime.utcnow() + timedelta(seconds=ttl)
            await dynamodb_service.set(
                OAUTH_TOKEN_EXPIRY_KEY,
                expiry.isoformat(),
                ttl_seconds=ttl,
                namespace=OAUTH_NAMESPACE,
            )

            logger.info(
                "Cached Salesforce access token",
                extra={
                    "ttl": ttl,
                    "expiry": expiry.isoformat(),
                },
            )

        except Exception as e:
            # Log error but don't fail - we can still use the token
            logger.warning(f"Failed to cache token: {e}")

    async def revoke_token(self, token: Optional[str] = None) -> None:
        """
        Revoke access token and clear cache.

        Args:
            token: Token to revoke (uses cached token if not provided)
        """
        try:
            # Get token if not provided
            if not token:
                token = await dynamodb_service.get(OAUTH_TOKEN_KEY, namespace=OAUTH_NAMESPACE)

            if token:
                # Revoke token with Salesforce
                revoke_url = f"{self.instance_url}/services/oauth2/revoke"
                await self.http_client.post(
                    revoke_url,
                    data={"token": token},
                )

                logger.info("Revoked Salesforce access token")

            # Clear cache
            await dynamodb_service.delete(OAUTH_TOKEN_KEY, namespace=OAUTH_NAMESPACE)
            await dynamodb_service.delete(OAUTH_INSTANCE_URL_KEY, namespace=OAUTH_NAMESPACE)
            await dynamodb_service.delete(OAUTH_TOKEN_EXPIRY_KEY, namespace=OAUTH_NAMESPACE)

        except Exception as e:
            logger.warning(f"Error revoking token: {e}")

    async def close(self) -> None:
        """Close HTTP client"""
        await self.http_client.aclose()


# Global OAuth client instance
salesforce_oauth = SalesforceOAuth()
