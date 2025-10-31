"""
Salesforce Bulk API 2.0 Service

Implements Salesforce Bulk API 2.0 for efficient batch processing of records.
Used for low-priority events (e.g., customer metadata updates) that can be batched.

Bulk API 2.0 Benefits:
- Process up to 150 million records
- Better performance than REST API for large datasets
- Asynchronous processing
- Reduced API call consumption

References:
- https://developer.salesforce.com/docs/atlas.en-us.api_asynch.meta/api_asynch/
"""

import asyncio
import csv
import io
import json
from datetime import datetime, timezone
from enum import Enum
from typing import Dict, Any, List, Optional

import httpx
from app.auth.salesforce_oauth import get_salesforce_oauth
from app.config import get_settings
from app.utils.logging_config import get_logger
from app.utils.exceptions import SalesforceAPIException, RetryableException

logger = get_logger(__name__)
settings = get_settings()


class BulkJobState(Enum):
    """Bulk API job states"""
    OPEN = "Open"
    UPLOAD_COMPLETE = "UploadComplete"
    IN_PROGRESS = "InProgress"
    JOB_COMPLETE = "JobComplete"
    ABORTED = "Aborted"
    FAILED = "Failed"


class BulkJobOperation(Enum):
    """Bulk API operations"""
    INSERT = "insert"
    UPDATE = "update"
    UPSERT = "upsert"
    DELETE = "delete"


