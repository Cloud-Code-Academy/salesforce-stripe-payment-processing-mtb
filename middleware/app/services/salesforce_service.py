"""
Salesforce REST API Service

Wrapper for Salesforce REST API operations with OAuth authentication,
error handling, and retry logic.
"""

from typing import Any, Dict, List, Optional

import httpx

from app.auth.salesforce_oauth import salesforce_oauth
from app.config import settings
from app.models.salesforce_records import (
    SalesforceCustomer,
    SalesforcePaymentTransaction,
    SalesforceSubscription,
)
from app.services.rate_limiter import get_rate_limiter
from app.utils.exceptions import RateLimitException, SalesforceAPIException, SalesforceAuthException
from app.utils.logging_config import get_logger
from app.utils.retry import retry_async

logger = get_logger(__name__)


class SalesforceService:
    """
    Service for interacting with Salesforce REST API.
    
    Includes rate limiting to prevent API limit violations.
    """
    
    def __init__(self):
        self.http_client = httpx.AsyncClient(timeout=30.0)
        self.api_version = settings.salesforce_api_version
        self.rate_limiter = get_rate_limiter()
    
    async def _get_api_url(self, endpoint: str = "") -> str:
        """
        Get full API URL with instance URL.

        Args:
            endpoint: API endpoint path

        Returns:
            Full API URL
        """
        instance_url = await salesforce_oauth.get_instance_url()
        base_url = f"{instance_url}/services/data/{self.api_version}"
        return f"{base_url}/{endpoint.lstrip('/')}" if endpoint else base_url

    async def _get_headers(self) -> Dict[str, str]:
        """
        Get HTTP headers with OAuth token.

        Returns:
            Headers dictionary with Authorization
        """
        access_token = await salesforce_oauth.get_access_token()
        return {
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        }

    @retry_async(
        max_attempts=3,
        retryable_exceptions=(httpx.RequestError, SalesforceAuthException),
    )
    async def _request(
        self,
        method: str,
        endpoint: str,
        json_data: Optional[Dict[str, Any]] = None,
        params: Optional[Dict[str, Any]] = None,
    ) -> Any:
        """
        Make authenticated HTTP request to Salesforce API.

        Args:
            method: HTTP method (GET, POST, PATCH, DELETE)
            endpoint: API endpoint
            json_data: Optional JSON body
            params: Optional query parameters

        Returns:
            Response data

        Raises:
            SalesforceAPIException: If request fails
            SalesforceAuthException: If authentication fails
        """
        url = await self._get_api_url(endpoint)
        headers = await self._get_headers()

        try:
            response = await self.http_client.request(
                method=method,
                url=url,
                headers=headers,
                json=json_data,
                params=params,
            )

            # Handle authentication errors
            if response.status_code == 401:
                logger.warning("Access token expired, refreshing...")
                # Force token refresh and retry once
                await salesforce_oauth.get_access_token(force_refresh=True)
                headers = await self._get_headers()
                response = await self.http_client.request(
                    method=method,
                    url=url,
                    headers=headers,
                    json=json_data,
                    params=params,
                )

            # Check for errors
            if response.status_code >= 400:
                error_data = {}
                try:
                    error_data = response.json()
                except Exception:
                    error_data = {"message": response.text}

                logger.error(
                    f"Salesforce API error: {response.status_code}",
                    extra={
                        "status_code": response.status_code,
                        "endpoint": endpoint,
                        "error": error_data,
                    },
                )

                raise SalesforceAPIException(
                    f"Salesforce API error: {error_data}",
                    status_code=response.status_code,
                    details={"error": error_data, "endpoint": endpoint},
                )

            # Return JSON response for successful requests
            if response.status_code != 204:  # No Content
                return response.json()

            return None

        except httpx.RequestError as e:
            logger.error(f"Network error calling Salesforce API: {e}")
            raise SalesforceAPIException(
                f"Network error: {e}",
                details={"error": str(e), "endpoint": endpoint},
            ) from e

    async def _make_api_call(
        self,
        method: str,
        endpoint: str,
        data: Optional[Dict[str, Any]] = None,
        params: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """
        Make rate-limited API call to Salesforce.
        
        Acquires rate limit permission before making the call. If rate limit
        is exceeded, raises RateLimitException with retry_after duration.
        
        Args:
            method: HTTP method (GET, POST, PATCH, DELETE)
            endpoint: API endpoint path (e.g., '/sobjects/Account')
            data: Request body data for POST/PATCH
            params: Query parameters for GET
            
        Returns:
            API response as dictionary
            
        Raises:
            RateLimitException: If rate limit is exceeded
            SalesforceAPIException: If API call fails
        """
        # Acquire rate limit permission
        try:
            rate_limit_result = await self.rate_limiter.acquire()
            
            logger.debug(
                "Rate limit acquired for Salesforce API call",
                extra={
                    "current_usage": rate_limit_result["current_usage"],
                    "limits": rate_limit_result["limits"]
                }
            )
            
        except RateLimitException as e:
            logger.warning(
                f"Rate limit exceeded: {e.tier}",
                extra={
                    "tier": e.tier,
                    "retry_after": e.retry_after,
                    "current_usage": e.current_usage
                }
            )
            raise
        
        # Make the actual API call
        try:
            url = await self._get_api_url(endpoint)
            headers = await self._get_headers()

            response = await self.http_client.request(
                method=method,
                url=url,
                headers=headers,
                json=data,
                params=params,
            )

            # Handle authentication errors
            if response.status_code == 401:
                logger.warning("Access token expired, refreshing...")
                # Force token refresh and retry once
                await salesforce_oauth.get_access_token(force_refresh=True)
                headers = await self._get_headers()
                response = await self.http_client.request(
                    method=method,
                    url=url,
                    headers=headers,
                    json=data,
                    params=params,
                )

            # Check for errors
            if response.status_code >= 400:
                error_data = {}
                try:
                    error_data = response.json()
                except Exception:
                    error_data = {"message": response.text}

                logger.error(
                    f"Salesforce API error: {response.status_code}",
                    extra={
                        "status_code": response.status_code,
                        "endpoint": endpoint,
                        "error": error_data,
                    },
                )

                raise SalesforceAPIException(
                    f"Salesforce API error: {error_data}",
                    status_code=response.status_code,
                    details={"error": error_data, "endpoint": endpoint},
                )

            # Return JSON response for successful requests
            if response.status_code != 204:  # No Content
                return response.json()

            return None

        except httpx.RequestError as e:
            logger.error(f"Network error calling Salesforce API: {e}")
            raise SalesforceAPIException(
                f"Network error: {e}",
                details={"error": str(e), "endpoint": endpoint},
            ) from e

    async def upsert_record(
        self,
        sobject_type: str,
        external_id_field: str,
        external_id_value: str,
        record_data: Dict[str, Any],
    ) -> Dict[str, Any]:
        """
        Upsert a record using external ID.

        Args:
            sobject_type: Salesforce object type (e.g., 'Stripe_Customer__c')
            external_id_field: External ID field name
            external_id_value: External ID value
            record_data: Record field values

        Returns:
            Upsert response

        Raises:
            SalesforceAPIException: If upsert fails
        """
        endpoint = f"sobjects/{sobject_type}/{external_id_field}/{external_id_value}"

        logger.info(
            f"Upserting {sobject_type} record",
            extra={
                "sobject_type": sobject_type,
                "external_id": external_id_value,
            },
        )

        response = await self._request("PATCH", endpoint, json_data=record_data)

        logger.info(
            f"Successfully upserted {sobject_type}",
            extra={
                "sobject_type": sobject_type,
                "external_id": external_id_value,
                "response": response,
            },
        )

        return response

    async def upsert_customer(self, customer_data: SalesforceCustomer) -> Dict[str, Any]:
        """
        Upsert Stripe customer record.

        Args:
            customer_data: Customer data model

        Returns:
            Upsert response
        """
        return await self.upsert_record(
            sobject_type="Stripe_Customer__c",
            external_id_field="Stripe_Customer_ID__c",
            external_id_value=customer_data.Stripe_Customer_ID__c,
            record_data=customer_data.model_dump(exclude_none=True),
        )

    async def upsert_subscription(
        self, subscription_data: SalesforceSubscription
    ) -> Dict[str, Any]:
        """
        Upsert subscription record.

        Args:
            subscription_data: Subscription data model

        Returns:
            Upsert response
        """
        return await self.upsert_record(
            sobject_type="Stripe_Subscription__c",
            external_id_field="Stripe_Subscription_ID__c",
            external_id_value=subscription_data.Stripe_Subscription_ID__c,
            record_data=subscription_data.model_dump(exclude_none=True),
        )

    async def upsert_payment_transaction(
        self, transaction_data: SalesforcePaymentTransaction
    ) -> Dict[str, Any]:
        """
        Upsert payment transaction record.

        Args:
            transaction_data: Transaction data model

        Returns:
            Upsert response
        """
        return await self.upsert_record(
            sobject_type="Payment_Transaction__c",
            external_id_field="Stripe_Payment_Intent_ID__c",
            external_id_value=transaction_data.Stripe_Payment_Intent_ID__c,
            record_data=transaction_data.model_dump(exclude_none=True),
        )

    async def query(self, soql: str) -> Dict[str, Any]:
        """
        Execute SOQL query.

        Args:
            soql: SOQL query string

        Returns:
            Query results

        Raises:
            SalesforceAPIException: If query fails
        """
        logger.debug(f"Executing SOQL query: {soql}")

        response = await self._request("GET", "query", params={"q": soql})

        logger.info(
            f"Query returned {response.get('totalSize', 0)} records",
            extra={"total_size": response.get("totalSize", 0)},
        )

        return response

    async def create_record(
        self,
        sobject_type: str,
        record_data: Dict[str, Any],
    ) -> Dict[str, Any]:
        """
        Create a new record.

        Args:
            sobject_type: Salesforce object type
            record_data: Record field values

        Returns:
            Create response with record ID

        Raises:
            SalesforceAPIException: If creation fails
        """
        endpoint = f"sobjects/{sobject_type}"

        logger.info(f"Creating {sobject_type} record")

        response = await self._request("POST", endpoint, json_data=record_data)

        logger.info(
            f"Successfully created {sobject_type}",
            extra={
                "sobject_type": sobject_type,
                "record_id": response.get("id"),
            },
        )

        return response

    async def update_record(
        self,
        sobject_type: str,
        record_id: str,
        record_data: Dict[str, Any],
    ) -> None:
        """
        Update an existing record.

        Args:
            sobject_type: Salesforce object type
            record_id: Salesforce record ID
            record_data: Fields to update

        Raises:
            SalesforceAPIException: If update fails
        """
        endpoint = f"sobjects/{sobject_type}/{record_id}"

        logger.info(f"Updating {sobject_type} record", extra={"record_id": record_id})

        await self._request("PATCH", endpoint, json_data=record_data)

        logger.info(
            f"Successfully updated {sobject_type}",
            extra={"record_id": record_id},
        )

    async def delete_record(self, sobject_type: str, record_id: str) -> None:
        """
        Delete a record.

        Args:
            sobject_type: Salesforce object type
            record_id: Salesforce record ID

        Raises:
            SalesforceAPIException: If deletion fails
        """
        endpoint = f"sobjects/{sobject_type}/{record_id}"

        logger.info(f"Deleting {sobject_type} record", extra={"record_id": record_id})

        await self._request("DELETE", endpoint)

        logger.info(
            f"Successfully deleted {sobject_type}",
            extra={"record_id": record_id},
        )

    async def close(self) -> None:
        """Close HTTP client"""
        await self.http_client.aclose()


# Global Salesforce service instance
salesforce_service = SalesforceService()
