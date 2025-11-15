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
    SalesforceContact,
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
        self.api_version = settings.salesforce_api_version
        self.rate_limiter = get_rate_limiter()
        self._http_client = None

    async def _get_http_client(self) -> httpx.AsyncClient:
        """
        Get or create httpx AsyncClient.
        Creates a fresh client for each use to avoid Lambda event loop issues.

        Returns:
            httpx.AsyncClient instance
        """
        # Create a new client for each request to avoid event loop issues in Lambda
        limits = httpx.Limits(max_connections=1, max_keepalive_connections=1)
        return httpx.AsyncClient(timeout=30.0, limits=limits)
    
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

        # Create a new client for each request to avoid Lambda event loop issues
        async with await self._get_http_client() as client:
            try:
                response = await client.request(
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
                    response = await client.request(
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
            sobject_type: Salesforce object type (e.g., 'Contact')
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

    async def upsert_contact(self, contact_data: SalesforceContact) -> Dict[str, Any]:
        """
        Upsert Contact record using Stripe Customer ID as external ID.

        Args:
            contact_data: Contact data model

        Returns:
            Upsert response
        """
        if not contact_data.Stripe_Customer_ID__c:
            raise SalesforceAPIException(
                "Stripe_Customer_ID__c is required for upserting Contact",
                details={"contact_data": contact_data.model_dump()},
            )

        # Parse name into FirstName and LastName if needed
        record_data = contact_data.model_dump(mode="json", exclude_none=True)

        return await self.upsert_record(
            sobject_type="Contact",
            external_id_field="Stripe_Customer_ID__c",
            external_id_value=contact_data.Stripe_Customer_ID__c,
            record_data=record_data,
        )

    async def upsert_contact(self, contact_data: SalesforceContact) -> Dict[str, Any]:
        """
        Upsert Contact record using Stripe Customer ID as external ID.

        Args:
            contact_data: Contact data model

        Returns:
            Upsert response
        """
        if not contact_data.Stripe_Customer_ID__c:
            raise SalesforceAPIException(
                "Stripe_Customer_ID__c is required for upserting Contact",
                details={"contact_data": contact_data.model_dump()},
            )

        # Parse name into FirstName and LastName if needed
        record_data = contact_data.model_dump(exclude_none=True)

        return await self.upsert_record(
            sobject_type="Contact",
            external_id_field="Stripe_Customer_ID__c",
            external_id_value=contact_data.Stripe_Customer_ID__c,
            record_data=record_data,
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
        # Exclude the external ID field from the request body
        record_data = subscription_data.model_dump(mode="json", exclude_none=True)
        record_data.pop("Stripe_Subscription_ID__c", None)

        return await self.upsert_record(
            sobject_type="Stripe_Subscription__c",
            external_id_field="Stripe_Subscription_ID__c",
            external_id_value=subscription_data.Stripe_Subscription_ID__c,
            record_data=record_data,
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
        # Exclude the external ID field from the request body
        record_data = transaction_data.model_dump(mode="json", exclude_none=True)
        record_data.pop("Stripe_Payment_Intent_ID__c", None)

        return await self.upsert_record(
            sobject_type="Payment_Transaction__c",
            external_id_field="Stripe_Payment_Intent_ID__c",
            external_id_value=transaction_data.Stripe_Payment_Intent_ID__c,
            record_data=record_data,
        )

    async def upsert_invoice(
        self, invoice_data: "SalesforceInvoice"
    ) -> Dict[str, Any]:
        """
        Upsert invoice record.

        Args:
            invoice_data: Invoice data model

        Returns:
            Upsert response
        """
        # Exclude the external ID field from the request body
        record_data = invoice_data.model_dump(mode="json", exclude_none=True)
        record_data.pop("Stripe_Invoice_ID__c", None)

        return await self.upsert_record(
            sobject_type="Stripe_Invoice__c",
            external_id_field="Stripe_Invoice_ID__c",
            external_id_value=invoice_data.Stripe_Invoice_ID__c,
            record_data=record_data,
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

    async def composite_request(
        self,
        composite_requests: List[Dict[str, Any]],
        all_or_none: bool = True
    ) -> Dict[str, Any]:
        """
        Execute multiple operations in a single Composite API request.

        Composite API allows referencing results from previous operations using @{referenceId.field}.
        This is useful for creating related records where one depends on the ID of another.

        Args:
            composite_requests: List of composite request objects with structure:
                [
                    {
                        "method": "POST|PATCH|GET|DELETE",
                        "url": "/services/data/vXX.X/sobjects/Object__c",
                        "referenceId": "uniqueId",
                        "body": {...}  # Optional for GET/DELETE
                    }
                ]
            all_or_none: If True, all operations must succeed or all are rolled back

        Returns:
            Composite API response with structure:
                {
                    "compositeResponse": [
                        {
                            "referenceId": "uniqueId",
                            "httpStatusCode": 201,
                            "body": {"id": "a00xxx000000001", ...}
                        }
                    ]
                }

        Raises:
            SalesforceAPIException: If composite request fails

        Example:
            >>> requests = [
            ...     {
            ...         "method": "PATCH",
            ...         "url": f"/services/data/v{version}/sobjects/Invoice__c/External_Id__c/inv_123",
            ...         "referenceId": "invoice",
            ...         "body": {"Amount__c": 100}
            ...     },
            ...     {
            ...         "method": "POST",
            ...         "url": f"/services/data/v{version}/sobjects/Payment__c",
            ...         "referenceId": "payment",
            ...         "body": {
            ...             "Amount__c": 100,
            ...             "Invoice__c": "@{invoice.id}"  # References invoice result
            ...         }
            ...     }
            ... ]
            >>> result = await salesforce_service.composite_request(requests)
        """
        endpoint = "composite"

        composite_data = {
            "allOrNone": all_or_none,
            "compositeRequest": composite_requests
        }

        logger.info(
            f"Executing composite request with {len(composite_requests)} operations",
            extra={
                "operation_count": len(composite_requests),
                "all_or_none": all_or_none,
                "reference_ids": [req.get("referenceId") for req in composite_requests]
            }
        )

        response = await self._request("POST", endpoint, json_data=composite_data)

        # Check for any failures in the composite response
        if response and "compositeResponse" in response:
            failed_requests = [
                r for r in response["compositeResponse"]
                if r.get("httpStatusCode", 0) >= 400
            ]

            if failed_requests:
                logger.error(
                    f"Composite request had {len(failed_requests)} failed operations",
                    extra={"failed_requests": failed_requests}
                )

                if all_or_none:
                    # With allOrNone=true, Salesforce rolls back everything
                    raise SalesforceAPIException(
                        f"Composite request failed: {failed_requests}",
                        details={"failed_requests": failed_requests}
                    )

        logger.info(
            f"Successfully executed composite request",
            extra={
                "operation_count": len(composite_requests),
                "response": response
            }
        )

        return response

    async def create_invoice_and_transaction_composite(
        self,
        invoice_data: Dict[str, Any],
        transaction_data: Dict[str, Any],
        stripe_invoice_id: str
    ) -> Dict[str, Any]:
        """
        Create both Invoice and Payment Transaction in a single Composite API call.
        The Payment Transaction will be automatically linked to the Invoice using reference IDs.

        Args:
            invoice_data: Stripe_Invoice__c record data
            transaction_data: Payment_Transaction__c record data (without Stripe_Invoice__c field)
            stripe_invoice_id: Stripe invoice ID for upsert external ID

        Returns:
            Dictionary with both IDs:
                {
                    "invoice_id": "a02xxx000000001",
                    "transaction_id": "a01xxx000000001"
                }

        Raises:
            SalesforceAPIException: If composite request fails
        """
        # Remove the Stripe_Invoice__c field if present - we'll use reference instead
        transaction_data_copy = transaction_data.copy()
        transaction_data_copy.pop("Stripe_Invoice__c", None)

        # Remove the Stripe_Invoice_ID__c field from invoice_data since it's used in the URL
        invoice_data_copy = invoice_data.copy()
        invoice_data_copy.pop("Stripe_Invoice_ID__c", None)

        composite_requests = [
            {
                "method": "PATCH",
                "url": f"/services/data/{self.api_version}/sobjects/Stripe_Invoice__c/Stripe_Invoice_ID__c/{stripe_invoice_id}",
                "referenceId": "invoice",
                "body": invoice_data_copy
            },
            {
                "method": "POST",
                "url": f"/services/data/{self.api_version}/sobjects/Payment_Transaction__c",
                "referenceId": "transaction",
                "body": {
                    **transaction_data_copy,
                    "Stripe_Invoice__c": "@{invoice.id}"  # Reference to invoice result
                }
            }
        ]

        response = await self.composite_request(composite_requests, all_or_none=True)

        # Extract IDs from response
        invoice_response = next(
            (r for r in response["compositeResponse"] if r["referenceId"] == "invoice"),
            None
        )
        transaction_response = next(
            (r for r in response["compositeResponse"] if r["referenceId"] == "transaction"),
            None
        )

        return {
            "invoice_id": invoice_response["body"]["id"] if invoice_response else None,
            "transaction_id": transaction_response["body"]["id"] if transaction_response else None,
            "composite_response": response
        }

    async def close(self) -> None:
        """Close HTTP client"""
        await self.http_client.aclose()


# Global Salesforce service instance
salesforce_service = SalesforceService()