class SalesforceBulkAPIService:
    """
    Salesforce Bulk API 2.0 service for batch operations.

    Workflow:
    1. Create a bulk job
    2. Upload CSV data to the job
    3. Close the job (marks upload complete)
    4. Poll job status until completion
    5. Retrieve results
    """

    def __init__(self):
        """Initialize Bulk API service"""
        self.oauth = get_salesforce_oauth()
        self.base_url = f"{settings.salesforce_instance_url}/services/data/v{settings.salesforce_api_version}/jobs/ingest"
        self.timeout = httpx.Timeout(30.0, connect=10.0)

    async def _get_headers(self) -> Dict[str, str]:
        """Get authorization headers with OAuth token"""
        token = await self.oauth.get_access_token()
        return {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json"
        }

    async def create_job(
        self,
        object_name: str,
        operation: BulkJobOperation,
        external_id_field: Optional[str] = None,
        line_ending: str = "LF"
    ) -> Dict[str, Any]:
        """
        Create a new bulk ingest job.

        Args:
            object_name: Salesforce object API name (e.g., 'Stripe_Customer__c')
            operation: Operation type (insert, update, upsert, delete)
            external_id_field: Required for upsert operations (e.g., 'Stripe_Customer_ID__c')
            line_ending: Line ending style ('LF', 'CRLF')

        Returns:
            Job information including job ID

        Raises:
            SalesforceAPIException: If job creation fails
        """
        headers = await self._get_headers()

        payload = {
            "object": object_name,
            "operation": operation.value,
            "lineEnding": line_ending,
            "contentType": "CSV",
            "columnDelimiter": "COMMA"
        }

        # External ID field required for upsert
        if operation == BulkJobOperation.UPSERT:
            if not external_id_field:
                raise ValueError("external_id_field required for upsert operation")
            payload["externalIdFieldName"] = external_id_field

        logger.info(
            f"Creating Bulk API job: {operation.value} on {object_name}",
            extra={
                "object": object_name,
                "operation": operation.value,
                "external_id_field": external_id_field
            }
        )

        try:
            async with httpx.AsyncClient(timeout=self.timeout) as client:
                response = await client.post(
                    self.base_url,
                    headers=headers,
                    json=payload
                )
                response.raise_for_status()

            job_info = response.json()

            logger.info(
                f"Bulk API job created: {job_info['id']}",
                extra={
                    "job_id": job_info["id"],
                    "state": job_info["state"]
                }
            )

            return job_info

        except httpx.HTTPStatusError as e:
            logger.error(
                f"Failed to create Bulk API job: {e.response.status_code} - {e.response.text}",
                exc_info=True
            )
            raise SalesforceAPIException(
                f"Bulk API job creation failed: {e.response.text}",
                status_code=e.response.status_code
            )
        except Exception as e:
            logger.error(f"Unexpected error creating Bulk API job: {str(e)}", exc_info=True)
            raise SalesforceAPIException(f"Bulk API job creation failed: {str(e)}")

    async def upload_job_data(self, job_id: str, csv_data: str) -> None:
        """
        Upload CSV data to a bulk job.

        Args:
            job_id: Bulk job ID
            csv_data: CSV data as string

        Raises:
            SalesforceAPIException: If upload fails
        """
        token = await self.oauth.get_access_token()
        headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "text/csv"
        }

        url = f"{self.base_url}/{job_id}/batches"

        logger.info(
            f"Uploading data to Bulk API job: {job_id}",
            extra={
                "job_id": job_id,
                "data_size": len(csv_data)
            }
        )

        try:
            async with httpx.AsyncClient(timeout=self.timeout) as client:
                response = await client.put(
                    url,
                    headers=headers,
                    content=csv_data
                )
                response.raise_for_status()

            logger.info(f"Data uploaded successfully to job {job_id}")

        except httpx.HTTPStatusError as e:
            logger.error(
                f"Failed to upload data to job {job_id}: {e.response.status_code} - {e.response.text}",
                exc_info=True
            )
            raise SalesforceAPIException(
                f"Bulk API data upload failed: {e.response.text}",
                status_code=e.response.status_code
            )
        except Exception as e:
            logger.error(f"Unexpected error uploading job data: {str(e)}", exc_info=True)
            raise SalesforceAPIException(f"Bulk API data upload failed: {str(e)}")

    async def close_job(self, job_id: str) -> Dict[str, Any]:
        """
        Close a bulk job to mark upload complete and begin processing.

        Args:
            job_id: Bulk job ID

        Returns:
            Updated job information

        Raises:
            SalesforceAPIException: If closing job fails
        """
        headers = await self._get_headers()
        url = f"{self.base_url}/{job_id}"

        payload = {"state": "UploadComplete"}

        logger.info(f"Closing Bulk API job: {job_id}")

        try:
            async with httpx.AsyncClient(timeout=self.timeout) as client:
                response = await client.patch(
                    url,
                    headers=headers,
                    json=payload
                )
                response.raise_for_status()

            job_info = response.json()

            logger.info(
                f"Bulk API job closed: {job_id}",
                extra={
                    "job_id": job_id,
                    "state": job_info["state"]
                }
            )

            return job_info

        except httpx.HTTPStatusError as e:
            logger.error(
                f"Failed to close job {job_id}: {e.response.status_code} - {e.response.text}",
                exc_info=True
            )
            raise SalesforceAPIException(
                f"Bulk API job close failed: {e.response.text}",
                status_code=e.response.status_code
            )
        except Exception as e:
            logger.error(f"Unexpected error closing job: {str(e)}", exc_info=True)
            raise SalesforceAPIException(f"Bulk API job close failed: {str(e)}")

    async def get_job_status(self, job_id: str) -> Dict[str, Any]:
        """
        Get current status of a bulk job.

        Args:
            job_id: Bulk job ID

        Returns:
            Job status information including state and record counts

        Raises:
            SalesforceAPIException: If status retrieval fails
        """
        headers = await self._get_headers()
        url = f"{self.base_url}/{job_id}"

        try:
            async with httpx.AsyncClient(timeout=self.timeout) as client:
                response = await client.get(url, headers=headers)
                response.raise_for_status()

            return response.json()

        except httpx.HTTPStatusError as e:
            logger.error(
                f"Failed to get job status {job_id}: {e.response.status_code} - {e.response.text}",
                exc_info=True
            )
            raise SalesforceAPIException(
                f"Bulk API status check failed: {e.response.text}",
                status_code=e.response.status_code
            )
        except Exception as e:
            logger.error(f"Unexpected error getting job status: {str(e)}", exc_info=True)
            raise SalesforceAPIException(f"Bulk API status check failed: {str(e)}")

    async def wait_for_job_completion(
        self,
        job_id: str,
        poll_interval: int = 5,
        max_wait_time: int = 300
    ) -> Dict[str, Any]:
        """
        Poll job status until completion or timeout.

        Args:
            job_id: Bulk job ID
            poll_interval: Seconds between status checks
            max_wait_time: Maximum seconds to wait

        Returns:
            Final job status

        Raises:
            SalesforceAPIException: If job fails or times out
        """
        start_time = datetime.now(timezone.utc)
        elapsed = 0

        logger.info(
            f"Waiting for job completion: {job_id}",
            extra={
                "job_id": job_id,
                "poll_interval": poll_interval,
                "max_wait_time": max_wait_time
            }
        )

        while elapsed < max_wait_time:
            status = await self.get_job_status(job_id)
            state = status["state"]

            logger.debug(
                f"Job {job_id} state: {state}",
                extra={
                    "job_id": job_id,
                    "state": state,
                    "records_processed": status.get("numberRecordsProcessed", 0),
                    "records_failed": status.get("numberRecordsFailed", 0)
                }
            )

            if state == BulkJobState.JOB_COMPLETE.value:
                logger.info(
                    f"Job completed successfully: {job_id}",
                    extra={
                        "job_id": job_id,
                        "records_processed": status.get("numberRecordsProcessed", 0),
                        "records_failed": status.get("numberRecordsFailed", 0)
                    }
                )
                return status

            elif state in [BulkJobState.FAILED.value, BulkJobState.ABORTED.value]:
                error_msg = status.get("errorMessage", "Unknown error")
                logger.error(
                    f"Job failed: {job_id} - {error_msg}",
                    extra={
                        "job_id": job_id,
                        "state": state,
                        "error": error_msg
                    }
                )
                raise SalesforceAPIException(f"Bulk job failed: {error_msg}")

            # Job still processing
            await asyncio.sleep(poll_interval)
            elapsed = (datetime.now(timezone.utc) - start_time).total_seconds()

        # Timeout
        logger.warning(
            f"Job timeout waiting for completion: {job_id}",
            extra={"job_id": job_id, "elapsed": elapsed}
        )
        raise SalesforceAPIException(f"Job timeout after {elapsed} seconds")

    async def get_job_results(self, job_id: str) -> List[Dict[str, Any]]:
        """
        Get successful and failed results for a completed job.

        Args:
            job_id: Bulk job ID

        Returns:
            List of result records with success/failure status
        """
        headers = await self._get_headers()

        # Get successful results
        success_url = f"{self.base_url}/{job_id}/successfulResults"
        failed_url = f"{self.base_url}/{job_id}/failedResults"

        results = []

        try:
            async with httpx.AsyncClient(timeout=self.timeout) as client:
                # Get successful results
                success_response = await client.get(success_url, headers={
                    "Authorization": headers["Authorization"],
                    "Accept": "text/csv"
                })
                if success_response.status_code == 200:
                    success_csv = success_response.text
                    results.extend(self._parse_csv_results(success_csv, success=True))

                # Get failed results
                failed_response = await client.get(failed_url, headers={
                    "Authorization": headers["Authorization"],
                    "Accept": "text/csv"
                })
                if failed_response.status_code == 200:
                    failed_csv = failed_response.text
                    results.extend(self._parse_csv_results(failed_csv, success=False))

            return results

        except Exception as e:
            logger.error(f"Error retrieving job results: {str(e)}", exc_info=True)
            return []

    def _parse_csv_results(self, csv_data: str, success: bool) -> List[Dict[str, Any]]:
        """Parse CSV results into list of dictionaries"""
        if not csv_data.strip():
            return []

        results = []
        reader = csv.DictReader(io.StringIO(csv_data))

        for row in reader:
            result = dict(row)
            result["success"] = success
            results.append(result)

        return results

    def _records_to_csv(self, records: List[Dict[str, Any]]) -> str:
        """
        Convert list of record dictionaries to CSV string.

        Args:
            records: List of record dictionaries with field names as keys

        Returns:
            CSV-formatted string
        """
        if not records:
            return ""

        # Get all unique field names from all records
        fieldnames = set()
        for record in records:
            fieldnames.update(record.keys())

        fieldnames = sorted(list(fieldnames))

        # Create CSV
        output = io.StringIO()
        writer = csv.DictWriter(output, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(records)

        return output.getvalue()

    async def upsert_records(
        self,
        object_name: str,
        records: List[Dict[str, Any]],
        external_id_field: str,
        wait_for_completion: bool = True
    ) -> Dict[str, Any]:
        """
        Upsert records using Bulk API 2.0.

        High-level convenience method that handles the full workflow:
        1. Create job
        2. Upload data
        3. Close job
        4. Optionally wait for completion

        Args:
            object_name: Salesforce object API name
            records: List of records to upsert
            external_id_field: External ID field for matching
            wait_for_completion: Whether to wait for job completion

        Returns:
            Job information and results
        """
        logger.info(
            f"Starting bulk upsert: {len(records)} {object_name} records",
            extra={
                "object": object_name,
                "record_count": len(records),
                "external_id_field": external_id_field
            }
        )

        # Create job
        job_info = await self.create_job(
            object_name=object_name,
            operation=BulkJobOperation.UPSERT,
            external_id_field=external_id_field
        )
        job_id = job_info["id"]

        try:
            # Convert records to CSV
            csv_data = self._records_to_csv(records)

            # Upload data
            await self.upload_job_data(job_id, csv_data)

            # Close job
            await self.close_job(job_id)

            # Wait for completion if requested
            if wait_for_completion:
                final_status = await self.wait_for_job_completion(job_id)
                results = await self.get_job_results(job_id)

                return {
                    "job_id": job_id,
                    "status": final_status,
                    "results": results
                }
            else:
                return {
                    "job_id": job_id,
                    "status": job_info,
                    "message": "Job submitted, processing asynchronously"
                }

        except Exception as e:
            # Attempt to abort job on error
            try:
                await self.abort_job(job_id)
            except:
                pass  # Best effort
            raise

    async def abort_job(self, job_id: str) -> Dict[str, Any]:
        """
        Abort a bulk job.

        Args:
            job_id: Bulk job ID

        Returns:
            Updated job information
        """
        headers = await self._get_headers()
        url = f"{self.base_url}/{job_id}"

        payload = {"state": "Aborted"}

        logger.warning(f"Aborting Bulk API job: {job_id}")

        try:
            async with httpx.AsyncClient(timeout=self.timeout) as client:
                response = await client.patch(
                    url,
                    headers=headers,
                    json=payload
                )
                response.raise_for_status()

            return response.json()

        except Exception as e:
            logger.error(f"Error aborting job {job_id}: {str(e)}")
            raise


# Singleton instance
_bulk_api_service_instance: Optional[SalesforceBulkAPIService] = None


def get_bulk_api_service() -> SalesforceBulkAPIService:
    """Get or create Bulk API service singleton instance"""
    global _bulk_api_service_instance
    if _bulk_api_service_instance is None:
        _bulk_api_service_instance = SalesforceBulkAPIService()
    return _bulk_api_service_instance
